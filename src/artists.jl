function generate_colors(muon, hits; cherenkov_thresholds=(-5, 25), early_hit_threshold=100, t₀=missing, timespan=3000, cmap=ColorSchemes.matter)
    cphotons = cherenkov(muon, hits)

    #main_cmap = ColorSchemes.batlow
    #main_cmap = reverse(ColorSchemes.roma)
    #main_cmap = ColorSchemes.linear_kry_0_97_c73_n256
    main_cmap = cmap
    cherenkov_late_cmap = ColorSchemes.linear_blue_5_95_c73_n256
    cherenkov_early_cmap = ColorSchemes.linear_ternary_red_0_50_c52_n256
    early_cmap = ColorSchemes.linear_wyor_100_45_c55_n256

    if ismissing(t₀)
        t₀ = first(triggered(hits)).t
        @show t₀
    end
    t₁ = t₀ + timespan
    Δt = t₁ - t₀

    colors = ColorSchemes.RGB{Float64}[]
    for hit in hits
        cphoton = cherenkov(muon, hit)
        if cherenkov_thresholds[1] <= cphoton.Δt <= cherenkov_thresholds[2]
            # color = cherenkov_late_cmap[cphoton.Δt/cherenkov_threshold]
            #color = cherenkov_late_cmap[cphoton.Δt/cherenkov_threshold]
            color = ColorSchemes.RGB(0.0, 0.6, 0.8)
        else
            # color = ColorSchemes.RGB(0.0, 0.0, 0.0)
            color = main_cmap[(hit.t - t₀) / Δt]
        end
        # elseif cphoton.Δt < -cherenkov_threshold
        #     color = early_cmap[(cphoton.Δt + cherenkov_threshold) / early_hit_threshold]
        # else
        #     color = main_cmap[(hit.t - t₀) / Δt]
        # end

        push!(colors, color)
    end
    colors
end


# Shower locations (reference https://git.km3net.de/working_groups/dpdq/mass_production_2023/-/issues/49#note_68700):
# 190, 295 and 450 m from the best jpp track vertex, quite close to what Aart found. Although it might be 4 showers as well at 170, 190, 290, 450 m.
function generate_shower_colors(muon, hits, shower_distance; threshold=200)
    colors = ColorSchemes.RGBA{Float64}[]

    t₀ = first(triggered(hits)).t

#    for (shower_distance, color) in [(295, ColorSchemes.RGB(0.0, 1.0, 0.2)), (450, ColorSchemes.RGB(1.0, 0.0, 0.0))]

    shower_vertex = muon.pos + muon.dir * shower_distance
    shower_time = muon.t + KM3io.Constants.C_LIGHT * shower_distance

    for hit in hits
        distance = LinearAlgebra.norm(shower_vertex - hit.pos)
        shower_arrival_time = shower_time + distance * KM3io.Constants.C_WATER

        Δt = hit.t - shower_arrival_time

        if hit.t > shower_time && (-100 < Δt < threshold)
            color = ColorSchemes.RGBA(1.0, 0.0, 0.0, 1.0)
        else
            color = ColorSchemes.RGBA(0.0, 0.0, 0.0, 0.3)
        end
        push!(colors, color)
    end
    colors
end
