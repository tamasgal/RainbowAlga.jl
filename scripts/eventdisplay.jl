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
    event_id = 1
    # pos_x = f["E/Evt/trks/trks.pos.x"][event_id]
    # pos_y = f["E/Evt/trks/trks.pos.y"][event_id]
    # pos_z = f["E/Evt/trks/trks.pos.z"][event_id]
    # track_positions = [Point3f(pos_x[i], pos_y[i], pos_z[i]) for i ∈ length(pos_x)]
    # dir_x = f["E/Evt/trks/trks.dir.x"][event_id]
    # dir_y = f["E/Evt/trks/trks.dir.y"][event_id]
    # dir_z = f["E/Evt/trks/trks.dir.z"][event_id]
    # track_directions = [Point3f(dir_x[i], dir_y[i], dir_z[i]) for i ∈ length(dir_x)]

    println("Loading detector geometry.")
    det = Detector(args["-D"])
    # detector = meshscatter!(scene, [mod.pos for mod ∈ det], color=RGBf(0, 0, 1), markersize = [Vec3f(10) for mod ∈ det])
    det_center = center(det)

    @show det_center
    cam = cam3d!(scene, rotation_centre = det_center) # leave out if you implement your own camera
    update_cam!(scene, cameracontrols(scene), Vec3f(1000), det_center)

    # pos = 10 .* rand(Point3f, 1000)
    # colors = rand(RGBf, 1000)
    # scales = 0.2 .* [Vec3f(0.5) .+ v for v in rand(Vec3f, 1000)]
    # meshplot = meshscatter!(scene, pos, color = colors, markersize = scales)

    mesh!(scene, Sphere(Point3f(0), 100.0), color=:black)
    mesh!(scene, Sphere(Point3f(det_center), 100.0), color=:red)

    event = f.online.events[event_id]
    chits = calibrate(det, event.triggered_hits);

    t_min, t_max = extrema(h.t for h ∈ chits)
    Δt = t_max - t_min

    for m ∈ det
        mesh!(scene, Sphere(Point3f(m.pos), 1.5), color=:grey)
    end

    for hit ∈ chits
        color = (hit.t - t_min) / Δt
        mesh!(scene, Sphere(Point3f(hit.pos), √hit.tot), color=cmap[color])
    end


    basegrid!(scene)
    # lines!(scene, [Point3f(0), Point3f(0, 0, 10)])  # centre pole, just for reference

    tracks = Track[]
    # for track ∈ f.offline[event.header.trigger_counter + 1].mc_trks
    #     push!(tracks, Track(scene, track.pos, track.dir, 300000000.0, 0.0))
    # end
    # println("Found $(length(tracks)) tracks.")

    center!(scene)

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
        # meshplot.markersize = 0.2 .* [Vec3f(0.5) .+ v for v in rand(Vec3f, 1000)]
        # meshplot[1] = 10 .* rand(Point3f, 1000)

        for track ∈ tracks
            draw!(track, frame_idx / 10.0)
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
