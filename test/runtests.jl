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
                :select_first_hits, :select_cherenkov_hits, :global_scene, :annotate!,
                :AbstractEventFile, :EventFile, :load!, :load_event!,
                :next_event!, :previous_event!)
        @test isdefined(RainbowAlga, sym)
    end

    # Annotations: add primitives/text to the scene and delete them again.
    n0 = length(rba.scene.plots)
    s = annotate!(rba.scene, (0.0, 0.0, 0.0), :Sphere; size = 5, color = :gold)
    @test s isa RainbowAlga.Annotation
    @test length(rba.scene.plots) == n0 + 1
    c = annotate!(rba.scene, (10.0, 0.0, 0.0), :Cube)
    t = annotate!(rba.scene, (0.0, 0.0, 5.0), "label")
    @test length(rba.scene.plots) == n0 + 3
    @test_throws ErrorException annotate!(rba.scene, (0.0, 0.0, 0.0), :Banana)
    delete!(s); delete!(c); delete!(t)
    @test length(rba.scene.plots) == n0
    delete!(s)  # deleting twice is a no-op
    @test length(rba.scene.plots) == n0
end
