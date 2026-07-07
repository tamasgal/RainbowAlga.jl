# GUI: infobox, render loop and screen/recording setup.

# Every `print_status` line starts with an ASCII prefix whose colour advances one step along a
# fixed rainbow gradient (and wraps around)
# 256-colour ANSI index (the 6x6x6 colour cube, 16..231) nearest to a saturated rainbow hue.
_ansi256_rainbow(fraction) = let c = convert(RGB, HSV(360 * fraction, 1.0, 1.0))
    16 + 36 * round(Int, c.r * 5) + 6 * round(Int, c.g * 5) + round(Int, c.b * 5)
end

const STATUS_RAINBOW = let raw = [_ansi256_rainbow((i - 1) / 36) for i in 1:36], uniq = Int[]
    for c in raw
        (isempty(uniq) || uniq[end] != c) && push!(uniq, c)
    end
    length(uniq) > 1 && uniq[end] == uniq[1] && pop!(uniq)  # avoid a wrap-around duplicate
    uniq
end
const STATUS_PREFIX = ">>>"
const STATUS_COLOR_IDX = Ref(0)  # walks STATUS_RAINBOW, wrapping around

"""
Print a startup/status line immediately (flushing `stdout`) so the user sees what `run` is doing
during its several-seconds-long steps -- reading files, drawing the detector geometry,
calibrating the first event, and compiling shaders when the window first opens -- instead of
staring at a seemingly frozen terminal. The line is prefixed with an ASCII marker (`>>>`) tinted
in a rainbow colour that advances one step per call, cycling through the fixed [`STATUS_RAINBOW`]
gradient. `printstyled` only emits the colour codes when `stdout` is colour-capable, so piped or
redirected output stays clean.
"""
function print_status(msg::AbstractString)
    color = STATUS_RAINBOW[STATUS_COLOR_IDX[] % length(STATUS_RAINBOW) + 1]
    STATUS_COLOR_IDX[] += 1
    printstyled(STATUS_PREFIX; color = color, bold = true)
    println(" ", msg)
    flush(stdout)
    nothing
end

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

"""
    setup_search_overlay!(rba)

Create the (initially hidden) "Searching..." overlay, centred on the window in pixel space.
It is shown by [`request_search!`](@ref) for the frame before the potentially slow selector
scan (S / Shift+S) runs, so the window does not look frozen while the selector walks the file.
"""
function setup_search_overlay!(rba::RBA)
    scene = rba.scene
    cpscene = campixel(scene)
    viewport = scene.viewport

    visible = Observable(false)
    label = "Searching..."
    fontsize = 26
    pad = 22
    panel_w = round(Int, length(label) * cellwidth(fontsize) + 2pad)
    panel_h = round(Int, cellheight(fontsize) + 2pad)

    # Bottom-left corner of the panel, kept centred as the window resizes.
    x0 = @lift(round(Int, (width($viewport) - panel_w) / 2))
    y0 = @lift(round(Int, (height($viewport) - panel_h) / 2))

    poly!(cpscene, @lift(Rect2f($x0, $y0, panel_w, panel_h));
          color = RGBAf(0.25, 0.25, 0.27, 0.82),
          strokecolor = RGBAf(0.7, 0.7, 0.72, 0.4), strokewidth = 1.0, visible = visible)
    text!(cpscene, @lift(Point2f($x0 + panel_w / 2, $y0 + panel_h / 2));
          text = label, font = overlayfont(), fontsize = fontsize,
          align = (:center, :center), color = RGBAf(0.9, 0.9, 0.92, 0.95), visible = visible)

    rba._plots["searching_visible"] = visible
    nothing
end

"Show or hide the centred \"Searching...\" overlay (no-op if it was never set up)."
function set_searching!(rba::RBA, on::Bool)
    haskey(rba._plots, "searching_visible") || return
    rba._plots["searching_visible"][] = on
    nothing
end

"""
    step_pending_search!(rba)

Advance a deferred selector search (queued by [`request_search!`](@ref)) by one render tick.
On the first tick after a request it only bumps the wait counter so the "Searching..." overlay
gets one fully rendered frame; on the next tick it runs the blocking selector scan and hides
the overlay. No-op when no search is pending.
"""
function step_pending_search!(rba::RBA)
    sp = rba.simparams
    sp.pending_search === :none && return
    if sp.search_frames_waited >= 1
        dir = sp.pending_search
        sp.pending_search = :none
        sp.search_frames_waited = 0
        # A bad event  must not kill the render loop or leave the overlay stuck on screen:
        # catch and warn, and always hide the overlay in `finally`, otherwise the window would
        # look exactly as "crashed" as this feature is meant to avoid.
        # The selector itself is accepted on the raw event, so an
        # accepted event can still throw when its hits are calibrated on load.
        try
            dir === :previous ? previous_selected_event!(rba) : next_selected_event!(rba)
        catch e
            @warn "Selector search failed to load an event" exception = (e, catch_backtrace())
        finally
            set_searching!(rba, false)
        end
    else
        sp.search_frames_waited += 1
    end
    nothing
end

function start_eventloop(rba; interactive=true)
    print_status("Opening the window (the first launch can take several seconds while OpenGL shaders compile) ...")
    screen = display(GLMakie.Screen(start_renderloop=false, focus_on_show=true, title="RainbowAlga", framerate=rba.simparams.fps), rba.scene)
    glw = screen.glscreen
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

    print_status("Setting up controls and overlays ...")
    register_events(rba, screen, recorder)
    setup_colorbar!(rba)
    register_colorbar_events(rba)
    setup_help_overlay!(rba)
    setup_search_overlay!(rba)
    setup_hover_overlay!(rba)
    register_hover_events(rba)

    print_status("RainbowAlga is ready. Press H in the window for the keybindings.")
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
    # This is kind of an annoying addition but I decided to add it because otherwise
    # the user might think RainbowAlga has crashd, yay! Selector search is basically
    # deferred: the keyboard handler runs before this callback within the same `pollevents`,
    # so on the request frame this only bumps the wait counter and lets the frame render
    # the "Searching..." overlay. The blocking selector scan runs on the
    # next tick, while that already-presented frame stays on screen, so the window shows
    # feedback instead of looking frozen. Falls through to the normal draw below either way.
    step_pending_search!(rba)
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

