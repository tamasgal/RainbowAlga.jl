"""
A particle track.
"""
struct Track
    pos::Position{Float64}
    dir::Direction{Float64}
    v::Float64
    t::Float64
    _lines::Lines{Tuple{Vector{Point{3, Float32}}}}

    function Track(scene, pos, dir, v, t; color=RGBf(1, 0.2, 0))
        _lines = lines!(scene, [pos, pos], color=color)
        new(pos, dir, v, t, _lines)
    end
end

function draw!(track::Track, t)
    if t < track.t
        track._lines[1] = [track.pos, track.pos]
        return track
    end
    endpos =  track.pos + track.v * track.dir * (t - track.t) / 1e9
    track._lines[1] = [track.pos, endpos]
    track
end


@kwdef mutable struct RBA
    detector::Detector
    rootfile::Union{ROOTFile, Nothing} = nothing
    scene::Scene = Scene(backgroundcolor=RGBf(0.9))
    cam::Makie.Camera3D = cam3d!(scene, rotation_center = :lookat)
    infobox::GLMakie.Text = text!(GLMakie.campixel(scene), Point2f(10, 10), fontsize=12, text = "", color=RGBf(0.2, 0.2, 0.2))
    tracks::Vector{Track} = Track[]
    hits::Vector{XCalibratedHit} = XCalibratedHit[]
    hits_meshes::Vector{GLMakie.Makie.MeshScatter{Tuple{Vector{GeometryBasics.Point{3, Float32}}}}} = []
    hits_mesh_descriptions::Vector{String} = []
end
Base.show(io::IO, rba::RBA) = print(io, "RainbowAlga event display.")

function RBA(detector::Detector; kwargs...)
    rba = RBA(detector=detector; kwargs...)
    # TODO: this needs some rework
    update!(rba.scene, detector)
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
    start_eventloop(rba)
end

# const rba = RBA(detector=Detector(joinpath(@__DIR__, "assets", "km3net_jul13_90m_r1494_corrected.detx")))


function update!(rba::RBA, hits::Vector{XCalibratedHit})
    positions = generate_hit_positions(hits)

    if length(triggered(hits)) == 0
        t_min, t_max = extrema(h.t for h ∈ hits)
    else
        t_min, t_max = extrema(h.t for h ∈ triggered(hits))
    end
    Δt = t_max - t_min
    simparams.t_offset = t_min
    simparams.loop_end_frame_idx = Int(ceil(Δt))

    rba.hits = hits

    for colorscheme in (:hawaii, :managua, :roma)
        cmap = getproperty(ColorSchemes, colorscheme)
        hits_mesh = meshscatter!(
            rba.scene,
            positions,
            color = [cmap[(h.t - simparams.t_offset) / Δt] for h ∈ hits],
            markersize = [0 for _ ∈ hits],
            alpha = 0.5,
        )

        push!(rba.hits_meshes, hits_mesh)
        push!(rba.hits_mesh_descriptions, string(colorscheme))
    end
end

function update!(rba::RBA, track::Track, hits::Vector{XCalibratedHit}, particle_name::AbstractString, track_id::Int)
    positions = generate_hit_positions(hits)

    cherenkov_photons = cherenkov(track, hits)


    cherenkov_hits_mesh = meshscatter!(
        rba.scene,
        positions,
        color = [reverse(ColorSchemes.redblue)[abs(c.Δt / 50.0)] for c in cherenkov_photons],
        markersize = [0 for _ ∈ hits],
        alpha = 0.5,
    )

    push!(rba.hits_meshes, cherenkov_hits_mesh)
    push!(rba.hits_mesh_descriptions, "Cherenkov wrt. track #$(track_id) ($particle_name)")
    rba
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

"""

Generate hit positions for each hit, stacking them on top of each other along the PMT axis
when the same PMT is hit multiple times.

"""
function generate_hit_positions(hits)
    pmt_map = Dict{Tuple{Int, Int, Int}, Int}()
    pos = Point3f[]
    for hit ∈ hits
        loc = (hit.string, hit.floor, hit.channel_id)
        if !(loc ∈ keys(pmt_map))
            pmt_map[loc] = 0
        else
            pmt_map[loc] += 1
        end
        i = pmt_map[loc]
        push!(pos, Point3f(hit.pos + hit.dir*5 + hit.dir/2*i))
    end
    pos
end

function update!(scene::Scene, det::Detector)
    det_center = center(det)
    basegrid!(scene; center=Point3f(det_center[1], det_center[2], 0))
    for m ∈ det
        if !isbasemodule(m)
            mesh!(scene, Sphere(Point3f(m.pos), 1.5), color=RGBAf(0.3, 0.3, 0.3, 0.5))
        end
    end
    basemodules = [m for m ∈ det if isbasemodule(m)]
    meshscatter!(
        scene,
        [m.pos for m ∈ basemodules],
        marker=Rect3f(Vec3f(-0.5), Vec3f(0.5)),
        markersize=5,
        color=:black
    )
    for string ∈ det.strings
        modules = filter(m->m.location.string == string, collect(values(det.modules)))
        sort!(modules, by=m->m.location.floor)
        segments = [m.pos for m in modules]
        top_module = modules[end]
        buoy_pos = top_module.pos + Point3f(0, 0, 100)
        push!(segments, buoy_pos)
        lines!(scene, segments; color=:grey, linewidth=1)
        mesh!(scene, Sphere(Point3f(buoy_pos), 7), color=:yellow, alpha=0.3)
    end

    scene
