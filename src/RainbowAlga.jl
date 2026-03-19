module RainbowAlga

# Disable precompilation so the backend selection via RAINBOWALGA_BACKEND
# environment variable is re-evaluated on every load.
__precompile__(false)

using Printf
using LinearAlgebra

using KM3io

using Makie
using GeometryBasics
using Corpuscles
using Colors
using Colors: N0f8
using ColorSchemes

const BACKEND = Symbol(get(ENV, "RAINBOWALGA_BACKEND", "glfw"))

if BACKEND === :webgl
    using WGLMakie
else
    using GLMakie
    using GLFW
end

export update!, clearhits!, setfps!, add!, recolor!, describe!
export generate_colors, save_perspective, load_perspective
export global_scene
export select_first_hits, select_cherenkov_hits
export positionof
export load_event!, next_event!, previous_event!

include("params.jl")
include("recording.jl")
include("core.jl")
include("interactivity.jl")
include("runtime.jl")
include("artists.jl")
include("utils.jl")

end  # module
