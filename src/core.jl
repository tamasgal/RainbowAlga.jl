"""
A particle track.
"""
struct Track
    pos::Position{Float64}
    dir::Direction{Float64}
    v::Float64
    t::Float64
    _lines::Lines{Tuple{Vector{Point{3, Float64}}}}
    cone::Surface{Tuple{Matrix{Float64}, Matrix{Float64}, Matrix{Float32}}}
    cone_x::Matrix{Float64}
    cone_y::Matrix{Float64}
    cone_z::Matrix{Float64}

    function Track(scene, pos, dir, v, t; color=RGBf(1, 0.1, 0.4), with_cherenkov_cone=true)
        _lines = lines!(scene, [pos, pos], color=color, linewidth=5)

        # Cherenkov cone
        β = v / KM3io.Constants.c
        θ = π/2 - acos(1/KM3io.Constants.INDEX_OF_REFRACTION_WATER/β)  # opening angle is "90deg - emission angle"
        p = range(0, 2π, length = 50)
        u = 0:0.1:200
        x = [u * sin(p) * tan(θ) for p in p, u in u]
        y = [u * cos(p) * tan(θ) for p in p, u in u]
        z = [u for p in p, u in u]
        # Rotation matrix from (0, 0, -1) (cone) to track direction
        a = [0.0, 0.0, -1.0]
        b = dir
        _v = cross(a, b)
        s = norm(_v)
        c = dot(a, b)

        if s < 1e-10
            # Track is (anti)parallel to the cone axis (0, 0, -1): the cross product
            # vanishes and Rodrigues' formula would divide by zero. Use the exact
            # rotation: identity when parallel, 180 deg about the x-axis when antiparallel.
            R = c > 0 ? [1.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 1.0] :
                        [1.0 0.0 0.0; 0.0 -1.0 0.0; 0.0 0.0 -1.0]
        else
            V = [0.0 -_v[3] _v[2];
                _v[3] 0.0 -_v[1];
                -_v[2] _v[1] 0.0]

            R = I + V + V^2 * (1 - c) / s^2
        end

        # Apply the rotation and then the translation
        x_rot = R[1, 1] .* x .+ R[1, 2] .* y .+ R[1, 3] .* z
        y_rot = R[2, 1] .* x .+ R[2, 2] .* y .+ R[2, 3] .* z
        z_rot = R[3, 1] .* x .+ R[3, 2] .* y .+ R[3, 3] .* z

        # Translate to the track position
        target_pos = pos
        x_new = x_rot .+ target_pos.x
        y_new = y_rot .+ target_pos.y
        z_new = z_rot .+ target_pos.z

        s = surface!(scene, x_new, y_new, z_new, color = z, colormap = [ColorSchemes.RGBA(0.0, 0.6, 0.8, 0.7), ColorSchemes.RGBA(0.0, 0.6, 0.8, 0.0)], backlight = 2.0f0, transparency = true)
        s.visible[] = with_cherenkov_cone

        new(pos, dir, v, t, _lines, s, x_rot, y_rot, z_rot)
    end
end

"""
Return the position of the track at a given time.
"""
function positionof(track::Track, t)
    track.pos + track.v * track.dir * (t - track.t) / 1e9
end

function draw!(track::Track, t; trail_length=0)
    startpos = track.pos - track.dir * trail_length
    if t < track.t
        track._lines[1] = [startpos, track.pos]
        return track
    end
    endpos =  track.pos + track.v * track.dir * (t - track.t) / 1e9
    track._lines[1] = [startpos, endpos]
    if track.cone.visible[]
        track.cone[1][] = track.cone_x .+ endpos.x
        track.cone[2][] = track.cone_y .+ endpos.y
        track.cone[3][] = track.cone_z .+ endpos.z
    end
    track
end

struct Hit
    pos::Position{Float64}
    dir::Direction{Float64}
    tot::Float64
    t::Float64
end

"""

Pure-data container for a set of hits: their positions and (time-based) colours plus a
`description`. The hits are not a GPU object themselves; the scene holds a single shared
`MeshScatter` (`RBA.hits_mesh`) which is reconfigured from the selected cloud. The
`description` doubles as the name of the `ColorSchemes` colour map used for the colorbar.

"""
mutable struct HitsCloud
    hits::Vector{Hit}
    positions::Vector{Point3f}
    colors::Vector{RGBAf}
    alpha::Float64
    description::String
