# Summaryslice visualisation: animate per-PMT (or per-DOM) rates over the detector by
# stepping through summaryslice frame indices instead of continuous nanosecond time.
#
# A KM3NeT online ROOT file stores one `Summaryslice` per frame index (each 100 ms),
# holding one `SummaryFrame` per active optical module with 31 log-encoded PMT rates
# (2 kHz - 2 MHz). In this mode "play" advances the slice ordinal and every frame repaints
# the shared `rate_mesh`; there are no hits to reveal and no tracks.

"""
    SummarysliceFile(rootfile, detector)
    SummarysliceFile(rootfile_path, detector_or_detx_path)

A KM3NeT online `KM3io.ROOTFile` (which must contain summaryslices) bundled with the
`Detector` used to draw the geometry and to place the rate field. Drive it with
[`run`](@ref) to open an interactive summaryslice display.
"""
struct SummarysliceFile
    rootfile::KM3io.ROOTFile
    detector::Detector
    function SummarysliceFile(rootfile::KM3io.ROOTFile, detector::Detector)
        hassummaryslices(rootfile) || error("This ROOT file has no summaryslices.")
        new(rootfile, detector)
    end
end
SummarysliceFile(rootfile_path::AbstractString, detector::Detector) =
    SummarysliceFile(KM3io.ROOTFile(rootfile_path), detector)
SummarysliceFile(rootfile_path::AbstractString, detector_path::AbstractString) =
    SummarysliceFile(rootfile_path, Detector(detector_path))

nslices(f::SummarysliceFile) = length(f.rootfile.online.summaryslices)
getslice(f::SummarysliceFile, i::Integer) = f.rootfile.online.summaryslices[i]

"""
Per-module geometry index built once from a `Detector`, mapping summaryslice DOM ids to
positions in the two rate-field point clouds (per-PMT and per-DOM). The position vectors
are stored in a stable order and the dictionaries map a `dom_id` to its slot(s), so each
frame only needs to scatter the decoded rates into pre-allocated arrays.
"""
struct RateGeometry
    pmt_positions::Vector{Point3f}                 # one per PMT, detector + channel order
    pmt_channels::Vector{Int}                      # PMT channel (0..30) for each slot above
    pmt_dom_ranges::Dict{Int32, UnitRange{Int}}    # dom_id -> contiguous slice into pmt_positions
    dom_positions::Vector{Point3f}                 # one per optical module
    dom_index::Dict{Int32, Int}                    # dom_id -> index into dom_positions
end

"""
Build the [`RateGeometry`](@ref) for `det`. The per-PMT positions use the same outward
offset as the PMT markers drawn by `update!(::RBA, ::Detector)`, so the rate field sits on
the optical modules.
"""
function build_rate_geometry(det::Detector; dom_diameter=0.4, pmt_diameter=0.076, dom_scaling=5)
    pmt_positions = Point3f[]
    pmt_channels = Int[]
    pmt_dom_ranges = Dict{Int32, UnitRange{Int}}()
    dom_positions = Point3f[]
    dom_index = Dict{Int32, Int}()
    for m in det
        isopticalmodule(m) || continue
        push!(dom_positions, Point3f(m.pos))
        dom_index[Int32(m.id)] = length(dom_positions)
        start = length(pmt_positions) + 1
        for (ch1, pmt) in enumerate(m)  # iterating a module yields its PMTs in channel order
            pos = pmt.pos + pmt.dir*dom_diameter*dom_scaling - pmt.dir*pmt_diameter*dom_scaling
            push!(pmt_positions, Point3f(pos))
            push!(pmt_channels, ch1 - 1)
        end
        pmt_dom_ranges[Int32(m.id)] = start:length(pmt_positions)
    end
    RateGeometry(pmt_positions, pmt_channels, pmt_dom_ranges, dom_positions, dom_index)
end

# Default rate colorbar limits. KM3io can encode 2 kHz - 2 MHz, but a typical single-PMT
# rate is dominated by K40 (a few kHz) plus bioluminescence, so the full range squashes
# everything into the bottom of the colormap. These tighter defaults give the PMT view good
# contrast; the right-mouse colorbar drag widens/shifts them and double-click resets here.
const DEFAULT_RATE_MIN_HZ = 2.0e3   # 2 kHz
const DEFAULT_RATE_MAX_HZ = 2.0e4   # 20 kHz

