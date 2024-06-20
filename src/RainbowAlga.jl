module RainbowAlga

using Printf

using KM3io

using Makie
using GLMakie
using GeometryBasics
using GLFW
using Corpuscles
using ColorSchemes

export run, update!

include("params.jl")
include("core.jl")
include("interactivity.jl")
include("runtime.jl")

end  # module