end
function Base.show(io::IO, h::HitsCloud)
    print(io, "HitsCloud '$(h.description)' ($(length(h.hits)) hits)")
end


@kwdef mutable struct RBA
    scene::Scene = Scene(backgroundcolor=RGBf(1.0))
    cam::Makie.Camera3D = cam3d!(scene, rotation_center = :lookat,
        down_key          = Keyboard.unknown,  # conflicts with F (frame/TC jump)
        zoom_out_key      = Keyboard.unknown,  # conflicts with O (auto-rotate)
        increase_fov_key  = Keyboard.unknown,  # conflicts with B (dark mode)
        decrease_fov_key  = Keyboard.unknown,  # conflicts with N (next event)
        pan_right_key     = Keyboard.unknown,  # conflicts with L (loop)
        roll_clockwise_key = Keyboard.unknown, # conflicts with E (event jump)
        fix_x_key         = Keyboard.unknown,  # conflicts with X (infobox)
    )
    infobox::GLMakie.Text = text!(GLMakie.campixel(scene), Point2f(10, 10), fontsize=12, text = "", color=RGBf(0.2, 0.2, 0.2))
    tracks::Vector{Track} = Track[]
    hitsclouds::Vector{HitsCloud} = HitsCloud[]
    center::Point3f = Point3f(0.0, 0.0, 0.0)
    simparams::SimParams = SimParams()
    perspectives::Vector{Tuple{Vec{3, Float64}, Vec{3, Float64}}} = fill((Vec3(1000.0), Vec3(0.0)), 9)
    # A single shared mesh holds all hits; it is reconfigured (positions/colours/sizes)
    # from the selected cloud instead of allocating a mesh per cloud or per event.
    hits_mesh::MeshScatter{Tuple{Vector{Point{3, Float32}}}} = meshscatter!(scene, Point3f[], color = RGBAf[], markersize = Float64[])
    _plots::Dict{String, Any} = Dict()
    eventfile::Union{Nothing, AbstractEventFile} = nothing
    current_event_idx::Int = 0
    current_frame_index::Int = 0
    current_trigger_counter::Int = 0
    _colorbar::Dict{String, Any} = Dict{String, Any}()
end
Base.show(io::IO, rba::RBA) = print(io, "RainbowAlga event display.")

function RBA(detector::Detector; kwargs...)
    rba = RBA(kwargs...)

    update!(rba, detector)
    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), center(detector), Vec3f(0, 0, 1))

    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    rba
end

get_current_cam_position(rba::RBA) = rba.cam.eyeposition.val
get_current_cam_position() = get_current_cam_position(global_rba())
get_current_cam_target(rba::RBA) = rba.cam.lookat.val
get_current_cam_target() = get_current_cam_target(global_rba())

function save_perspective(rba::RBA, idx::Int)
    pos = get_current_cam_position(rba)
    target = get_current_cam_target(rba)
    rba.perspectives[idx] = (pos, target)
    println("Perspective $idx saved.\n  Position: $(pos)\n  Target: $(target)")
end
save_perspective(idx::Int) = save_perspective(global_rba(), idx::Int)
function save_perspective(rba::RBA, idx::Int, eyeposition, lookat)
    rba.perspectives[idx] = (eyeposition, lookat)
end
save_perspective(idx::Int, eyeposition, lookat) = save_perspective(global_rba(), idx::Int, eyeposition, lookat)
function load_perspective(rba::RBA, idx::Int)
    update_cam!(rba.scene, rba.cam, rba.perspectives[idx][1], rba.perspectives[idx][2], Vec3f(0,0,1))
end
load_perspective(idx::Int) = load_perspective(global_rba(), idx::Int)

"""
Index (1-based) of the currently selected hits cloud, or 0 if there are none.
The selection is driven by `simparams.hits_selector`, cycled with the C key.
"""
active_hitscloud_index(rba::RBA) =
    isempty(rba.hitsclouds) ? 0 : abs(rba.simparams.hits_selector) % length(rba.hitsclouds) + 1

"""

Upload the data of the currently selected hits cloud into the single shared GPU mesh
(`rba.hits_mesh`). Positions, colours and the alpha value are uploaded here and only
change when the selection changes (or a new event/cloud is loaded); the per-frame
animation in the render loop only updates `markersize`, so the mesh is reused and
resized on the GPU instead of being reallocated.

"""
function apply_hitscloud!(rba::RBA)
    idx = active_hitscloud_index(rba)
    rba.simparams.displayed_hitscloud = idx
    hm = rba.hits_mesh
    if idx == 0
        hm.positions[] = Point3f[]
        hm.color[] = RGBAf[]
        hm.markersize[] = Float64[]
        return rba
    end
    cloud = rba.hitsclouds[idx]
    hm.positions[] = cloud.positions
    hm.color[] = cloud.colors
    hm.markersize[] = zeros(length(cloud.positions))
    hm.alpha[] = cloud.alpha
    rba
