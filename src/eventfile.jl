"""
    EventFile(rootfile, detector; source=nothing)
    EventFile(rootfile_path, detector_or_detx_path; source=nothing)

Built-in [`AbstractEventFile`] bundling a `KM3io.ROOTFile` with the `Detector` used to
draw the geometry and (for online events) calibrate the hits.

`source` selects the tree:

  - `:online`  -- raw DAQ events (`f.rootfile.online.events`), calibrated on the fly,
  - `:offline` -- `KM3io.Evt` events (`f.rootfile.offline`) with already-calibrated
    hits and optional reconstructed/MC tracks.

When omitted, it defaults to `:offline` if the file has an offline tree, otherwise
`:online`.
"""
struct EventFile <: AbstractEventFile
    rootfile::KM3io.ROOTFile
    detector::Detector
    source::Symbol
end

function EventFile(rootfile::KM3io.ROOTFile, detector::Detector; source::Union{Nothing, Symbol}=nothing)
    if isnothing(source)
        source = !isnothing(rootfile.offline) ? :offline : :online
    end
    source in (:online, :offline) || error("`source` has to be :online or :offline, got :$(source)")
    source === :online && isnothing(rootfile.online) && error("The file has no online tree.")
    source === :offline && isnothing(rootfile.offline) && error("The file has no offline tree.")
    EventFile(rootfile, detector, source)
end
EventFile(rootfile_path::AbstractString, detector::Detector; kwargs...) =
    EventFile(KM3io.ROOTFile(rootfile_path), detector; kwargs...)
EventFile(rootfile_path::AbstractString, detector_path::AbstractString; kwargs...) =
    EventFile(rootfile_path, Detector(detector_path); kwargs...)

geometry(f::EventFile) = f.detector
nevents(f::EventFile) = f.source === :online ? length(f.rootfile.online.events) : length(f.rootfile.offline)

function eventsample(f::EventFile, idx::Int)
    if f.source === :online
        event = getevent(f.rootfile.online, idx)
        hits = calibrate(f.detector, event.snapshot_hits)
        t_range = isempty(event.triggered_hits) ? nothing :
                  extrema(h.t for h in calibrate(f.detector, event.triggered_hits))
        return (hits = hits, t_range = t_range,
                frame_index = Int(event.header.frame_index),
                trigger_counter = Int(event.header.trigger_counter),
                event = nothing)
    else
        event = f.rootfile.offline[idx]
        hits = event.hits
        trig = triggered(hits)
        t_range = isempty(trig) ? nothing : extrema(h.t for h in trig)
        return (hits = hits, t_range = t_range,
                frame_index = Int(event.frame_index),
                trigger_counter = Int(event.trigger_counter),
                event = event)
    end
end

"""
Load an online event identified by its `frame_index` and `trigger_counter` (used by the
F-key modal input). Only meaningful for online event files.
"""
load_event_by_frame_tc!(rba::RBA, frame_index::Int, trigger_counter::Int) =
    load_event_by_frame_tc!(rba, rba.eventfile, frame_index, trigger_counter)
load_event_by_frame_tc!(::RBA, ::Nothing, ::Int, ::Int) = nothing
load_event_by_frame_tc!(::RBA, f::AbstractEventFile, ::Int, ::Int) =
    (@warn "Frame index / trigger counter lookup is not implemented for $(typeof(f))."; nothing)
function load_event_by_frame_tc!(rba::RBA, f::EventFile, frame_index::Int, trigger_counter::Int)
    if f.source !== :online
        @warn "Frame index / trigger counter lookup is only supported for online files."
        return
    end
    event = getevent(f.rootfile.online, frame_index, trigger_counter)
    rba.current_event_idx = 0
    rba.current_frame_index = frame_index
    rba.current_trigger_counter = trigger_counter
    empty!(rba)
    hits = calibrate(f.detector, event.snapshot_hits)
    t_range = isempty(event.triggered_hits) ? nothing :
              extrema(h.t for h in calibrate(f.detector, event.triggered_hits))
    isempty(hits) || add!(rba, hits; t_range = t_range)
    reset_time(rba)
    println("Loaded event with frame_index=$frame_index, trigger_counter=$trigger_counter")
    nothing
end

"""
Convenience: start RainbowAlga directly from a `ROOTFile` and `Detector` (wraps them in
an [`EventFile`], auto-detecting the tree).
"""
run(rootfile::KM3io.ROOTFile, detector::Detector; kwargs...) = run(EventFile(rootfile, detector); kwargs...)
