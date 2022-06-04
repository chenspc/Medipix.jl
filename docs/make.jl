using Medipix
using Documenter

DocMeta.setdocmeta!(Medipix, :DocTestSetup, :(using Medipix); recursive=true)

makedocs(;
    modules=[Medipix],
    authors="Chen Huang <chen1huang2@gmail.com> and contributors",
    repo="https://github.com/chenspc/Medipix.jl/blob/{commit}{path}#{line}",
    sitename="Medipix.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://chenspc.github.io/Medipix.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/chenspc/Medipix.jl",
)
