module RainbowAlga

using KM3io

using GLMakie
using GLFW
using ColorSchemes

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

function generate_hit_positions(hits)
    pmt_map = Dict{Location, Int}()
    pos = Point3f[]
    for hit ∈ hits
        loc = Location(hit.du, hit.floor)
        if !(loc ∈ keys(pmt_map))
            pmt_map[loc] = 0
        else
            pmt_map[loc] += 1
        end
        i = pmt_map[loc]
        push!(pos, Point3f(hit.pos + hit.dir*10 + hit.dir/8*i))
    end
    pos
end

function draw!(scene, det::Detector)
    for m ∈ det
        if !isbasemodule(m)
            mesh!(scene, Sphere(Point3f(m.pos), 1.5), color=:grey)
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
        mesh!(scene, Sphere(Point3f(buoy_pos), 7), color=:yellow)
    end
    scene
end

"""

Draws a grid on the XY-plane with an optional `center` point, `span`, grid-`spacing` and
styling options.

"""
function basegrid!(scene; center=(0, 0, 0), span=(-500, 500), spacing=50, linewidth=1, color=(:grey, 0.5))
    min, max = span
    center = Point3f(center)
    for q ∈ range(min, max; step=spacing)
        lines!(scene, [Point3f(q, min, 0) + center, Point3f(q, max, 0) + center], color=color, linewidth=linewidth)
        lines!(scene, [Point3f(min, q, 0) + center, Point3f(max, q, 0) + center], color=color, linewidht=linewidth)
    end
    scene
end


"""
Only displays the detector.
"""
run(detector_fname::AbstractString) = run(detector_fname, "", 0)

"""
Run the RainbowAlga GUI and display the specified event.
"""
function run(detector_fname::AbstractString, event_fname::AbstractString, event_id::Int)
    println("Creating scene.")
    scene = Scene(backgroundcolor=RGBf(0.9))
    cmap = ColorSchemes.hawaii

    println("Loading detector geometry.")
    det = Detector(detector_fname)
    det_center = center(det)
    basegrid!(scene; center=Point3f(det_center[1], det_center[2], 0))
    draw!(scene, det)

    cam = cam3d!(scene, rotation_center = :lookat) # leave out if you implement your own camera

    tracks = Track[]

    if event_fname != ""
        println("Loading event data.")
        f = ROOTFile(event_fname)

        event = f.online.events[event_id]
        cthits = calibrate(det, event.triggered_hits)
        chits = calibrate(det, event.snapshot_hits)

        t_min, t_max = extrema(h.t for h ∈ cthits)
        Δt = t_max - t_min
        t_offset = t_min
        @show t_offset

        mc_event = f.offline[event.header.trigger_counter + 1]
        for track ∈ [mc_event.mc_trks[1]]
            track_t = mc_event.mc_t - (event.header.frame_index - 1) * 100e6
            @show track_t - t_offset
            push!(tracks, Track(scene, track.pos, track.dir, KM3io.Constants.c, track_t))
            # push!(tracks, Track(scene, track.pos, track.dir, KM3io.Constants.c, 0))
        end

        positions = generate_hit_positions(chits)

        if !isempty(tracks)
            track = tracks[1]
            cherenkov_photons = cherenkov(track, chits)

            cherenkov_hits_mesh = meshscatter!(
                scene,
                positions,
                color = [reverse(ColorSchemes.redblue)[abs(c.Δt / 50.0)] for c in cherenkov_photons],
                markersize = [0 for _ ∈ chits]
            )
        end

        hits_mesh = meshscatter!(
            scene,
            positions,
            #color = [cmap[(h.t - t_offset) / Δt] for h ∈ chits],
            color = [cmap[(h.t - t_offset) / Δt] for h ∈ chits],
            markersize = [0 for _ ∈ chits]
        )

        println("Found $(length(tracks)) tracks.")
    end

    center!(scene)
    update_cam!(scene, cam, Vec3f(1000), det_center)

    screen = display(GLMakie.Screen(start_renderloop=false), scene)

    pix = Makie.campixel(scene)
    frame_idx = 0
    framecounter = text!(pix, Point2f(10, 10), text = "t = $frame_idx ns")

    quit = false
    rotation_enabled = true
    show_cherenkov = false
    speed = 3
    previous_speed = speed

    on(events(scene).keyboardbutton, priority = 20) do event
        if ispressed(scene, Makie.Keyboard.r)
            frame_idx = 0
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.left)
            frame_idx -= 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.right)
            frame_idx += 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.a)
            rotation_enabled = !rotation_enabled
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c)
            show_cherenkov = !show_cherenkov
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.up)
            speed += 1
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.down)
            speed -= 1
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.space)
            if speed == 0
                speed = previous_speed
            else
                previous_speed = speed
                speed = 0
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.q)
            quit = true
            return Consume()
        end
    end


    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    while isopen(screen)
        if quit
            quit = false
            break
        end
        # meshplot.colors = rand(RGBf, 1000)
        # meshplot[1] = 10 .* rand(Point3f, 1000)
        rotation_enabled && rotate_cam!(scene, Vec3f(0, 0.001, 0))
        if event_fname != ""
            t = t_offset + frame_idx
            hit_sizes = [show_cherenkov && t >= h.t ? √h.tot/4 : 0 for h ∈ chits]
            cherenkov_hits_mesh.markersize = hit_sizes

            hit_sizes = [!show_cherenkov && t >= h.t ? √h.tot/4 : 0 for h ∈ chits]
            hits_mesh.markersize = hit_sizes

            for track ∈ tracks
                draw!(track, t)
            end

            framecounter.text = "t = $frame_idx ns (offset $t_offset ns)"
        end

        GLMakie.pollevents(screen)
        GLMakie.render_frame(screen)

        GLFW.SwapBuffers(GLMakie.to_native(screen))

        frame_idx += speed
    end
    GLMakie.destroy!(screen)
end
end
