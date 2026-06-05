# Interactive time colorbar.

"""
Set up the colorbar overlay in pixel space. Called once during `start_eventloop`.
"""
function setup_colorbar!(rba::RBA)
    scene = rba.scene
    cpscene = campixel(scene)

    n = 256
    n_ticks_max = 25
    _, win_h_init = displayparams.size
    cb_w = 20
    cb_h = round(Int, win_h_init * 0.55)
    margin_right = 75

    # Reactive position: always centred on the right edge regardless of window size
    viewport = scene.viewport
    cb_x_obs = @lift(width($viewport) - margin_right)
    cb_y_obs = @lift((height($viewport) - cb_h) ÷ 2)

    cbar_colors = Observable(fill(RGBAf(0, 0, 0, 0), 1, n))
    cbar_ticks_text = Observable(fill("", n_ticks_max))
    cbar_tick_positions = Observable(fill(Point2f(0, 0), n_ticks_max))
    cbar_visible = Observable(false)

    x_range = @lift(Float32($cb_x_obs) .. Float32($cb_x_obs + cb_w))
    y_range = @lift(Float32($cb_y_obs) .. Float32($cb_y_obs + cb_h))

    img_plot = image!(cpscene, x_range, y_range, cbar_colors;
                      visible=cbar_visible, interpolate=true)

    ticks_plot = text!(cpscene, cbar_tick_positions;
                       text=cbar_ticks_text,
                       fontsize=10,
                       color=RGBf(0.2, 0.2, 0.2),
                       visible=cbar_visible,
                       align=(:left, :center))

    title_pos = @lift Point2f($cb_x_obs + cb_w / 2, $cb_y_obs + cb_h + 15)
    title_plot = text!(cpscene, title_pos;
                       text="Δt / ns",
                       fontsize=11,
                       color=RGBf(0.2, 0.2, 0.2),
                       visible=cbar_visible,
                       align=(:center, :bottom))

    rba._colorbar["cpscene"] = cpscene
    rba._colorbar["colors"] = cbar_colors
    rba._colorbar["ticks_text"] = cbar_ticks_text
    rba._colorbar["tick_positions"] = cbar_tick_positions
    rba._colorbar["visible"] = cbar_visible
    rba._colorbar["img_plot"] = img_plot
    rba._colorbar["ticks_plot"] = ticks_plot
    rba._colorbar["title_plot"] = title_plot
    rba._colorbar["cb_x"] = cb_x_obs
    rba._colorbar["cb_w"] = cb_w
    rba._colorbar["cb_y"] = cb_y_obs
    rba._colorbar["cb_h"] = cb_h

    # Recompute tick label positions whenever the window is resized
    on(viewport) do _
        update_colorbar!(rba)
    end

    update_colorbar!(rba)
    nothing
end

"""
Update the colorbar to reflect the currently selected hits cloud.
"""
function update_colorbar!(rba::RBA)
    haskey(rba._colorbar, "visible") || return

    if rba.simparams.animation_mode === :summaryslice
        return update_rate_colorbar!(rba)
    end

    cbar_visible = rba._colorbar["visible"]
    cbar_colors = rba._colorbar["colors"]
    cbar_ticks_text = rba._colorbar["ticks_text"]
    cbar_tick_positions = rba._colorbar["tick_positions"]
    cb_x = rba._colorbar["cb_x"][]
    cb_w = rba._colorbar["cb_w"]
    cb_y = rba._colorbar["cb_y"][]
    cb_h = rba._colorbar["cb_h"]

    if isempty(rba.hitsclouds)
        cbar_visible[] = false
        return
    end

    n = size(cbar_colors[], 2)
    n_ticks_max = length(cbar_ticks_text[])

    idx = active_hitscloud_index(rba)
    hitscloud = rba.hitsclouds[idx]

    Δt = Float64(rba.simparams.loop_end_frame_idx)

    # The time colorbar only applies to time-coloured clouds (whose description names a
    # ColorScheme); hide it for Cherenkov clouds or a degenerate (zero) time window.
    cmap = try
        getproperty(ColorSchemes, Symbol(hitscloud.description))
    catch
        cbar_visible[] = false
        return
    end
    if iszero(Δt)
        cbar_visible[] = false
        return
    end

    new_colors = Matrix{RGBAf}(undef, 1, n)
    for i in 1:n
        frac = (i - 1) / (n - 1)
        c = cmap[frac]
        new_colors[1, i] = RGBAf(c.r, c.g, c.b, 1.0)
    end
    cbar_colors[] = new_colors

    tick_interval = if Δt > 2000
        500.0
    elseif Δt > 200
        100.0
    else
        10.0
    end
    # Tick labels are relative to the first hit (cb_t_offset can be negative)
    t_rel_start = rba.simparams.cb_t_offset
    first_tick = ceil(t_rel_start / tick_interval) * tick_interval
    tick_values = collect(first_tick:tick_interval:t_rel_start + Δt)

    tick_x = Float32(cb_x + cb_w + 5)
    new_positions = fill(Point2f(0, 0), n_ticks_max)
    new_texts = fill("", n_ticks_max)
    for (j, tv) in enumerate(tick_values)
        frac = (tv - t_rel_start) / Δt
        new_positions[j] = Point2f(tick_x, cb_y + frac * cb_h)
        new_texts[j] = @sprintf("%.0f", tv)
    end
    cbar_tick_positions[] = new_positions
    cbar_ticks_text[] = new_texts

    cbar_visible[] = true
    nothing
