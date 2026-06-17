# GUI: infobox, render loop and screen/recording setup.

"""
Generates the text for the infobox on the lower left.
"""
function update_infotext!(rba)
    if !rba.simparams.show_infobox
        rba.infobox.text = ""
        return
    end

    if rba.simparams.animation_mode === :summaryslice && !isnothing(rba.summaryslices)
        rba.infobox.text = summaryslice_infotext(rba)
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
        push!(lines, "$(idx_str)frame=$(rba.current_frame_index)  TC=$(rba.current_trigger_counter)  [N/Shift+N: next/prev, S/Shift+S: selected, E: #, F: frame/TC]")
        if !isnothing(eventselector(rba.eventfile))
            verdict = get(rba._selection_verdicts, rba.current_event_idx, nothing)
            status = isnothing(verdict) ? "?" : (verdict ? "selected" : "rejected")
            push!(lines, "Selector: $(length(rba.selected_events)) matched so far  current: $(status)")
        end
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

"""
Infobox text for the summaryslice mode: the slice ordinal, hardware frame index, UTC time
and per-slice activity, plus the current display-option states.
"""
function summaryslice_infotext(rba)
    d = rba.summaryslices
    sp = rba.simparams
    lines = String[]
    push!(lines, "slice $(d.current_index) / $(nslices(d.file))   frame_index = $(d.current_frame_index)")
    push!(lines, "UTC $(d.current_utc)   (100 ms per slice, loop=$(sp.loop_enabled))")
    push!(lines, "active DOMs = $(d.n_active)   HRV PMTs = $(d.n_hrv)   speed = $(sp.speed) slice/tick")
    push!(lines, @sprintf "Position: x=%.1f y=%.1f z=%1.f" get_current_cam_position()...)
    push!(lines, @sprintf "Target: x=%.1f y=%.1f z=%1.f" get_current_cam_target()...)
    push!(lines, "granularity=$(d.granularity)  scale=$(d.color_scale)  size=$(d.size_mode)  " *
                 "HRV=$(d.show_hrv ? "on" : "off")  FIFO=$(d.show_fifo ? "on" : "off")  " *
                 "no-data=$(d.hide_nodata ? "hidden" : "dimmed")  cmap=$(d.colorscheme)  " *
                 "smoothing=$(d.smoothing ? "$(d.smoothing_window) slices" : "off")")
    push!(lines, "[Space play, </> step, G gran, K log/lin, R size, U HRV, I FIFO, Y no-data, C cmap, S smooth, [ ] window]")
    push!(lines, "Press H for keybindings")
    join(lines, "\n")
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
    setup_hover_overlay!(rba)
    register_hover_events(rba)

    recording_task = @async fps_renderloop(screen, recorder)

    on(screen.render_tick) do tick
        # Keep the render loop paced at the requested FPS; picks up live setfps! changes.
        if screen.config.framerate != rba.simparams.fps
            screen.config.framerate = rba.simparams.fps
            Makie.reset!(screen.timer, 1.0 / rba.simparams.fps)
        end

        advance_and_draw!(rba, scene)
    end
    if !interactive
        wait(screen)
        wait(recording_task)
    end
end

"""
One animation step driven by the render tick. In the default `:time` mode it reveals hits
and moves tracks at `t = t_offset + frame_idx` (ns); in `:summaryslice` mode `frame_idx` is
the slice ordinal and the rate field for that slice is painted instead.
"""
function advance_and_draw!(rba, scene)
    sp = rba.simparams
    if sp.animation_mode === :summaryslice
        if sp.loop_enabled && sp.frame_idx > sp.loop_end_frame_idx
            sp.frame_idx = 0
        elseif sp.frame_idx < 0
            sp.frame_idx = sp.loop_enabled ? sp.loop_end_frame_idx : 0
        end
        rotation_enabled(rba) && rotate_cam!(scene, Vec3f(0, 0.001, 0))
        apply_slice!(rba, sp.frame_idx)
        update_infotext!(rba)
        if !isstopped(rba)
            sp.frame_idx += sp.speed
        end
    else
        if sp.loop_enabled && sp.frame_idx > sp.loop_end_frame_idx
            sp.frame_idx = 0
        end
        rotation_enabled(rba) && rotate_cam!(scene, Vec3f(0, 0.001, 0))
        # Single shared mesh: reconfigure positions/colours only when the selection
        # changed, then resize markers every tick to animate hits as time advances.
        apply_frame!(rba, sp.t_offset + sp.frame_idx)
        update_infotext!(rba)
        if !isstopped(rba)
            sp.frame_idx += sp.speed
        end
    end
    # Keep the hover tooltip correct when the camera moves on its own (auto-rotation):
    # the module under a stationary cursor changes without a mouse-move event.
    refresh_hover!(rba)
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

