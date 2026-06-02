# RainbowAlga.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tgal.pages.km3net.de/RainbowAlga.jl/dev)
[![Build Status](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/pipeline.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/pipelines)
[![Coverage](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/coverage.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/commits/main)

`RainbowAlga.jl` is an interactive 3D event display for water and ice Cherenkov neutrino
telescopes (KM3NeT). It renders the detector geometry, particle tracks with their
Cherenkov cones and photon hit clouds in real time. The underlying engine is
[`Makie.jl`](https://doi.org/10.5281/zenodo.3735092).

![RainbowAlga Screenshot](https://git.km3net.de/tgal/RainbowAlga.jl/-/raw/main/docs/images/RainbowAlga_Screenshot.png?ref_type=heads)

> **Note:** RainbowAlga opens a real OpenGL window, so it needs a working GPU/display.
> On a headless machine, run it against a virtual framebuffer (e.g. `xvfb-run julia ...`).

## Installation

`RainbowAlga.jl` is not an officially registered Julia package, but it is available via
the [KM3NeT Julia registry](https://git.km3net.de/common/julia-registry). To add the
registry, follow the instructions in its
[README](https://git.km3net.de/common/julia-registry#adding-the-registry) or simply run

```shell
git clone https://git.km3net.de/common/julia-registry ~/.julia/registries/KM3NeT
```

After that, add `RainbowAlga.jl` like any other Julia package:

```julia
julia> import Pkg; Pkg.add("RainbowAlga")
```

## Quickstart

### Browsing an event file

The easiest way to look at events is to wrap a KM3NeT ROOT file together with its
detector in an `EventFile` and hand it to `RainbowAlga.run()`. The first event is shown
immediately. Online (DAQ) files are calibrated on the fly; offline files already carry
calibrated hits and additionally show the reconstructed and MC tracks.

```julia
julia> using RainbowAlga, KM3io

julia> f = EventFile("KM3NeT_00000133_00013336.offline.root", "KM3NeT_00000133.detx")

julia> RainbowAlga.run(f)
```

Step through events with <kbd>N</kbd> / <kbd>Shift</kbd><kbd>N</kbd>, jump to one with
<kbd>E</kbd>, or drive it from the REPL with `next_event!()`, `previous_event!()` and
`load_event!(idx)`.

The detector can also come from the database via the `KM3DB.jl` extension to `KM3io.jl`
(`Detector(det_id::Int)`), and as a shortcut you can pass the `ROOTFile` and `Detector`
straight to `run`:

```julia
julia> using RainbowAlga, KM3io, KM3DB

julia> RainbowAlga.run(ROOTFile("KM3NeT_00000265_00026302.root"), Detector(265))
```

To plug in a custom event source, derive from `AbstractEventFile` and implement its
interface (`geometry`, `nevents`, `eventsample`).

### Building a scene by hand

RainbowAlga also exposes a global scene that you can populate directly. `update!()` draws
the detector geometry and `add!()` adds tracks or hits; both act on the global instance.

```julia
julia> using RainbowAlga, KM3io, KM3DB

julia> setfps!(20)

julia> update!(Detector(133))         # draw the geometry

julia> f = ROOTFile("KM3NeT_00000133_00013336.offline.root");

julia> add!(f.offline[1].hits)        # add a hits cloud

julia> RainbowAlga.run()

julia> clearhits!()                   # remove all hits clouds again

julia> add!(f.offline[2].hits)        # ...and show another event's hits
```

Apply custom, physics-based colourings with `recolor!` and `generate_colors` (or
`generate_shower_colors`), then cycle through them with the <kbd>C</kbd> key:

```julia
julia> muon = bestjppmuon(f.offline[1]);

julia> recolor!(1, generate_colors(muon, f.offline[1].hits))
```

## Annotations

You can add your own primitives (`:Sphere`, `:Cube`, `:Cylinder`) or text labels to the
scene and remove them again with `delete!`:

```julia
julia> mysphere = annotate!((32, 1, 56), :Sphere; size=8, color=:gold)

julia> delete!(mysphere)

julia> annotate!((0, 0, 700), "North"; fontsize=30)
```

`size` is the radius (sphere/cylinder) or half-side (cube); extra keyword arguments are
forwarded to Makie. The global scene is reachable via `global_scene()` if you want to
draw with Makie directly.

## Colour bar

When hits are added, a colour bar appears on the right of the window. It reflects the
colour mapping of the currently selected hits cloud, with the bottom corresponding to
0 ns and the top to the full duration Δt since the time offset. Tick marks are placed at
multiples of 10, 100 or 500 ns depending on the event duration.

The colour bar is interactive via the **right mouse button**:

| Gesture | Effect |
|---------|--------|
| Right-click + drag left / right | Shrink / expand the time window (Δt) |
| Right-click + drag up / down | Shift the time offset forward / backward |
| Double right-click | Reset Δt and the time offset to their defaults |

Both the ticks and the hit colours update live while dragging.

## Keybindings

Press <kbd>H</kbd> inside the window to toggle an overlay listing every keybinding.

| Key | Command |
|-----|---------|
| <kbd>Space</kbd> | Play / pause |
| <kbd>&larr;</kbd> / <kbd>&rarr;</kbd> | Step time backward / forward |
| <kbd>&uarr;</kbd> / <kbd>&darr;</kbd> | Faster / slower |
| <kbd>,</kbd> / <kbd>.</kbd> | Decrease / increase ToT cut |
| <kbd>-</kbd> / <kbd>=</kbd> | Smaller / larger hits |
| <kbd>0</kbd> | Reset time to the start |
| <kbd>C</kbd> / <kbd>Shift</kbd><kbd>C</kbd> | Next / previous hit colouring |
| <kbd>O</kbd> | Toggle auto-rotation |
| <kbd>L</kbd> | Toggle loop |
| <kbd>B</kbd> | Toggle dark mode |
| <kbd>X</kbd> | Toggle the info box |
| <kbd>1</kbd> - <kbd>9</kbd> | Load camera perspective |
| <kbd>Shift</kbd><kbd>1</kbd> - <kbd>9</kbd> | Save camera perspective |
| <kbd>P</kbd> | Save a screenshot |
| <kbd>V</kbd> | Start / stop video recording |
| <kbd>N</kbd> / <kbd>Shift</kbd><kbd>N</kbd> | Next / previous event |
| <kbd>E</kbd> | Jump to an event by index (type digits, then Enter) |
| <kbd>F</kbd> | Jump by frame index + trigger counter (type, Enter, type, Enter) |
| <kbd>H</kbd> | Toggle the keybindings overlay |

The <kbd>N</kbd>, <kbd>E</kbd> and <kbd>F</kbd> keys are only active when an event file is
loaded.

## Performance

If the animation is not smooth or the Julia REPL becomes unresponsive, lower the frames
per second before calling `RainbowAlga.run()`:

```julia
julia> setfps!(10)
```

DOMs are drawn as simple spheres by default (`simplified_doms=true`). Rendering each PMT
individually is much more expensive on large detectors, so only enable it when you
actually need that detail:

```julia
julia> update!(d; simplified_doms=false)   # per-PMT rendering, slower
```

Adding several hits clouds is cheap: they all share a single GPU mesh and only the
currently selected one is animated, so the others add no per-frame cost.
