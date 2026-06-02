# GUI: infobox, render loop and screen/recording setup.

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
    push!(lines, "Press H for keybindings")

    rba.infobox.text = join(lines, "\n")
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
    setup_help_overlay!(rba)

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

