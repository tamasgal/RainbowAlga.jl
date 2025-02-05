println("Loading libaries...")
using KM3io, ColorSchemes
using RainbowAlga
using LinearAlgebra
using GeometryBasics
using GLMakie
using ColorSchemes
using FileIO
using ProgressMeter


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
    hit_sizes = [0.0 for h in hits]

    cmap = getproperty(ColorSchemes, colorscheme)
    hits_mesh = meshscatter!(
        scene,
        positions,
        color = colors,
        markersize = hit_sizes,
        alpha = 0.9,
    )

    hits_mesh
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
    frame_idx = 8350

    t_offset = muon.t + 800  # where the hit colouring starts
    timespan = 1800  # total time span for hit colouring

    cmap = ColorSchemes.matter

    detector = Detector("vhe-event-and-calibration-data/detector.dynamical.datx")

    hits = filter(h->h.dom_id != 808950076 && h.channel_id != 3, event.hits)
    hits = select_first_hits(hits; n=5, maxtot=256)
    @show length(hits)
    colors = generate_colors(muon, hits; cherenkov_thresholds=(-5, 25), t_offset=t_offset, timespan=timespan, cmap=cmap)

    println("Creating scene...")
    fig = Figure(size=(3840, 2160), figure_padding = 0, backgroundcolor=:gray80)
    lscene = LScene(fig[1, 1]; show_axis=false, scenekw = (;size=(3840, 2160)))

    scene = lscene.scene
    cam = cam3d!(scene, rotation_center = :lookat)

    draw_detector!(scene, detector; with_basegrid=false)

    hits_mesh = add_hits!(scene, hits, colors;
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
   #track = RainbowAlga.Track(scene, muon.pos, muon.dir, KM3io.Constants.c, t_offset+frame_idx-muon.t; with_cherenkov_cone=true)
   track = RainbowAlga.Track(scene, muon.pos, muon.dir, KM3io.Constants.c, muon.t; with_cherenkov_cone=true)

   # t = muon.t + 2000
   # update_cam!(scene, cam, perspectives[1]..., Vec3f(0,0,1))
   # RainbowAlga.draw!(track, t)
   # @show t - track.t
   # fname = "vhe_still.png"
   # println("Saving $fname...")
   # save(fname, fig; px_per_unit=300/inch, update=false)
   

   nframes = 600
   time_iterator = range(muon.t, muon.t+3500, length=nframes)
   p = Progress(nframes)
   frame_idx = 0
   record(fig, "uhe_animation.mp4", time_iterator; framerate = 60) do t
     track_pos = positionof(track, t)
     cam_lookat = (center(detector) + track_pos) / 2
     cam_pos = Vec3f(391.5, 911.7, 727.7)
     update_cam!(scene, cam, cam_pos, cam_lookat, Vec3f(0,0,1))
     RainbowAlga.draw!(track, t; trail_length=10000)
     hit_sizes = [t >= h.t ? (1+(hit_scaling/5)) * sqrt(h.tot/255) : 0 for h ∈ hits]
     hits_mesh.markersize = hit_sizes
     frame_idx += 1
     next!(p)
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