"""
All runtime-configurable state of the summaryslice display. Held by `RBA.summaryslices`.
Every cue is independently toggleable: granularity (PMT/DOM), colour scale (log/lin),
marker size (fixed/rate-scaled), HRV and FIFO highlighting and how DOMs without data in a
slice are drawn.
"""
Base.@kwdef mutable struct SummarysliceDisplay <: AbstractSummarysliceView
    file::SummarysliceFile
    geom::RateGeometry
    granularity::Symbol = :pmt          # :pmt | :dom               (G)
    applied_granularity::Symbol = :none # which positions are on the mesh
    color_scale::Symbol = :log          # :log | :lin               (K)
    size_mode::Symbol = :rate           # :fixed | :rate            (R)
    show_hrv::Bool = true               # highlight high-rate-veto   (U)
    show_fifo::Bool = true              # highlight FIFO-almost-full (I)
    hide_nodata::Bool = true            # hide vs dim no-data DOMs   (Y)
    smoothing::Bool = false             # average rates over a slice window (S)
    smoothing_window::Int = 5           # number of slices averaged   ([ / ])
    rate_min::Float64 = DEFAULT_RATE_MIN_HZ
    rate_max::Float64 = DEFAULT_RATE_MAX_HZ
    colorscheme::Symbol = :viridis
    alpha::Float64 = 0.95
    base_size_pmt::Float64 = 5.0
    base_size_dom::Float64 = 12.0
    size_scale::Float64 = 1.0           # adjusted with - / =
    hrv_color::RGBAf = RGBAf(1.0, 0.1, 0.1, 1.0)
    fifo_color::RGBAf = RGBAf(1.0, 0.6, 0.0, 1.0)
    nodata_color::RGBAf = RGBAf(0.45, 0.45, 0.45, 0.25)
    # Cached stats of the currently shown slice (for the infobox; avoids re-reading it).
    current_index::Int = 0              # 1-based slice number
    current_frame_index::Int = 0        # hardware frame_index from the slice header
    current_utc::DateTime = unix2datetime(0)
    n_active::Int = 0                   # active optical modules in the slice
    n_hrv::Int = 0                      # PMT channels in high-rate veto across the slice
    # Memoised single-slice decoded fields, keyed by (granularity, ordinal); reused by the
    # smoothing window and by plain stepping so each slice is decoded at most once.
    _field_cache::Dict{Tuple{Symbol,Int}, Tuple{Vector{Float64},BitVector,BitVector,BitVector}} =
        Dict{Tuple{Symbol,Int}, Tuple{Vector{Float64},BitVector,BitVector,BitVector}}()
end
Base.show(io::IO, d::SummarysliceDisplay) =
    print(io, "SummarysliceDisplay($(nslices(d.file)) slices, $(d.granularity))")

const RATE_COLORSCHEMES = [:viridis, :hawaii, :inferno, :turbo, :thermal]

# Decode the PMT rates / HRV / FIFO / has-data of one slice into arrays aligned with the
# per-PMT positions of the geometry index.
function pmt_frame_data(d::SummarysliceDisplay, slice)
    geom = d.geom
    n = length(geom.pmt_positions)
    rates = zeros(Float64, n)
    hrv = falses(n)
    fifo = falses(n)
    hasdata = falses(n)
    for frame in slice.frames
        rng = get(geom.pmt_dom_ranges, frame.dom_id, nothing)
        rng === nothing && continue
        frrates = pmtrates(frame)
        for slot in rng
            ch = geom.pmt_channels[slot]  # 0..30
            rates[slot] = frrates[ch + 1]
            hrv[slot] = hrvstatus(frame, ch)
            fifo[slot] = fifostatus(frame, ch)
            hasdata[slot] = true
        end
    end
    (rates, hrv, fifo, hasdata)
end

