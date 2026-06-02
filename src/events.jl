# Event navigation and the run entrypoints.

"""
Load the event at sequential index `idx` from the attached [`AbstractEventFile`] and
replace the current hit display (and, for offline events, the reconstructed/MC tracks).
The detector geometry and the shared hits mesh are reused.
"""
function load_event!(rba::RBA, idx::Int)
    f = rba.eventfile
    isnothing(f) && return
    n = nevents(f)
    n == 0 && return
    idx = clamp(idx, 1, n)
    rba.current_event_idx = idx
    empty!(rba)  # clears tracks + hits, keeps detector + shared mesh
    s = eventsample(f, idx)
    rba.current_frame_index = s.frame_index
    rba.current_trigger_counter = s.trigger_counter
    isempty(s.hits) || add!(rba, s.hits; t_range=s.t_range)
    isnothing(s.event) || add_reco_and_mc!(rba, s.event, s.hits)
    reset_time(rba)
    println("Event $idx / $n loaded")
    nothing
end
load_event!(idx::Int) = load_event!(global_rba(), idx)

next_event!(rba::RBA) = load_event!(rba, rba.current_event_idx + 1)
next_event!() = next_event!(global_rba())

previous_event!(rba::RBA) = load_event!(rba, rba.current_event_idx - 1)
previous_event!() = previous_event!(global_rba())

function run(rba::RBA; interactive=true)
    println("Registering events")
    println("Centering scene")
    center!(rba.scene)
    println("Updating camera")
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))
    start_eventloop(rba; interactive=interactive)
    nothing
end
run(;interactive=true) = run(global_rba(); interactive=interactive)

"""
    load!([rba::RBA], f::AbstractEventFile)

Attach an event file, draw its detector geometry once and load the first event. Does
not open a window (use [`run`](@ref) for that).
"""
load!(f::AbstractEventFile) = load!(global_rba(), f)
function load!(rba::RBA, f::AbstractEventFile)
    update!(rba, geometry(f))
    rba.eventfile = f
    load_event!(rba, 1)
    rba
end

"""
Start RainbowAlga with an [`AbstractEventFile`] (e.g. an [`EventFile`] wrapping a
KM3NeT online or offline ROOT file). The geometry is drawn once and the first event is
shown; N / Shift+N navigate forward/backward and E lets you jump by index.
"""
function run(f::AbstractEventFile; interactive=true)
    rba = global_rba()
    load!(rba, f)
    run(rba; interactive=interactive)
end
