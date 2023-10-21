Base.@kwdef mutable struct DisplayParams
    pos::Tuple{Int, Int} = (0, 0)
    size::Tuple{Int, Int} = (600, 600)
end

const displayparams = DisplayParams()

Base.@kwdef mutable struct SimParams
    frame_idx::Int = 0
    t_offset::Float64 = 0.0
    stopped::Bool = false
    speed::Int = 3
    min_tot::Float64 = 26.0
    loop_end_frame_idx::Int = 10000
    rotation_enabled::Bool = true
    loop_enabled::Bool = true
    darkmode_enabled::Bool = false
    hits_selector::Int = 0  # selects the hits mesh (normal, cherenkov, ...)
    quit::Bool = false
end

# The global parameters for the 3D simulation
const simparams = SimParams()

# Control functions to steer the 3D simulation
@inline isstopped() = simparams.stopped
@inline stop() = simparams.stopped = true
@inline start() = simparams.stopped = false
@inline reset_time() = simparams.frame_idx = 0
@inline faster(n::Int) = simparams.speed += n
@inline slower(n::Int) = simparams.speed -= n
@inline increasetot(t::Float64) = simparams.min_tot += t
@inline decreasetot(t::Float64) = simparams.min_tot -= t
@inline speed() = simparams.speed
@inline toggle_rotation() = simparams.rotation_enabled = !simparams.rotation_enabled
@inline toggle_loop() = simparams.loop_enabled = !simparams.loop_enabled
@inline rotation_enabled() = simparams.rotation_enabled
@inline cycle_hits() = simparams.hits_selector += 1
