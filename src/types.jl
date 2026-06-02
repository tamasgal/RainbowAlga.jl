# Core data containers: Hit, HitsCloud and the RBA scene object.

struct Hit
    pos::Position{Float64}
    dir::Direction{Float64}
    tot::Float64
    t::Float64
end

"""

Pure-data container for a set of hits: their positions and (time-based) colours plus a
`description`. The hits are not a GPU object themselves; the scene holds a single shared
`MeshScatter` (`RBA.hits_mesh`) which is reconfigured from the selected cloud. The
`description` doubles as the name of the `ColorSchemes` colour map used for the colorbar.

"""
mutable struct HitsCloud
    hits::Vector{Hit}
    positions::Vector{Point3f}
    colors::Vector{RGBAf}
    alpha::Float64
    description::String
end
function Base.show(io::IO, h::HitsCloud)
    print(io, "HitsCloud '$(h.description)' ($(length(h.hits)) hits)")
end


@kwdef mutable struct RBA
    scene::Scene = Scene(backgroundcolor=RGBf(1.0))
    # Disable all default Camera3D keyboard controls (translate r/f/a/d/w/s, zoom u/o,
    # fov b/n, pan j/l, tilt i/k, roll e/q, axis-fix x/y/z); RainbowAlga binds its own
    # keys. Mouse rotate/zoom/pan still work.
    cam::Makie.Camera3D = cam3d!(scene, rotation_center = :lookat,
        up_key = Keyboard.unknown, down_key = Keyboard.unknown,
        left_key = Keyboard.unknown, right_key = Keyboard.unknown,
        forward_key = Keyboard.unknown, backward_key = Keyboard.unknown,
        zoom_in_key = Keyboard.unknown, zoom_out_key = Keyboard.unknown,
        increase_fov_key = Keyboard.unknown, decrease_fov_key = Keyboard.unknown,
        pan_left_key = Keyboard.unknown, pan_right_key = Keyboard.unknown,
        tilt_up_key = Keyboard.unknown, tilt_down_key = Keyboard.unknown,
        roll_clockwise_key = Keyboard.unknown, roll_counterclockwise_key = Keyboard.unknown,
        fix_x_key = Keyboard.unknown, fix_y_key = Keyboard.unknown, fix_z_key = Keyboard.unknown,
    )
    infobox::GLMakie.Text = text!(GLMakie.campixel(scene), Point2f(10, 10), fontsize=12, text = "", color=RGBf(0.2, 0.2, 0.2))
    tracks::Vector{Track} = Track[]
    hitsclouds::Vector{HitsCloud} = HitsCloud[]
    center::Point3f = Point3f(0.0, 0.0, 0.0)
    simparams::SimParams = SimParams()
    perspectives::Vector{Tuple{Vec{3, Float64}, Vec{3, Float64}}} = fill((Vec3(1000.0), Vec3(0.0)), 9)
    # A single shared mesh holds all hits; it is reconfigured (positions/colours/sizes)
    # from the selected cloud instead of allocating a mesh per cloud or per event.
    hits_mesh::MeshScatter{Tuple{Vector{Point{3, Float32}}}} = meshscatter!(scene, Point3f[], color = RGBAf[], markersize = Float64[])
    _plots::Dict{String, Any} = Dict()
    eventfile::Union{Nothing, AbstractEventFile} = nothing
    current_event_idx::Int = 0
    current_frame_index::Int = 0
    current_trigger_counter::Int = 0
    _colorbar::Dict{String, Any} = Dict{String, Any}()
end
Base.show(io::IO, rba::RBA) = print(io, "RainbowAlga event display.")

function RBA(detector::Detector; kwargs...)
    rba = RBA(kwargs...)

    update!(rba, detector)
    center!(rba.scene)
    update_cam!(rba.scene, rba.cam, Vec3f(1000), center(detector), Vec3f(0, 0, 1))

    # subwindow = Scene(scene, px_area=Observable(Rect(100, 100, 200, 200)), clear=true, backgroundcolor=:green)
    # subwindow.clear = true
    # meshscatter!(subwindow, rand(Point3f, 10), color=:gray)
    # plot!(subwindow, [1, 2, 3], rand(3))

    rba
end

get_current_cam_position(rba::RBA) = rba.cam.eyeposition.val
get_current_cam_position() = get_current_cam_position(global_rba())
get_current_cam_target(rba::RBA) = rba.cam.lookat.val
get_current_cam_target() = get_current_cam_target(global_rba())

"""
    save_perspective(idx)
    save_perspective(idx, eyeposition, lookat)

Store the current camera (or an explicit `eyeposition`/`lookat`) in slot `idx` (1-9).
Recall it with [`load_perspective`](@ref) or by pressing the corresponding number key.
"""
function save_perspective(rba::RBA, idx::Int)
    pos = get_current_cam_position(rba)
    target = get_current_cam_target(rba)
    rba.perspectives[idx] = (pos, target)
    println("Perspective $idx saved.\n  Position: $(pos)\n  Target: $(target)")
end
save_perspective(idx::Int) = save_perspective(global_rba(), idx::Int)
function save_perspective(rba::RBA, idx::Int, eyeposition, lookat)
    rba.perspectives[idx] = (eyeposition, lookat)
end
save_perspective(idx::Int, eyeposition, lookat) = save_perspective(global_rba(), idx::Int, eyeposition, lookat)

"""
    load_perspective(idx)

Restore the camera from perspective slot `idx` (1-9), as saved by [`save_perspective`](@ref).
"""
function load_perspective(rba::RBA, idx::Int)
    update_cam!(rba.scene, rba.cam, rba.perspectives[idx][1], rba.perspectives[idx][2], Vec3f(0,0,1))
end
load_perspective(idx::Int) = load_perspective(global_rba(), idx::Int)
