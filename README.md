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

RainbowAlga has a global scene object which can be manipulated using several
functions. `RainbowAlga.run()` can be called to display the scene at any time,
usually right after loading the package.

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
Check out the `scripts/vhe_paper.jl` script for more inspiration.

## Performance Issues

If you encounter any performance issues, you can remove e.g. the detailed DOM rendering
by passing `simplified_doms=true` to `update!(detector; ...)`, like

```julia
julia> update!(d; simplified_doms=true)
```

Make sure not to overuse `add!(hits)`, since each hit cloud adds some overhead to the
animation loop, even if not fully displayed.

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
| <kbd>R</kbd>      | Reset time to 0           |
| <kbd>A</kbd>      | Toggle auto-rotation      |
| <kbd>L</kbd>      | Toggle loop               |
| <kbd>D</kbd>      | Toggle dark mode          |
| <kbd>C</kbd>      | Cycle between hit clouds  |
| <kbd>1</kbd> - <kbd>9</kbd>      | Load perspective |
| <kbd>Shift</kbd><kbd>1</kbd> - <kbd>9</kbd>      | Save perspective |
| <kbd>Space</kbd>  | Play/Pause                |
| <kbd>Q</kbd>      | Quit                      |


![RainbowAlga Screenshot](https://git.km3net.de/tgal/RainbowAlga.jl/-/raw/main/docs/images/RainbowAlga_Screenshot.png?ref_type=heads)

## Performance

In case your computer is too slow to run a smooth animation and the Julia REPL is not responding quickly enough (or at all), consider lowering the framees per second (FPS) of the animation. It is best to set the FPS before calling `RainbowAlga.run()`, e.g. to 10 FPS:

``` julia
julia> setfps!(10)
```