end

"""
Marker sizes for the animation at simulation time `t`: a hit becomes visible (scaled)
once the clock has reached it (`t >= hit.t`) and it passes the ToT cut (`min_tot`),
otherwise its size is 0. Returns one size per hit in `cloud`.
"""
hit_markersizes(cloud::HitsCloud, t, scale, min_tot) =
    [(h.tot >= min_tot && t >= h.t) ? scale * sqrt(h.tot / 255) : 0.0 for h in cloud.hits]


"""

Adds hits to the scene.

"""
function add!(rba::RBA, hits::T; pmt_distance=5, hit_distance=2, colorscheme=:hawaii, t_range=nothing) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}

    positions = generate_hit_positions(hits; pmt_distance=pmt_distance, hit_distance=hit_distance)

    if !isnothing(t_range)
        t_min, t_max = t_range
    elseif length(triggered(hits)) > 0
        t_min, t_max = extrema(h.t for h ∈ triggered(hits))
    else
        t_min, t_max = extrema(h.t for h ∈ hits)
    end
    Δt = t_max - t_min
    rba.simparams.t_offset = t_min
    rba.simparams.cb_t_offset = 0.0
    rba.simparams.loop_end_frame_idx = Int(ceil(Δt))

    cmap = getproperty(ColorSchemes, colorscheme)
    # Guard against Δt == 0 (a single hit or all hits at the same time) which would make
    # the colour fraction 0/0 = NaN.
    colorfrac(h) = iszero(Δt) ? 0.0 : clamp((h.t - t_min) / Δt, 0.0, 1.0)
    colors = [RGBAf(cmap[colorfrac(h)]) for h ∈ hits]
    rbahits = [Hit(h.pos, h.dir, h.tot, h.t) for h in hits]
    push!(rba.hitsclouds, HitsCloud(rbahits, positions, colors, 0.9, string(colorscheme)))
    rba._colorbar["default_t_offset"] = rba.simparams.t_offset
    rba._colorbar["default_loop_end_frame_idx"] = rba.simparams.loop_end_frame_idx
    apply_hitscloud!(rba)
    update_colorbar!(rba)
    rba
end
function add!(hits::T; kwargs...) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}
    add!(global_rba(), hits; kwargs...)
end
"""
Recompute and apply hit colors for all clouds based on the current `t_offset` and
`loop_end_frame_idx` in `SimParams`. Called after interactive colorbar adjustments.
"""
function recolor_hits_from_simparams!(rba::RBA)
    isempty(rba.hitsclouds) && return
    t_min = rba.simparams.t_offset + rba.simparams.cb_t_offset
    Δt = Float64(rba.simparams.loop_end_frame_idx)
    iszero(Δt) && return
    active = active_hitscloud_index(rba)
    for (idx, hitscloud) in enumerate(rba.hitsclouds)
        # Only time-coloured clouds (whose description names a ColorScheme) follow the
        # colorbar; Cherenkov clouds keep their Δt-residual colours.
        cmap = try
            getproperty(ColorSchemes, Symbol(hitscloud.description))
        catch
            continue
        end
        hitscloud.colors = [RGBAf(cmap[clamp((h.t - t_min) / Δt, 0.0, 1.0)]) for h in hitscloud.hits]
        idx == active && (rba.hits_mesh.color[] = hitscloud.colors)
    end
    nothing
end

function clearhits!(rba::RBA)
    rba.simparams.hits_selector = 0
    empty!(rba.hitsclouds)
    # Keep the shared mesh alive (reused across events); just empty its data.
    apply_hitscloud!(rba)
    update_colorbar!(rba)
