"""
    AbstractEventFile

Supertype for event sources. An event file bundles the events together with the
detector geometry needed to display them, so a single object fully describes what to
show. Derive from this type and implement the interface below to make a custom event
source navigable with [`next_event!`](@ref) / [`previous_event!`](@ref):

  - `geometry(f)::Detector` -- the detector geometry (drawn once, including DOMs
    without hits).
  - `nevents(f)::Int` -- the number of events available.
  - `eventsample(f, idx::Int)` -- a named tuple
    `(; hits, t_range, frame_index, trigger_counter, event)` describing event `idx`,
    where `hits` are calibrated hits, `t_range` is an optional `(t_min, t_max)` used
    for the colour/time window (or `nothing`), `frame_index`/`trigger_counter` are
    shown in the infobox (use `0` if not applicable) and `event` is the raw event for
    reconstructed/MC track overlays (or `nothing`).

See [`EventFile`](@ref) for the built-in implementation covering KM3NeT online and
offline ROOT files.
"""
abstract type AbstractEventFile end

# Interface (extend these for custom AbstractEventFile subtypes)
function geometry end
function nevents end
function eventsample end

"""
    AbstractSummarysliceView

Supertype for the summaryslice display state held by an [`RBA`](@ref). Declared here (ahead
of `RBA`) so the `RBA.summaryslices` field can refer to it; the concrete `SummarysliceDisplay`
is defined in `summaryslices.jl`.
"""
abstract type AbstractSummarysliceView end