end

"""

Draws a grid on the XY-plane with an optional `center` point, `span`, grid-`spacing` and
styling options.

"""
function basegrid!(scene; center=(0, 0, 0), span=(-500, 500), spacing=50, linewidth=1, color=(:grey, 0.3))
    min, max = span
    center = Point3f(center)
    for q ∈ range(min, max; step=spacing)
        lines!(scene, [Point3f(q, min, 0) + center, Point3f(q, max, 0) + center], color=color, linewidth=linewidth)
        lines!(scene, [Point3f(min, q, 0) + center, Point3f(max, q, 0) + center], color=color, linewidth=linewidth)
    end
    scene
end


"""
Run the RainbowAlga GUI and display the specified event.
"""
function run(detector_fname::AbstractString, event_fname::AbstractString, event_id::Int)
    println("Creating scene.")
    det = Detector(detector_fname)
    rba = RBA(det)
    simparams.frame_idx = 0
    # TODO: this needs some rework
    update!(rba.scene, det)

    println("Loading event data.")
    f = ROOTFile(event_fname)
    if isnothing(f.online)
        error("No online tree found in file, RainbowAlga currently only supports online events.")
    end
    event = f.online.events[event_id]
    chits = calibrate(det, combine(event.snapshot_hits, event.triggered_hits))
    update!(rba, chits)

    if !isnothing(f.offline) && length(f.offline) > 0
        println("Loading MC event with event ID $(event.header.trigger_counter + 1)")
        mc_event = f.offline[event.header.trigger_counter + 1]
        length(mc_event.mc_trks) > 0 && println("MC track information found.")
        for mc_track ∈ mc_event.mc_trks
            !islepton(mc_track.type) && continue

            particle_name = Particle(mc_track.type).name

            println("  found a lepton: $(particle_name)")
            track_t = mc_event.mc_t - (event.header.frame_index - 1) * 100e6
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
    end

    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), center(det), Vec3f(0, 0, 1))


    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    start_eventloop(rba)
end

"""
Generates the text for the infobox on the lower left.
"""
function update_infotext!(rba)
    lines = String[]
    push!(lines, "t = $(simparams.frame_idx) ns (loop=$(simparams.loop_enabled))")
    push!(lines, @sprintf "time offset = %.0f ns" simparams.t_offset)
    push!(lines, @sprintf "ToT cut = %.1f ns" simparams.min_tot)

    # TODO: hits_selector is a counter and does not respect the actual number of hits hits_meshes
    # we need to make sure it does not overflow, but we should make this better upstream
    idx = abs(simparams.hits_selector) % length(rba.hits_meshes) + 1
    push!(lines, "Colour scheme: $(rba.hits_mesh_descriptions[idx])")
    
    rba.infobox.text = join(lines, "\n")
end

function start_eventloop(rba)
    screen = display(GLMakie.Screen(start_renderloop=false, focus_on_show=true, title="RainbowAlga"), rba.scene)
    glw = screen.glscreen
    GLMakie.GLFW.SetWindowPos(glw, displayparams.pos...)
    GLMakie.GLFW.SetWindowSize(glw, displayparams.size...)

    scene = rba.scene

    while isopen(screen)
        frame_start = time()

        if simparams.quit
            simparams.quit = false
            break
        end

        if simparams.loop_enabled && simparams.frame_idx > simparams.loop_end_frame_idx
            simparams.frame_idx = 0
        end


        rotation_enabled() && rotate_cam!(scene, Vec3f(0, 0.001, 0))

        t = simparams.t_offset + simparams.frame_idx

        for (idx, mesh) in enumerate(rba.hits_meshes)
            isselected = idx == (abs(simparams.hits_selector) % length(rba.hits_meshes) + 1)
            # hit_sizes = [isselected && h.tot >= simparams.min_tot && t >= h.t ? simparams.hit_scaling / 5 * √h.tot/4 : 0 for h ∈ rba.hits]
            hit_sizes = [isselected && h.tot >= simparams.min_tot && t >= h.t ? (1+(simparams.hit_scaling/5)) * sqrt(h.tot/255) : 0 for h ∈ rba.hits]
            mesh.markersize = hit_sizes
        end

        for track ∈ rba.tracks
            draw!(track, t)
        end

        update_infotext!(rba)

        GLMakie.pollevents(screen)
        GLMakie.render_frame(screen)

        GLMakie.GLFW.SwapBuffers(GLMakie.to_native(screen))

        if !isstopped()
            simparams.frame_idx += simparams.speed
        end

        yield()

        Δt = time() - frame_start
        sleep_time = 1.0/simparams.fps - Δt
        if sleep_time > 0
            sleep(sleep_time)
        end
    end

    GLMakie.destroy!(screen)
end
