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
