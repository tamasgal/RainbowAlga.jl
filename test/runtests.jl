using RainbowAlga
using Test

@testset "RainbowAlga.jl" begin
    # Loading the package initialises GLMakie, which requires a working OpenGL context
    # (Mesa software rendering + Xvfb in headless CI). Constructing an RBA builds the
    # GLMakie scene together with the single shared hits mesh.
    rba = RainbowAlga.RBA()
    @test rba isa RainbowAlga.RBA
    @test isempty(rba.hitsclouds)
    @test isempty(rba.tracks)
    @test rba.hits_mesh !== nothing

    # The keybindings overlay data is the single source of truth for the help panel.
    @test !isempty(RainbowAlga.KEYBINDINGS)
    @test all(kb -> kb isa Tuple{String,String}, RainbowAlga.KEYBINDINGS)

    # Public API surface is present.
    for sym in (:add!, :update!, :clearhits!, :recolor!, :setfps!, :save_perspective,
                :load_perspective, :generate_colors, :generate_shower_colors,
                :select_first_hits, :select_cherenkov_hits, :global_scene,
                :AbstractEventFile, :EventFile, :load!, :load_event!,
                :next_event!, :previous_event!)
        @test isdefined(RainbowAlga, sym)
    end
end
