# Particle tracks and their Cherenkov cones.

"""
A particle track.
"""
struct Track
    pos::Position{Float64}
    dir::Direction{Float64}
    v::Float64
    t::Float64
    _lines::Lines{Tuple{Vector{Point{3, Float64}}}}
    cone::Surface{Tuple{Matrix{Float64}, Matrix{Float64}, Matrix{Float32}}}
    cone_x::Matrix{Float64}
    cone_y::Matrix{Float64}
    cone_z::Matrix{Float64}

    function Track(scene, pos, dir, v, t; color=RGBf(1, 0.1, 0.4), with_cherenkov_cone=true)
        _lines = lines!(scene, [pos, pos], color=color, linewidth=5)

        # Cherenkov cone
        β = v / KM3io.Constants.c
        θ = π/2 - acos(1/KM3io.Constants.INDEX_OF_REFRACTION_WATER/β)  # opening angle is "90deg - emission angle"
        p = range(0, 2π, length = 50)
        u = range(0, 200, length = 100)  # cone is linear in u, so a coarse grid suffices
        x = [u * sin(p) * tan(θ) for p in p, u in u]
        y = [u * cos(p) * tan(θ) for p in p, u in u]
        z = [u for p in p, u in u]
        # Rotation matrix from (0, 0, -1) (cone) to track direction
        a = [0.0, 0.0, -1.0]
        b = dir
        _v = cross(a, b)
        s = norm(_v)
        c = dot(a, b)

        if s < 1e-10
            # Track is (anti)parallel to the cone axis (0, 0, -1): the cross product
            # vanishes and Rodrigues' formula would divide by zero. Use the exact
            # rotation: identity when parallel, 180 deg about the x-axis when antiparallel.
            R = c > 0 ? [1.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 1.0] :
                        [1.0 0.0 0.0; 0.0 -1.0 0.0; 0.0 0.0 -1.0]
        else
            V = [0.0 -_v[3] _v[2];
                _v[3] 0.0 -_v[1];
                -_v[2] _v[1] 0.0]

            R = I + V + V^2 * (1 - c) / s^2
        end

        # Build the cone with its apex at the origin; it is positioned with translate!
        # here and in draw!, so animating it is an O(1) GPU transform instead of
        # re-tessellating the whole surface every frame.
        x_rot = R[1, 1] .* x .+ R[1, 2] .* y .+ R[1, 3] .* z
        y_rot = R[2, 1] .* x .+ R[2, 2] .* y .+ R[2, 3] .* z
        z_rot = R[3, 1] .* x .+ R[3, 2] .* y .+ R[3, 3] .* z

        s = surface!(scene, x_rot, y_rot, z_rot, color = z, colormap = [ColorSchemes.RGBA(0.0, 0.6, 0.8, 0.7), ColorSchemes.RGBA(0.0, 0.6, 0.8, 0.0)], backlight = 2.0f0, transparency = true)
        s.visible[] = with_cherenkov_cone
        translate!(s, pos.x, pos.y, pos.z)

        new(pos, dir, v, t, _lines, s, x_rot, y_rot, z_rot)
    end
end

function draw!(track::Track, t; trail_length=0)
    startpos = track.pos - track.dir * trail_length
    if t < track.t
        track._lines[1] = [startpos, track.pos]
        track.cone.visible[] && translate!(track.cone, track.pos.x, track.pos.y, track.pos.z)
        return track
    end
    endpos =  track.pos + track.v * track.dir * (t - track.t) / 1e9
    track._lines[1] = [startpos, endpos]
    if track.cone.visible[]
        # O(1) GPU translation of the apex; no per-frame re-tessellation/allocation.
        translate!(track.cone, endpos.x, endpos.y, endpos.z)
    end
    track
end