end
clearhits!() = clearhits!(global_rba())
function recolor!(rba::RBA, hitscloud_idx::Integer, colors)
    if hitscloud_idx < 1 || hitscloud_idx > length(rba.hitsclouds)
        error("No hits cloud with index $(hitscloud_idx) found. There is a total of $(length(rba.hitsclouds)) hits clouds to choose from.")
    end
    hitscloud = rba.hitsclouds[hitscloud_idx]
    if length(colors) != length(hitscloud.hits)
        error("$(length(colors)) colors were provided, however one color per hit is requred => a total of $(length(hitscloud.hits)) for this hits cloud.")
    end
    hitscloud.colors = convert(Vector{RGBAf}, RGBAf.(colors))
    # Refresh the shared mesh only if this cloud is the one currently displayed.
    active_hitscloud_index(rba) == hitscloud_idx && (rba.hits_mesh.color[] = hitscloud.colors)
    nothing
end

recolor!(hitscloud_idx::Integer, colors) = recolor!(global_rba(), hitscloud_idx, colors)

"""

Add a hits cloud coloured by the Cherenkov time residual (`Δt`) with respect to
`track`. The hits and positions are the same as the plain hits cloud, so cycling with
the C key compares the same photons against different track hypotheses.

"""
function add_cherenkov_cloud!(rba::RBA, track, hits, description::AbstractString)
    positions = generate_hit_positions(hits)
    cphotons = cherenkov(track, hits)
    cmap = reverse(ColorSchemes.redblue)
    colors = [RGBAf(cmap[clamp(abs(c.Δt) / 50.0, 0.0, 1.0)]) for c in cphotons]
    rbahits = [Hit(h.pos, h.dir, h.tot, h.t) for h in hits]
    push!(rba.hitsclouds, HitsCloud(rbahits, positions, colors, 0.9, description))
    apply_hitscloud!(rba)
    update_colorbar!(rba)
    nothing
end

"""

Add the reconstructed (best Jpp muon) and MC lepton tracks of an offline event,
together with their Cherenkov hits clouds. Failures for a single track are warned
about but do not abort loading the event.

"""
function add_reco_and_mc!(rba::RBA, event::Evt, hits)
    if length(event.trks) > 0
        reco = bestjppmuon(event)
        if !ismissing(reco)
            try
                println("  adding best Jpp muon")
                track = Track(rba.scene, reco.pos, reco.dir, KM3io.Constants.c, reco.t; color=RGBf(5/255, 176/255, 255/255))
                add!(rba, track)
                isempty(hits) || add_cherenkov_cloud!(rba, track, hits, "Cherenkov wrt. Jpp muon (lik=$(round(Int, reco.lik)))")
            catch e
                @warn "Could not add the reconstructed Jpp muon" exception=(e, catch_backtrace())
            end
        end
    end

    for mc_track in event.mc_trks
        Corpuscles.islepton(mc_track.type) || continue
        try
            particle_name = string(Corpuscles.Particle(mc_track.type).name)
            println("  found a lepton: $(particle_name)")
            color = isnothing(match(r"nu", particle_name)) ? RGBf(0.0, 0.8, 0.7) : RGBf(1.0, 0.2, 0.0)
            track = Track(rba.scene, mc_track.pos, mc_track.dir, KM3io.Constants.c, mc_track.t; color=color)
            add!(rba, track)
            if !isempty(hits) && Corpuscles.charge(mc_track.type) != 0
                println("   -> adding Cherenkov hit information")
                add_cherenkov_cloud!(rba, track, hits, "Cherenkov wrt. MC $(particle_name) (#$(mc_track.id))")
            end
        catch e
            @warn "Could not add MC track" exception=(e, catch_backtrace())
        end
    end
    rba
end

# Removes the per-event plots (track lines and Cherenkov cones) and the hits clouds,
# while keeping the detector geometry and the shared hits mesh alive so they are reused
# when stepping through events.
function Base.empty!(rba::RBA)
    for track in rba.tracks
        delete!(rba.scene, track._lines)
        delete!(rba.scene, track.cone)
    end
    empty!(rba.tracks)
    clearhits!(rba)
    nothing
end

function add!(rba::RBA, track::Track)
    push!(rba.tracks, track)
end
add!(track::T; kwargs...) where T<:Union{Track, Trk} = add!(global_rba(), track; kwargs...)
add!(trk::Trk; kwargs...) = add!(global_rba(), Track(global_rba().scene, trk.pos, trk.dir, KM3io.Constants.c, trk.t; kwargs...))

