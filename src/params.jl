Base.@kwdef mutable struct DisplayParams
    pos::Tuple{Int, Int} = (0, 0)
    size::Tuple{Int, Int} = (600, 600)
end

const displayparams = let m = GLFW.GetVideoMode(GLFW.GetPrimaryMonitor())
    width = Int(round(m.width * 0.6))
    height = Int(round(m.height * 0.6))
    DisplayParams(
        # pos = (Int(round(m.width - width / 2)), Int(round(m.height - height / 2))),
        pos = (100, 100),
        size = (width, height)
    )
end

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
    hit_scaling::Int = 1  # factor to multiply the size of the hits
    fps::Int = 24  # framews per second
    quit::Bool = false
end

