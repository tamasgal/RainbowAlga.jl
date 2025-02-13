println("Loading libaries...")
using KM3io, ColorSchemes
using RainbowAlga
using LinearAlgebra
using GeometryBasics
using GLMakie
using ColorSchemes
using FileIO
using ProgressMeter


function draw_detector!(
    scene,
    det::Detector;
    simplified_doms = false,
    dom_diameter = 0.4,
    pmt_diameter = 0.076,
    dom_scaling = 5,
    with_basegrid = true,
)
    det_center = center(det)

    if with_basegrid
        basegrid!(scene; center = Point3f(det_center[1], det_center[2], 0))
    end

    opticalmodules = [m for m in det if isopticalmodule(m)]
    meshscatter!(
        scene,
        [m.pos for m ∈ opticalmodules],
        markersize = dom_diameter * dom_scaling,
        color = RGBAf(0.3, 0.3, 0.3, 0.8),
    )

    if !simplified_doms
        pmt_positions = Position{Float64}[]
        for m in det
            !isopticalmodule(m) && continue
            for pmt in m
                push!(
                    pmt_positions,
                    pmt.pos + pmt.dir * dom_diameter * dom_scaling -
                    pmt.dir * pmt_diameter * dom_scaling,
                )
            end
        end
        meshscatter!(
            scene,
            pmt_positions,
            markersize = pmt_diameter * dom_scaling,
            color = RGBAf(1.0, 1.0, 1.0, 0.4),
        )
    end

    for string ∈ det.strings
        modules = filter(m -> m.location.string == string, collect(values(det.modules)))
        sort!(modules, by = m -> m.location.floor)
        segments = [m.pos for m in modules]
        top_module = modules[end]
        buoy_height = 20.0
        buoy_pos = top_module.pos + Point3f(0, 0, 100)
        push!(segments, buoy_pos)
        lines!(scene, segments; color = :grey, linewidth = 0.5)
        mesh!(
            scene,
            Cylinder(
                Point3f(buoy_pos),
                Point3f(buoy_pos + Point3f(0.0, 0.0, buoy_height)),
                7.0f0,
            ),
            color = :yellow,
            alpha = 0.1,
        )
    end
    scene
end


"""

Draws a grid on the XY-plane with an optional `center` point, `span`, grid-`spacing` and
styling options.

"""
function basegrid!(
    scene;
    center = (0, 0, 0),
    span = (-1000, 1000),
    spacing = 50,
    linewidth = 1,
    color = (:grey, 0.3),
)
    min, max = span
    center = Point3f(center)
    for q ∈ range(min, max; step = spacing)
        lines!(
            scene,
            [Point3f(q, min, 0) + center, Point3f(q, max, 0) + center],
            color = color,
            linewidth = linewidth,
        )
        lines!(
            scene,
            [Point3f(min, q, 0) + center, Point3f(max, q, 0) + center],
            color = color,
            linewidth = linewidth,
        )
    end
    scene
end

"""

Adds hits to the scene.

"""
function add_hits!(
    scene,
    hits::T,
    colors;
    pmt_distance = 5,
    hit_distance = 2,
) where {
    T<:Union{
        Vector{KM3io.CalibratedHit},
        Vector{KM3io.XCalibratedHit},
        Vector{KM3io.CalibratedMCHit},
    },
}

    positions = generate_hit_positions(
        hits;
        pmt_distance = pmt_distance,
        hit_distance = hit_distance,
    )
    hit_sizes = [0.0 for h in hits]

    hits_mesh =
        meshscatter!(scene, positions, color = colors, markersize = hit_sizes, alpha = 0.9)

    hits_mesh
end


"""

Generate hit positions for each hit, stacking them on top of each other along the PMT axis
when the same PMT is hit multiple times.

"""
function generate_hit_positions(hits; pmt_distance = 5, hit_distance = 2)
    pmt_map = Dict{Tuple{Int,Int},Int}()
    pos = Point3f[]
    for hit ∈ hits
        loc = (hit.dom_id, hit.channel_id)
        if !(loc ∈ keys(pmt_map))
            pmt_map[loc] = 0
        else
            pmt_map[loc] += 1
        end
        i = pmt_map[loc]
        push!(pos, Point3f(hit.pos + hit.dir * (pmt_distance + hit_distance * i)))
    end
    pos
end


function generate_colors(
    muon,
    hits;
    cherenkov_thresholds = (-5, 25),
    t_offset = missing,
    timespan = 3000,
    cmap = ColorSchemes.matter,
)
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
            color = main_cmap[(hit.t-t_offset)/Δt]
        end

        push!(colors, color)
    end
    colors
end


