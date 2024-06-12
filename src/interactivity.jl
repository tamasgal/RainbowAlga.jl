"""
    register_events(rba::RBA)

Registers keyboard and mouse events for the interactive access.
"""
function register_events(rba::RBA)
    scene = rba.scene
    on(events(scene).mousebutton) do event
        # if scene.events.hasfocus[]
        #     println("focus")
        #     simparams.fps = 60
        # else
        #     println("no focus")
        #     simparams.fps = 15
        # end
    end
    on(events(scene).keyboardbutton, priority = 20) do event
        if ispressed(scene, Makie.Keyboard.r)
            reset_time()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.space)
            simparams.stopped = !simparams.stopped
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.left)
            simparams.loop_enabled = false
            simparams.frame_idx -= 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.right)
            simparams.loop_enabled = false
            simparams.frame_idx += 200
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.a)
            toggle_rotation()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c & (Makie.Keyboard.left_shift | Makie.Keyboard.right_shift))
            previous_hits_colouring()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.c)
            next_hits_colouring()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.l)
            toggle_loop()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.l)
            toggle_loop()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.d)
            if simparams.darkmode_enabled
                scene.backgroundcolor = RGBf(0.9, 0.9, 0.9)
                rba.infobox.color = RGBf(0.1, 0.1, 0.1)
                simparams.darkmode_enabled = false
            else
                scene.backgroundcolor = RGBf(0.0, 0.0, 0.1)
                simparams.darkmode_enabled = true
                rba.infobox.color = RGBf(0.9, 0.9, 0.9)
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.up)
            faster(1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.down)
            slower(1)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.comma)
            decreasetot(0.5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.period)
            increasetot(0.5)
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.i)
            simparams.hit_scaling += 1
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.u)
            if simparams.hit_scaling > 1
                simparams.hit_scaling -= 1
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.q)
            simparams.quit = true
            return Consume()
        end
    end
end
