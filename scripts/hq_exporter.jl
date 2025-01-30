println("Loading libaries...")
using KM3io, ColorSchemes
using LinearAlgebra
using GeometryBasics
using GLMakie
using ColorSchemes
using FileIO

const inch = 96
const pt = 4/3
const cm = inch / 2.54


function draw_detector!(scene, det::Detector; simplified_doms=false, dom_diameter=0.4, pmt_diameter=0.076, dom_scaling=5, with_basegrid=true)
    det_center = center(det)

    if with_basegrid
        basegrid!(scene; center=Point3f(det_center[1], det_center[2], 0))
    end

    opticalmodules = [m for m in det if isopticalmodule(m)]
    meshscatter!(
        scene,
        [m.pos for m ∈ opticalmodules],
        markersize=dom_diameter*dom_scaling,
        color=RGBAf(0.3, 0.3, 0.3, 0.8)
    )

    if !simplified_doms
      pmt_positions = Position{Float64}[]
      for m in det
          !isopticalmodule(m) && continue
          for pmt in m
            push!(pmt_positions, pmt.pos + pmt.dir*dom_diameter*dom_scaling - pmt.dir*pmt_diameter*dom_scaling)
          end
      end
      meshscatter!(
          scene,
          pmt_positions,
          markersize=pmt_diameter*dom_scaling,
          color=RGBAf(1.0, 1.0, 1.0, 0.4)
      )
    end
    # basemodules = [m for m ∈ det if isbasemodule(m)]
    # push!(scene, meshscatter!(
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
        lines!(scene, segments; color=:grey, linewidth=0.5)
        mesh!(scene, Cylinder(Point3f(buoy_pos), Point3f(buoy_pos + Point3f(0.0, 0.0, buoy_height)), 7.0f0), color=:yellow, alpha=0.1)
#        text!(scene, buoy_pos + Point3f(0.0, 0.0, 1.5buoy_height); fontsize=6pt, font=:bold, text = "$string", color=RGBf(120/255, 105/255, 11/255), markerspace=:pixel, align = (:center, :center))
    end
    scene
end


"""

Draws a grid on the XY-plane with an optional `center` point, `span`, grid-`spacing` and
styling options.

"""
function basegrid!(scene; center=(0, 0, 0), span=(-1000, 1000), spacing=50, linewidth=1, color=(:grey, 0.3))
    min, max = span
    center = Point3f(center)
    for q ∈ range(min, max; step=spacing)
        lines!(scene, [Point3f(q, min, 0) + center, Point3f(q, max, 0) + center], color=color, linewidth=linewidth)
        lines!(scene, [Point3f(min, q, 0) + center, Point3f(max, q, 0) + center], color=color, linewidth=linewidth)
    end
    scene
end

"""

Adds hits to the scene.

"""
function add_hits!(scene, hits::T, colors; t_offset=0, hit_scaling=1, min_tot=0, frame_idx=0.0, timespan=1800, pmt_distance=5, hit_distance=2, colorscheme=:matter) where T<:Union{Vector{KM3io.CalibratedHit}, Vector{KM3io.XCalibratedHit}, Vector{KM3io.CalibratedMCHit}}

    positions = generate_hit_positions(hits; pmt_distance=pmt_distance, hit_distance=hit_distance)

    hit_sizes = [h.tot >= min_tot && frame_idx >= h.t - t_offset ? (1+(hit_scaling/5)) * sqrt(h.tot/255) : 0 for h ∈ hits]

    cmap = getproperty(ColorSchemes, colorscheme)
    meshscatter!(
        scene,
        positions,
        color = colors,
        markersize = hit_sizes,
        alpha = 0.9,
    )

    scene
end


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


