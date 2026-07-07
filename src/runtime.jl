const GLOBAL_RBA = Ref{Union{RBA, Nothing}}(nothing)

function global_rba()
    if isnothing(GLOBAL_RBA[])
        # The first use in a session builds the scene, which triggers Makie/GLMakie's one-time
        # "time to first plot" compilation (this is what makes the first `run` pause for tens of
        # seconds before anything appears). Announce it so the wait is not a silent freeze.
        print_status("Initialising the 3D scene (Makie compiles on first use, this can take up to a minute) ...")
        GLOBAL_RBA[] = RBA(Detector(joinpath(@__DIR__, "assets", "km3net_jul13_90m_r1494_corrected.detx")))
        print_status("Scene initialised.")
    end
    GLOBAL_RBA[]
end

"""
    global_scene()

Returns the GLMakie scene of the global RainbowAlga instance
"""
global_scene() = global_rba().scene
