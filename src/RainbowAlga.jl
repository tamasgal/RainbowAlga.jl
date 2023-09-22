module RainbowAlga

using KM3io

using GLMakie
using GLFW
using ColorSchemes

struct Track
    pos
    dir
    v
    t₀
    _lines

    function Track(scene, pos, dir, v, t₀)
        _lines = lines!(scene, [pos, pos], color=RGBf(1, 0.2, 0))
        new(pos, dir, v, t₀, _lines)
    end
end

function draw!(track::Track, t)
    endpos =  track.pos + track.v * track.dir * (track.t₀ + t)*1e-9
    track._lines[1] = [track.pos, endpos]
    nothing
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
    floors = 18  # TODO: implement floor field in KM3io.jl
    for string ∈ det.strings
        segments = [det.locations[(string, floor)].pos for floor ∈ 0:floors]
        top_module = det.locations[(string, floors)]
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


function run(fname, detx)
    println("Creating scene.")
    scene = Scene(backgroundcolor=RGBf(0.9))
    cmap = ColorSchemes.hawaii

    println("Loading event data.")
    f = ROOTFile(fname)
    event_id = 19

    println("Loading detector geometry.")
    det = Detector(detx)
    det_center = center(det)

    @show det_center
    cam = cam3d!(scene, rotation_center = :lookat) # leave out if you implement your own camera

    event = f.online.events[event_id]
    cthits = calibrate(det, event.triggered_hits)
    chits = calibrate(det, event.snapshot_hits)

    t_min, t_max = extrema(h.t for h ∈ cthits)
    Δt = t_max - t_min

    draw!(scene, det)

    pos = generate_hit_positions(chits)
    hits_mesh = meshscatter!(
        scene,
        pos,
        color = [cmap[(h.t - t_min) / Δt] for h ∈ chits],
        markersize = [0 for _ ∈ chits]
    )


    basegrid!(scene; center=Point3f(det_center[1], det_center[2], 0))

    tracks = Track[]
    for track ∈ f.offline[event.header.trigger_counter + 1].mc_trks
        push!(tracks, Track(scene, track.pos, track.dir, 300000000.0, 0.0))
    end
    println("Found $(length(tracks)) tracks.")

    center!(scene)
    update_cam!(scene, cam, Vec3f(1000), det_center)

    screen = display(GLMakie.Screen(start_renderloop=false), scene)

    pix = Makie.campixel(scene)
    frame_idx = 0
    framecounter = text!(pix, Point2f(10, 10), text = "t = 0 ns")

    on(events(scene).keyboardbutton, priority = 20) do event
        if event.key == Makie.Keyboard.r
            frame_idx = 0
            return Consume()
        end
        if event.key == Makie.Keyboard.left
            frame_idx -= 100
            return Consume()
        end
        if event.key == Makie.Keyboard.right
            frame_idx += 100
            return Consume()
        end
    end


    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    while isopen(screen)
        # meshplot.colors = rand(RGBf, 1000)
        # meshplot[1] = 10 .* rand(Point3f, 1000)
        rotate_cam!(scene, Vec3f(0, 0.001, 0))
        t = t_min + frame_idx
        hit_sizes = [t >= h.t ? √h.tot/4 : 0 for h ∈ chits]
        hits_mesh.markersize = hit_sizes

        for track ∈ tracks
            draw!(track, frame_idx)
        end

        framecounter.text = "t = $frame_idx ns"

        GLMakie.pollevents(screen)
        GLMakie.render_frame(screen)

        GLFW.SwapBuffers(GLMakie.to_native(screen))

        frame_idx += 3
    end
    GLMakie.destroy!(screen)
end
end
