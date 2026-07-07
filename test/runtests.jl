using RainbowAlga
using KM3io
using Test

# Minimal AbstractEventFile used to exercise the selector navigation without any GLMakie /
# ROOT I/O: `rawevent` returns the index itself so a selector can be expressed over `1:n`.
struct DummyFile <: RainbowAlga.AbstractEventFile
    n::Int
    selector::Union{Nothing,Function}
end
RainbowAlga.geometry(::DummyFile) = nothing
RainbowAlga.nevents(f::DummyFile) = f.n
RainbowAlga.rawevent(::DummyFile, idx::Int) = idx
RainbowAlga.eventselector(f::DummyFile) = f.selector
# Enough of eventsample for load_event! to run without any hit/track I/O (used by the deferred
# search test): an empty hit list and no reco/MC event, with frame index and trigger counter
# echoing the index.
RainbowAlga.eventsample(::DummyFile, idx::Int) =
    (; hits = RainbowAlga.Hit[], t_range = (0.0, 0.0), frame_index = idx,
       trigger_counter = idx, event = nothing)

# A file that accepts every event but whose event LOAD throws, to exercise the deferred search
# error path (an event accepted on the raw event can still fail when its hits are calibrated).
struct ThrowingLoadFile <: RainbowAlga.AbstractEventFile end
RainbowAlga.geometry(::ThrowingLoadFile) = nothing
RainbowAlga.nevents(::ThrowingLoadFile) = 3
RainbowAlga.rawevent(::ThrowingLoadFile, idx::Int) = idx
RainbowAlga.eventselector(::ThrowingLoadFile) = (evt, det) -> true
RainbowAlga.eventsample(::ThrowingLoadFile, idx::Int) = error("corrupt event $idx")

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
                :load_event!, :next_event!, :previous_event!,
                :next_selected_event!, :previous_selected_event!)
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

    # ----------------------------------------------------------------------------------
    # Selector-based navigation (S / Shift+S). The pure navigation core
    # (find_selected_from / is_selected!) is exercised over a DummyFile so it needs no
    # GLMakie render or ROOT I/O.
    @testset "selector navigation" begin
        # Selector accepting even indices over 1:6, counting its invocations.
        calls = Ref(0)
        evens(evt, det) = (calls[] += 1; iseven(evt))
        srba2 = RBA()
        srba2.eventfile = DummyFile(6, evens)

        # forward, lazily discovering the accepted indices
        @test RainbowAlga.find_selected_from(srba2, 0, 1) == 2   # first even from the start
        @test RainbowAlga.find_selected_from(srba2, 2, 1) == 4
        @test RainbowAlga.find_selected_from(srba2, 4, 1) == 6
        @test RainbowAlga.find_selected_from(srba2, 6, 1) == 2   # wrap past the end

        # every index has now been evaluated exactly once; wrapping re-uses the cache
        @test calls[] == 6
        @test srba2.selected_events == [2, 4, 6]            # sorted + unique
        @test issorted(srba2.selected_events) && allunique(srba2.selected_events)
        @test length(srba2._selection_verdicts) == 6        # all verdicts cached
        @test RainbowAlga.find_selected_from(srba2, 6, 1) == 2
        @test calls[] == 6                                  # selector never re-ran

        # backward direction, with wrap to the last accepted index
        @test RainbowAlga.find_selected_from(srba2, 6, -1) == 4
        @test RainbowAlga.find_selected_from(srba2, 2, -1) == 6   # wrap past the start
        @test RainbowAlga.find_selected_from(srba2, 0, -1) == 6   # no current -> last accepted

        # no selector -> every event qualifies, cache stays empty
        nrba = RBA()
        nrba.eventfile = DummyFile(6, nothing)
        @test RainbowAlga.is_selected!(nrba, 3) == true
        @test RainbowAlga.find_selected_from(nrba, 0, 1) == 1
        @test RainbowAlga.find_selected_from(nrba, 3, 1) == 4
        @test RainbowAlga.find_selected_from(nrba, 6, 1) == 1     # wrap
        @test isempty(nrba.selected_events) && isempty(nrba._selection_verdicts)

        # nothing matches -> find_selected_from returns nothing
        zrba = RBA()
        zrba.eventfile = DummyFile(4, (evt, det) -> false)
        @test RainbowAlga.find_selected_from(zrba, 0, 1) === nothing
        @test isempty(zrba.selected_events)

        # a single match found from itself returns that index (next_selected_event! no-ops)
        orba = RBA()
        orba.eventfile = DummyFile(5, (evt, det) -> evt == 3)
        @test RainbowAlga.find_selected_from(orba, 3, 1) == 3

        # a throwing selector is treated as a rejection rather than aborting navigation
        trba = RBA()
        trba.eventfile = DummyFile(4, (evt, det) -> evt == 2 ? error("boom") : evt == 4)
        @test RainbowAlga.find_selected_from(trba, 0, 1) == 4
    end

    # Deferred selector search: S / Shift+S queue a scan that runs one render tick later, with
    # a "Searching..." overlay shown in between so a slow selector does not look like a freeze.
    @testset "deferred selector search" begin
        # Build on the real detector so the shared hits mesh is realized (load_event! uploads to
        # it); a DummyFile drives the selector logic without any hit/track I/O.
        drba = RBA(KM3io.Detector(joinpath(datadir, "detector.dynamical.datx")))
        RainbowAlga.setup_search_overlay!(drba)
        vis = drba._plots["searching_visible"]
        @test vis[] == false                                   # overlay starts hidden
        drba.current_event_idx = 0
        drba.eventfile = DummyFile(6, (evt, det) -> iseven(evt))

        # requesting a search queues the direction and shows the overlay immediately
        RainbowAlga.request_search!(drba, :next)
        @test drba.simparams.pending_search === :next
        @test drba.simparams.search_frames_waited == 0
        @test vis[] == true

        # a repeat request while one is queued is ignored (key-repeat must not starve the scan)
        RainbowAlga.request_search!(drba, :previous)
        @test drba.simparams.pending_search === :next

        # first tick: only the wait counter advances; the scan has NOT run yet and the overlay
        # stays visible so it gets a fully rendered frame before the blocking walk
        RainbowAlga.step_pending_search!(drba)
        @test drba.simparams.pending_search === :next
        @test drba.simparams.search_frames_waited == 1
        @test vis[] == true
        @test drba.current_event_idx == 0                      # no event loaded yet

        # second tick: the scan runs (lands on the first accepted, even, index), then the
        # overlay hides and the pending state clears
        RainbowAlga.step_pending_search!(drba)
        @test drba.simparams.pending_search === :none
        @test drba.simparams.search_frames_waited == 0
        @test vis[] == false
        @test iseven(drba.current_event_idx)

        # a further tick with nothing pending is a harmless no-op
        RainbowAlga.step_pending_search!(drba)
        @test drba.simparams.pending_search === :none

        # Shift+S queues a backward scan the same way
        RainbowAlga.request_search!(drba, :previous)
        @test drba.simparams.pending_search === :previous
        @test vis[] == true
        RainbowAlga.step_pending_search!(drba)                 # wait frame
        RainbowAlga.step_pending_search!(drba)                 # scan frame
        @test iseven(drba.current_event_idx)
        @test vis[] == false

        # A search whose event load throws must not propagate out of the render step nor leave
        # the "Searching..." overlay stuck: the error is caught+warned and the overlay hidden.
        trba = RBA(KM3io.Detector(joinpath(datadir, "detector.dynamical.datx")))
        RainbowAlga.setup_search_overlay!(trba)
        tvis = trba._plots["searching_visible"]
        trba.current_event_idx = 0
        trba.eventfile = ThrowingLoadFile()
        RainbowAlga.request_search!(trba, :next)
        @test tvis[] == true
        RainbowAlga.step_pending_search!(trba)                 # wait frame
        @test tvis[] == true
        # scan frame: load throws internally -> caught (warns), overlay hidden, state cleared,
        # and crucially no exception escapes to crash the render loop.
        @test_logs (:warn,) match_mode = :any RainbowAlga.step_pending_search!(trba)
        @test trba.simparams.pending_search === :none
        @test trba.simparams.search_frames_waited == 0
        @test tvis[] == false
    end

    # End-to-end with the bundled offline file: a selector lands on the first accepted event
    # and a reject-all selector falls back to event 1.
    @testset "selector end-to-end" begin
        @test RainbowAlga.eventselector(f) === nothing   # plain EventFile has no selector

        fsel = EventFile(joinpath(datadir, "KM3-230213A_allhits.root"),
                         joinpath(datadir, "detector.dynamical.datx");
                         selector = (evt, det) -> length(evt.hits) > 0)
        @test RainbowAlga.eventselector(fsel) !== nothing
        selrba = RBA()
        load!(selrba, fsel)
        @test selrba.current_event_idx >= 1
        @test RainbowAlga.is_selected!(selrba, selrba.current_event_idx)
        @test !isempty(selrba.selected_events)
        @test issorted(selrba.selected_events) && allunique(selrba.selected_events)

        # driving the public navigation functions stays on an accepted event
        next_selected_event!(selrba)
        @test RainbowAlga.is_selected!(selrba, selrba.current_event_idx)
        previous_selected_event!(selrba)
        @test RainbowAlga.is_selected!(selrba, selrba.current_event_idx)

        # navigation on a file without a selector is a no-op (keeps the current event)
        idx0 = erba.current_event_idx
        next_selected_event!(erba)
        @test erba.current_event_idx == idx0

        fnone = EventFile(joinpath(datadir, "KM3-230213A_allhits.root"),
                          joinpath(datadir, "detector.dynamical.datx");
                          selector = (evt, det) -> false)
        norba = RBA()
        load!(norba, fnone)
        @test norba.current_event_idx == 1          # fallback to event 1
        @test isempty(norba.selected_events)
    end

    # run(...) convenience methods dispatch on paths/objects and forward source + selector
    # to the EventFile constructor (the window-opening path itself is not exercised here).
    @testset "run convenience signatures" begin
        @test hasmethod(RainbowAlga.run, Tuple{AbstractString, AbstractString}, (:source, :selector, :interactive))
        @test hasmethod(RainbowAlga.run, Tuple{AbstractString, KM3io.Detector}, (:source, :selector, :interactive))
        @test hasmethod(RainbowAlga.run, Tuple{KM3io.ROOTFile, KM3io.Detector}, (:source, :selector, :interactive))
    end
end
