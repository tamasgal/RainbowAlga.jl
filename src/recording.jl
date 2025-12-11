mutable struct VideoIO
    process::Any
    buffer::Matrix{ColorTypes.RGB{N0f8}}
    write_buffer::Vector{UInt8}
    path::String
end

function VideoIO(
        frame::Matrix{ColorTypes.RGB{N0f8}};
        format = "mp4",
        framerate=24,
        compression=nothing,
        profile=nothing,
        pixel_format="yuv420p",
        loop=nothing,
        loglevel="quiet",
        path="RBA_recording.$(format)",
        preset="ultrafast",
        crf=23  # quality parameter
    )

    vso = Makie.VideoStreamOptions(format, framerate, compression, profile, pixel_format, loop, loglevel, "pipe:0", true)

    _xdim, _ydim = size(frame)
    xdim = iseven(_xdim) ? _xdim : _xdim + 1
    ydim = iseven(_ydim) ? _ydim : _ydim + 1
    
    cmd = Makie.to_ffmpeg_cmd(vso, xdim, ydim)
    
    extra_flags = [
        "-preset", preset,
        "-crf", string(crf),
        "-tune", "zerolatency",  # Optimize for fast encoding
        "-threads", "0",  # Use all available threads
        "-bufsize", "10M",  # Larger buffer
    ]
    
    full_cmd = `$(Makie.FFMPEG_jll.ffmpeg()) $cmd $extra_flags $path`
    buffer = Matrix{ColorTypes.RGB{N0f8}}(undef, xdim, ydim)
    write_buffer = Vector{UInt8}(undef, xdim * ydim * 3)
    process = open(pipeline(full_cmd; stdout=devnull, stderr=devnull), "w")
    
    return VideoIO(process, buffer, write_buffer, path)
end

function write_frame!(io::VideoIO, frame::Matrix{ColorTypes.RGB{N0f8}})
    buffer = io.buffer
    
    if size(frame) != size(buffer)
        xdim, ydim = size(frame)
        copy!(view(io.buffer, 1:xdim, 1:ydim), frame)
        frame_to_write = io.buffer
    else
        frame_to_write = frame
    end
    
    # Write directly without intermediate allocations
    # This is faster than letting write() handle the conversion
    unsafe_write(io.process.in, Ptr{UInt8}(pointer(frame_to_write)), sizeof(frame_to_write))
end

mutable struct VideoRecorder
    io::Union{Nothing, VideoIO}
    frames::Union{Nothing, Channel{Matrix{ColorTypes.RGB{N0f8}}}}
    recording::Threads.Atomic{Bool}
    kw::Any
    task::Union{Nothing, Task}
    frame_count::Ref{Int}  # Track frames for debugging
end

VideoRecorder(; kw...) = VideoRecorder(nothing, nothing, Threads.Atomic{Bool}(false), kw, nothing, Ref(0))

function start!(recorder::VideoRecorder; outfname="foo.mp4")
    recorder.recording[] = true
    recorder.frame_count[] = 0
    # Use bounded channel to prevent memory buildup if encoding is slow
    recorder.frames = Channel{Matrix{ColorTypes.RGB{N0f8}}}(Inf)
    
    recorder.task = Makie.spawnat(2) do
        for frame in recorder.frames
            try
                if recorder.io === nothing
                    recorder.io = VideoIO(frame; recorder.kw...)
                end
                write_frame!(recorder.io, frame)
                recorder.frame_count[] += 1
            catch e
                @warn "Error while writing video frame" exception = e
            end
        end
        close(recorder.io.process)
        mv(recorder.io.path, outfname)
        println("Wrote $(recorder.frame_count[]) frames total to $(outfname)")
        recorder.task = nothing
        recorder.frames = nothing
        recorder.io = nothing
    end
    Base.errormonitor(recorder.task)
    return
end

function stop!(recorder::VideoRecorder)
    recorder.recording[] = false
    close(recorder.frames)
    # Wait for encoding to finish
    if recorder.task !== nothing
        wait(recorder.task)
    end
    return
end

function copy_colorbuffer!(screen)
    ctex = screen.framebuffer.buffers[:color]
    if size(ctex) != size(screen.framecache)
        screen.framecache = Matrix{RGB{N0f8}}(undef, size(ctex))
    end
    GLMakie.fast_color_data!(screen.framecache, ctex)
    return copy(screen.framecache)
end

function fps_renderloop(screen::GLMakie.Screen, recorder)
    Makie.reset!(screen.timer, 1.0 / screen.config.framerate)
    while isopen(screen)
        GLMakie.pollevents(screen, Makie.RegularRenderTick)
        GLMakie.poll_updates(screen)
        GLMakie.render_frame(screen)
        GLMakie.GLFW.SwapBuffers(GLMakie.to_native(screen))
        GC.safepoint()
        if recorder.recording[]
            frame = copy_colorbuffer!(screen)
            # Non-blocking put with timeout to avoid hanging
            # TODO: currently the buffer length is not checked, so the memory
            # can fill easily fill up. This proably needs to be made a little
            # bit more user-friendly ;) Let's leave it here for now...
            # if !isready(recorder.frames) || length(recorder.frames.data) < 90
                put!(recorder.frames, frame)
            # else
            #     @warn "Frame buffer full, dropping frame"
            # end
        end
        sleep(screen.timer)
    end
    GLMakie.destroy!(screen)
    return nothing
end