function main()
    println("Loading event data...")
    f = ROOTFile(
        "vhe-event-and-calibration-data/KM3NeT_00000133_00014728.data.jppmuon_aashower_dynamic.offline.v9.0.vhe.root",
    )
    event = first(f.offline)
    muon = bestjppmuon(event)

    hit_scaling = 9
    min_tot = 0

    hit_t_offset = 800
    t_offset = muon.t + hit_t_offset  # where the hit colouring starts
    timespan = 1800  # total time span for hit colouring

    cmap = ColorSchemes.matter

    detector = Detector("vhe-event-and-calibration-data/detector.dynamical.datx")

    hits = filter(h -> h.dom_id != 808950076 && h.channel_id != 3, event.hits)
    hits = select_first_hits(hits; n = 5, maxtot = 256)
    colors = generate_colors(
        muon,
        hits;
        cherenkov_thresholds = (-5, 25),
        t_offset = t_offset,
        timespan = timespan,
        cmap = cmap,
    )

    println("Creating scene...")
    # bgcolor = :gray80
    bgcolor = RGBf(0.0, 0.0, 0.1)
    fig = Figure(size = (3840, 2160), figure_padding = 0, backgroundcolor = bgcolor)
    lscene = LScene(fig[1, 1]; show_axis = false, scenekw = (; size = (3840, 2160)))

    scene = lscene.scene
    cam = cam3d!(scene, rotation_center = :lookat)

    draw_detector!(scene, detector; with_basegrid = false)

    hits_mesh = add_hits!(scene, hits, colors; pmt_distance = 3.5, hit_distance = 3)

    track_linewidth = 4
    track = RainbowAlga.Track(
        scene,
        muon.pos,
        muon.dir,
        KM3io.Constants.c,
        muon.t;
        with_cherenkov_cone = true,
    )


    framerate = 60
    duration = 30  # [s]
    nframes = framerate * duration
    time_iterator = range(muon.t, muon.t + 3500, length = nframes)
    p = Progress(nframes)
    frame_idx = 0

    # Camera ride #1
    cam_pos_start, cam_lookat_start = (
        [-0.9523286435178022, 812.5768866715557, 214.2786332039779],
        [-94.40157010128716, 473.06610115312986, 261.717431763082],
    )
    cam_pos_end, cam_lookat_end = (
        [446.1705158931006, 957.7570233855922, 477.07876179708234],
        [29.27006668403001, 387.0723575623845, 233.11875207979952],
    )

    # Camera ride #2
    cam_pos_start, cam_lookat_start = (
        [-672.8690962109935, 623.2107094382475, 342.42235846645616],
        [-63.53399247358708, 393.6253697734687, 307.5961805275387],
    )
    cam_pos_end, cam_lookat_end = (
        [501.96099394649707, 1129.1310276904364, 452.8152663613697],
        [14.813800501998088, 337.4907547855251, 342.63404890438886],
    )

    # Camera ride #3
    cam_pos_start, cam_lookat_start = (
        [-687.3087460770153, -9.998398607057652, 155.91527178915078],
        [21.560567129273526, 351.1037109219317, 332.11418080267384],
    )
    cam_pos_end, cam_lookat_end = (
        [223.18353822411638, 933.3578551733629, 1274.053832804231],
        [2.272564231790892, 331.64555221929885, 382.2112308410932],
    )

    cam_pos_start = Vec3f(cam_pos_start)
    cam_pos_end = Vec3f(cam_pos_end)
    cam_lookat_start = Vec3f(cam_lookat_start)
    cam_lookat_end = Vec3f(cam_lookat_end)

    record(fig, "uhe_animation.mp4", time_iterator; framerate = framerate) do t
        cam_lookat =
            cam_lookat_start + frame_idx / nframes * (cam_lookat_end - cam_lookat_start)
        cam_pos = cam_pos_start + frame_idx / nframes * (cam_pos_end - cam_pos_start)
        update_cam!(scene, cam, cam_pos, cam_lookat, Vec3f(0, 0, 1))
        RainbowAlga.draw!(track, t; trail_length = 10000)
        hit_sizes =
            [t >= h.t ? (1 + (hit_scaling / 5)) * sqrt(h.tot / 255) : 0 for h ∈ hits]
        hits_mesh.markersize = hit_sizes
        frame_idx += 1
        next!(p)
    end
end


"""

Select hits within a specific Cherenkov time window with respect to the given track.

"""
function select_hits(
    hits::T,
    track;
    mintot = 20,
    maxtot = 255,
    tmin = -50,
    tmax = 500,
) where {T}
    hits = filter(h -> mintot < h.tot < maxtot, hits)
    out = T()
    for hit in hits
        chit = cherenkov(track, hit)
        if tmin < chit.Δt < tmax
            push!(out, hit)
        end
    end
    sort(out; by = h -> h.t)
end


"""

Select the first `n` hits on each PMT.

"""
function select_first_hits(hits::T; n = 1, mintot = 20, maxtot = 255) where {T}
    hits = filter(h -> mintot < h.tot < maxtot, hits)
    out = T()
    sort!(hits; by = h -> h.t)
    pmts = Dict{Tuple{Int,Int},Int}()
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
