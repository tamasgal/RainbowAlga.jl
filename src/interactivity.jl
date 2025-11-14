"""
    register_events(rba::RBA)

Registers keyboard and mouse events for the interactive access.
"""
function register_events(rba::RBA)
    scene = rba.scene
    on(events(scene).mousebutton) do event
        # if scene.events.hasfocus[]
        #     println("focus")
        #     rba.simparams.fps = 60
        # else
        #     println("no focus")
        #     rba.simparams.fps = 15
        # end
    end
    on(events(scene).keyboardbutton, priority = 20000000) do event
        if ispressed(scene, Makie.Keyboard.r)
            reset_time(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.space)
            rba.simparams.stopped = !rba.simparams.stopped
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.left)
            rba.simparams.loop_enabled = false
            rba.simparams.frame_idx -= 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.right)
            rba.simparams.loop_enabled = false
            rba.simparams.frame_idx += 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.a)
            toggle_rotation(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._1 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._2 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 2)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._3 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 3)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._4 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 4)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._5 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._6 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 6)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._7 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 7)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._8 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 8)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._9 & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            save_perspective(rba, 9)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._1)
            load_perspective(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._2)
            load_perspective(rba, 2)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._3)
            load_perspective(rba, 3)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._4)
            load_perspective(rba, 4)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._5)
            load_perspective(rba, 5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._6)
            load_perspective(rba, 6)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._7)
            load_perspective(rba, 7)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._8)
            load_perspective(rba, 8)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard._9)
            load_perspective(rba, 9)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            previous_hits_colouring(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c)
            next_hits_colouring(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.s)
            rba.simparams.save_next_frame = true
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.v)
            if rba.simparams.recording
                rba.simparams.finalise_recording = true
            end
            rba.simparams.recording = !rba.simparams.recording
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.x)
            rba.simparams.show_infobox = !rba.simparams.show_infobox
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.l)
            toggle_loop(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.l)
            toggle_loop(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.d)
            if rba.simparams.darkmode_enabled
                scene.backgroundcolor = RGBf(0.9, 0.9, 0.9)
                rba.infobox.color = RGBf(0.1, 0.1, 0.1)
                rba.simparams.darkmode_enabled = false
            else
                scene.backgroundcolor = RGBf(0.0, 0.0, 0.1)
                rba.simparams.darkmode_enabled = true
                rba.infobox.color = RGBf(0.9, 0.9, 0.9)
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.up)
            faster(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.down)
            slower(rba, 1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.comma)
            decreasetot(rba, 0.5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.period)
            increasetot(rba, 0.5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.i)
            rba.simparams.hit_scaling += 1
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.u)
            if rba.simparams.hit_scaling > 1
                rba.simparams.hit_scaling -= 1
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.q)
            rba.simparams.quit = true
            return Consume()
        end
    end
end

# Control functions to steer the 3D simulation
isstopped(rba::RBA) = rba.simparams.stopped
stop(rba::RBA) = rba.simparams.stopped = true
start(rba::RBA) = rba.simparams.stopped = false
reset_time(rba::RBA) = rba.simparams.frame_idx = 0
faster(rba::RBA, n::Int) = rba.simparams.speed += n
slower(rba::RBA, n::Int) = rba.simparams.speed -= n
increasetot(rba::RBA, t::Float64) = rba.simparams.min_tot += t
decreasetot(rba::RBA, t::Float64) = rba.simparams.min_tot -= t
speed(rba::RBA) = rba.simparams.speed
toggle_rotation(rba::RBA) = rba.simparams.rotation_enabled = !global_rba().simparams.rotation_enabled
toggle_loop(rba::RBA) = rba.simparams.loop_enabled = !global_rba().simparams.loop_enabled
rotation_enabled(rba::RBA) = rba.simparams.rotation_enabled
function next_hits_colouring(rba::RBA)
    hidehits!(rba)
    rba.simparams.hits_selector += 1
end
function previous_hits_colouring(rba::RBA)
    hidehits!(rba)
    rba.simparams.hits_selector -= 1
end
function hidehits!(rba::RBA)
    for hitscloud in rba.hitsclouds
        n_hits = length(hitscloud.hits)
        hitscloud.mesh.markersize = zeros(n_hits)
    end
end

"""

Set the frames per second for the animation.

"""
function setfps!(rba::RBA, fps::Integer)
    rba.simparams.fps = fps
    nothing
end
setfps!(fps::Integer) = setfps!(global_rba(), fps)

function describe!(rba::RBA, hitscloud_idx::Integer, description::AbstractString)
    rba.hitsclouds[hitscloud_idx].description = description
end
function describe!(hitscloud_idx::Integer, description::AbstractString)
    describe!(global_rba(), hitscloud_idx, description)
end
