"""
    register_events(rba::RBA)

Registers keyboard and mouse events for the interactive access.
"""
function register_events(rba::RBA, screen, recorder)
    scene = rba.scene
    on(events(scene).mousebutton) do event
        # if scene.events.hasfocus[]
        #     println("focus")
        #     rba.simparams.fps = 60
        # else
        #     println("no focus")
        #     rba.simparams.fps = 15
        # end
    end
    on(events(scene).keyboardbutton, priority = 20000000) do event
        # Modal event-index input (activated by E key)
        if rba.simparams.event_input_mode
            # Ignore release events to avoid spurious cancellation
            event.action == Keyboard.release && return Consume()
            digit_keys = (
                (Makie.Keyboard._0, "0"), (Makie.Keyboard._1, "1"),
                (Makie.Keyboard._2, "2"), (Makie.Keyboard._3, "3"),
                (Makie.Keyboard._4, "4"), (Makie.Keyboard._5, "5"),
                (Makie.Keyboard._6, "6"), (Makie.Keyboard._7, "7"),
                (Makie.Keyboard._8, "8"), (Makie.Keyboard._9, "9"),
            )
            for (key, digit) in digit_keys
                if ispressed(scene, key)
                    rba.simparams.event_input_buffer *= digit
                    return Consume()
                end
            end
            if ispressed(scene, Makie.Keyboard.backspace)
                if !isempty(rba.simparams.event_input_buffer)
                    rba.simparams.event_input_buffer = rba.simparams.event_input_buffer[1:end-1]
                end
                return Consume()
            end
            if ispressed(scene, Makie.Keyboard.enter)
                if !isempty(rba.simparams.event_input_buffer)
                    idx = parse(Int, rba.simparams.event_input_buffer)
                    rba.simparams.event_input_mode = false
                    rba.simparams.event_input_buffer = ""
                    load_event!(rba, idx)
                else
                    rba.simparams.event_input_mode = false
                end
                return Consume()
            end
            # Any other key cancels input mode
            rba.simparams.event_input_mode = false
            rba.simparams.event_input_buffer = ""
            return Consume()
        end

        # Modal frame_index / trigger_counter input (activated by F key)
        if rba.simparams.frame_tc_input_stage > 0
            event.action == Keyboard.release && return Consume()
            digit_keys = (
                (Makie.Keyboard._0, "0"), (Makie.Keyboard._1, "1"),
                (Makie.Keyboard._2, "2"), (Makie.Keyboard._3, "3"),
                (Makie.Keyboard._4, "4"), (Makie.Keyboard._5, "5"),
                (Makie.Keyboard._6, "6"), (Makie.Keyboard._7, "7"),
                (Makie.Keyboard._8, "8"), (Makie.Keyboard._9, "9"),
            )
            active_buf = rba.simparams.frame_tc_input_stage == 1 ? :frame_index_buffer : :trigger_counter_buffer
            for (key, digit) in digit_keys
                if ispressed(scene, key)
                    setproperty!(rba.simparams, active_buf, getproperty(rba.simparams, active_buf) * digit)
                    return Consume()
                end
            end
            if ispressed(scene, Makie.Keyboard.backspace)
                buf = getproperty(rba.simparams, active_buf)
                if !isempty(buf)
                    setproperty!(rba.simparams, active_buf, buf[1:end-1])
                end
                return Consume()
            end
            if ispressed(scene, Makie.Keyboard.enter)
                if rba.simparams.frame_tc_input_stage == 1
                    if !isempty(rba.simparams.frame_index_buffer)
                        rba.simparams.frame_tc_input_stage = 2
                    else
                        rba.simparams.frame_tc_input_stage = 0
                    end
                else
                    if !isempty(rba.simparams.frame_index_buffer) && !isempty(rba.simparams.trigger_counter_buffer)
                        fi = parse(Int, rba.simparams.frame_index_buffer)
                        tc = parse(Int, rba.simparams.trigger_counter_buffer)
                        rba.simparams.frame_tc_input_stage = 0
                        rba.simparams.frame_index_buffer = ""
                        rba.simparams.trigger_counter_buffer = ""
                        event_obj = getevent(rba.event_file.online, fi, tc)
                        rba.current_event_idx = 0
                        rba.current_frame_index = fi
                        rba.current_trigger_counter = tc
                        chits = calibrate(rba.event_detector, event_obj.snapshot_hits)
                        t_range = if !isempty(event_obj.triggered_hits)
                            tchits = calibrate(rba.event_detector, event_obj.triggered_hits)
                            extrema(h.t for h ∈ tchits)
                        else
                            nothing
                        end
                        clearhits!(rba)
                        add!(rba, chits; t_range=t_range)
                        reset_time(rba)
                        println("Loaded event with frame_index=$fi, trigger_counter=$tc")
                    else
                        rba.simparams.frame_tc_input_stage = 0
                        rba.simparams.frame_index_buffer = ""
                        rba.simparams.trigger_counter_buffer = ""
                    end
                end
                return Consume()
            end
            # Any other key cancels
            rba.simparams.frame_tc_input_stage = 0
            rba.simparams.frame_index_buffer = ""
            rba.simparams.trigger_counter_buffer = ""
            return Consume()
        end

        if ispressed(scene, Makie.Keyboard._0)
            reset_time(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.space)
            rba.simparams.stopped = !rba.simparams.stopped
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.left)
            rba.simparams.loop_enabled = false
            rba.simparams.frame_idx -= 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.right)
            rba.simparams.loop_enabled = false
            rba.simparams.frame_idx += 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.o)
            toggle_rotation(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._1 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._2 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 2)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._3 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 3)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._4 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 4)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._5 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._6 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 6)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._7 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 7)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._8 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 8)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._9 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 9)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._1)
            load_perspective(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._2)
            load_perspective(rba, 2)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._3)
            load_perspective(rba, 3)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._4)
            load_perspective(rba, 4)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._5)
            load_perspective(rba, 5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._6)
            load_perspective(rba, 6)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._7)
            load_perspective(rba, 7)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._8)
            load_perspective(rba, 8)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._9)
            load_perspective(rba, 9)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            previous_hits_colouring(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c)
            next_hits_colouring(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.p)
            fname = "RBA_$(lpad(rba.simparams.screenshot_counter, 3, '0')).png"
            @async save(fname, scene)
            println("Screenshot saved as $(fname)")
            rba.simparams.screenshot_counter += 1
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.v)
            if BACKEND === :webgl
                @warn "Video recording is not supported with the WebGL backend"
            elseif recorder.recording[]
                println("Recording stopped...")
                stop!(recorder)
            else
                if Threads.nthreads() < 2
                    @warn "Cannot record with only one thread, please restart the Julia process with at least two threads (\"julia -t 2\")"
                    return Consume()
                end
                println("Recording started...")
                fname = "RBA_$(lpad(rba.simparams.recording_counter, 3, '0')).mp4"
                start!(recorder; outfname=fname)
                rba.simparams.recording_counter += 1
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.x)
            rba.simparams.show_infobox = !rba.simparams.show_infobox
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.l)
            toggle_loop(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.b)
            if rba.simparams.darkmode_enabled
                scene.backgroundcolor = RGBf(0.9, 0.9, 0.9)
                rba.infobox.color = RGBf(0.1, 0.1, 0.1)
                rba.simparams.darkmode_enabled = false
                if haskey(rba._colorbar, "ticks_plot")
                    rba._colorbar["ticks_plot"].color = RGBf(0.1, 0.1, 0.1)
                    rba._colorbar["title_plot"].color = RGBf(0.1, 0.1, 0.1)
                end
            else
                scene.backgroundcolor = RGBf(0.0, 0.0, 0.1)
                rba.simparams.darkmode_enabled = true
                rba.infobox.color = RGBf(0.9, 0.9, 0.9)
                if haskey(rba._colorbar, "ticks_plot")
                    rba._colorbar["ticks_plot"].color = RGBf(0.9, 0.9, 0.9)
                    rba._colorbar["title_plot"].color = RGBf(0.9, 0.9, 0.9)
                end
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.up)
            faster(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.down)
            slower(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.comma)
            decreasetot(rba, 0.5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.period)
            increasetot(rba, 0.5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.h & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            rba.simparams.hit_scaling += 1
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.h)
            if rba.simparams.hit_scaling > 1
                rba.simparams.hit_scaling -= 1
            end
            return Consume()
        end
        if !isnothing(rba.event_file)
            if ispressed(scene, Makie.Keyboard.n & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
                previous_event!(rba)
                return Consume()
            end
            if ispressed(scene, Makie.Keyboard.n)
                next_event!(rba)
                return Consume()
            end
            if ispressed(scene, Makie.Keyboard.e)
                rba.simparams.event_input_mode = true
                rba.simparams.event_input_buffer = ""
                return Consume()
            end
            if ispressed(scene, Makie.Keyboard.f)
                rba.simparams.frame_tc_input_stage = 1
                rba.simparams.frame_index_buffer = ""
                rba.simparams.trigger_counter_buffer = ""
                return Consume()
            end
        end
    end
end

"""
Register mouse interactions for the colorbar overlay.

- Right-click + drag left/right on the colorbar: shrink/expand the time duration (Δt).
- Right-click + drag up/down on the colorbar: shift the time offset forward/backward.
"""
function register_colorbar_events(rba::RBA)
    isempty(rba._colorbar) && return
    scene = rba.scene

    cb_x_obs = rba._colorbar["cb_x"]
    cb_w = rba._colorbar["cb_w"]
    cb_y_obs = rba._colorbar["cb_y"]
    cb_h = rba._colorbar["cb_h"]
    win_h = displayparams.size[2]

    dragging = Ref(false)
    last_pos = Ref(Point2f(0, 0))
    last_click_time = Ref(0.0)
    double_click_threshold = 0.3  # seconds

    on(events(scene).mousebutton, priority=100) do event
        # events().mouseposition uses window coords: (0,0) top-left, y-down.
        # Flip y to match campixel coords (0,0) bottom-left, y-up.
        mpos = Point2f(events(scene).mouseposition[])
        cp_y = win_h - mpos[2]
        cb_x = cb_x_obs[]; cb_y = cb_y_obs[]
        in_cb = cb_x <= mpos[1] <= cb_x + cb_w + 65 && cb_y <= cp_y <= cb_y + cb_h
        if event.button == Mouse.right
            if event.action == Mouse.press && in_cb
                now = time()
                if now - last_click_time[] < double_click_threshold
                    # Double click: reset to defaults
                    dragging[] = false
                    last_click_time[] = 0.0
                    if haskey(rba._colorbar, "default_loop_end_frame_idx")
                        rba.simparams.cb_t_offset = 0.0
                        rba.simparams.loop_end_frame_idx = rba._colorbar["default_loop_end_frame_idx"]
                        update_colorbar!(rba)
                        recolor_hits_from_simparams!(rba)
                    end
                else
                    last_click_time[] = now
                    dragging[] = true
                    last_pos[] = mpos
                end
                return Consume()
            elseif event.action == Mouse.release && dragging[]
                dragging[] = false
                return Consume()
            end
        end
    end

    on(events(scene).mouseposition, priority=100) do raw_mpos
        !dragging[] && return

        mpos = Point2f(raw_mpos)
        delta = mpos - last_pos[]
        last_pos[] = mpos

        Δt = Float64(rba.simparams.loop_end_frame_idx)

        # Horizontal: right = expand window, left = shrink (proportional to current Δt)
        if abs(delta[1]) > 0
            rba.simparams.loop_end_frame_idx = max(50, round(Int, Δt + delta[1] * Δt / 100.0))
        end

        # Vertical: up (negative GLFW delta) = later in time, down = earlier
        if abs(delta[2]) > 0
            rba.simparams.cb_t_offset -= delta[2] * Δt / cb_h
        end

        update_colorbar!(rba)
        recolor_hits_from_simparams!(rba)
        return Consume()
    end

    nothing
end

# Control functions to steer the 3D simulation
isstopped(rba::RBA) = rba.simparams.stopped
stop(rba::RBA) = rba.simparams.stopped = true
start(rba::RBA) = rba.simparams.stopped = false
reset_time(rba::RBA) = rba.simparams.frame_idx = 0
faster(rba::RBA, n::Int) = rba.simparams.speed += n
slower(rba::RBA, n::Int) = rba.simparams.speed -= n
increasetot(rba::RBA, t::Float64) = rba.simparams.min_tot += t
decreasetot(rba::RBA, t::Float64) = rba.simparams.min_tot -= t
speed(rba::RBA) = rba.simparams.speed
toggle_rotation(rba::RBA) = rba.simparams.rotation_enabled = !global_rba().simparams.rotation_enabled
toggle_loop(rba::RBA) = rba.simparams.loop_enabled = !global_rba().simparams.loop_enabled
rotation_enabled(rba::RBA) = rba.simparams.rotation_enabled
function next_hits_colouring(rba::RBA)
    hidehits!(rba)
    rba.simparams.hits_selector += 1
    update_colorbar!(rba)
end
function previous_hits_colouring(rba::RBA)
    hidehits!(rba)
    rba.simparams.hits_selector -= 1
    update_colorbar!(rba)
end
function hidehits!(rba::RBA)
    for hitscloud in rba.hitsclouds
        n_hits = length(hitscloud.hits)
        hitscloud.mesh.markersize = zeros(n_hits)
    end
end

"""

Set the frames per second for the animation.

"""
function setfps!(rba::RBA, fps::Integer)
    rba.simparams.fps = fps
    nothing
end
setfps!(fps::Integer) = setfps!(global_rba(), fps)

function describe!(rba::RBA, hitscloud_idx::Integer, description::AbstractString)
    rba.hitsclouds[hitscloud_idx].description = description
end
function describe!(hitscloud_idx::Integer, description::AbstractString)
    describe!(global_rba(), hitscloud_idx, description)
end
