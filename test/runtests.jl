using MedipixMerlinEM
using Test

@testset "MedipixMerlinEM.jl" begin
    @test MedipixMerlinEM.make_medipix_message("SET", "NUMFRAMESTOACQUIRE"; value="5") == "MPX,0000000025,SET,NUMFRAMESTOACQUIRE,5"
end
