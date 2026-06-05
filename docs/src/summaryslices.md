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
position on the module, coloured by its rate on a linear scale. When the file is opened the
colour range is auto-calibrated from the data so that ordinary rate variations spread across
the whole colormap instead of collapsing into one colour (see [Rate scales](@ref)); press
`k` to switch to a logarithmic scale. The marker size grows with the rate, so hot channels
stand out. PMTs flagged in high-rate veto are highlighted (red by default) and those with an
almost-full FIFO in orange.

```@example summaryslices
using RainbowAlga, KM3io

datadir = joinpath(pkgdir(RainbowAlga), "data", "uhe-event")
sf = SummarysliceFile(joinpath(datadir, "KM3-230213A_allhits.root"),
                      joinpath(datadir, "detector.dynamical.datx"))

rba = RBA()
load_summaryslices!(rba, sf)          # draw the detector and show the first slice
rba.summaryslices.size_scale = 0.7    # marker size for the still image

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
coloured by its **total** count rate -- the sum of its 31 PMT rates, so a module sits about
31 times higher than a single PMT (a few hundred kHz). Toggle it interactively with the `g`
key, or set the granularity directly:

```@example summaryslices
rba.summaryslices.granularity = :dom   # one sphere per module (total module rate)
rba.summaryslices.size_scale = 1.6
snapshot(rba, "ss_dom.png"; size = (1000, 750), time = 0,
         eyeposition = (486, 1364, 937), lookat = (73, 328, 374))
nothing # hide
```

![The per-DOM aggregate rate field](ss_dom.png)

The per-DOM view carries its **own** colour scale: a module total sits about 31 times above a
single PMT, so it is calibrated separately (see [Rate scales](@ref)) and switching
granularity swaps the colour bar with it. Modules in HRV (red) or with an
almost-full FIFO (orange) are flagged, and modules absent from a slice are hidden (or dimmed
-- see below).

## Rate scales

Single-PMT rates at KM3NeT depths (about 2.5-3.5 km in the Mediterranean) sit at a few kHz,
but the exact level depends on the site and the sea state, so no fixed colour range fits
every file. Instead, when a file is opened RainbowAlga samples up to ten summaryslices spread
across it and derives the colour limits from the spread of the rates it observes -- the 5th
to 95th percentile -- **once for the single-PMT rates and once for the per-module total
rates** (the sum of a module's 31 PMTs, hence roughly 31 times higher). The two views
therefore carry independent, data-tuned scales
([`calibrate_rate_scales!`](@ref)), reachable as `rba.summaryslices.pmt_scale` and
`rba.summaryslices.dom_scale`, and switching granularity (`g`) swaps the colour bar with the
view.

You can pin either scale -- or both -- and set the sample size when opening the file:

```julia
load_summaryslices!(rba, sf;
                    pmt_rate = (4000, 9000),       # per-PMT colour limits in Hz
                    dom_rate = (150000, 250000),   # per-DOM (total) colour limits in Hz
                    calibration_slices = 20)       # slices sampled for calibration (default 10)
```

The active scale can also be changed at any time by mutating its `min` / `max`, or
interactively by dragging the colour bar with the right mouse button; a double-click resets
it to the auto-calibrated baseline for the current view.

## Configuring the display

Every cue is independently configurable, either through keyword arguments to
[`load_summaryslices!`](@ref) (forwarded to the underlying display state) ...

```julia
load_summaryslices!(rba, sf;
                    granularity = :dom,   # :pmt | :dom
                    color_scale = :log,   # :lin | :log
                    size_mode   = :fixed, # :fixed | :rate
                    show_hrv    = false,
                    show_fifo   = false,
                    hide_nodata = false,
                    smoothing   = false,  # on by default
                    smoothing_window = 10) # slices averaged (the default)
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
| `k` | toggle linear / logarithmic rate scale |
| `r` | toggle fixed / rate-scaled marker size |
| `u` | toggle HRV highlighting |
| `i` | toggle FIFO highlighting |
| `y` | hide / dim modules with no data in the slice |
| `s` | toggle rate smoothing |
| `[` / `]` | shorten / lengthen the smoothing window |
| `c` / `Shift+c` | next / previous colour scheme |
| `-` / `=` | smaller / larger markers |

A rate colour bar is shown on the right edge of the window and reflects the active view's
scale. As with the event time window, you can **adjust it with the right mouse button**: drag
horizontally to widen or narrow the rate range, vertically to shift it to higher or lower
rates, and double-click to reset it to the auto-calibrated baseline for the current view.

## Smoothing: suppressing outliers

A single noisy slice -- a brief bioluminescence flash or a readout glitch -- can dominate
one frame. Smoothing replaces each PMT/DOM rate with its average over a centred window of
slices, so transient spikes are diluted across the window while sustained activity remains.
It is **on by default** over a 10-slice window (~1 s); turn it off with the `s` key to see
instantaneous rates, and size the window with `[` / `]` (or set `smoothing` /
`smoothing_window` up front):

```julia
rba.summaryslices.smoothing = false      # show instantaneous, unsmoothed rates
rba.summaryslices.smoothing_window = 23   # or change the window (default 10 slices)
```

Only the rate magnitude is smoothed; the HRV/FIFO flags stay instantaneous (read from the
current slice) so data-quality issues remain visible the moment they occur. Averaging skips
slices in which a given module has no data, and decoded slices are cached so playback stays
responsive.