function generate_colors(muon, hits; cherenkov_thresholds=(-5, 25), t_offset=missing, timespan=3000, cmap=ColorSchemes.matter)
    main_cmap = cmap

    if ismissing(t_offset)
        t_offset = first(triggered(hits)).t
        @show t_offset
    end
    t₁ = t_offset + timespan
    Δt = t₁ - t_offset

    colors = ColorSchemes.RGB{Float64}[]
    for hit in hits
        cphoton = cherenkov(muon, hit)
        if cherenkov_thresholds[1] <= cphoton.Δt <= cherenkov_thresholds[2]
            color = ColorSchemes.RGB(0.0, 0.6, 0.8)
        else
            color = main_cmap[(hit.t - t_offset) / Δt]
        end

        push!(colors, color)
    end
    colors
end


function add_track!(scene, pos, dir, v, t; color=RGBf(1, 0.1, 0.4), with_cherenkov_cone=true, linewidth=2)
    endpos =  pos + v * dir * t / 1e9
    lines!(scene, [pos, endpos], color=color, linewidth=linewidth)

    # Cherenkov cone
    β = v / KM3io.Constants.c
    θ = π/2 - acos(1/KM3io.Constants.INDEX_OF_REFRACTION_WATER/β)  # opening angle is "90deg - emission angle"
    p = range(0, 2π, length = 50)
    u = 0:0.1:200
    x = [u * sin(p) * tan(θ) for p in p, u in u]
    y = [u * cos(p) * tan(θ) for p in p, u in u]
    z = [u for p in p, u in u]
    # Rotation matrix from (0, 0, -1) (cone) to track direction
    a = [0.0, 0.0, -1.0]
    b = dir
    _v = cross(a, b)
    s = norm(_v)
    c = dot(a, b)

    V = [0.0 -_v[3] _v[2];
        _v[3] 0.0 -_v[1];
        -_v[2] _v[1] 0.0]

    R = I + V + V^2 * (1 - c) / s^2

    # Apply the rotation and then the translation
    x_rot = R[1, 1] .* x .+ R[1, 2] .* y .+ R[1, 3] .* z
    y_rot = R[2, 1] .* x .+ R[2, 2] .* y .+ R[2, 3] .* z
    z_rot = R[3, 1] .* x .+ R[3, 2] .* y .+ R[3, 3] .* z

    # Translate to the track position
    target_pos = endpos
    x_new = x_rot .+ target_pos.x
    y_new = y_rot .+ target_pos.y
    z_new = z_rot .+ target_pos.z

    s = surface!(scene, x_new, y_new, z_new, color = z, colormap = [ColorSchemes.RGBA(0.0, 0.6, 0.8, 0.7), ColorSchemes.RGBA(0.0, 0.6, 0.8, 0.0)], backlight = 2.0f0, transparency = true)
    s.visible[] = with_cherenkov_cone

    scene
end

