using MedipixMerlinEM
using Documenter

DocMeta.setdocmeta!(MedipixMerlinEM, :DocTestSetup, :(using MedipixMerlinEM); recursive=true)

makedocs(;
    modules=[MedipixMerlinEM],
    authors="Chen Huang <chen1huang2@gmail.com> and contributors",
    repo="https://github.com/chenspc/MedipixMerlinEM.jl/blob/{commit}{path}#{line}",
    sitename="MedipixMerlinEM.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://chenspc.github.io/MedipixMerlinEM.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/chenspc/MedipixMerlinEM.jl",
)
