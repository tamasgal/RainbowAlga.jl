module RainbowAlga

using Printf
using LinearAlgebra

using KM3io

using Makie
using GLMakie
using GeometryBasics
using GLFW
using Corpuscles
using Colors
using Colors: N0f8
using ColorSchemes

export add!, update!, clearhits!, recolor!, setfps!
export save_perspective, load_perspective
export generate_colors, generate_shower_colors, select_first_hits, select_cherenkov_hits
export global_scene, annotate!
export AbstractEventFile, EventFile, load!, load_event!, next_event!, previous_event!

# Load order matters: interfaces and structs (tracks, types) must come before the RBA
# methods that operate on them, and runtime.jl (which holds a typed RBA reference) after.
include("interfaces.jl")   # AbstractEventFile + extension interface
include("params.jl")       # DisplayParams, SimParams
include("recording.jl")    # video recording
include("tracks.jl")       # Track + Cherenkov cone
include("types.jl")        # Hit, HitsCloud, RBA
include("runtime.jl")      # global_rba, global_scene
include("hits.jl")         # hit clouds + shared mesh
include("detector.jl")     # detector geometry
include("events.jl")       # event navigation + run
include("colorbar.jl")     # interactive colorbar
include("help.jl")         # keybindings overlay
include("app.jl")          # infobox, render loop
include("eventfile.jl")    # EventFile (online/offline)
include("interactivity.jl")# keyboard + control functions
include("artists.jl")      # colour schemes
include("utils.jl")        # hit selection helpers
include("annotations.jl")  # user-added scene primitives

end  # module