# Same, but aggregated per optical module (mean PMT rate, so the same rate colorbar serves
# both granularities; HRV/FIFO are "any channel flagged").
function dom_frame_data(d::SummarysliceDisplay, slice)
    geom = d.geom
    n = length(geom.dom_positions)
    rates = zeros(Float64, n)
    hrv = falses(n)
    fifo = falses(n)
    hasdata = falses(n)
    for frame in slice.frames
        idx = get(geom.dom_index, frame.dom_id, nothing)
        idx === nothing && continue
        rs = pmtrates(frame)
        rates[idx] = sum(rs) / length(rs)
        hrv[idx] = hrvstatus(frame)
        fifo[idx] = fifostatus(frame)
        hasdata[idx] = true
    end
    (rates, hrv, fifo, hasdata)
end

# Normalised position [0, 1] of a rate on the configured (log or linear) scale.
function rate_fraction(rate, d::SummarysliceDisplay)
    rmin, rmax = d.rate_min, d.rate_max
    frac = if d.color_scale === :log
        (log(max(rate, rmin)) - log(rmin)) / (log(rmax) - log(rmin))
    else
        (rate - rmin) / (rmax - rmin)
    end
    clamp(frac, 0.0, 1.0)
end

# Turn the decoded rate field into per-point colours and marker sizes for the shared mesh.
function frame_appearance(d::SummarysliceDisplay, rates, hrv, fifo, hasdata, base)
    cmap = getproperty(ColorSchemes, d.colorscheme)
    n = length(rates)
    colors = Vector{RGBAf}(undef, n)
    sizes = Vector{Float64}(undef, n)
    for i in 1:n
        if !hasdata[i]
            if d.hide_nodata
                colors[i] = RGBAf(0, 0, 0, 0)
                sizes[i] = 0.0
            else
                colors[i] = d.nodata_color
                sizes[i] = base * d.size_scale * 0.5
            end
            continue
        end
        frac = rate_fraction(rates[i], d)
        if d.show_hrv && hrv[i]
            colors[i] = d.hrv_color
        elseif d.show_fifo && fifo[i]
            colors[i] = d.fifo_color
        else
            c = cmap[frac]
            colors[i] = RGBAf(c.r, c.g, c.b, d.alpha)
        end
        sizes[i] = d.size_mode === :fixed ? base * d.size_scale :
                   base * d.size_scale * (0.4 + 1.2 * frac)
    end
    (colors, sizes)
end

# One slice's decoded field at the current granularity, memoised by (granularity, ordinal).
function slice_field(d::SummarysliceDisplay, ordinal::Int)
    key = (d.granularity, ordinal)
    cached = get(d._field_cache, key, nothing)
    cached === nothing || return cached
    slice = getslice(d.file, ordinal + 1)
    field = d.granularity === :pmt ? pmt_frame_data(d, slice) : dom_frame_data(d, slice)
    length(d._field_cache) > 1024 && empty!(d._field_cache)  # crude bound on the cache size
    d._field_cache[key] = field
    field
end

# The rate field to display at `ordinal`: a single slice, or the per-slot mean over a
# centred window of `smoothing_window` slices when smoothing is on. Averaging suppresses
# single-slice outliers. HRV/FIFO flags are taken from the centre slice so status stays
# instantaneous; only the rate magnitude is smoothed.
function current_field(d::SummarysliceDisplay, ordinal::Int)
    nsl = nslices(d.file)
    center = clamp(ordinal, 0, nsl - 1)
    if !d.smoothing || d.smoothing_window <= 1 || nsl <= 1
        return slice_field(d, center)
    end
    half = (d.smoothing_window - 1) ÷ 2
    lo = clamp(center - half, 0, nsl - 1)
    hi = clamp(center + half, 0, nsl - 1)
    rates_c, hrv, fifo, _ = slice_field(d, center)
    n = length(rates_c)
    sumr = zeros(Float64, n)
    cnt = zeros(Int, n)
    for o in lo:hi
        r, _, _, hd = slice_field(d, o)
        @inbounds for i in 1:n
            if hd[i]
                sumr[i] += r[i]
                cnt[i] += 1
            end
        end
    end
    rates = [cnt[i] > 0 ? sumr[i] / cnt[i] : 0.0 for i in 1:n]
    hasdata = BitVector(cnt[i] > 0 for i in 1:n)
    (rates, hrv, fifo, hasdata)