"""

Generate hit positions for each hit, stacking them on top of each other along the PMT axis
when the same PMT is hit multiple times.

"""
function generate_hit_positions(hits; pmt_distance=5, hit_distance=2)
    pmt_map = Dict{Tuple{Int, Int}, Int}()
    pos = Point3f[]
    for hit ∈ hits
        loc = (hit.dom_id, hit.channel_id)
        if !(loc ∈ keys(pmt_map))
            pmt_map[loc] = 0
        else
            pmt_map[loc] += 1
        end
        i = pmt_map[loc]
        push!(pos, Point3f(hit.pos + hit.dir*(pmt_distance + hit_distance*i)))
        # push!(pos, Point3f(hit.pos + hit.dir))#*pmt_distance + hit.dir*hit_distance*i))
    end
    pos
end


function update!(rba::RBA, det::Detector; simplified_doms=true, dom_diameter=0.4, pmt_diameter=0.076, dom_scaling=5, with_basegrid=true)
    scene = rba.scene
    det_center = center(det)
    rba.center = det_center

    if "Basegrid" in keys(rba._plots)
        for element in rba._plots["Basegrid"]
            element in scene && delete!(rba.scene, element)
        end
        delete!(rba._plots, "Basegrid")
    end
    if with_basegrid
        basegrid!(rba; center=Point3f(det_center[1], det_center[2], 0))
    end

    if "Detector" in keys(rba._plots)
        for element in rba._plots["Detector"]
            element in scene && delete!(rba.scene, element)
        end
    end
    plots = rba._plots["Detector"] = []

    opticalmodules = [m for m in det if isopticalmodule(m)]
    push!(plots, meshscatter!(
        scene,
        [m.pos for m ∈ opticalmodules],
        markersize=dom_diameter*dom_scaling,
        color=RGBAf(0.3, 0.3, 0.3, 0.8)
    ))

    if !simplified_doms
      pmt_positions = Position{Float64}[]
      for m in det
          !isopticalmodule(m) && continue
          for pmt in m
            push!(pmt_positions, pmt.pos + pmt.dir*dom_diameter*dom_scaling - pmt.dir*pmt_diameter*dom_scaling)
          end
      end
      push!(plots, meshscatter!(
          scene,
          pmt_positions,
          markersize=pmt_diameter*dom_scaling,
          color=RGBAf(1.0, 1.0, 1.0, 0.4)
      ))
    end
    # basemodules = [m for m ∈ det if isbasemodule(m)]
    # push!(plots, meshscatter!(
    #     scene,
    #     [m.pos for m ∈ basemodules],
    #     marker=Rect3f(Vec3f(-0.5), Vec3f(0.5)),
    #     markersize=5,
    #     color=:black
    # ))
    for string ∈ det.strings
        modules = filter(m->m.location.string == string, collect(values(det.modules)))
        sort!(modules, by=m->m.location.floor)
        segments = [m.pos for m in modules]
        top_module = modules[end]
        buoy_height = 20.0
        buoy_pos = top_module.pos + Point3f(0, 0, 100)
        push!(segments, buoy_pos)
        push!(plots, lines!(scene, segments; color=:grey, linewidth=1))
        push!(plots, mesh!(scene, Cylinder(Point3f(buoy_pos), Point3f(buoy_pos + Point3f(0.0, 0.0, buoy_height)), 7.0f0), color=:yellow, alpha=0.1))
        push!(plots, text!(scene, buoy_pos + Point3f(0.0, 0.0, 1.5buoy_height); fontsize=24, font=:bold, text = "$string", color=RGBf(120/255, 105/255, 11/255), markerspace=:pixel, align = (:center, :center)))
    end

    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))

    nothing
end
update!(d::Detector; kwargs...) = update!(global_rba(), d; kwargs...)

"""

Draws a grid on the XY-plane with an optional `center` point, `span`, grid-`spacing` and
styling options.

"""
function basegrid!(rba; center=(0, 0, 0), span=(-1000, 1000), spacing=50, linewidth=1, color=(:grey, 0.3))
    scene = rba.scene
    min, max = span
    center = Point3f(center)
    plots = rba._plots["Basegrid"] = []
    for q ∈ range(min, max; step=spacing)
        push!(plots, lines!(scene, [Point3f(q, min, 0) + center, Point3f(q, max, 0) + center], color=color, linewidth=linewidth))
        push!(plots, lines!(scene, [Point3f(min, q, 0) + center, Point3f(max, q, 0) + center], color=color, linewidth=linewidth))
    end
    scene
end

