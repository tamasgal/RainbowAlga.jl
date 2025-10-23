const GLOBAL_RBA = Ref{Union{RBA, Nothing}}(nothing)

function global_rba()
    if isnothing(GLOBAL_RBA[])
        GLOBAL_RBA[] = RBA(Detector(joinpath(@__DIR__, "assets", "km3net_jul13_90m_r1494_corrected.detx")))
    end
    GLOBAL_RBA[]
end

"""
    global_scene()

Returns the GLMakie scene of the global RainbowAlga instance
"""
global_scene() = global_rba().scene
