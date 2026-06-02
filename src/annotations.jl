# User-facing scene annotations: add primitives or text labels and remove them again.

"""
A primitive or text label added to the scene with [`annotate!`](@ref). Remove it again
with `delete!(annotation)`. The underlying Makie plot is available as `annotation.plot`.
"""
struct Annotation
    plot
    scene::Scene
end
Base.show(io::IO, ::Annotation) = print(io, "RainbowAlga annotation")
Base.delete!(a::Annotation) = ((a.plot in a.scene) && delete!(a.scene, a.plot); nothing)

"""
    annotate!([scene,] position, shape::Symbol = :Sphere; size=10, color=:red, alpha=1.0, kwargs...)
    annotate!([scene,] position, text::AbstractString; fontsize=20, color=:black, kwargs...)

Add a primitive (or a text label) at `position` to the scene and return an
[`Annotation`](@ref) that can be removed again with `delete!`. Without an explicit
`scene`, the global scene ([`global_scene`](@ref)) is used.

Supported shapes are `:Sphere`, `:Cube` (alias `:Box`) and `:Cylinder`. `size` is the
radius (sphere/cylinder) or half-side (cube) in detector units. Any extra keyword
arguments are forwarded to the underlying Makie `mesh!` / `text!` call.

# Examples
```julia
mysphere = annotate!(Point3f(32, 1, 56), :Sphere; size=8, color=:gold)
delete!(mysphere)

annotate!(Point3f(0, 0, 700), "North"; fontsize=30)
```
"""
annotate!(position, shape = :Sphere; kwargs...) = annotate!(global_scene(), position, shape; kwargs...)

function annotate!(scene::Scene, position, shape::Symbol = :Sphere; size = 10.0, color = :red, alpha = 1.0, kwargs...)
    p = Point3f(position)
    s = Float32(size)
    geometry = if shape === :Sphere
        Sphere(p, s)
    elseif shape in (:Cube, :Box)
        Rect3f(Vec3f(p[1] - s, p[2] - s, p[3] - s), Vec3f(2s, 2s, 2s))
    elseif shape === :Cylinder
        Cylinder(p, Point3f(p[1], p[2], p[3] + 2s), s)
    else
        error("Unknown annotation shape :$(shape). Supported: :Sphere, :Cube, :Cylinder.")
    end
    Annotation(mesh!(scene, geometry; color = color, alpha = alpha, kwargs...), scene)
end

function annotate!(scene::Scene, position, text::AbstractString; fontsize = 20, color = :black, kwargs...)
    Annotation(text!(scene, Point3f(position); text = text, fontsize = fontsize, color = color, kwargs...), scene)
end
