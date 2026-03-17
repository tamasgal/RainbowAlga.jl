# RainbowAlga.jl

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tgal.gitlab.io/RainbowAlga.jl/dev)
[![Build Status](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/pipeline.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/pipelines)
[![Coverage](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/coverage.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/commits/main)

The `RainbowAlga.jl` package is an interactive 3D display which visualises events in water and ice Cherenkov neutrino telescopes. The underlying engine is [`Makie.jl`](https://doi.org/10.5281/zenodo.3735092).

## Installation

`RainbowAlga.jl` is not an officially registered Julia package but it's available via
the [KM3NeT Julia registry](https://git.km3net.de/common/julia-registry). To add
the KM3NeT Julia registry to your local Julia registry list, follow the
instructions in its
[README](https://git.km3net.de/common/julia-registry#adding-the-registry) or simply do

``` shell
git clone https://git.km3net.de/common/julia-registry ~/.julia/registries/KM3NeT
```

    
After that, you can add `RainbowAlga.jl` just like any other Julia package:

``` julia
julia> import Pkg; Pkg.add("RainbowAlga")
```

    
## Quickstart

### Skimming through online events

The easiest way to browse events from an online (DAQ) ROOT file is to pass the
file and detector directly to `RainbowAlga.run()`. The first event is loaded
automatically and the hits are coloured using the time range of the triggered
hits. Use <kbd>N</kbd> / <kbd>Shift</kbd><kbd>N</kbd> to step through events or
<kbd>E</kbd> to jump to a specific event index.

```julia
julia> using RainbowAlga, KM3io, KM3DB

julia> f = ROOTFile("KM3NeT_00000265_00026302.root")

julia> detector = Detector(265)

julia> RainbowAlga.run(f, detector)
```

### Manual scene control

RainbowAlga also exposes a global scene object that can be manipulated
directly. `RainbowAlga.run()` displays the scene at any time, usually right
after loading the package.

``` julia
julia> using RainbowAlga, KM3io, KM3NeTTestData

julia> d = Detector(datapath("detx", "KM3NeT_00000133_20221025.detx"))

julia> update!(d)

julia> RainbowAlga.run()
```

To manipulate the scene, the `update!()` and `add!()` functions can be used
which act on the global RainbowAlga instance.
As seen in the example above, the detector geometry is "updated" using `update!(d)`.
Tracks and hits can be added in a similar way, but using `add!(hits)`.

Here is an example of displaying some hit data from an offline file which already
contains calibrated hits. The detector is still needed to be able to display the
base geometry. It is obtained from the database by loading `KM3DB.jl` which allows
the automatic retrieval using an extension in `KM3io.jl` via `Detector(det_id::Int)`:

```julia
julia> using RainbowAlga, KM3io, KM3DB

julia> RainbowAlga.setfps!(20)

julia> detector = Detector(133)
Detector 133 (v5) with 21 strings and 399 modules.

julia> f = ROOTFile("KM3NeT_00000133_00013336.jterbr.jppmuon_aashower_static.offline.v9.2.root")
ROOTFile{OfflineTree (84963 events)}

julia> hits = f.offline[1].hits;

julia> add!(hits)
1-element Vector{RainbowAlga.HitsCloud}:
 HitsCloud 'hawaii' (528 hits)

julia> RainbowAlga.run()

julia> clearhits!()  # use this to clear all hits
RainbowAlga.HitsCloud[]

julia> hits = f.offline[2].hits;  # another event's hits...

julia> add!(hits)
1-element Vector{RainbowAlga.HitsCloud}:
 HitsCloud 'hawaii' (530 hits)
 ```

Check out the `scripts/vhe_paper.jl` script for more inspiration.

## Performance Issues

If you encounter any performance issues, you can remove e.g. the detailed DOM rendering
by passing `simplified_doms=true` to `update!(detector; ...)`, like

```julia
julia> update!(d; simplified_doms=true)
```

Make sure not to overuse `add!(hits)`, since each hit cloud adds some overhead to the
animation loop, even if not fully displayed.

## Colour bar

When hits are added to the scene, a colour bar appears on the right side of the
window. It reflects the colour mapping of the currently selected hit cloud, with
the bottom corresponding to 0 ns and the top to the full duration Δt since the
time offset. Tick marks are placed at multiples of 10, 100 or 500 ns depending
on the event duration.

The colour bar is interactive via the **right mouse button**:

| Gesture | Effect |
|---------|--------|
| Right-click + drag left / right | Shrink / expand the time window (Δt) |
| Right-click + drag up / down | Shift the time offset forward / backward |
| Double right-click | Reset both Δt and the time offset to their defaults |

Both the colour bar ticks and the hit colours update live while dragging.

## Keybindings

You can use <kbd>&larr;</kbd> and <kbd>&rarr;</kbd> to go back and forth in time and <kbd>R</kbd> to reset the time.

| Key               | Command                   |
|-------------------|---------------------------|
| <kbd>&larr;</kbd> | Time step back            |
| <kbd>&rarr;</kbd> | Time step forward         |
| <kbd>&uarr;</kbd> | Faster                    |
| <kbd>&darr;</kbd> | Slower                    |
| <kbd>,</kbd>      | Decrease ToT cut          |
| <kbd>.</kbd>      | Increase ToT cut          |
| <kbd></kbd><kbd>h</kbd>  | Decrease hit scaling |
| <kbd>Shift</kbd><kbd>h</kbd>  | Increase hit scaling |
| <kbd>0</kbd>      | Reset time to 0           |
| <kbd>O</kbd>      | Toggle auto-rotation      |
| <kbd>L</kbd>      | Toggle loop               |
| <kbd>B</kbd>      | Toggle dark mode          |
| <kbd>C</kbd>      | Cycle between hit clouds  |
| <kbd>P</kbd>      | Save a screenshot         |
| <kbd>V</kbd>      | Record video              |
| <kbd>1</kbd> - <kbd>9</kbd>      | Load perspective |
| <kbd>Shift</kbd><kbd>1</kbd> - <kbd>9</kbd>      | Save perspective |
| <kbd>Space</kbd>  | Play/Pause                |
| <kbd>N</kbd>      | Next event                |
| <kbd>Shift</kbd><kbd>N</kbd> | Previous event |
| <kbd>E</kbd>      | Jump to event by index (type digits + Enter, any other key cancels) |
| <kbd>F</kbd>      | Jump to event by frame index + trigger counter (type frame index, Enter, type trigger counter, Enter; any other key cancels) |


![RainbowAlga Screenshot](https://git.km3net.de/tgal/RainbowAlga.jl/-/raw/main/docs/images/RainbowAlga_Screenshot.png?ref_type=heads)

## Performance

In case your computer is too slow to run a smooth animation and the Julia REPL is not responding quickly enough (or at all), consider lowering the framees per second (FPS) of the animation. It is best to set the FPS before calling `RainbowAlga.run()`, e.g. to 10 FPS:

``` julia
julia> setfps!(10)
```

