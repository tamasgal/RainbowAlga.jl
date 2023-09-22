# RainbowAlga

[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://tgal.gitlab.io/RainbowAlga.jl/dev)
[![Build Status](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/pipeline.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/pipelines)
[![Coverage](https://git.km3net.de/tgal/RainbowAlga.jl/badges/main/coverage.svg)](https://git.km3net.de/tgal/RainbowAlga.jl/commits/main)

# Installation

`RainbowAlga.jl` is not an officially registered Julia package but it's available via
the [KM3NeT Julia registry](https://git.km3net.de/common/julia-registry). To add
the KM3NeT Julia registry to your local Julia registry list, follow the
instructions in its
[README](https://git.km3net.de/common/julia-registry#adding-the-registry) or simply do

    git clone https://git.km3net.de/common/julia-registry ~/.julia/registries/KM3NeT
    
After that, you can add `RainbowAlga.jl` just like any other Julia package:

    julia> import Pkg; Pkg.add("RainbowAlga")
    
# Quickstart

The `run(detector_fname, event_fname, event_id)` can be used to invoke the 3D display.

``` julia-repl
julia> using RainbowAlga

julia> run("some_detector.detx", "some_online_file.root", 23)
```

You can use <kbd>&larr;</kbd> and <kbd>&larr;</kbd> to go back and forth in time and `R` to reset the time.

![RainbowAlga Screenshot](https://git.km3net.de/tgal/RainbowAlga.jl/-/raw/main/docs/images/RainbowAlga_Screenshot.png?ref_type=heads)
