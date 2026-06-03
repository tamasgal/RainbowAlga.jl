# Hit clouds: building, colouring and the single shared mesh.

"""
Index (1-based) of the currently selected hits cloud, or 0 if there are none.
The selection is driven by `simparams.hits_selector`, cycled with the C key.
"""
active_hitscloud_index(rba::RBA) =
    isempty(rba.hitsclouds) ? 0 : abs(rba.simparams.hits_selector) % length(rba.hitsclouds) + 1

"""

Upload the data of the currently selected hits cloud into the single shared GPU mesh
(`rba.hits_mesh`). Positions, colours and the alpha value are uploaded here and only
change when the selection changes (or a new event/cloud is loaded); the per-frame
animation in the render loop only updates `markersize`, so the mesh is reused and
resized on the GPU instead of being reallocated.

"""
function apply_hitscloud!(rba::RBA)
    idx = active_hitscloud_index(rba)
    rba.simparams.displayed_hitscloud = idx
    hm = rba.hits_mesh
    if idx == 0
        hm.positions[] = Point3f[]
        hm.color[] = RGBAf[]
        hm.markersize[] = Float64[]
        return rba
    end
    cloud = rba.hitsclouds[idx]
    hm.positions[] = cloud.positions
    hm.color[] = cloud.colors
    hm.markersize[] = zeros(length(cloud.positions))
    hm.alpha[] = cloud.alpha
    rba
end

"""
Marker sizes for the animation at simulation time `t`: a hit becomes visible (scaled)
once the clock has reached it (`t >= hit.t`) and it passes the ToT cut (`min_tot`),
otherwise its size is 0. Returns one size per hit in `cloud`.
"""
hit_markersizes(cloud::HitsCloud, t, scale, min_tot) =
    [(h.tot >= min_tot && t >= h.t) ? scale * sqrt(h.tot / 255) : 0.0 for h in cloud.hits]

"""
Advance the scene to simulation time `t`: upload the active hits cloud if the selection
changed, resize the hit markers so that hits up to `t` are visible, and move every track
(and its Cherenkov cone) to its position at `t`. Shared by the interactive render loop
and by [`snapshot`](@ref), so both produce identical frames.
"""
function apply_frame!(rba::RBA, t)
    active = active_hitscloud_index(rba)
    if active != rba.simparams.displayed_hitscloud
        apply_hitscloud!(rba)
    end
    if active != 0
        cloud = rba.hitsclouds[active]
        scale = 1 + rba.simparams.hit_scaling / 5
        rba.hits_mesh.markersize[] = hit_markersizes(cloud, t, scale, rba.simparams.min_tot)
    end
    for track in rba.tracks
        draw!(track, t)
    end
    rba
end


"""

Adds hits to the scene.

"""
function add!(rba::RBA, hits::T; pmt_distance=5, hit_distance=2, colorscheme=:hawaii, t_range=nothing) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}

    positions = generate_hit_positions(hits; pmt_distance=pmt_distance, hit_distance=hit_distance)

    if !isnothing(t_range)
        t_min, t_max = t_range
    elseif length(triggered(hits)) > 0
        t_min, t_max = extrema(h.t for h ∈ triggered(hits))
    else
        t_min, t_max = extrema(h.t for h ∈ hits)
    end
    Δt = t_max - t_min
    rba.simparams.t_offset = t_min
    rba.simparams.cb_t_offset = 0.0
    rba.simparams.loop_end_frame_idx = Int(ceil(Δt))

    cmap = getproperty(ColorSchemes, colorscheme)
    # Guard against Δt == 0 (a single hit or all hits at the same time) which would make
    # the colour fraction 0/0 = NaN.
    colorfrac(h) = iszero(Δt) ? 0.0 : clamp((h.t - t_min) / Δt, 0.0, 1.0)
    colors = [RGBAf(cmap[colorfrac(h)]) for h ∈ hits]
    rbahits = [Hit(h.pos, h.dir, h.tot, h.t) for h in hits]
    push!(rba.hitsclouds, HitsCloud(rbahits, positions, colors, 0.9, string(colorscheme)))
    rba._colorbar["default_t_offset"] = rba.simparams.t_offset
    rba._colorbar["default_loop_end_frame_idx"] = rba.simparams.loop_end_frame_idx
    apply_hitscloud!(rba)
    update_colorbar!(rba)
    rba
end
function add!(hits::T; kwargs...) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}
    add!(global_rba(), hits; kwargs...)
end
"""
Recompute and apply hit colors for all clouds based on the current `t_offset` and
`loop_end_frame_idx` in `SimParams`. Called after interactive colorbar adjustments.
"""
function recolor_hits_from_simparams!(rba::RBA)
    isempty(rba.hitsclouds) && return
    t_min = rba.simparams.t_offset + rba.simparams.cb_t_offset
    Δt = Float64(rba.simparams.loop_end_frame_idx)
    iszero(Δt) && return
    active = active_hitscloud_index(rba)
    for (idx, hitscloud) in enumerate(rba.hitsclouds)
        # Only time-coloured clouds (whose description names a ColorScheme) follow the
        # colorbar; Cherenkov clouds keep their Δt-residual colours.
        cmap = try
            getproperty(ColorSchemes, Symbol(hitscloud.description))
        catch
            continue
        end
        hitscloud.colors = [RGBAf(cmap[clamp((h.t - t_min) / Δt, 0.0, 1.0)]) for h in hitscloud.hits]
        idx == active && (rba.hits_mesh.color[] = hitscloud.colors)
    end
    nothing
end

