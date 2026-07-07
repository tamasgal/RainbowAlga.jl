Base.@kwdef mutable struct DisplayParams
    pos::Tuple{Int, Int} = (0, 0)
    size::Tuple{Int, Int} = (600, 600)
end

const displayparams = let m = GLFW.GetVideoMode(GLFW.GetPrimaryMonitor())
    width = Int(round(m.width * 0.6))
    height = Int(round(m.height * 0.6))
    DisplayParams(
        pos = (Int(round((m.width - width)/2)), Int(round((m.height - height)/2))),
        size = (width, height)
    )
end

Base.@kwdef mutable struct SimParams
    frame_idx::Int = 0
    t_offset::Float64 = 0.0
    cb_t_offset::Float64 = 0.0  # colorbar display offset relative to t_offset (can be negative)
    stopped::Bool = false
    speed::Int = 10
    min_tot::Float64 = 0.0  # all hits
    loop_end_frame_idx::Int = 10000
    rotation_enabled::Bool = true
    loop_enabled::Bool = true
    darkmode_enabled::Bool = false
    show_infobox::Bool = true
    screenshot_counter::Int = 0
    recording_counter::Int = 0
    hits_selector::Int = 0  # selects the hits cloud (normal, cherenkov, ...)
    displayed_hitscloud::Int = 0  # index of the hits cloud currently uploaded to the shared mesh (0 = none)
    hit_scaling::Int = 50  # factor to multiply the size of the hits
    fps::Int = 30  # render frames per second (caps the GLMakie render loop)
    animation_mode::Symbol = :time  # :time (hits/tracks by ns) or :summaryslice (per-PMT rates by slice index)
    event_input_mode::Bool = false
    event_input_buffer::String = ""
    frame_tc_input_stage::Int = 0  # 0 = off, 1 = entering frame_index, 2 = entering trigger_counter
    frame_index_buffer::String = ""
    trigger_counter_buffer::String = ""
    # Deferred selector search (S / Shift+S): the render loop shows a centred "Searching..."
    # overlay for one rendered frame before running the potentially slow, blocking selector
    # scan, so the window does not look frozen. :none, :next or :previous.
    pending_search::Symbol = :none
    search_frames_waited::Int = 0
end

