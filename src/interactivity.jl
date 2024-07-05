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
    on(events(scene).keyboardbutton, priority = 20) do event
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
        if ispressed(scene, Makie.Keyboard.c & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            previous_hits_colouring(rba)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c)
            next_hits_colouring(rba)
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
@inline isstopped(rba::RBA) = rba.simparams.stopped
@inline stop(rba::RBA) = rba.simparams.stopped = true
@inline start(rba::RBA) = rba.simparams.stopped = false
@inline reset_time(rba::RBA) = rba.simparams.frame_idx = 0
@inline faster(rba::RBA, n::Int) = rba.simparams.speed += n
@inline slower(rba::RBA, n::Int) = rba.simparams.speed -= n
@inline increasetot(rba::RBA, t::Float64) = rba.simparams.min_tot += t
@inline decreasetot(rba::RBA, t::Float64) = rba.simparams.min_tot -= t
@inline speed(rba::RBA) = rba.simparams.speed
@inline toggle_rotation(rba::RBA) = rba.simparams.rotation_enabled = !_rba.simparams.rotation_enabled
@inline toggle_loop(rba::RBA) = rba.simparams.loop_enabled = !_rba.simparams.loop_enabled
@inline rotation_enabled(rba::RBA) = rba.simparams.rotation_enabled
@inline next_hits_colouring(rba::RBA) = rba.simparams.hits_selector += 1
@inline previous_hits_colouring(rba::RBA) = rba.simparams.hits_selector -= 1
