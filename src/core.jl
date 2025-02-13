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

        V = [0.0 -_v[3] _v[2];
            _v[3] 0.0 -_v[1];
            -_v[2] _v[1] 0.0]

        R = I + V + V^2 * (1 - c) / s^2

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

Container for hits including the mesh scatter and a description.

"""
mutable struct HitsCloud
    hits::Vector{Hit}
    positions::Observable{Vector{GeometryBasics.Point{3, Float32}}}
    mesh::MeshScatter{Tuple{Vector{GeometryBasics.Point{3, Float32}}}}
    description::String
end
function Base.show(io::IO, h::HitsCloud)
    print(io, "HitsCloud '$(h.description)' ($(length(h.hits)) hits)")
end


@kwdef mutable struct RBA
    scene::Scene = Scene(backgroundcolor=RGBf(1.0))
    cam::Makie.Camera3D = cam3d!(scene, rotation_center = :lookat)
    infobox::GLMakie.Text = text!(GLMakie.campixel(scene), Point2f(10, 10), fontsize=12, text = "", color=RGBf(0.2, 0.2, 0.2))
    tracks::Vector{Track} = Track[]
    hitsclouds::Vector{HitsCloud} = HitsCloud[]
    center::Point3f = Point3f(0.0, 0.0, 0.0)
    simparams::SimParams = SimParams()
    perspectives::Vector{Tuple{Vec{3, Float64}, Vec{3, Float64}}} = fill((Vec3(1000.0), Vec3(0.0)), 9)
   # hits::Union{Vector{XCalibratedHit}, Vector{KM3io.CalibratedHit}} = XCalibratedHit[]
   # hits_meshes::Vector{GLMakie.Makie.MeshScatter{Tuple{Vector{GeometryBasics.Point{3, Float64}}}}} = []
   # hits_mesh_descriptions::Vector{String} = []
    _plots::Dict{String, Any} = Dict()
end
Base.show(io::IO, rba::RBA) = print(io, "RainbowAlga event display.")

function RBA(detector::Detector; kwargs...)
    rba = RBA(kwargs...)

    update!(rba, detector)
    register_events(rba)
    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), center(detector), Vec3f(0, 0, 1))

    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    rba
end

function display3d(rba::RBA)
    Threads.@spawn start_eventloop(rba)
end

function save_perspective(rba::RBA, idx::Int)
    rba.perspectives[idx] = (rba.cam.eyeposition.val, rba.cam.lookat.val)
end
save_perspective(idx::Int) = save_perspective(_rba, idx::Int)
function save_perspective(rba::RBA, idx::Int, eyeposition, lookat)
    rba.perspectives[idx] = (eyeposition, lookat)
end
save_perspective(idx::Int, eyeposition, lookat) = save_perspective(_rba, idx::Int, eyeposition, lookat)
function load_perspective(rba::RBA, idx::Int)
    update_cam!(rba.scene, rba.cam, rba.perspectives[idx][1], rba.perspectives[idx][2], Vec3f(0,0,1))
end
load_perspective(idx::Int) = save_perspective(_rba, idx::Int)

# const rba = RBA(detector=Detector(joinpath(@__DIR__, "assets", "km3net_jul13_90m_r1494_corrected.detx")))


"""

Adds hits to the scene.

