"""

Select hits within a specific Cherenkov time window with respect to the given track.

"""
function select_cherenkov_hits(hits::T, track; mintot=20, maxtot=255, tmin=-50, tmax=500) where T
    hits = filter(h -> mintot < h.tot < maxtot, hits)
    out = T()
    for hit in hits
        chit = cherenkov(track, hit)
        if tmin < chit.Δt < tmax
            push!(out, hit)
        end
    end
    sort(out; by=h->h.t)
end


"""

Select the first `n` hits on each PMT.

"""
function select_first_hits(hits::T; n=1, mintot=20, maxtot=255) where T
    hits = filter(h -> mintot < h.tot < maxtot, hits)
    out = T()
    sort!(hits; by=h->h.t)
    pmts = Dict{Tuple{Int, Int}, Int}()
    for hit in hits
        pmtkey = (hit.dom_id, hit.channel_id)
        if !(pmtkey in keys(pmts))
            pmts[pmtkey] = 1
        end
        pmts[pmtkey] > n && continue
        pmts[pmtkey] += 1
        push!(out, hit)
    end
    out
end
