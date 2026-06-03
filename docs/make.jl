using RainbowAlga
using Documenter

DocMeta.setdocmeta!(RainbowAlga, :DocTestSetup, :(using RainbowAlga); recursive=true)

makedocs(;
    modules=[RainbowAlga],
    authors="Tamas Gal <himself@tamasgal.com> and contributors",
    repo=Documenter.Remotes.URL(
        "https://git.km3net.de/tgal/RainbowAlga.jl/blob/{commit}{path}#L{line}",
        "https://git.km3net.de/tgal/RainbowAlga.jl",
    ),
    sitename="RainbowAlga.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://tgal.pages.km3net.de/RainbowAlga.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "The KM3-230213A event" => "uhe-event.md",
    ],
)

deploydocs(;
    repo="git.km3net.de/tgal/RainbowAlga.jl",
    devbranch="main",
    push_preview=true,
)
