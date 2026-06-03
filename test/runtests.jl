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
    for sym in (:RBA, :add!, :update!, :clearhits!, :recolor!, :setfps!, :snapshot,
                :save_perspective, :load_perspective, :generate_colors,
                :generate_shower_colors, :select_first_hits, :select_cherenkov_hits,
                :global_scene, :annotate!, :AbstractEventFile, :EventFile, :load!,
                :load_event!, :next_event!, :previous_event!)
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

    # End-to-end: load the bundled KM3-230213A event and render it off-screen. This also
    # validates the bundled data files and exercises the full GLMakie render path that the
    # documentation relies on (headless via Xvfb on CI).
    datadir = joinpath(pkgdir(RainbowAlga), "data", "uhe-event")
    f = EventFile(joinpath(datadir, "KM3-230213A_allhits.root"),
                  joinpath(datadir, "detector.dynamical.datx"))
    erba = RBA()
    load!(erba, f)
    @test !isempty(erba.hitsclouds)   # hits cloud(s)
    @test !isempty(erba.tracks)       # reconstructed muon
    mktempdir() do dir
        out = joinpath(dir, "event.png")
        # The temporary hit_scaling/min_tot overrides must be restored afterwards.
        hs0, mt0 = erba.simparams.hit_scaling, erba.simparams.min_tot
        @test snapshot(erba, out; size = (320, 240), time = 2000,
                       hit_scaling = hs0 + 7, min_tot = mt0 + 1.0) == out
        @test isfile(out) && filesize(out) > 0
        @test erba.simparams.hit_scaling == hs0
        @test erba.simparams.min_tot == mt0
    end
end
