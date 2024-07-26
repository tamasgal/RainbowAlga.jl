module RainbowAlga

using Printf
using LinearAlgebra

using KM3io

using Makie
using GLMakie
using GeometryBasics
using GLFW
using Corpuscles
using ColorSchemes

export update!, clearhits!, setfps!, add!, recolor!, describe!
export generate_colors

include("params.jl")
include("core.jl")
include("interactivity.jl")
include("runtime.jl")
include("artists.jl")

end  # module
