# Deterministic monospace font and pixel metrics for the pixel-space overlays.
#
# DejaVuSansMono ships inside Makie's `MakieAssets` artifact, so it is byte-identical on every
# machine and pinned by the Manifest (no system-font lookup, no per-machine substitution). It
# is truly monospaced -- every glyph advances 0.6021 em -- and it covers the Greek and
# sub/superscript glyphs the physics overlays use (e.g. the colorbar's "Delta t"). Because the
# advance width and line height are fixed fractions of the font size, boxes can be sized and
# text columns aligned with plain arithmetic instead of querying per-glyph bounding boxes.

const OVERLAY_FONT_FILE = "DejaVuSansMono.ttf"

"Filesystem path to the bundled monospace overlay font (resolved at runtime from Makie's asset artifact)."
overlayfont() = Makie.assetpath("fonts", OVERLAY_FONT_FILE)

"""
Pixel metrics of the monospace overlay font.

`advance` and `linegap` are the per-em fractions read from the font; they match Makie's own
text layout, where a glyph advances `advance * fontsize` pixels and successive lines step by
`linegap * fontsize` pixels. `fontsize` is the default overlay text size and `char_width` /
`line_height` are the resulting monospace cell in pixels: a block of `cols` x `rows`
characters is exactly `cols * char_width` by `rows * line_height` pixels. Filled in `__init__`
from the actual font face so the numbers stay correct if the font is ever swapped.
"""
Base.@kwdef mutable struct OverlayFont
    fontsize::Float64 = 14.0
    advance::Float64 = 0.6021
    linegap::Float64 = 1.1641
    char_width::Float64 = 0.6021 * 14.0
    line_height::Float64 = 1.1641 * 14.0
end
const OVERLAYFONT = OverlayFont()

# Pixel width of one character / height of one line of the overlay font at an arbitrary size.
cellwidth(fontsize::Real) = OVERLAYFONT.advance * fontsize
cellheight(fontsize::Real) = OVERLAYFONT.linegap * fontsize

function __init__()
    # Measure the actual font face so the metrics stay correct if the font is ever swapped.
    # The defaults above already hold DejaVuSansMono's values, so a loading hiccup is harmless.
    try
        face = Makie.load_font(overlayfont())
        FTA = Makie.FreeTypeAbstraction
        OVERLAYFONT.advance = Float64(FTA.hadvance(FTA.get_extent(face, 'x')))
        OVERLAYFONT.linegap = Float64(face.height / face.units_per_EM)
    catch err
        @warn "Could not measure the overlay font; using default monospace metrics." exception = err
    end
    OVERLAYFONT.char_width = OVERLAYFONT.advance * OVERLAYFONT.fontsize
    OVERLAYFONT.line_height = OVERLAYFONT.linegap * OVERLAYFONT.fontsize
    nothing
end