"""
Load the event at sequential index `idx` from the attached [`AbstractEventFile`] and
replace the current hit display (and, for offline events, the reconstructed/MC tracks).
The detector geometry and the shared hits mesh are reused.
"""
function load_event!(rba::RBA, idx::Int)
    f = rba.eventfile
    isnothing(f) && return
    n = nevents(f)
    n == 0 && return
    idx = clamp(idx, 1, n)
    rba.current_event_idx = idx
    empty!(rba)  # clears tracks + hits, keeps detector + shared mesh
    s = eventsample(f, idx)
    rba.current_frame_index = s.frame_index
    rba.current_trigger_counter = s.trigger_counter
    isempty(s.hits) || add!(rba, s.hits; t_range=s.t_range)
    isnothing(s.event) || add_reco_and_mc!(rba, s.event, s.hits)
    reset_time(rba)
    println("Event $idx / $n loaded")
    nothing
end
load_event!(idx::Int) = load_event!(global_rba(), idx)

next_event!(rba::RBA) = load_event!(rba, rba.current_event_idx + 1)
next_event!() = next_event!(global_rba())

previous_event!(rba::RBA) = load_event!(rba, rba.current_event_idx - 1)
previous_event!() = previous_event!(global_rba())

function run(rba::RBA; interactive=true)
    println("Registering events")
    println("Centering scene")
    center!(rba.scene)
    println("Updating camera")
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))
    start_eventloop(rba; interactive=interactive)
    nothing
end
run(;interactive=true) = run(global_rba(); interactive=interactive)

"""
    load!([rba::RBA], f::AbstractEventFile)

Attach an event file, draw its detector geometry once and load the first event. Does
not open a window (use [`run`](@ref) for that).
"""
load!(f::AbstractEventFile) = load!(global_rba(), f)
function load!(rba::RBA, f::AbstractEventFile)
    update!(rba, geometry(f))
    rba.eventfile = f
    load_event!(rba, 1)
    rba
end

"""
Start RainbowAlga with an [`AbstractEventFile`] (e.g. an [`EventFile`] wrapping a
KM3NeT online or offline ROOT file). The geometry is drawn once and the first event is
shown; N / Shift+N navigate forward/backward and E lets you jump by index.
"""
function run(f::AbstractEventFile; interactive=true)
    rba = global_rba()
    load!(rba, f)
    run(rba; interactive=interactive)
end

"""
Display a single offline event: clear the previous event, add its hits and (when
present) the reconstructed and MC tracks, then recentre the camera.
"""
function display!(rba::RBA, event::Evt)
    empty!(rba)
    rba.simparams.frame_idx = 0
    hits = event.hits
    isempty(hits) || add!(rba, hits)
    add_reco_and_mc!(rba, event, hits)
    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))
    rba
end
display!(event::Evt) = display!(global_rba(), event)

"""
Generates the text for the infobox on the lower left.
"""
function update_infotext!(rba)
    if !rba.simparams.show_infobox
        rba.infobox.text = ""
        return
    end
    lines = String[]
    push!(lines, "t = $(rba.simparams.frame_idx) ns (loop=$(rba.simparams.loop_enabled))")
    push!(lines, @sprintf "time offset = %.0f ns  duration = %d ns" rba.simparams.t_offset rba.simparams.loop_end_frame_idx)
    push!(lines, @sprintf "ToT cut = %.1f ns  speed = %d  hit scaling = %d" rba.simparams.min_tot rba.simparams.speed rba.simparams.hit_scaling)
    push!(lines, @sprintf "Position: x=%.1f y=%.1f z=%1.f" get_current_cam_position()...)
    push!(lines, @sprintf "Target: x=%.1f y=%.1f z=%1.f" get_current_cam_target()...)

    if length(rba.hitsclouds) > 0
        idx = active_hitscloud_index(rba)
        push!(lines, "Hits cloud #$(idx)/$(length(rba.hitsclouds)): $(rba.hitsclouds[idx].description)")
    end

    if !isnothing(rba.eventfile)
        n = nevents(rba.eventfile)
        idx_str = rba.current_event_idx > 0 ? "Event: $(rba.current_event_idx) / $n  " : ""
        push!(lines, "$(idx_str)frame=$(rba.current_frame_index)  TC=$(rba.current_trigger_counter)  [N/Shift+N: next/prev, E: #, F: frame/TC]")
    end
    if rba.simparams.event_input_mode
        push!(lines, "Jump to event #: $(rba.simparams.event_input_buffer)_  (ENTER confirms, any other key cancels)")
    end
    if rba.simparams.frame_tc_input_stage == 1
        push!(lines, "Jump to frame index: $(rba.simparams.frame_index_buffer)_  TC: ?  (ENTER for TC, any other key cancels)")
    elseif rba.simparams.frame_tc_input_stage == 2
        push!(lines, "Jump to frame index: $(rba.simparams.frame_index_buffer)  TC: $(rba.simparams.trigger_counter_buffer)_  (ENTER loads, any other key cancels)")
    end

    rba.infobox.text = join(lines, "\n")
