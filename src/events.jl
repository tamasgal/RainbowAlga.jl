# Event navigation and the run entrypoints.

"""
Load the event at sequential index `idx` from the attached [`AbstractEventFile`](@ref) and
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
    # Reading and calibrating the hits (eventsample) is the slow part, so announce it first.
    print_status("Loading event $idx / $n (reading and calibrating hits) ...")
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

"""
    next_event!()

Show the next event of the currently loaded event file (bound to the `N` key).
"""
next_event!(rba::RBA) = load_event!(rba, rba.current_event_idx + 1)
next_event!() = next_event!(global_rba())

"""
    previous_event!()

Show the previous event of the currently loaded event file (bound to `Shift+N`).
"""
previous_event!(rba::RBA) = load_event!(rba, rba.current_event_idx - 1)
previous_event!() = previous_event!(global_rba())

"""
Return whether event `idx` is accepted by the attached event file's selector, caching the
verdict in `rba._selection_verdicts` so the selector runs at most once per event. Files
without a selector accept every event. A selector that throws is treated as a rejection.
"""
function is_selected!(rba::RBA, idx::Int)
    f = rba.eventfile
    isnothing(f) && return false
    sel = eventselector(f)
    isnothing(sel) && return true  # no selector -> every event qualifies
    get!(rba._selection_verdicts, idx) do
        ok = try
            sel(rawevent(f, idx), geometry(f))::Bool
        catch e
            @warn "Selector errored on event $idx; treating as rejected." exception = (e, catch_backtrace())
            false
        end
        # The do-block runs only on a cache miss, so each accepted index is inserted once.
        ok && insert!(rba.selected_events, searchsortedfirst(rba.selected_events, idx), idx)
        ok
    end
end

"""
Run the selector on the *first* event, returning its `Bool` verdict and priming the verdict
cache (and `selected_events`) accordingly. Meant to be called before the full match scan and
before the window opens: a selector that throws on the first event is almost certainly broken,
so this rethrows with an actionable message instead of letting [`find_selected_from`](@ref)
rerun the same error on every event -- which prints a backtrace per event and looks like an
unstoppable hang. Returns `nothing` when the file has no selector or no events.
"""
function check_first_event_selector!(rba::RBA, f::AbstractEventFile)
    sel = eventselector(f)
    (isnothing(sel) || nevents(f) == 0) && return nothing
    first_ok = try
        sel(rawevent(f, 1), geometry(f))::Bool
    catch e
        error("The event selector threw on the first event, so the display was not opened. " *
              "It must be a function `(event, detector) -> Bool` that returns a Bool and does " *
              "not throw. Underlying error: " * sprint(showerror, e))
    end
    # Prime the cache so the scan below does not re-evaluate event 1.
    rba._selection_verdicts[1] = first_ok
    first_ok && insert!(rba.selected_events, searchsortedfirst(rba.selected_events, 1), 1)
    first_ok
end

"""
Find the first event index accepted by the selector when walking from `start` in direction
`step` (`+1`/`-1`), wrapping around the end. Returns `nothing` if no event in the whole file
is accepted. `start == 0` (no event loaded) begins at the first/last index. Lazy: only the
indices it visits are evaluated, and each is cached via [`is_selected!`](@ref).

