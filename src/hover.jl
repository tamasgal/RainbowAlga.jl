# Hover tooltip: show the DU / floor / DOM id of the optical module under the mouse.

"""
    setup_hover_overlay!(rba)

Create the (initially hidden) hover tooltip in pixel space: a small background panel plus a
text label that follow the mouse and report the detection unit (DU), floor and DOM id of the
optical module underneath the cursor. Updated by [`update_hover!`](@ref) from the mouse-move
handler registered in [`register_hover_events`](@ref).
"""
function setup_hover_overlay!(rba::RBA)
    scene = rba.scene
    cpscene = campixel(scene)

    visible = Observable(false)
    box = Observable(Rect2f(0, 0, 1, 1))
    textpos = Observable(Point2f(0, 0))
    label = Observable("")

    poly!(cpscene, box;
          color = RGBAf(0.05, 0.05, 0.08, 0.85),
          strokecolor = RGBAf(1.0, 1.0, 1.0, 0.35), strokewidth = 1.0, visible = visible)
    text!(cpscene, textpos;
          text = label, font = overlayfont(), fontsize = OVERLAYFONT.fontsize,
          align = (:left, :top), color = RGBAf(0.95, 0.95, 0.95, 1.0), visible = visible)

    rba._plots["hover_visible"] = visible
    rba._plots["hover_box"] = box
    rba._plots["hover_textpos"] = textpos
    rba._plots["hover_text"] = label
    nothing
end

# Squared-distance nearest optical module to a 3D point. Used to map a picked rate marker
# (which sits on a PMT/DOM, at most ~2 m from the module centre, far below the DOM spacing)
# back to its module.
function nearest_module(modules, pos)
    best = nothing
    best_d = Inf
    px, py, pz = Float64(pos[1]), Float64(pos[2]), Float64(pos[3])
    for m in modules
        dx = Float64(m.pos.x) - px
        dy = Float64(m.pos.y) - py
        dz = Float64(m.pos.z) - pz
        d = dx*dx + dy*dy + dz*dz
        if d < best_d
            best_d = d
            best = m
        end
    end
    best
end

"""
    module_under_cursor(rba) -> DetectorModule or nothing

Return the optical module currently under the mouse, or `nothing` if the cursor is not over
one. Picks the topmost plot at the cursor: the grey DOM geometry markers map directly to the
canonical module order (`_plots["modules"]`), and the summaryslice rate markers map by
nearest module. Other plots (hit markers, tracks, ...) yield `nothing`.
"""
function module_under_cursor(rba::RBA)
    modules = get(rba._plots, "modules", nothing)
    modules === nothing && return nothing
    plt, idx = pick(rba.scene)
    plt === nothing && return nothing
    if plt === get(rba._plots, "dom_plot", nothing)
        return (1 <= idx <= length(modules)) ? modules[idx] : nothing
    elseif plt === rba.rate_mesh
        positions = rba.rate_mesh.positions[]
        (1 <= idx <= length(positions)) || return nothing
        return nearest_module(modules, positions[idx])
    end
    return nothing
end

"""
    update_hover!(rba, mousepos)

Refresh the hover tooltip for the current `mousepos` (campixel coordinates: origin
bottom-left, y up -- the same convention as `events(scene).mouseposition`). Shows the module
info beside the cursor, or hides the tooltip when no module is under it.
"""
function update_hover!(rba::RBA, mousepos)
    haskey(rba._plots, "hover_visible") || return
    visible = rba._plots["hover_visible"]

    m = module_under_cursor(rba)
    if m === nothing
        visible[] = false
        return
    end

    lines = ["DU $(m.location.string)", "Floor $(m.location.floor)", "DOM $(m.id)"]
    txt = join(lines, "\n")

    # Monospace metrics make the box exactly fit the text: width = columns * char_width,
    # height = rows * line_height (plus padding), with no per-glyph measuring.
    pad = 7
    w = round(Int, 2pad + OVERLAYFONT.char_width * maximum(length, lines))
    h = round(Int, 2pad + OVERLAYFONT.line_height * length(lines))

    win_w, win_h = widths(rba.scene.viewport[])
    cx = Float64(mousepos[1])
    cy = Float64(mousepos[2])

    # Default to the right of and slightly below the cursor; flip left near the right edge.
    ox = cx + 18
    ox + w > win_w - 4 && (ox = cx - 18 - w)
    oy = cy + 6 - h
    ox = clamp(ox, 4, max(4, win_w - w - 4))
    oy = clamp(oy, 4, max(4, win_h - h - 4))

    rba._plots["hover_box"][] = Rect2f(ox, oy, w, h)
    rba._plots["hover_textpos"][] = Point2f(ox + pad, oy + h - pad)
    rba._plots["hover_text"][] = txt
    visible[] = true
    nothing
end

"""
    refresh_hover!(rba)

Re-evaluate the hover tooltip against the current camera using the last known cursor position.
The mouse-move handler keeps the tooltip correct while the cursor moves, but when the camera
moves on its own (auto-rotation) the module under a stationary cursor changes without a mouse
event, so this is called from the render loop to keep the tooltip honest. Skipped when the
cursor is outside the window and when nothing would change (no rotation and no visible
tooltip) to avoid a per-frame pick readback while idle.
"""
function refresh_hover!(rba::RBA)
    haskey(rba._plots, "hover_visible") || return
    scene = rba.scene
    events(scene).entered_window[] || return
    (rotation_enabled(rba) || rba._plots["hover_visible"][]) || return
    update_hover!(rba, events(scene).mouseposition[])
    nothing
end

"""
    register_hover_events(rba)

Register the mouse-move handler that drives the hover tooltip, plus a handler that clears the
tooltip when the cursor leaves the window. Neither consumes the event, so the camera controls
keep working.
"""
function register_hover_events(rba::RBA)
    scene = rba.scene
    on(events(scene).mouseposition) do mp
        update_hover!(rba, mp)
        return Consume(false)
    end
    on(events(scene).entered_window) do inside
        inside || (rba._plots["hover_visible"][] = false)
        return Consume(false)
    end
    nothing
end
