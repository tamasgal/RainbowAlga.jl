doc = """Acoustics event builder.
Usage:
  eventdisplay.jl [options] -D DETX -i ROOTFILE
  eventdisplay.jl -h | --help
  eventdisplay.jl --version
Options:
  -i ROOTFILE  The ROOT file with events.
  -D DETX      The detector description file.
  -e EVENT_ID  The event ID, starting from 1 [default: 1].
  -h --help    Show this screen.
  --version    Show version.
"""
using DocOpt
const args = docopt(doc)
println("Loading backend, this may take a minute...")

using RainbowAlga
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


function main()
    println("Creating scene.")
    scene = Scene(backgroundcolor=RGBf(0.9))
    cmap = ColorSchemes.hawaii

    println("Loading event data.")
    fname = args["-i"]
    f = ROOTFile(fname)
    event_id = 19

    println("Loading detector geometry.")
    det = Detector(args["-D"])
    det_center = center(det)

    @show det_center
    cam = cam3d!(scene, rotation_centre = :lookat) # leave out if you implement your own camera

    event = f.online.events[event_id]
    chits = calibrate(det, event.triggered_hits);

    t_min, t_max = extrema(h.t for h ∈ chits)
    Δt = t_max - t_min

    # Static detector display
    for m ∈ det
        mesh!(scene, Sphere(Point3f(m.pos), 1.5), color=:grey)
    end

    hits_mesh = meshscatter!(
        scene,
        [Point3f(h.pos) for h ∈ chits],
        color = [cmap[(h.t - t_min) / Δt] for h ∈ chits],
        markersize = [0 for _ ∈ chits]
    )


    basegrid!(scene)

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
    end

    while isopen(screen)
        # meshplot.colors = rand(RGBf, 1000)
        # meshplot[1] = 10 .* rand(Point3f, 1000)
        t = t_min + frame_idx
        hit_sizes = [t >= h.t ? √h.tot : 0 for h ∈ chits]
        hits_mesh.markersize = hit_sizes

        for track ∈ tracks
            draw!(track, frame_idx)
        end

        framecounter.text = "t = $frame_idx ns"

        GLMakie.pollevents(screen)
        GLMakie.render_frame(screen)


        GLFW.SwapBuffers(GLMakie.to_native(screen))

        frame_idx += 1
    end
    GLMakie.destroy!(screen)
end

main()