end

"""
Set up the colorbar overlay in pixel space. Called once during `start_eventloop`.
"""
function setup_colorbar!(rba::RBA)
    scene = rba.scene
    cpscene = campixel(scene)

    n = 256
    n_ticks_max = 25
    _, win_h_init = displayparams.size
    cb_w = 20
    cb_h = round(Int, win_h_init * 0.55)
    margin_right = 75

    # Reactive position: always centred on the right edge regardless of window size
    viewport = scene.viewport
    cb_x_obs = @lift(width($viewport) - margin_right)
    cb_y_obs = @lift((height($viewport) - cb_h) ÷ 2)

    cbar_colors = Observable(fill(RGBAf(0, 0, 0, 0), 1, n))
    cbar_ticks_text = Observable(fill("", n_ticks_max))
    cbar_tick_positions = Observable(fill(Point2f(0, 0), n_ticks_max))
    cbar_visible = Observable(false)

    x_range = @lift(Float32($cb_x_obs) .. Float32($cb_x_obs + cb_w))
    y_range = @lift(Float32($cb_y_obs) .. Float32($cb_y_obs + cb_h))

    img_plot = image!(cpscene, x_range, y_range, cbar_colors;
                      visible=cbar_visible, interpolate=true)

    ticks_plot = text!(cpscene, cbar_tick_positions;
                       text=cbar_ticks_text,
                       fontsize=10,
                       color=RGBf(0.2, 0.2, 0.2),
                       visible=cbar_visible,
                       align=(:left, :center))

    title_pos = @lift Point2f($cb_x_obs + cb_w / 2, $cb_y_obs + cb_h + 15)
    title_plot = text!(cpscene, title_pos;
                       text="Δt / ns",
                       fontsize=11,
                       color=RGBf(0.2, 0.2, 0.2),
                       visible=cbar_visible,
                       align=(:center, :bottom))

    rba._colorbar["cpscene"] = cpscene
    rba._colorbar["colors"] = cbar_colors
    rba._colorbar["ticks_text"] = cbar_ticks_text
    rba._colorbar["tick_positions"] = cbar_tick_positions
    rba._colorbar["visible"] = cbar_visible
    rba._colorbar["img_plot"] = img_plot
    rba._colorbar["ticks_plot"] = ticks_plot
    rba._colorbar["title_plot"] = title_plot
    rba._colorbar["cb_x"] = cb_x_obs
    rba._colorbar["cb_w"] = cb_w
    rba._colorbar["cb_y"] = cb_y_obs
    rba._colorbar["cb_h"] = cb_h

    # Recompute tick label positions whenever the window is resized
    on(viewport) do _
        update_colorbar!(rba)
    end

    update_colorbar!(rba)
    nothing
end

"""
Update the colorbar to reflect the currently selected hits cloud.
"""
function update_colorbar!(rba::RBA)
    haskey(rba._colorbar, "visible") || return

    cbar_visible = rba._colorbar["visible"]
    cbar_colors = rba._colorbar["colors"]
    cbar_ticks_text = rba._colorbar["ticks_text"]
    cbar_tick_positions = rba._colorbar["tick_positions"]
    cb_x = rba._colorbar["cb_x"][]
    cb_w = rba._colorbar["cb_w"]
    cb_y = rba._colorbar["cb_y"][]
    cb_h = rba._colorbar["cb_h"]

    if isempty(rba.hitsclouds)
        cbar_visible[] = false
        return
    end

    n = size(cbar_colors[], 2)
    n_ticks_max = length(cbar_ticks_text[])

    idx = active_hitscloud_index(rba)
    hitscloud = rba.hitsclouds[idx]

    Δt = Float64(rba.simparams.loop_end_frame_idx)

    # The time colorbar only applies to time-coloured clouds (whose description names a
    # ColorScheme); hide it for Cherenkov clouds or a degenerate (zero) time window.
    cmap = try
        getproperty(ColorSchemes, Symbol(hitscloud.description))
    catch
        cbar_visible[] = false
        return
    end
    if iszero(Δt)
        cbar_visible[] = false
        return
    end

    new_colors = Matrix{RGBAf}(undef, 1, n)
    for i in 1:n
        frac = (i - 1) / (n - 1)
        c = cmap[frac]
        new_colors[1, i] = RGBAf(c.r, c.g, c.b, 1.0)
    end
    cbar_colors[] = new_colors

    tick_interval = if Δt > 2000
        500.0
    elseif Δt > 200
        100.0
    else
        10.0
    end
    # Tick labels are relative to the first hit (cb_t_offset can be negative)
    t_rel_start = rba.simparams.cb_t_offset
    first_tick = ceil(t_rel_start / tick_interval) * tick_interval
    tick_values = collect(first_tick:tick_interval:t_rel_start + Δt)

    tick_x = Float32(cb_x + cb_w + 5)
    new_positions = fill(Point2f(0, 0), n_ticks_max)
    new_texts = fill("", n_ticks_max)
    for (j, tv) in enumerate(tick_values)
        frac = (tv - t_rel_start) / Δt
        new_positions[j] = Point2f(tick_x, cb_y + frac * cb_h)
        new_texts[j] = @sprintf("%.0f", tv)
    end
    cbar_tick_positions[] = new_positions
    cbar_ticks_text[] = new_texts

    cbar_visible[] = true
    nothing
