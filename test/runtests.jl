using RainbowAlga
using KM3io
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

    # Summaryslice mode: the bundled online file carries summaryslices. Drive the full
    # non-GUI path (geometry index, slice -> rate field on the shared mesh, toggles) and
    # render the rate field off-screen to validate the GLMakie path.
    for sym in (:SummarysliceFile, :load_summaryslices!)
        @test isdefined(RainbowAlga, sym)
    end

    sf = SummarysliceFile(joinpath(datadir, "KM3-230213A_allhits.root"),
                          joinpath(datadir, "detector.dynamical.datx"))
    @test RainbowAlga.nslices(sf) > 0

    geom = RainbowAlga.build_rate_geometry(sf.detector)
    @test length(geom.pmt_positions) == sum(length(r) for r in values(geom.pmt_dom_ranges))
    @test length(geom.dom_positions) == length(geom.dom_index)
    @test !isempty(geom.dom_positions)

    srba = RBA()
    load_summaryslices!(srba, sf)
    d = srba.summaryslices
    @test srba.simparams.animation_mode === :summaryslice
    @test isnothing(srba.eventfile)
    @test srba.simparams.loop_end_frame_idx == RainbowAlga.nslices(sf) - 1

    # per-view rate scales are auto-calibrated from the data: independent windows, within the
    # physical band, and the per-DOM total (sum of 31 PMTs) sits far above the single-PMT one
    @test d.color_scale === :lin
    @test d.pmt_scale !== d.dom_scale
    @test 0 < d.pmt_scale.min < d.pmt_scale.max <= KM3io.Constants.MAXIMAL_RATE_HZ
    @test 0 < d.dom_scale.min < d.dom_scale.max
    @test d.dom_scale.min > d.pmt_scale.max
    @test RainbowAlga.active_scale(d) === d.pmt_scale   # PMT view active by default

    # explicit per-view overrides bypass calibration entirely
    let orba = RBA()
        load_summaryslices!(orba, sf; pmt_rate = (4000, 9000), dom_rate = (150000, 250000))
        od = orba.summaryslices
        @test (od.pmt_scale.min, od.pmt_scale.max) == (4000.0, 9000.0)
        @test (od.dom_scale.min, od.dom_scale.max) == (150000.0, 250000.0)
    end

    # a scale minimum is always strictly positive, so toggling to the log colour scale can
    # never hit log(0) -> -Inf/NaN (calibration floor, override clamp, and log path)
    @test RainbowAlga.nice_rate_bounds(33.0, 7700.0)[1] >= 100.0
    @test RainbowAlga.RateScale(0.0, 7500.0).min > 0.0
    let zrba = RBA()
        load_summaryslices!(zrba, sf; pmt_rate = (0, 7500))
        zd = zrba.summaryslices
        @test zd.pmt_scale.min > 0.0
        zd.color_scale = :log
        @test isfinite(RainbowAlga.rate_fraction(6000.0, zd))   # log(min) finite, no NaN
    end

    # per-PMT field of the first slice
    RainbowAlga.apply_slice!(srba, 0)
    npmt = length(geom.pmt_positions)
    @test length(srba.rate_mesh.positions[]) == npmt
    @test length(srba.rate_mesh.color[]) == npmt
    @test length(srba.rate_mesh.markersize[]) == npmt
    @test d.n_active > 0
    @test d.current_frame_index > 0

    # decoded rates sit in the physical band (raw byte 0 decodes to 0 Hz = disabled PMT)
    fr = RainbowAlga.getslice(sf, 1).frames[1]
    rs = pmtrates(fr)
    @test all(r -> 0.0 <= r <= KM3io.Constants.MAXIMAL_RATE_HZ + 1, rs)

    # granularity toggle switches the mesh to one point per optical module
    RainbowAlga.toggle_granularity!(srba)
    @test d.granularity === :dom
    @test length(srba.rate_mesh.positions[]) == length(geom.dom_positions)
    @test length(srba.rate_mesh.color[]) == length(geom.dom_positions)
    RainbowAlga.toggle_granularity!(srba)
    @test d.granularity === :pmt

    # the remaining display toggles flip state and keep the mesh consistent
    RainbowAlga.toggle_color_scale!(srba);    @test d.color_scale === :log
    RainbowAlga.toggle_color_scale!(srba);    @test d.color_scale === :lin   # back to default
    RainbowAlga.toggle_size_mode!(srba);      @test d.size_mode === :fixed
    RainbowAlga.toggle_hrv_highlight!(srba);  @test d.show_hrv == false
    RainbowAlga.toggle_fifo_highlight!(srba); @test d.show_fifo == false
    RainbowAlga.toggle_hide_nodata!(srba);    @test d.hide_nodata == false
    RainbowAlga.cycle_colorscheme!(srba, 1)
    @test length(srba.rate_mesh.color[]) == length(srba.rate_mesh.markersize[])

    # right-mouse colorbar adjustment of the active (per-view) rate scale + reset to baseline
    sc = RainbowAlga.active_scale(d)        # PMT view is active
    @test sc === d.pmt_scale
    base_lo, base_hi = sc.default_min, sc.default_max
    lo0, hi0 = sc.min, sc.max
    RainbowAlga.adjust_rate_bounds!(srba, 30.0, 0.0, 300.0)   # widen range
    @test sc.max - sc.min > hi0 - lo0
    RainbowAlga.adjust_rate_bounds!(srba, 0.0, -50.0, 300.0)  # shift up
    @test sc.min > 0 && sc.max > sc.min
    @test length(srba.rate_mesh.color[]) == length(srba.rate_mesh.positions[])
    RainbowAlga.reset_rate_bounds!(srba)
    @test sc.min == base_lo && sc.max == base_hi          # restored to the calibrated baseline
    @test sc.max < KM3io.Constants.MAXIMAL_RATE_HZ        # tighter than the full physical range

    # rate smoothing toggle + window adjustment (single-slice file: window collapses but
    # the path must stay valid). The averaging math is validated on a multi-slice file in
    # the dedicated smoke test. Smoothing is on by default over a 10-slice window.
    @test d.smoothing == true
    @test d.smoothing_window == 10
    RainbowAlga.toggle_smoothing!(srba)
    @test d.smoothing == false
    RainbowAlga.toggle_smoothing!(srba)
    @test d.smoothing == true
    RainbowAlga.apply_slice!(srba, 0)
    @test length(srba.rate_mesh.color[]) == length(srba.rate_mesh.positions[])
    w0 = d.smoothing_window
    RainbowAlga.change_smoothing_window!(srba, 4)
    @test d.smoothing_window == w0 + 4
    RainbowAlga.change_smoothing_window!(srba, -10^6)
    @test d.smoothing_window == 1

    # slice stepping clamps to the available range
    srba.simparams.frame_idx = 0
    RainbowAlga.step_slice!(srba, -5)
    @test srba.simparams.frame_idx == 0
    RainbowAlga.step_slice!(srba, 10^6)
    @test srba.simparams.frame_idx == srba.simparams.loop_end_frame_idx

    @test occursin("slice", RainbowAlga.summaryslice_infotext(srba))

    # off-screen render of the rate field (summaryslice-aware snapshot)
    mktempdir() do dir
        out = joinpath(dir, "slice.png")
        @test snapshot(srba, out; size = (320, 240), time = 0) == out
        @test isfile(out) && filesize(out) > 0
    end
end
