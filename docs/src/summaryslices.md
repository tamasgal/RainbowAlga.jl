```@meta
CurrentModule = RainbowAlga
```

# Summaryslices: animating detector rate fields

Besides single events, KM3NeT online ROOT files contain **summaryslices**: a condensed form
of the raw timeslices in which the hit information of each optical module is reduced to one
byte per PMT, encoding that PMT's count rate over a 100 ms window (logarithmically, from
2 kHz to 2 MHz). Each summaryslice carries a `frame_index` (and a UTC timestamp) and holds
one summary frame per active module, with 31 PMT rates plus the high-rate-veto (HRV) and
FIFO status flags.

RainbowAlga can play these back as a **rate field over the whole detector**. This is a
separate animation mode: instead of revealing hits along a nanosecond clock, *play* steps
through the summaryslices (100 ms each) and every frame repaints the per-PMT (or per-DOM)
rates. It is the natural way to watch bioluminescence bursts, ``^{40}``K background, HRV
patterns and overall data quality evolve in space and time.

Every figure below is rendered at documentation build time with [`snapshot`](@ref) (no
window opens), straight from the summaryslice that ships inside the bundled KM3-230213A
data -- so the same code works on a headless machine under `xvfb-run`.

## Opening a summaryslice file

Wrap an online ROOT file that contains summaryslices together with its detector in a
[`SummarysliceFile`](@ref) and hand it to [`run`](@ref):

```julia
using RainbowAlga

run(SummarysliceFile("path/to/online.root", "path/to/detector.detx"))
```

`run` draws the geometry, shows the first slice and opens the window in summaryslice mode;
`Space` plays through the slices, `Left`/`Right` step one slice at a time. To attach a file
to an existing display without opening a window (e.g. for [`snapshot`](@ref)), use
[`load_summaryslices!`](@ref).

## The per-PMT rate field

By default each of the (up to 31) PMTs of every optical module is drawn as a point at its
position on the module, coloured by its rate. The colour scale is logarithmic over a range
tuned for typical single-PMT rates (2-20 kHz), and the marker size grows with the rate, so
hot channels stand out. PMTs flagged in high-rate veto are highlighted (red by default) and
those with an almost-full FIFO in orange.

```@example summaryslices
using RainbowAlga, KM3io

datadir = joinpath(pkgdir(RainbowAlga), "data", "uhe-event")
sf = SummarysliceFile(joinpath(datadir, "KM3-230213A_allhits.root"),
                      joinpath(datadir, "detector.dynamical.datx"))

rba = RBA()
load_summaryslices!(rba, sf)          # draw the detector and show the first slice
rba.summaryslices.size_scale = 1.4    # marker size for the still image

snapshot(rba, "ss_pmt.png"; size = (1000, 750), time = 0,
         eyeposition = (486, 1364, 937), lookat = (73, 328, 374))
nothing # hide
```

![The per-PMT rate field of a summaryslice](ss_pmt.png)

In summaryslice mode the `time` keyword of [`snapshot`](@ref) selects the **slice ordinal**
(0-based) instead of a nanosecond offset, so `time = 0` freezes the first slice. The red
points are PMTs in high-rate veto.

## Per-DOM aggregate

For a detector-wide overview you can collapse each optical module to a single sphere
coloured by the **mean** of its 31 PMT rates. Toggle it interactively with the `g` key, or
set the granularity directly:

```@example summaryslices
rba.summaryslices.granularity = :dom   # one sphere per module (mean PMT rate)
rba.summaryslices.size_scale = 1.6
snapshot(rba, "ss_dom.png"; size = (1000, 750), time = 0,
         eyeposition = (486, 1364, 937), lookat = (73, 328, 374))
nothing # hide
```

![The per-DOM aggregate rate field](ss_dom.png)

The same rate colour scale serves both views, because the per-DOM value is a mean of the
per-PMT rates. Modules in HRV (red) or with an almost-full FIFO (orange) are flagged, and
modules absent from a slice are hidden (or dimmed -- see below).

## Configuring the display

Every cue is independently configurable, either through keyword arguments to
[`load_summaryslices!`](@ref) (forwarded to the underlying display state) ...

```julia
load_summaryslices!(rba, sf;
                    granularity = :dom,   # :pmt | :dom
                    color_scale = :lin,   # :log | :lin
                    size_mode   = :fixed, # :fixed | :rate
                    show_hrv    = false,
                    show_fifo   = false,
                    hide_nodata = false,
                    smoothing   = true,
                    smoothing_window = 9)
```

... by mutating the fields of `rba.summaryslices` at any time, or interactively with the
keyboard:

| Key | Action |
|-----|--------|
| `Space` | play / pause |
| `Left` / `Right` | step one slice backward / forward |
| `Up` / `Down` | faster / slower (slices per tick) |
| `0` | reset to the first slice |
| `g` | toggle PMT / DOM granularity |
| `k` | toggle logarithmic / linear rate scale |
| `r` | toggle fixed / rate-scaled marker size |
| `u` | toggle HRV highlighting |
| `i` | toggle FIFO highlighting |
| `y` | hide / dim modules with no data in the slice |
| `s` | toggle rate smoothing |
| `[` / `]` | shorten / lengthen the smoothing window |
| `c` / `Shift+c` | next / previous colour scheme |
| `-` / `=` | smaller / larger markers |

A rate colour bar is shown on the right edge of the window. As with the event time
window, you can **adjust it with the right mouse button**: drag horizontally to widen or
narrow the rate range, vertically to shift it to higher or lower rates, and double-click to
reset it to the default limits.

## Smoothing: suppressing outliers

A single noisy slice -- a brief bioluminescence flash or a readout glitch -- can dominate
one frame. Smoothing replaces each PMT/DOM rate with its average over a centred window of
slices, so transient spikes are diluted across the window while sustained activity remains.
Toggle it with the `s` key and size the window with `[` / `]` (or set `smoothing` /
`smoothing_window` up front):

```julia
rba.summaryslices.smoothing = true
rba.summaryslices.smoothing_window = 9   # average over 9 slices (~0.9 s), centred
```

Only the rate magnitude is smoothed; the HRV/FIFO flags stay instantaneous (read from the
current slice) so data-quality issues remain visible the moment they occur. Averaging skips
slices in which a given module has no data, and decoded slices are cached so playback stays
responsive.
