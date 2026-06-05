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
  - `time`: simulation time in nanoseconds, measured from the first hit of the event
    (`0` freezes at the very start with only the earliest hits visible, the default shows
    the fully developed event).
  - `size`: output image size in scene units as `(width, height)`; the on-disk image is
    `size .* px_per_unit` pixels.
  - `px_per_unit`: pixels per scene unit (defaults to `1`, so the image is exactly `size`
    pixels regardless of the display's DPI). Increase it for higher-resolution output.
  - `perspective`: index `1`-`9` of a camera saved with [`save_perspective`](@ref).
  - `eyeposition`, `lookat`: explicit camera position and target (override `perspective`).
  - `hit_scaling`, `min_tot`: temporarily override the corresponding `SimParams` values for
    this render only; the original values are restored afterwards.

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
                  time=nothing, size=nothing, px_per_unit=1, perspective=nothing,
                  eyeposition=nothing, lookat=nothing,
                  hit_scaling=nothing, min_tot=nothing)
    # Override the rendering-only SimParams for the duration of this render and restore
    # them afterwards, so a snapshot never leaks state into the interactive display or a
    # subsequent snapshot (the camera and frozen frame are left in place on purpose).
    saved_hit_scaling = rba.simparams.hit_scaling
    saved_min_tot = rba.simparams.min_tot
    try
        isnothing(hit_scaling) || (rba.simparams.hit_scaling = hit_scaling)
        isnothing(min_tot) || (rba.simparams.min_tot = min_tot)
        isnothing(size) || resize!(rba.scene, size...)

        if !isnothing(perspective)
            load_perspective(rba, perspective)
        end
        if !isnothing(eyeposition) && !isnothing(lookat)
            update_cam!(rba.scene, rba.cam, Vec3f(eyeposition), Vec3f(lookat), Vec3f(0, 0, 1))
        end

        if rba.simparams.animation_mode === :summaryslice
            # In summaryslice mode `time` denotes the slice ordinal (0-based); default to
            # the slice currently selected by the animation cursor.
            apply_slice!(rba, isnothing(time) ? rba.simparams.frame_idx : Int(time))
        else
            t = rba.simparams.t_offset + (isnothing(time) ? full_event_time(rba) : time)
            apply_frame!(rba, t)
        end

        save(filename, rba.scene; px_per_unit=px_per_unit)
    finally
        rba.simparams.hit_scaling = saved_hit_scaling
        rba.simparams.min_tot = saved_min_tot
    end
    filename
end
snapshot(filename::AbstractString; kwargs...) = snapshot(global_rba(), filename; kwargs...)
