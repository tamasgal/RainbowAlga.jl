using RainbowAlga
using Documenter

DocMeta.setdocmeta!(RainbowAlga, :DocTestSetup, :(using RainbowAlga); recursive=true)

makedocs(;
    modules=[RainbowAlga],
    authors="Tamas Gal <himself@tamasgal.com> and contributors",
    repo="https://git.km3net.de/tgal/RainbowAlga.jl/blob/{commit}{path}#{line}",
    sitename="RainbowAlga.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://tgal.gitlab.io/RainbowAlga.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