end

"""
    apply_slice!(rba, ordinal)

Repaint the shared `rate_mesh` for summaryslice `ordinal` (0-based, clamped to the file).
Mirrors [`apply_frame!`](@ref) for the time-animation mode: positions are only re-uploaded
when the granularity changes, colours and sizes every call. When smoothing is enabled the
rates are averaged over a window of slices (see [`current_field`](@ref)).
"""
function apply_slice!(rba::RBA, ordinal::Integer)
    d = rba.summaryslices
    d === nothing && return rba
    n = nslices(d.file)
    n == 0 && return rba
    i0 = clamp(Int(ordinal), 0, n - 1)

    if d.applied_granularity !== d.granularity
        rba.rate_mesh.positions[] = d.granularity === :pmt ? d.geom.pmt_positions : d.geom.dom_positions
        d.applied_granularity = d.granularity
    end

    rates, hrv, fifo, hasdata = current_field(d, i0)
    base = d.granularity === :pmt ? d.base_size_pmt : d.base_size_dom
    colors, sizes = frame_appearance(d, rates, hrv, fifo, hasdata, base)
    rba.rate_mesh.color[] = colors
    rba.rate_mesh.markersize[] = sizes

    slice = getslice(d.file, i0 + 1)
    d.current_index = i0 + 1
    d.current_frame_index = Int(slice.header.frame_index)
    d.current_utc = convert(DateTime, slice.header.t)
    d.n_active = length(slice.frames)
    d.n_hrv = isempty(slice.frames) ? 0 : sum(count_hrvstatus(fr) for fr in slice.frames)
    rba
end

# Refresh the mesh in place after a configuration toggle (so paused displays update too).
refresh_slice!(rba::RBA) = apply_slice!(rba, rba.simparams.frame_idx)

function toggle_granularity!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.granularity = d.granularity === :pmt ? :dom : :pmt
    refresh_slice!(rba)
    println("Summaryslice granularity: $(d.granularity)")
end
function toggle_color_scale!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.color_scale = d.color_scale === :log ? :lin : :log
    refresh_slice!(rba)
    update_colorbar!(rba)
    println("Summaryslice rate scale: $(d.color_scale)")
end
function toggle_size_mode!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.size_mode = d.size_mode === :fixed ? :rate : :fixed
    refresh_slice!(rba)
    println("Summaryslice marker size: $(d.size_mode)")
end
function toggle_hrv_highlight!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.show_hrv = !d.show_hrv
    refresh_slice!(rba)
    println("Summaryslice HRV highlight: $(d.show_hrv ? "on" : "off")")
end
function toggle_fifo_highlight!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.show_fifo = !d.show_fifo
    refresh_slice!(rba)
    println("Summaryslice FIFO highlight: $(d.show_fifo ? "on" : "off")")
end
function toggle_hide_nodata!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.hide_nodata = !d.hide_nodata
    refresh_slice!(rba)
    println("Summaryslice no-data DOMs: $(d.hide_nodata ? "hidden" : "dimmed")")
end
function cycle_colorscheme!(rba::RBA, dir::Int)
    d = rba.summaryslices; d === nothing && return
    i = findfirst(==(d.colorscheme), RATE_COLORSCHEMES)
    i = i === nothing ? 1 : mod1(i + dir, length(RATE_COLORSCHEMES))
    d.colorscheme = RATE_COLORSCHEMES[i]
    refresh_slice!(rba)
    update_colorbar!(rba)
    println("Summaryslice colour scheme: $(d.colorscheme)")
end
function scale_marker_size!(rba::RBA, factor)
    d = rba.summaryslices; d === nothing && return
    d.size_scale = clamp(d.size_scale * factor, 0.1, 20.0)
    refresh_slice!(rba)
end
function toggle_smoothing!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.smoothing = !d.smoothing
    refresh_slice!(rba)
    println("Summaryslice smoothing: $(d.smoothing ? "on ($(d.smoothing_window) slices)" : "off")")
