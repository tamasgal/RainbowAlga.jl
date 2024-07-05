# RainbowAlga

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tgal.gitlab.io/RainbowAlga.jl/dev)
[![Build Status](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/pipeline.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/pipelines)
[![Coverage](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/coverage.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/commits/main)

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

julia> RainbowAlga.run()  # opens the 3D display with the default KM3NeT detector
```

The function to update (usually replace) objects like the detector, hits or
tracks is called `update!` and can be called with the corresponding objects. It
will modify the global scene immediately. Here is an example how to load or
update the detector geometry:

```julia
julia> d = Detector(datapath("detx", "KM3NeT_00000133_20221025.detx"))

julia> update!(d)
```

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
| <kbd>C</kbd>      | Toggle hit colouring mode |
| <kbd>Space</kbd>  | Play/Pause                |
| <kbd>Q</kbd>      | Quit                      |


![RainbowAlga Screenshot](https://git.km3net.de/tgal/RainbowAlga.jl/-/raw/main/docs/images/RainbowAlga_Screenshot.png?ref_type=heads)

## Performance

In case your computer is too slow to run a smooth animation and the Julia REPL is not responding quickly enough (or at all), consider lowering the framees per second (FPS) of the animation. It is best to set the FPS before calling `RainbowAlga.run()`, e.g. to 10 FPS:

``` julia
julia> setfps!(10)
```

