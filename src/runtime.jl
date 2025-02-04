const _rba = RBA(Detector(joinpath(@__DIR__, "assets", "km3net_jul13_90m_r1494_corrected.detx")))

"""
    global_scene()

Returns the GLMakie scene of the global RainbowAlga instance
"""
global_scene() = _rba.scene