"""
    clearhits!()

Remove all hits clouds from the display. The detector geometry and the shared hits mesh
are kept.
"""
function clearhits!(rba::RBA)
    rba.simparams.hits_selector = 0
    empty!(rba.hitsclouds)
    # Keep the shared mesh alive (reused across events); just empty its data.
    apply_hitscloud!(rba)
    update_colorbar!(rba)
end
clearhits!() = clearhits!(global_rba())

"""
    recolor!(hitscloud_idx, colors)

Replace the colours of the `hitscloud_idx`-th hits cloud (one colour per hit). Combine
with [`generate_colors`](@ref) for physics-based colourings and cycle them with the C key.
"""
function recolor!(rba::RBA, hitscloud_idx::Integer, colors)
    if hitscloud_idx < 1 || hitscloud_idx > length(rba.hitsclouds)
        error("No hits cloud with index $(hitscloud_idx) found. There is a total of $(length(rba.hitsclouds)) hits clouds to choose from.")
    end
    hitscloud = rba.hitsclouds[hitscloud_idx]
    if length(colors) != length(hitscloud.hits)
        error("$(length(colors)) colors were provided, however one color per hit is requred => a total of $(length(hitscloud.hits)) for this hits cloud.")
    end
    hitscloud.colors = convert(Vector{RGBAf}, RGBAf.(colors))
    # Refresh the shared mesh only if this cloud is the one currently displayed.
    active_hitscloud_index(rba) == hitscloud_idx && (rba.hits_mesh.color[] = hitscloud.colors)
    nothing
end

recolor!(hitscloud_idx::Integer, colors) = recolor!(global_rba(), hitscloud_idx, colors)

"""

Add a hits cloud coloured by the Cherenkov time residual (`Δt`) with respect to
`track`. The hits and positions are the same as the plain hits cloud, so cycling with
the C key compares the same photons against different track hypotheses.

"""
function add_cherenkov_cloud!(rba::RBA, track, hits, description::AbstractString)
    positions = generate_hit_positions(hits)
    cphotons = cherenkov(track, hits)
    cmap = reverse(ColorSchemes.redblue)
    colors = [RGBAf(cmap[clamp(abs(c.Δt) / 50.0, 0.0, 1.0)]) for c in cphotons]
    rbahits = [Hit(h.pos, h.dir, h.tot, h.t) for h in hits]
    push!(rba.hitsclouds, HitsCloud(rbahits, positions, colors, 0.9, description))
    apply_hitscloud!(rba)
    update_colorbar!(rba)
    nothing
end

"""

Add the reconstructed (best Jpp muon) and MC lepton tracks of an offline event,
together with their Cherenkov hits clouds. Failures for a single track are warned
about but do not abort loading the event.

"""
function add_reco_and_mc!(rba::RBA, event::Evt, hits)
    if length(event.trks) > 0
        reco = bestjppmuon(event)
        if !ismissing(reco)
            try
                println("  adding best Jpp muon")
                track = Track(rba.scene, reco.pos, reco.dir, KM3io.Constants.c, reco.t; color=RGBf(5/255, 176/255, 255/255))
                add!(rba, track)
                isempty(hits) || add_cherenkov_cloud!(rba, track, hits, "Cherenkov wrt. Jpp muon (lik=$(round(Int, reco.lik)))")
            catch e
                @warn "Could not add the reconstructed Jpp muon" exception=(e, catch_backtrace())
            end
        end
    end

    for mc_track in event.mc_trks
        Corpuscles.islepton(mc_track.type) || continue
        try
            particle_name = string(Corpuscles.Particle(mc_track.type).name)
            println("  found a lepton: $(particle_name)")
            color = isnothing(match(r"nu", particle_name)) ? RGBf(0.0, 0.8, 0.7) : RGBf(1.0, 0.2, 0.0)
            track = Track(rba.scene, mc_track.pos, mc_track.dir, KM3io.Constants.c, mc_track.t; color=color)
            add!(rba, track)
            if !isempty(hits) && Corpuscles.charge(mc_track.type) != 0
                println("   -> adding Cherenkov hit information")
                add_cherenkov_cloud!(rba, track, hits, "Cherenkov wrt. MC $(particle_name) (#$(mc_track.id))")
            end
        catch e
            @warn "Could not add MC track" exception=(e, catch_backtrace())
        end
    end
    rba
end

# Removes the per-event plots (track lines and Cherenkov cones) and the hits clouds,
# while keeping the detector geometry and the shared hits mesh alive so they are reused
# when stepping through events.
function Base.empty!(rba::RBA)
    for track in rba.tracks
        delete!(rba.scene, track._lines)
        delete!(rba.scene, track.cone)
    end
    empty!(rba.tracks)
    clearhits!(rba)
    nothing
end

function add!(rba::RBA, track::Track)
    push!(rba.tracks, track)
end
add!(rba::RBA, trk::Trk; kwargs...) = add!(rba, Track(rba.scene, trk.pos, trk.dir, KM3io.Constants.c, trk.t; kwargs...))
add!(trk::Trk; kwargs...) = add!(global_rba(), trk; kwargs...)

"""

Generate hit positions for each hit, stacking them on top of each other along the PMT axis
when the same PMT is hit multiple times.

"""
function generate_hit_positions(hits; pmt_distance=5, hit_distance=2)
    pmt_map = Dict{Tuple{Int, Int}, Int}()
    pos = Point3f[]
    for hit ∈ hits
        loc = (hit.dom_id, hit.channel_id)
        if !(loc ∈ keys(pmt_map))
            pmt_map[loc] = 0
        else
            pmt_map[loc] += 1
        end
        i = pmt_map[loc]
        push!(pos, Point3f(hit.pos + hit.dir*(pmt_distance + hit_distance*i)))
        # push!(pos, Point3f(hit.pos + hit.dir))#*pmt_distance + hit.dir*hit_distance*i))
    end
    pos
end

