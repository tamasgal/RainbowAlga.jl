# Keybindings help overlay (toggled with the H key).

"""
All interactive keybindings as (key, action) pairs. This is the single source of truth
for the help overlay; keep it in sync with the handlers in `register_events`.
"""
const KEYBINDINGS = [
    ("Space",        "play / pause"),
    ("0",            "reset to the start"),
    ("Left / Right", "step time / slice backward / forward"),
    ("Up / Down",    "increase / decrease speed"),
    (", / .",        "lower / raise the ToT cut"),
    ("- / =",        "smaller / larger markers"),
    ("c / Shift+c",  "next / previous colouring (colormap in slices)"),
    ("l",            "toggle the time loop"),
    ("o",            "toggle auto-rotation"),
    ("b",            "toggle dark mode"),
    ("x",            "toggle the info box"),
    ("1 - 9",        "load camera perspective 1-9"),
    ("Shift+1 - 9",  "save camera perspective 1-9"),
    ("p",            "save a screenshot (PNG)"),
    ("v",            "start / stop video recording"),
    ("n / Shift+n",  "next / previous event"),
    ("e",            "jump to an event by index"),
    ("f",            "jump by frame index / trigger counter"),
    ("g",            "PMT / DOM granularity (slices)"),
    ("k",            "log / linear rate scale (slices)"),
    ("r",            "fixed / rate-scaled size (slices)"),
    ("u",            "toggle HRV highlight (slices)"),
    ("i",            "toggle FIFO highlight (slices)"),
    ("y",            "hide / dim no-data DOMs (slices)"),
    ("s",            "toggle rate smoothing (slices)"),
    ("[ / ]",        "shorten / lengthen smoothing window (slices)"),
    ("h",            "toggle this help"),
]

"""
    setup_help_overlay!(rba)

Create the (initially hidden) keybindings overlay in pixel space, centred on the window.
Toggle its visibility with `toggle_help` (bound to the H key).
"""
function setup_help_overlay!(rba::RBA)
    scene = rba.scene
    cpscene = campixel(scene)
    viewport = scene.viewport

    keys_str    = join(first.(KEYBINDINGS), "\n")
    actions_str = join(last.(KEYBINDINGS), "\n")

    visible = Observable(false)
    pad = 18
    line_h = 20
    panel_w = 560
    panel_h = (length(KEYBINDINGS) + 3) * line_h + 2pad

    # Bottom-left corner of the panel, kept centred as the window resizes.
    x0 = @lift((width($viewport) - panel_w) ÷ 2)
    y0 = @lift((height($viewport) - panel_h) ÷ 2)

    poly!(cpscene, @lift(Rect2f($x0, $y0, panel_w, panel_h));
          color = RGBAf(0.05, 0.05, 0.08, 0.85),
          strokecolor = RGBAf(1.0, 1.0, 1.0, 0.35), strokewidth = 1.0, visible = visible)

    text!(cpscene, @lift(Point2f($x0 + pad, $y0 + panel_h - pad));
          text = "Keybindings   (press H to close)", fontsize = 16, font = :bold,
          color = :white, align = (:left, :top), visible = visible)

    top = @lift(Point2f($x0 + pad, $y0 + panel_h - pad - 2line_h))
    text!(cpscene, top; text = keys_str, fontsize = 14, align = (:left, :top),
          color = RGBAf(0.55, 0.8, 1.0, 1.0), visible = visible)
    text!(cpscene, @lift($top + Point2f(165, 0)); text = actions_str, fontsize = 14,
          align = (:left, :top), color = RGBAf(0.92, 0.92, 0.92, 1.0), visible = visible)

    text!(cpscene, @lift(Point2f($x0 + pad, $y0 + pad)); align = (:left, :bottom),
          text = "n, e, f need an event file; g, k, r, u, i, y apply in summaryslice mode.", fontsize = 12,
          color = RGBAf(0.7, 0.7, 0.7, 1.0), visible = visible)

    rba._plots["help_visible"] = visible
    nothing
end

"""
Show or hide the keybindings overlay.
"""
function toggle_help(rba::RBA)
    haskey(rba._plots, "help_visible") || return
    v = rba._plots["help_visible"]
    v[] = !v[]
    nothing
end