end
function change_smoothing_window!(rba::RBA, delta::Int)
    d = rba.summaryslices; d === nothing && return
    d.smoothing_window = clamp(d.smoothing_window + delta, 1, 101)
    d.smoothing && refresh_slice!(rba)
    println("Summaryslice smoothing window: $(d.smoothing_window) slices" *
            (d.smoothing ? "" : " (smoothing off)"))
end

"""
Reset the rate colour scale to the default limits ([`DEFAULT_RATE_MIN_HZ`],
[`DEFAULT_RATE_MAX_HZ`]). Bound to a double right-click on the colorbar, mirroring the
time-window reset in event mode.
"""
function reset_rate_bounds!(rba::RBA)
    d = rba.summaryslices; d === nothing && return
    d.rate_min = DEFAULT_RATE_MIN_HZ
    d.rate_max = DEFAULT_RATE_MAX_HZ
    refresh_slice!(rba)
    update_colorbar!(rba)
end

"""
Adjust the rate colour scale by a right-mouse drag on the colorbar (like the event time
window): horizontal `dx` expands (right) / shrinks (left) the rate range about its centre,
vertical `dy` shifts it towards higher (up) / lower (down) rates. Works in log space for a
log scale and linearly otherwise; `cb_h` is the colorbar height in pixels.
"""
function adjust_rate_bounds!(rba::RBA, dx, dy, cb_h)
    d = rba.summaryslices; d === nothing && return
    if d.color_scale === :log
        lo, hi = log10(d.rate_min), log10(d.rate_max)
        span = hi - lo
        if dx != 0
            c = (lo + hi) / 2
            span = clamp(span * (1 + dx / 150), 0.3, 6.0)  # 0.3 .. 6 decades
            lo, hi = c - span/2, c + span/2
        end
        if dy != 0
            shift = -dy * span / cb_h
            lo += shift; hi += shift
        end
        lo = clamp(lo, 0.0, 8.0)               # 1 Hz .. 100 MHz
        hi = clamp(hi, lo + 0.1, 8.3)
        d.rate_min = 10.0^lo
        d.rate_max = 10.0^hi
    else
        lo, hi = d.rate_min, d.rate_max
        span = hi - lo
        if dx != 0
            c = (lo + hi) / 2
            span = clamp(span * (1 + dx / 150), 100.0, 1e8)
            lo, hi = c - span/2, c + span/2
        end
        if dy != 0
            shift = -dy * span / cb_h
            lo += shift; hi += shift
        end
        lo = max(lo, 0.0)
        hi = max(hi, lo + 1.0)
        d.rate_min = lo
        d.rate_max = hi
    end
    refresh_slice!(rba)
    update_colorbar!(rba)
end

"""
    load_summaryslices!([rba::RBA], f::SummarysliceFile; kwargs...)

Switch `rba` into summaryslice mode: draw the geometry of `f`, build the rate-field
geometry index and show the first slice. Extra keyword arguments are forwarded to
[`SummarysliceDisplay`](@ref) (e.g. `granularity=:dom`, `color_scale=:lin`). Does not open
a window (use [`run`](@ref)).
"""
function load_summaryslices!(rba::RBA, f::SummarysliceFile; kwargs...)
    update!(rba, f.detector)
    geom = build_rate_geometry(f.detector)
    rba.eventfile = nothing
    rba.summaryslices = SummarysliceDisplay(; file=f, geom=geom, kwargs...)
    sp = rba.simparams
    sp.animation_mode = :summaryslice
    sp.frame_idx = 0
    sp.speed = 1
    sp.loop_enabled = true
    sp.loop_end_frame_idx = max(0, nslices(f) - 1)
    apply_slice!(rba, 0)
    update_colorbar!(rba)
    rba
end
load_summaryslices!(f::SummarysliceFile; kwargs...) = load_summaryslices!(global_rba(), f; kwargs...)

"""
Start RainbowAlga in summaryslice mode from a [`SummarysliceFile`](@ref). The detector is
drawn once and the first slice shown; Space plays/pauses through the slices (100 ms each),
Left/Right step a single slice and G/K/R/U/I/Y toggle the display options.
"""
function run(f::SummarysliceFile; interactive=true, kwargs...)
    rba = global_rba()
    load_summaryslices!(rba, f; kwargs...)
    run(rba; interactive=interactive)
end
