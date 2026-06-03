# Static, off-screen rendering of a scene to an image file (no interactive window).

"""
Simulation time at which the whole event is shown, i.e. just past the latest hit of the
active cloud (so every hit is visible). Falls back to the loop length when there are no
hits. Used as the default freeze time for [`snapshot`](@ref).
"""
function full_event_time(rba::RBA)
    active = active_hitscloud_index(rba)
    active == 0 && return Float64(rba.simparams.loop_end_frame_idx)
    hits = rba.hitsclouds[active].hits
    isempty(hits) && return Float64(rba.simparams.loop_end_frame_idx)
    maximum(h.t for h in hits) - rba.simparams.t_offset
end

"""
    snapshot([rba::RBA], filename; kwargs...) -> filename

Render the scene to an image file off-screen and return `filename`. The file format is
taken from the extension (`.png` is recommended). Unlike [`run`](@ref) this does **not**
open a window or start the animation loop, which makes it suitable for scripts and for
generating figures on a headless machine (e.g. under `xvfb-run`).

The scene is frozen at a single simulation time: hits up to that time are shown and every
track is drawn to its position at that time. By default the whole event is shown (all hits
visible), which extrapolates a through-going track along its full path; pass a smaller
`time` to freeze the animation earlier, e.g. while the muon and its Cherenkov cone are
still crossing the detector.

# Keyword arguments
  - `time`: simulation time in nanoseconds, measured from the start of the event
    (`0` shows nothing yet, the default shows the fully developed event).
  - `size`: output image size in pixels as `(width, height)`.
  - `perspective`: index `1`-`9` of a camera saved with [`save_perspective`](@ref).
  - `eyeposition`, `lookat`: explicit camera position and target (override `perspective`).
  - `hit_scaling`, `min_tot`: temporarily override the corresponding `SimParams` values.

# Examples
```julia
f = EventFile("events.root", "detector.detx")
rba = RBA()
load!(rba, f)
snapshot(rba, "event.png"; size=(1200, 900),
         eyeposition=(391.5, 1411.7, 1127.7), lookat=(73.0, 323.8, 380.1))
```
"""
function snapshot(rba::RBA, filename::AbstractString;
                  time=nothing, size=nothing, perspective=nothing,
                  eyeposition=nothing, lookat=nothing,
                  hit_scaling=nothing, min_tot=nothing)
    isnothing(hit_scaling) || (rba.simparams.hit_scaling = hit_scaling)
    isnothing(min_tot) || (rba.simparams.min_tot = min_tot)
    isnothing(size) || resize!(rba.scene, size...)

    if !isnothing(perspective)
        load_perspective(rba, perspective)
    end
    if !isnothing(eyeposition) && !isnothing(lookat)
        update_cam!(rba.scene, rba.cam, Vec3f(eyeposition), Vec3f(lookat), Vec3f(0, 0, 1))
    end

    t = rba.simparams.t_offset + (isnothing(time) ? full_event_time(rba) : time)
    apply_frame!(rba, t)

    save(filename, rba.scene)
    filename
end
snapshot(filename::AbstractString; kwargs...) = snapshot(global_rba(), filename; kwargs...)
