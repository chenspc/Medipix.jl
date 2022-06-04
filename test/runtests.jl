using Medipix
using Test

@testset "Medipix.jl" begin
    @test Medipix.make_medipix_message("SET", "NUMFRAMESTOACQUIRE"; value="5") == "MPX,0000000025,SET,NUMFRAMESTOACQUIRE,5"
end