function main()
    perspectives = [
     # Nature Paper perspectives
     # # front
     # (Vec3f(391.5, 1411.7, 1127.7), Vec3f(73.0, 323.8, 380.1)),
     # # top
     # (Vec3f(76.3, 640.4, 1631.5), Vec3f(75.8, 324.6, 379.8)),
     # # zoom
     # (Vec3f(392.9, 634.0, 449.7), Vec3f(70.4, 392.8, 284.1)),
     # perspective1 (Vladimir)
     (Vec3f(216, 1124, 1500), Vec3f(46, 339, 394)),
    ]

    println("Loading event data...")
    f = ROOTFile("vhe-event-and-calibration-data/KM3NeT_00000133_00014728.data.jppmuon_aashower_dynamic.offline.v9.0.vhe.root")
    event = first(f.offline)
    muon = bestjppmuon(event)

    hit_scaling = 9
    min_tot = 0
    #frame_idx = 1950  # Nature paper
    frame_idx = 1350
    t_offset = muon.t + 800
    timespan = 1800

    cmap = ColorSchemes.matter

    detector = Detector("vhe-event-and-calibration-data/detector.dynamical.datx")

    hits = filter(h->h.dom_id != 808950076 && h.channel_id != 3, event.hits)
    hits = select_first_hits(hits; n=5, maxtot=256)
    @show length(hits)
    colors = generate_colors(muon, hits; cherenkov_thresholds=(-5, 25), t_offset=t_offset, timespan=timespan, cmap=cmap)

    println("Creating scene...")
    fig = Figure(size=(21.3cm, 28.5cm), figure_padding = 0, backgroundcolor=:gray80)
    lscene = LScene(fig[1, 1]; show_axis=false, scenekw = (;size=(21.3cm, 28.5cm)))

    scene = lscene.scene
    cam = cam3d!(scene, rotation_center = :lookat)

    draw_detector!(scene, detector; with_basegrid=false)

    add_hits!(scene, hits, colors;
            pmt_distance=3.5,
            hit_distance=3,
            min_tot=min_tot,
            frame_idx=frame_idx,
            t_offset=t_offset,
            timespan=timespan,
            hit_scaling=hit_scaling,
            colorscheme=:matter
    )

   track_linewidth = 4
   add_track!(scene, muon.pos, muon.dir, KM3io.Constants.c, t_offset+frame_idx-muon.t; with_cherenkov_cone=true, linewidth=track_linewidth)

    cascade_positions = (199, 297, 477)
    meshscatter!(
        scene,
        [muon.pos + muon.dir*i for i in cascade_positions],
        color = [:black for _ in length(cascade_positions)],
        markersize = 5,
        marker = :Sphere,
        alpha = 0.9
    )

    # compass pointing towards (0, 1, 0) which is north
    compass_pos = Point3f(150, 500, 0)
    compass_size = 40
    text!(scene, compass_pos + Point3f(0.0, -compass_size/2, 0.0); text = "N", markerspace=:data, font=:bold, fontsize=compass_size*0.8, color=:black, align=(:center, :bottom))
    xyz = [
        Point3f(-1, 0, 0),
        Point3f(0, 2.5, 0),
        Point3f(1, 0, 0),
        Point3f(0, 0.6, 0),
    ] * compass_size
    xyz .+= compass_pos
    xy = Point2f0.(xyz)
    f =  faces(Polygon(xy))
    m = GeometryBasics.Mesh(Point3f0.(xyz), f)
    mesh!(scene, m; color = :red)


    # Scale
    scale_opts = Dict(:color => :black, :linewidth => 2)
    scale_pos = Point3d(50, 600, 0)
    scale_length = 100
    lines!(scene, [scale_pos + Point3d(scale_length/2, 10, 0), scale_pos + Point3d(scale_length/2, -10, 0)]; scale_opts...)
    lines!(scene, [scale_pos - Point3d(scale_length/2, -10, 0), scale_pos - Point3d(scale_length/2, 10, 0)]; scale_opts...)
    lines!(scene, [scale_pos - Point3d(scale_length/2, 0, 0), scale_pos + Point3d(scale_length/2, 0, 0)]; scale_opts...)
    text!(scene, scale_pos + Point3d(0.0, -10, 0.0); text = "$(scale_length) m", markerspace=:data, font=:bold, fontsize=23, color=:black, align=(:center, :bottom), rotation=deg2rad(180))


    # Eiffel Tower
    eiffel = load("assets/eiffel.stl")
    scale_factor = 330 / maximum([p[3] for p in eiffel.position])  # height of the Eiffel Tower with tip: 330m
    eiffel.position .*= scale_factor
    eiffel.position .+= Point3f(-150, 630, 0)
    mesh!(scene, eiffel; color = RGBAf(0.6039, 0.5569, 0.5137, 0.3))  # Eiffel Tower Colour from https://encycolorpedia.com/9a8e83

    for (idx, perspective) in enumerate(perspectives)
      update_cam!(scene, cam, perspective..., Vec3f(0,0,1))
      fname = "vhe_cover_$idx.png"
      println("Saving $fname...")
      save(fname, fig; px_per_unit=900/inch, update=false)
    end
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
