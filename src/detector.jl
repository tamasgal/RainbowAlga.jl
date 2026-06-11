# Detector geometry rendering.

"""
    update!(detector; simplified_doms=true, dom_scaling=5, with_basegrid=true, kwargs...)

Draw the geometry of `detector` (optical modules, strings, buoys and an optional base
grid). Replaces any previously drawn detector and recentres the camera.
"""
function update!(rba::RBA, det::Detector; simplified_doms=true, dom_diameter=0.4, pmt_diameter=0.076, dom_scaling=5, with_basegrid=true)
    scene = rba.scene
    det_center = center(det)
    rba.center = det_center

    if "Basegrid" in keys(rba._plots)
        for element in rba._plots["Basegrid"]
            element in scene && delete!(rba.scene, element)
        end
        delete!(rba._plots, "Basegrid")
    end
    if with_basegrid
        basegrid!(rba; center=Point3f(det_center[1], det_center[2], 0))
    end

    if "Detector" in keys(rba._plots)
        for element in rba._plots["Detector"]
            element in scene && delete!(rba.scene, element)
        end
    end
    plots = rba._plots["Detector"] = []

    opticalmodules = [m for m in det if isopticalmodule(m)]
    dom_plot = meshscatter!(
        scene,
        [m.pos for m ∈ opticalmodules],
        markersize=dom_diameter*dom_scaling,
        color=RGBAf(0.3, 0.3, 0.3, 0.8)
    )
    push!(plots, dom_plot)
    # Remember the DOM markers and the modules behind them (in the same order) so the hover
    # tooltip can map a picked marker back to its module. `opticalmodules` here uses the
    # identical detector iteration order as `build_rate_geometry`, so the rate markers share
    # this mapping too.
    rba._plots["dom_plot"] = dom_plot
    rba._plots["modules"] = opticalmodules

    if !simplified_doms
      pmt_positions = Position{Float64}[]
      for m in det
          !isopticalmodule(m) && continue
          for pmt in m
            push!(pmt_positions, pmt.pos + pmt.dir*dom_diameter*dom_scaling - pmt.dir*pmt_diameter*dom_scaling)
          end
      end
      push!(plots, meshscatter!(
          scene,
          pmt_positions,
          markersize=pmt_diameter*dom_scaling,
          color=RGBAf(1.0, 1.0, 1.0, 0.4)
      ))
    end
    # basemodules = [m for m ∈ det if isbasemodule(m)]
    # push!(plots, meshscatter!(
    #     scene,
    #     [m.pos for m ∈ basemodules],
    #     marker=Rect3f(Vec3f(-0.5), Vec3f(0.5)),
    #     markersize=5,
    #     color=:black
    # ))
    for string ∈ det.strings
        modules = filter(m->m.location.string == string, collect(values(det.modules)))
        sort!(modules, by=m->m.location.floor)
        segments = [m.pos for m in modules]
        top_module = modules[end]
        buoy_height = 20.0
        buoy_pos = top_module.pos + Point3f(0, 0, 100)
        push!(segments, buoy_pos)
        push!(plots, lines!(scene, segments; color=:grey, linewidth=1))
        push!(plots, mesh!(scene, Cylinder(Point3f(buoy_pos), Point3f(buoy_pos + Point3f(0.0, 0.0, buoy_height)), 7.0f0), color=:yellow, alpha=0.1))
        push!(plots, text!(scene, buoy_pos + Point3f(0.0, 0.0, 1.5buoy_height); fontsize=24, font=:bold, text = "$string", color=RGBf(120/255, 105/255, 11/255), markerspace=:pixel, align = (:center, :center)))
    end

    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), rba.center, Vec3f(0, 0, 1))

    nothing
end
update!(d::Detector; kwargs...) = update!(global_rba(), d; kwargs...)

"""

Draws a grid on the XY-plane with an optional `center` point, `span`, grid-`spacing` and
styling options.

"""
function basegrid!(rba; center=(0, 0, 0), span=(-1000, 1000), spacing=50, linewidth=1, color=(:grey, 0.3))
    scene = rba.scene
    min, max = span
    center = Point3f(center)
    plots = rba._plots["Basegrid"] = []
    for q ∈ range(min, max; step=spacing)
        push!(plots, lines!(scene, [Point3f(q, min, 0) + center, Point3f(q, max, 0) + center], color=color, linewidth=linewidth))
        push!(plots, lines!(scene, [Point3f(min, q, 0) + center, Point3f(max, q, 0) + center], color=color, linewidth=linewidth))
    end
    scene
end
