println("Loading libaries...")
using RainbowAlga, KM3io, ColorSchemes; setfps!(20)
using LinearAlgebra
using CairoMakie


function main()
    println("Creating scene...")
    RainbowAlga._rba.simparams.hit_scaling = 10
    RainbowAlga._rba.simparams.speed = 6
    RainbowAlga._rba.simparams.show_infobox = false
    RainbowAlga._rba.simparams.rotation_enabled = false
    RainbowAlga._rba.simparams.stopped = true
    RainbowAlga._rba.simparams.loop_enabled = false
    RainbowAlga._rba.simparams.frame_idx = 2000

    detector = Detector("/Users/tamasgal/Dev/vhe-event-and-calibration-data/detector.dynamical.datx")
    f = ROOTFile("/Users/tamasgal/Dev/vhe-event-and-calibration-data/KM3NeT_00000133_00014728.data.jppmuon_aashower_dynamic.offline.v9.0.vhe.root")

    event = first(f.offline)
    muon = bestjppmuon(event)
    #hits = select_hits(event.hits, muon)
    hits = select_first_hits(event.hits; n=5)

    update!(detector)
    add!(hits)
    add!(hits; hit_distance=3)
    add!(hits)
    add!(muon; with_cherenkov_cone=true)

    t₀ = muon.t + 800
    timespan = 1800

    #cmap = ColorSchemes.thermal
    cmap = reverse(ColorSchemes.jet1)

    recolor!(1,  generate_colors(muon, hits; cherenkov_thresholds=(NaN, NaN), t₀=t₀, timespan=timespan, cmap=cmap))
    recolor!(2,  generate_colors(muon, hits; cherenkov_thresholds=(NaN, NaN), t₀=t₀, timespan=timespan, cmap=cmap))
    recolor!(3,  generate_colors(muon, hits; cherenkov_thresholds=(-5, 25), t₀=t₀, timespan=timespan, cmap=ColorSchemes.roma))
    RainbowAlga._rba.simparams.t_offset = t₀

    # manually adding secondary cascades
    cascade_positions = (199, 297, 477)
    meshscatter!(
        RainbowAlga._rba.scene,
        [muon.pos + muon.dir*i for i in cascade_positions],
        color = [:black for _ in length(cascade_positions)],
        markersize = 5,
        marker = :Sphere,
        alpha = 0.9
    )

    RainbowAlga.run(;interactive=false)

    fig = Figure(size = (300, 1400), backgroundcolor=:transparent)
    Colorbar(fig[1,1]; limits=(0, timespan), ticks=0:200:timespan, colormap=cmap,
             label="Time [ns]", labelsize=35, ticklabelsize=35, ticklabelspace=100, size=50); fig
    save("colorbar.pdf", fig)
    save("colorbar.png", fig)
    println("Colorbar saved separately as: colorbar.pdf")
end


"""

Select hits within a specific Cherenkov time window with respect to the given track.

"""
function select_hits(hits::T, track; mintot=20, maxtot=255, tmin=-50, tmax=500) where T
    hits = filter(h -> mintot < h.tot < maxtot, hits)
    out = T()
    for hit in hits
        chit = cherenkov(track, hit)
        if tmin < chit.Δt < tmax
            push!(out, hit)
        end
    end
    sort(out; by=h->h.t)
end


"""

Select the first `n` hits on each PMT.

"""
function select_first_hits(hits::T; n=1, mintot=20, maxtot=255) where T
    hits = filter(h -> mintot < h.tot < maxtot, hits)
    out = T()
    sort!(hits; by=h->h.t)
    pmts = Dict{Tuple{Int, Int}, Int}()
    for hit in hits
        pmtkey = (hit.dom_id, hit.channel_id)
        if !(pmtkey in keys(pmts))
            pmts[pmtkey] = 1
        end
        pmts[pmtkey] > n && continue
        pmts[pmtkey] += 1
        push!(out, hit)
    end
    out
end

main()