end

function start_eventloop(rba; interactive=true)
    println("Creating screen")
    screen = display(GLMakie.Screen(start_renderloop=false, focus_on_show=true, title="RainbowAlga", framerate=rba.simparams.fps), rba.scene)
    glw = screen.glscreen
    println("Setting window position and size")
    GLMakie.GLFW.SetWindowPos(glw, displayparams.pos...)
    GLMakie.GLFW.SetWindowSize(glw, displayparams.size...)

    scene = rba.scene

    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    counters = get_capture_counters()
    rba.simparams.screenshot_counter = counters.screenshot + 1
    rba.simparams.recording_counter = counters.recording + 1

    recorder = VideoRecorder(; 
        framerate=24,
        preset="ultrafast",  # Can also try "veryfast" or "faster" for better quality
        crf=28,  # Higher = lower quality but faster encoding (23 is default, 28 is faster)
        pixel_format="yuv420p"
    )

    register_events(rba, screen, recorder)
    setup_colorbar!(rba)
    register_colorbar_events(rba)

    recording_task = @async fps_renderloop(screen, recorder)

    on(screen.render_tick) do tick
        # Keep the render loop paced at the requested FPS; picks up live setfps! changes.
        if screen.config.framerate != rba.simparams.fps
            screen.config.framerate = rba.simparams.fps
            Makie.reset!(screen.timer, 1.0 / rba.simparams.fps)
        end

        if rba.simparams.loop_enabled && rba.simparams.frame_idx > rba.simparams.loop_end_frame_idx
            rba.simparams.frame_idx = 0
        end

        rotation_enabled(rba) && rotate_cam!(scene, Vec3f(0, 0.001, 0))

        t = rba.simparams.t_offset + rba.simparams.frame_idx

        # Single shared mesh: reconfigure positions/colours only when the selection
        # changed, then resize markers every tick to animate hits as time advances.
        active = active_hitscloud_index(rba)
        if active != rba.simparams.displayed_hitscloud
            apply_hitscloud!(rba)
        end
        if active != 0
            cloud = rba.hitsclouds[active]
            scale = 1 + rba.simparams.hit_scaling / 5
            rba.hits_mesh.markersize[] = hit_markersizes(cloud, t, scale, rba.simparams.min_tot)
        end

        for track ∈ rba.tracks
            draw!(track, t)
        end

        update_infotext!(rba)

        if !isstopped(rba)
            rba.simparams.frame_idx += rba.simparams.speed
        end
    end
    if !interactive
        wait(screen)
        wait(recording_task)
    end
end


"""
Return the current recording counters for screenshots and videos.
"""
function get_capture_counters()
    files = readdir()

    function extract_counter(path)
        m = match(r"RBA_(\d+)\.(mp4|png)", path)
        return m === nothing ? nothing : (parse(Int, m.captures[1]), m.captures[2])
    end

    counters = filter(!isnothing, extract_counter.(files))
    mp4_counters = [0]
    png_counters = [0]

    for (counter, ext) in counters
        if ext == "mp4"
            push!(mp4_counters, counter)
        elseif ext == "png"
            push!(png_counters, counter)
        end
    end

    (screenshot=maximum(png_counters), recording=maximum(mp4_counters))
end

