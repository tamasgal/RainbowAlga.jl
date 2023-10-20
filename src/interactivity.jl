function register_keyboard_events(scene::Scene)
    on(events(scene).keyboardbutton, priority = 20) do event
        if ispressed(scene, Makie.Keyboard.r)
            reset_time()
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
        if ispressed(scene, Makie.Keyboard.c)
            cycle_hits()
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.l)
            toggle_loop()
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
        if ispressed(scene, Makie.Keyboard.space)
            if isstopped()
                start()
            else
                stop()
            end
            return Consume()
        end
        if ispressed(scene, Makie.Keyboard.q)
            simparams.quit = true
            return Consume()
        end
    end
end
