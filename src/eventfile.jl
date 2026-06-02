"""

An event file wrapping a `KM3io.ROOTFile` together with the `Detector` needed to
calibrate and display its events. It supports both the online (`:online`) and the
offline (`:offline`) tree:

  - online events (`f.rootfile.online.events`) carry raw DAQ hits which are calibrated
    on the fly via the detector,
  - offline events (`f.rootfile.offline`, of type `KM3io.Evt`) already contain
    calibrated hits and may additionally provide reconstructed and MC tracks.

In both cases the full detector geometry is drawn (including DOMs without hits).

"""
mutable struct EventFile <: AbstractEventFile
    rootfile::KM3io.ROOTFile
    detector::KM3io.Detector
    source::Symbol   # :online or :offline
    idx::Int         # 1-based index of the currently shown event (0 = none loaded yet)
end

function EventFile(rootfile::KM3io.ROOTFile, detector::KM3io.Detector; source::Union{Nothing, Symbol}=nothing)
    if isnothing(source)
        source = !isnothing(rootfile.offline) ? :offline : :online
    end
    source in (:online, :offline) || error("`source` has to be :online or :offline, got :$(source)")
    source === :online && isnothing(rootfile.online) && error("The file has no online tree.")
    source === :offline && isnothing(rootfile.offline) && error("The file has no offline tree.")
    EventFile(rootfile, detector, source, 0)
end
EventFile(rootfile_path::AbstractString, detector::KM3io.Detector; kwargs...) =
    EventFile(KM3io.ROOTFile(rootfile_path), detector; kwargs...)
EventFile(rootfile_path::AbstractString, detector_path::AbstractString; kwargs...) =
    EventFile(rootfile_path, KM3io.Detector(detector_path); kwargs...)

"""
Number of events in the currently selected tree.
"""
nevents(f::EventFile) = f.source === :online ? length(f.rootfile.online.events) : length(f.rootfile.offline)

_getevent(f::EventFile, idx::Integer) =
    f.source === :online ? f.rootfile.online.events[idx] : f.rootfile.offline[idx]

# Online events need calibration, offline events already carry calibrated hits.
_calibrated_hits(f::EventFile, event::KM3io.DAQEvent) =
    KM3io.calibrate(f.detector, KM3io.combine(event.snapshot_hits, event.triggered_hits))
_calibrated_hits(::EventFile, event::KM3io.Evt) = event.hits

"""
Short one-line description of the current position in the event file, shown in the
infobox.
"""
eventinfo(f::EventFile) = "Event $(f.idx)/$(nevents(f)) ($(f.source))"
eventinfo(::AbstractEventFile) = ""

"""
    load!([rba::RBA], f::EventFile; event_idx=1)

Attach the event file to the display, draw the detector geometry once and show the
first (or `event_idx`-th) event.
"""
load!(f::AbstractEventFile; kwargs...) = load!(global_rba(), f; kwargs...)
function load!(rba::RBA, f::EventFile; event_idx::Int=1)
    rba.eventfile = f
    println("Drawing detector geometry")
    update!(rba, f.detector)
    show_event!(rba, f, event_idx)
end

"""
    show_event!([rba::RBA, f::EventFile,] idx::Int)

Show the `idx`-th event of the file (1-based, wrapping around). The detector geometry
and the shared hits mesh are reused; only the per-event tracks and hits are replaced.
"""
show_event!(idx::Int) = (rba = global_rba(); show_event!(rba, rba.eventfile, idx))
function show_event!(rba::RBA, f::EventFile, idx::Int)
    n = nevents(f)
    if n == 0
        println("No $(f.source) events in this file.")
        return rba
    end
    idx = mod1(idx, n)
    f.idx = idx
    event = _getevent(f, idx)
    println("Loading $(f.source) event $(idx)/$(n)")

    empty!(rba)
    rba.simparams.frame_idx = 0

    hits = _calibrated_hits(f, event)
    if isempty(hits)
        println("  event has no hits")
    end

    if event isa KM3io.Evt
        add_event!(rba, event, hits)
    else
        isempty(hits) || add!(rba, hits)
    end
    apply_hitscloud!(rba)
    rba
end

"""
    next_event!(); previous_event!()

Step to the next / previous event of the currently loaded event file.
"""
next_event!() = (rba = global_rba(); next_event!(rba, rba.eventfile))
previous_event!() = (rba = global_rba(); previous_event!(rba, rba.eventfile))
next_event!(rba::RBA, f::EventFile) = show_event!(rba, f, f.idx + 1)
previous_event!(rba::RBA, f::EventFile) = show_event!(rba, f, f.idx - 1)
