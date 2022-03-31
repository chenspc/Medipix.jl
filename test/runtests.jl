using Medipix
using Test

@testset "Medipix.jl" begin
    # Write your tests here.
    @test make_medipix_message("SET", "NUMFRAMESTOACQUIRE", 5) == "MPX,0000000025,SET,NUMFRAMESTOACQUIRE,5"
end