While walking it overwrites a single terminal line with the event currently being checked, so a
slow (disk-bound) scan shows live progress instead of looking hung. The line is only drawn once
the scan has been running for a moment and then at ~10 Hz, so a fast, fully-cached scan prints
nothing and adds no flush overhead, and it is erased before the function returns.
"""
function find_selected_from(rba::RBA, start::Int, step::Int)
    f = rba.eventfile
    isnothing(f) && return nothing
    n = nevents(f)
    n == 0 && return nothing
    # Normalize a "no current event" start so the first candidate is index 1 (forward) or n (backward).
    if start < 1 || start > n
        start = step > 0 ? 0 : n + 1
    end
    cur = start
    width = ndigits(n)
    prefix = "Searching... event "
    msg_len = length(prefix) + 2 * width + 1  # "cur/n", each of cur and n `width` wide, plus "/"
    printed = false
    last_print = time()
    for _ in 1:n
        cur = mod1(cur + step, n)
        now = time()
        if now - last_print > 0.1
            print("\r", prefix, lpad(cur, width), "/", n)
            flush(stdout)
            last_print = now
            printed = true
        end
        if is_selected!(rba, cur)
            printed && (print("\r", " "^msg_len, "\r"); flush(stdout))
            return cur
        end
    end
    printed && (print("\r", " "^msg_len, "\r"); flush(stdout))
    nothing
end

"""
    next_selected_event!()

Show the next event accepted by the event file's selector (bound to the `S` key), wrapping
to the first accepted event past the end. Does nothing if the file has no selector.
"""
function next_selected_event!(rba::RBA)
    isnothing(rba.eventfile) && return
    if isnothing(eventselector(rba.eventfile))
        @info "No selector set on this event file; use N / Shift+N for sequential navigation."
        return
    end
    idx = find_selected_from(rba, rba.current_event_idx, 1)
    if isnothing(idx)
        @info "No events match the selector."
    elseif idx != rba.current_event_idx  # avoid reloading when it is the only accepted event
        load_event!(rba, idx)
    end
    nothing
end
next_selected_event!() = next_selected_event!(global_rba())

"""
    previous_selected_event!()

Show the previous event accepted by the event file's selector (bound to `Shift+S`), wrapping
to the last accepted event past the start. Does nothing if the file has no selector.
"""
function previous_selected_event!(rba::RBA)
    isnothing(rba.eventfile) && return
    if isnothing(eventselector(rba.eventfile))
        @info "No selector set on this event file; use N / Shift+N for sequential navigation."
        return
    end
    idx = find_selected_from(rba, rba.current_event_idx, -1)
    if isnothing(idx)
        @info "No events match the selector."
    elseif idx != rba.current_event_idx
        load_event!(rba, idx)
    end
    nothing
end
previous_selected_event!() = previous_selected_event!(global_rba())

function run(rba::RBA; interactive=true)
    print_status("Centering the camera ...")
    center!(rba.scene)
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
    print_status("Drawing the detector geometry ...")
    update!(rba, geometry(f))
    rba.eventfile = f
    empty!(rba.selected_events)
    empty!(rba._selection_verdicts)
    if isnothing(eventselector(f))
        load_event!(rba, 1)
        return rba
    end
    if nevents(f) == 0
        @warn "The event file contains no events."
        return rba
    end
    # Before scanning the whole file (and before the window opens) make sure the selector runs
    # on the first event and returns a Bool; a broken selector fails fast here with one clear
    # message instead of throwing on every event during the scan below.
    first_ok = check_first_event_selector!(rba, f)
    @info "Selector: the first event " * (first_ok ? "matches" : "does not match") *
          "; scanning for a matching event ..."
    # Confirm at least one event matches before launching, so an all-rejecting selector is
    # reported up front instead of silently opening on event 1.
    idx = find_selected_from(rba, 0, 1)
    if isnothing(idx)
        @warn "No events match the selector; opening event 1 (use N / Shift+N for sequential navigation)."
        load_event!(rba, 1)
    else
        @info "Selector matched event $idx; $(length(rba.selected_events)) matching event(s) found so far. Opening it."
        load_event!(rba, idx)
    end
    rba
end

"""
Start RainbowAlga with an [`AbstractEventFile`](@ref) (e.g. an [`EventFile`](@ref) wrapping a
KM3NeT online or offline ROOT file). The geometry is drawn once and the first event is
shown; N / Shift+N navigate forward/backward and E lets you jump by index.
"""
function run(f::AbstractEventFile; interactive=true)
    rba = global_rba()
    load!(rba, f)
    run(rba; interactive=interactive)
end