"""
function add!(rba::RBA, hits::T; pmt_distance=5, hit_distance=2, colorscheme=:hawaii) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}

    positions = Observable(generate_hit_positions(hits; pmt_distance=pmt_distance, hit_distance=hit_distance))

    if length(triggered(hits)) == 0
        t_min, t_max = extrema(h.t for h ∈ hits)
    else
        t_min, t_max = extrema(h.t for h ∈ triggered(hits))
    end
    Δt = t_max - t_min
    rba.simparams.t_offset = t_min
    rba.simparams.loop_end_frame_idx = Int(ceil(Δt))

    # rba.hits = hits

    cmap = getproperty(ColorSchemes, colorscheme)
    hits_mesh = meshscatter!(
        rba.scene,
        positions,
        color = [cmap[(h.t - rba.simparams.t_offset) / Δt] for h ∈ hits],
        markersize = [0 for _ ∈ hits],
        alpha = 0.9,
    )
    rbahits = [Hit(h.pos, h.dir, h.tot, h.t) for h in hits]
    push!(rba.hitsclouds, HitsCloud(rbahits, positions, hits_mesh, string(colorscheme)))
end
function add!(hits::T; pmt_distance=5, hit_distance=2) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}
    add!(_rba, hits; pmt_distance=pmt_distance, hit_distance=hit_distance)
end
function clearhits!(rba::RBA)
    for hitscloud in rba.hitsclouds
        hitscloud.mesh in rba.scene && delete!(rba.scene, hitscloud.mesh)
    end
    empty!(rba.hitsclouds)
end
clearhits!() = clearhits!(_rba)
function recolor!(rba::RBA, hitscloud_idx::Integer, colors)
    if hitscloud_idx < 1 || hitscloud_idx > length(rba.hitsclouds)
        error("No hits cloud with index $(hitscloud_idx) found. There is a total of $(length(rba.hitsclouds)) hits clouds to choose from.")
    end
    hitscloud = rba.hitsclouds[hitscloud_idx]
    if length(colors) != length(hitscloud.hits)
        error("$(length(colors)) colors were provided, however one color per hit is requred => a total of $(length(hitscloud.hits)) for this hits cloud.")
    end
    hitscloud.mesh.color = colors
    nothing
end

recolor!(hitscloud_idx::Integer, colors) = recolor!(_rba, hitscloud_idx, colors)

function update!(rba::RBA, track::T, hits, particle_name::AbstractString, track_id::Int) where T<:Union{Track, Trk}
    positions = Observable(generate_hit_positions(hits))

    cherenkov_photons = cherenkov(track, hits)

    cherenkov_hits_mesh = meshscatter!(
        rba.scene,
        positions,
        color = [reverse(ColorSchemes.redblue)[abs(c.Δt / 50.0)] for c in cherenkov_photons],
        markersize = [0 for _ ∈ hits],
        alpha = 0.9,
    )

    push!(rba.hitsclouds, HitsCloud([], positions, cherenkov_hits_mesh, "Cherenkov wrt. track #$(track_id) ($particle_name)"))
    nothing
end

function Base.empty!(rba::RBA)
    for track in rba.tracks
        delete!(rba.scene, track._lines)
    end
    empty!(rba.tracks)
    empty!(rba.hits)
    for hits_mesh in rba.hits_meshes
        delete!(rba.scene, hits_mesh)
    end
    empty!(rba.hits_meshes)
    empty!(rba.hits_mesh_descriptions)

    # TODO: this is need to get rid of everything, otherwise "plots" still contains hundreds of elements
    # Not sure why...
    empty!(rba.scene.plots)
    nothing
end

function add!(rba::RBA, track::Track)
    push!(rba.tracks, track)
end
add!(track::T; kwargs...) where T<:Union{Track, Trk} = add!(_rba, track; kwargs...)
add!(trk::Trk; kwargs...) = add!(_rba, Track(_rba.scene, trk.pos, trk.dir, KM3io.Constants.c, trk.t; kwargs...))

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


function update!(rba::RBA, det::Detector; simplified_doms=false, dom_diameter=0.4, pmt_diameter=0.076, dom_scaling=5, with_basegrid=true)
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
update!(d::Detector; kwargs...) = update!(_rba, d; kwargs...)

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

function run(rba::RBA; interactive=true)
    register_events(rba)
    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))
    if interactive
        Threads.@spawn :interactive start_eventloop(rba)
    else
        start_eventloop(rba)
    end
    nothing
end
run(;interactive=true) = run(_rba; interactive=interactive)

"""
Run the RainbowAlga GUI and display the specified event.
"""
function display!(rba::RBA, event::Evt)
    rba.simparams.frame_idx = 0

    chits = event.hits
    update!(rba, chits)

    if length(event.trks) > 0
        println("Reconstruction information found, adding the best candidates")
        reco = bestjppmuon(event)
        if !ismissing(reco)
            println("  adding best Jpp muon")
            track = Track(rba.scene, reco.pos, reco.dir, KM3io.Constants.c, reco.t; color=RGBf(5/255, 176/255, 255/255))
            add!(rba, track)
            update!(rba, track, chits, "Jpp muon (lik = $(reco.lik))", reco.id)
        end
    end

    length(event.mc_trks) > 0 && println("MC track information found.")
    for mc_track ∈ event.mc_trks
        !islepton(mc_track.type) && continue

        particle_name = Particle(mc_track.type).name

        println("  found a lepton: $(particle_name)")

        if tree == :online
            track_t = event.mc_t - (event.header.frame_index - 1) * 100e6
        else
            track_t = mc_track.t
        end

        if !isnothing(match(r"nu(.+)", particle_name))
            color = RGBf(1.0, 0.2, 0)
        else
            color = RGBf(0.0, 0.8, 0.7)
        end

        # track = Track(rba.scene, mc_track.pos - mc_track.dir * abs(mc_track.len), mc_track.dir, KM3io.Constants.c, track_t; color=color)
        track = Track(rba.scene, mc_track.pos, mc_track.dir, KM3io.Constants.c, track_t; color=color)
        # TODO: rba.scene should not be needed
        add!(rba, track)


        if charge(mc_track.type) != 0
            println("   -> adding Cherenkov hit information")
            update!(rba, track, chits, particle_name, mc_track.id)
        end
    end

    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))

    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    # Threads.@spawn :interactive start_eventloop(rba)
    rba
end

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
    push!(lines, @sprintf "time offset = %.0f ns" rba.simparams.t_offset)
    push!(lines, @sprintf "ToT cut = %.1f ns" rba.simparams.min_tot)

    # TODO: hits_selector is a counter and does not respect the actual number of hits hits_meshes
    # we need to make sure it does not overflow, but we should make this better upstream
    if length(rba.hitsclouds) > 0
        idx = abs(rba.simparams.hits_selector) % length(rba.hitsclouds) + 1
        push!(lines, "Hits cloud #$(idx): $(rba.hitsclouds[idx].description)")
    end

    rba.infobox.text = join(lines, "\n")
end

function start_eventloop(rba)
    screen = display(GLMakie.Screen(start_renderloop=false, focus_on_show=true, title="RainbowAlga"), rba.scene)
    glw = screen.glscreen
    GLMakie.GLFW.SetWindowPos(glw, displayparams.pos...)
    GLMakie.GLFW.SetWindowSize(glw, displayparams.size...)

    scene = rba.scene

    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    # on(screen.render_tick) do tick
    while isopen(screen)
        frame_start = time()

        if rba.simparams.quit
            rba.simparams.quit = false
            break
        end

        if rba.simparams.loop_enabled && rba.simparams.frame_idx > rba.simparams.loop_end_frame_idx
            rba.simparams.frame_idx = 0
        end

        rotation_enabled(rba) && rotate_cam!(scene, Vec3f(0, 0.001, 0))

        t = rba.simparams.t_offset + rba.simparams.frame_idx

        for (idx, hitscloud) in enumerate(rba.hitsclouds)
            isselected = idx == (abs(rba.simparams.hits_selector) % length(rba.hitsclouds) + 1)
            !isselected && continue
            hit_sizes = [h.tot >= rba.simparams.min_tot && t >= h.t ? (1+(rba.simparams.hit_scaling/5)) * sqrt(h.tot/255) : 0 for h ∈ hitscloud.hits]
            hitscloud.mesh.markersize = hit_sizes
        end

        for track ∈ rba.tracks
            draw!(track, t)
        end

        update_infotext!(rba)

        GLMakie.pollevents(screen, Makie.RegularRenderTick)
        GLMakie.render_frame(screen)

        GLMakie.GLFW.SwapBuffers(GLMakie.to_native(screen))

        if !isstopped(rba)
            rba.simparams.frame_idx += rba.simparams.speed
        end

        # if rba.simparams.save_next_frame
        #     println("Saving frame")
        #     rba.simparams.save_next_frame = false
        #     @show frame
        #     #save("rba.png", colorbuffer(rba.scene))
        #     #println("Frame saved as rba.png")
        # end

        yield()

        Δt = time() - frame_start
        sleep_time = 1.0/rba.simparams.fps - Δt
        if sleep_time > 0
            sleep(sleep_time)
        end
    end
    #wait(screen)

    GLMakie.destroy!(screen)
end
