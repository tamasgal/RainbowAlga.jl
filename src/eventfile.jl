load!(f::AbstractEventFile) = load!(global_rba(), f)
function load!(rba::RBA, f::AbstractEventFile)
    rba.eventfile = f
    println("Updating detector")
    update!(rba, f.detector)
end


# Interface example based on KM3NeT
struct KM3NeTOnlineEventFile <: AbstractEventFile
    eventfile::KM3io.ROOTFile
    detector::KM3io.Detector
    current_event_index::Int
end

function next_event!()
    rba = global_rba()
    next_event!(rba, rba.eventfile)
end
next_event!(f::KM3NeTOnlineEventFile) = next_event!(global_rba(), f)
function next_event!(rba::RBA, f::KM3NeTOnlineEventFile)
    idx = f.current_event_index
    if idx == length(f.eventfile.online.events)
        idx = 1
    else
        idx += 1
    end

    empty!(rba)

    event = f.eventfile.online.events[idx]
    println("Loading event $(event)")
    update!(rba, f.detector)
    hits = calibrate(f.detector, KM3io.combine(event.snapshot_hits, event.triggered_hits))
    add!(hits)
end
