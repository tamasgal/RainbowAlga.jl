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
    linepts = Observable([Point2f(0, 0), Point2f(0, 0)])

    # Leader line from the tooltip box to the exact projected centre of the hovered module.
    # A polyline writes pick ids only along its thin stroke (no fill), so it does not block
    # picking the DOM it points at.
    leader = lines!(cpscene, linepts;
          color = RGBAf(1.0, 0.8, 0.1, 0.95), linewidth = 2, visible = visible)
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
    rba._plots["hover_line"] = leader
    rba._plots["hover_linepts"] = linepts
    rba._plots["hover_module"] = nothing
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
canonical module order (`_plots["modules"]`); a hit marker maps to the module its hit belongs
to (so a DOM buried under its own hit blob is still selectable); and the summaryslice rate
markers map by nearest module. Other plots (tracks, ...) yield `nothing`.
"""
function module_under_cursor(rba::RBA)
    modules = get(rba._plots, "modules", nothing)
    modules === nothing && return nothing
    plt, idx = pick(rba.scene)
    plt === nothing && return nothing
    if plt === get(rba._plots, "dom_plot", nothing)
        return (1 <= idx <= length(modules)) ? modules[idx] : nothing
    elseif plt === rba.hits_mesh
        # Hovering a hit blob resolves to the module the picked hit belongs to, so DOMs hidden
        # behind their own hits stay selectable (the pick buffer keeps only the front hit).
        ci = rba.simparams.displayed_hitscloud
        (1 <= ci <= length(rba.hitsclouds)) || return nothing
        dom_ids = rba.hitsclouds[ci].dom_ids
        (1 <= idx <= length(dom_ids)) || return nothing
        dom_by_id = get(rba._plots, "dom_by_id", nothing)
        dom_by_id === nothing && return nothing
        return get(dom_by_id, dom_ids[idx], nothing)
    elseif plt === rba.rate_mesh
        positions = rba.rate_mesh.positions[]
        (1 <= idx <= length(positions)) || return nothing
        return nearest_module(modules, positions[idx])
    elseif plt === get(rba._plots, "hover_line", nothing)
        # The cursor is on the leader line of the currently hovered module; keep it so the
        # tooltip does not flicker as the cursor grazes the stroke.
        return get(rba._plots, "hover_module", nothing)
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
        rba._plots["hover_module"] = nothing
        visible[] = false
        return
    end
    rba._plots["hover_module"] = m

    scene = rba.scene
    # DOM centre projected to screen pixels (same space as campixel and the cursor).
    domcenter = Point2f(Makie.project(scene, Point3f(m.pos)))

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
    # Leader line: from the middle of the box's left side to the DOM centre exactly. When the
    # box is flipped to the left of the cursor (near the right window edge) the DOM is on the
    # box's right, so attach to the right side instead to avoid crossing the box.
    anchor_x = domcenter[1] < ox + w / 2 ? Float64(ox) : Float64(ox + w)
    anchor = Point2f(anchor_x, oy + h / 2)
    rba._plots["hover_linepts"][] = [anchor, domcenter]
    visible[] = true
    nothing
end

"""
    refresh_hover!(rba)

Re-evaluate the hover tooltip and leader line against the current camera using the last known
cursor position. The mouse-move handler keeps them correct while the cursor moves, but when the camera
moves on its own (auto-rotation) the module under a stationary cursor changes without a mouse
event, so this is called from the render loop to re-pick and re-project. Skipped when nothing
would change (no rotation and no visible tooltip) to avoid a per-frame pick readback while idle.
A cursor outside the window needs no special case: `pick` returns nothing for an out-of-bounds
position, so `update_hover!` simply hides the tooltip.
"""
function refresh_hover!(rba::RBA)
    haskey(rba._plots, "hover_visible") || return
    (rotation_enabled(rba) || rba._plots["hover_visible"][]) || return
    update_hover!(rba, events(rba.scene).mouseposition[])
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