end

# Compact label for a rate in Hz (e.g. "100 kHz", "6.5 kHz", "2.0 MHz"). Sub-kHz steps in
# the kHz range keep one decimal so neighbouring linear ticks do not collapse to one label.
ratelabel(hz) = hz >= 1e6 ? @sprintf("%.1f MHz", hz/1e6) :
                hz >= 1e3 ? (hz/1e3 == round(hz/1e3) ? @sprintf("%.0f kHz", hz/1e3) :
                                                        @sprintf("%.1f kHz", hz/1e3)) :
                @sprintf("%.0f Hz", hz)

# Round tick values inside [lo, hi] on a "nice" 1/2/5 x 10^k step (about `count` ticks), so a
# data-derived linear rate range still gets clean, evenly spaced labels.
function nice_linear_ticks(lo, hi; count=6)
    hi <= lo && return [float(lo)]
    raw = (hi - lo) / (count - 1)
    mag = 10.0^floor(log10(raw))
    norm = raw / mag
    step = (norm < 1.5 ? 1.0 : norm < 3.0 ? 2.0 : norm < 7.0 ? 5.0 : 10.0) * mag
    ticks = Float64[]
    t = ceil(lo / step) * step
    while t <= hi + step * 1e-6
        push!(ticks, t)
        t += step
    end
    ticks
end

"""
Update the colorbar for the summaryslice rate field: map the configured colour scheme over
the rate range on a log or linear scale, with rate (Hz) tick labels. Called from
[`update_colorbar!`](@ref) when the animation mode is `:summaryslice`.
"""
function update_rate_colorbar!(rba::RBA)
    haskey(rba._colorbar, "visible") || return
    cbar_visible = rba._colorbar["visible"]
    d = rba.summaryslices
    if isnothing(d)
        cbar_visible[] = false
        return
    end

    cbar_colors = rba._colorbar["colors"]
    cbar_ticks_text = rba._colorbar["ticks_text"]
    cbar_tick_positions = rba._colorbar["tick_positions"]
    cb_x = rba._colorbar["cb_x"][]
    cb_w = rba._colorbar["cb_w"]
    cb_y = rba._colorbar["cb_y"][]
    cb_h = rba._colorbar["cb_h"]
    title_plot = rba._colorbar["title_plot"]

    n = size(cbar_colors[], 2)
    n_ticks_max = length(cbar_ticks_text[])

    cmap = try
        getproperty(ColorSchemes, d.colorscheme)
    catch
        cbar_visible[] = false
        return
    end

    new_colors = Matrix{RGBAf}(undef, 1, n)
    for i in 1:n
        c = cmap[(i - 1) / (n - 1)]
        new_colors[1, i] = RGBAf(c.r, c.g, c.b, 1.0)
    end
    cbar_colors[] = new_colors
    title_plot.text = d.color_scale === :log ? "rate / Hz (log)" : "rate / Hz"

    sc = active_scale(d)
    rmin, rmax = sc.min, sc.max
    # Log scale: the two endpoints plus every interior power of ten, so the labels track
    # an interactively adjusted range. Linear scale: round "nice" steps for clean labels.
    ticks = if d.color_scale === :log
        decades = [10.0^e for e in ceil(Int, log10(rmin)):floor(Int, log10(rmax))]
        sort(unique([rmin; decades; rmax]))
    else
        nice_linear_ticks(rmin, rmax)
    end
    tick_x = Float32(cb_x + cb_w + 5)
    new_positions = fill(Point2f(0, 0), n_ticks_max)
    new_texts = fill("", n_ticks_max)
    j = 0
    for tv in ticks
        (tv < rmin || tv > rmax) && continue
        j += 1
        j > n_ticks_max && break
        frac = d.color_scale === :log ? (log(tv) - log(rmin)) / (log(rmax) - log(rmin)) :
               (tv - rmin) / (rmax - rmin)
        new_positions[j] = Point2f(tick_x, cb_y + clamp(frac, 0.0, 1.0) * cb_h)
        new_texts[j] = ratelabel(tv)
    end
    cbar_tick_positions[] = new_positions
    cbar_ticks_text[] = new_texts

    cbar_visible[] = true
    nothing
end
