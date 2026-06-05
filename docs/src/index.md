```@meta
CurrentModule = RainbowAlga
```

# RainbowAlga

[RainbowAlga](https://git.km3net.de/tgal/RainbowAlga.jl) is an interactive 3D event
display for water/ice Cherenkov neutrino telescopes (KM3NeT). It renders the detector
geometry, particle tracks with their Cherenkov cones and photon hit clouds in real time
using [GLMakie](https://docs.makie.org/stable/explanations/backends/glmakie/).

```@setup hero
using RainbowAlga, KM3io, ColorSchemes
datadir = joinpath(pkgdir(RainbowAlga), "data", "uhe-event")
detector = Detector(joinpath(datadir, "detector.dynamical.datx"))
event = first(ROOTFile(joinpath(datadir, "KM3-230213A_allhits.root")).offline)
muon = bestjppmuon(event)
hits = select_first_hits(event.hits; n = 5, maxtot = 256)
rba = RBA()
update!(rba, detector)
add!(rba, hits; hit_distance = 3)
add!(rba, muon)
t₀ = muon.t + 800
recolor!(rba, 1, generate_colors(muon, hits; cherenkov_thresholds = (-5, 25),
                                 t₀ = t₀, timespan = 1800, cmap = ColorSchemes.thermal))
rba.simparams.t_offset = t₀
snapshot(rba, "uhe_hero.png"; size = (1200, 800), hit_scaling = 10, time = 1800,
         eyeposition = (391.5, 1411.7, 1127.7), lookat = (73.0, 323.8, 380.1))
```

![The ultra-high-energy neutrino event KM3-230213A in KM3NeT/ARCA](uhe_hero.png)

The figure above is the real KM3NeT open-data event **KM3-230213A**, rendered by the code
in [The KM3-230213A ultra-high-energy event](@ref) -- and produced at documentation build
time on a headless machine, straight from the bundled data.

## Installation

```julia
using Pkg
Pkg.add(url = "https://git.km3net.de/tgal/RainbowAlga.jl")
```

RainbowAlga opens a real OpenGL window, so it needs a working GPU/display. On a headless
machine run it against a virtual framebuffer (e.g. `xvfb-run julia ...`).

## Quick start

### Browsing an event file

The easiest way to look at events is to wrap a KM3NeT ROOT file together with its
detector in an [`EventFile`](@ref) and hand it to [`run`](@ref). Online files are
calibrated on the fly; offline files already carry calibrated hits and may add
reconstructed and MC tracks:

```julia
using RainbowAlga

f = EventFile("path/to/events.root", "path/to/detector.detx")
run(f)            # opens the window on the first event
```

Step through events with `N` / `Shift+N`, or from the REPL with [`next_event!`](@ref) /
[`previous_event!`](@ref), and jump to a specific one with [`load_event!`](@ref).

To plug in your own event source, derive from [`AbstractEventFile`](@ref) and implement
its interface (`geometry`, `nevents`, `eventsample`).

### Animating summaryslices

Online files also carry **summaryslices** -- per-PMT count rates over 100 ms windows.
RainbowAlga can animate these as a rate field over the whole detector, stepping by
summaryslice `frame_index` instead of nanosecond time. Wrap the file in a
[`SummarysliceFile`](@ref) and hand it to [`run`](@ref):

```julia
run(SummarysliceFile("path/to/online.root", "path/to/detector.detx"))
```

See [Summaryslices: animating detector rate fields](@ref) for the full walkthrough,
configuration options and keybindings.

### Building a display by hand

You can also assemble a scene from calibrated hits and tracks directly:

```julia
using RainbowAlga, KM3io

update!(Detector("detector.detx"))        # draw the geometry

event = first(ROOTFile("events.root").offline)
hits  = select_first_hits(event.hits; n = 5)
add!(hits)                                 # a hits cloud
add!(bestjppmuon(event))                   # the reconstructed muon + Cherenkov cone

RainbowAlga.run()
```

Apply custom, physics-based colourings with [`recolor!`](@ref) and
[`generate_colors`](@ref), then cycle through them with the `C` key.

### Saving figures

To render a scene to an image file without opening a window -- in a script, or on a
headless machine under `xvfb-run` -- use [`snapshot`](@ref) instead of [`run`](@ref). It
freezes the animation at a chosen time, optionally points the camera and writes a PNG:

```julia
snapshot(rba, "event.png"; size = (1200, 900), time = 1800,
         eyeposition = (391.5, 1411.7, 1127.7), lookat = (73.0, 323.8, 380.1))
```

See [The KM3-230213A ultra-high-energy event](@ref) for a complete, rendered walkthrough.

## Annotations

Add your own primitives or text labels and remove them again with `delete!`:

```julia
mysphere = annotate!((32, 1, 56), :Sphere; size = 8, color = :gold)
delete!(mysphere)

annotate!((0, 0, 700), "North"; fontsize = 30)
```

Primitives can be made transparent with the `alpha` keyword (`0` fully transparent, `1`
fully opaque). For correct see-through when several transparent objects overlap, also
pass `transparency = true`, which is forwarded to Makie:

```julia
annotate!((32, 1, 56), :Sphere; size = 8, color = :gold, alpha = 0.3, transparency = true)
```

Text labels take no `alpha` keyword, but you can pass a transparent colour directly:

```julia
annotate!((0, 0, 700), "North"; fontsize = 30, color = (:black, 0.5))
```

See [`annotate!`](@ref); the global scene is reachable with [`global_scene`](@ref) if you
want to draw with Makie directly.

## Keybindings

Press `H` inside the window to toggle an overlay listing every binding. The most common:

| Key | Action |
|-----|--------|
| `Space` | play / pause |
| `Left` / `Right` | step time backward / forward |
| `Up` / `Down` | increase / decrease speed |
| `,` / `.` | lower / raise the ToT cut |
| `-` / `=` | smaller / larger hits |
| `c` / `Shift+c` | next / previous hit colouring |
| `n` / `Shift+n` | next / previous event |
| `1`-`9` / `Shift+1`-`9` | load / save camera perspective |
| `p` / `v` | screenshot / video recording |
| `h` | toggle the help overlay |

In summaryslice mode the keys `g`, `k`, `r`, `u`, `i`, `y`, `s` and `[` / `]` configure the
rate field; see [Summaryslices: animating detector rate fields](@ref).

## API reference

```@index
```

```@autodocs
Modules = [RainbowAlga]
```
