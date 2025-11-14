mutable struct VideoRecordingState
    isrecording::Bool
    videostream::Union{@NamedTuple{chan::Channel{Nothing}, vio::@NamedTuple{io::Base.PipeEndpoint, process::Base.Process, options::Makie.VideoStreamOptions, buffer::Matrix{ColorTypes.RGB{N0f8}}, path::String}}, Nothing}
    counter::Int
end


function _save(path::String, vio)
    close(vio.process)
    wait(vio.process)
    p, typ = splitext(path)
    video_fmt = vio.options.format
    if typ != ".$(video_fmt)"
        # Maybe warn?
        Makie.convert_video(vio.path, path)
    else
        cp(vio.path, path; force=true)
    end
    return path
end


function blit_colorbuffer!(screen, vio)
    glnative = colorbuffer(screen, Makie.GLNative)
    xdim, ydim = size(glnative)
    if eltype(glnative) == eltype(vio.buffer) && size(glnative) == size(vio.buffer)
        write(vio.io, glnative)
    else
        copy!(view(vio.buffer, 1:xdim, 1:ydim), glnative)
        write(vio.io, vio.buffer)
    end
    return Core.println("Wrote frame to video stream")
end


"""

A huge thanks to Simon Danisch for this function (and a couple more)!

"""
function video_stream(
        screen::GLMakie.Screen;
        format="mp4", framerate=24, compression=nothing, profile=nothing, pixel_format=nothing, loop=nothing,
        loglevel="quiet"
    )

    dir = mktempdir()
    path = joinpath(dir, "$(gensym(:video)).$(format)")
    first_frame = colorbuffer(screen)
    _ydim, _xdim = size(first_frame)
    xdim = iseven(_xdim) ? _xdim : _xdim + 1
    ydim = iseven(_ydim) ? _ydim : _ydim + 1
    buffer = Matrix{RGB{N0f8}}(undef, xdim, ydim)
    vso = Makie.VideoStreamOptions(format, framerate, compression, profile, pixel_format, loop, loglevel, "pipe:0", true)
    cmd = Makie.to_ffmpeg_cmd(vso, xdim, ydim)
    # a plain `open` without the `pipeline` causes hangs when IOCapture.capture closes over a function that creates
    # a `VideoStream` without closing the process explicitly, such as when returning `Record` in a cell in Documenter or quarto
    process = open(pipeline(`$(Makie.FFMPEG_jll.ffmpeg()) $cmd $path`; stdout=devnull, stderr=devnull), "w")
    vio = (io=process.in, process=process, options=vso, buffer=buffer, path=path)
    chan = Channel{Nothing}(Inf) do c
        # Somehow this needs to happen here otherwise write(io) blocks!
        for f in c
            blit_colorbuffer!(screen, vio)
        end
    end
    return (chan=chan, vio=vio)
end
