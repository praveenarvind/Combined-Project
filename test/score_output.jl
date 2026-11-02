# Run after scripts/baseline.jl --smoke; CI starts from a checkout with no result files.
using Test
using JSON3
using DistributedFilming

@testset "Fresh CLI score schema and compatible legacy reader" begin
    dir = joinpath(@__DIR__, "..", "results", "smoke", "greedy")
    output = JSON3.read(read(joinpath(dir, "solution.json"), String))
    run = JSON3.read(read(joinpath(dir, "run.json"), String))
    restored = MDMA.load_solution(joinpath(dir, "solution.json"))
    expected = evaluate_solution(smoke_configuration(load_scenario()), restored)
    @test output.score_schema_version == run.score_schema_version == 2
    @test output.value_kind == "legacy"
    @test output.value == output.legacy_value == restored.value == expected.legacy_value
    @test output.joint_srppa == run.scores.joint_srppa == expected.joint_srppa
    @test output.heading_bonus == run.scores.heading_bonus == expected.heading_bonus
    @test output.stationary_bonus == run.scores.stationary_bonus == expected.stationary_bonus
    @test run.scores.legacy_value == expected.legacy_value
    @test (run.scenario, run.planner, run.robots, run.horizon, run.seed, run.reduced_smoke) ==
          ("cluster", "greedy", 2, 4, 2026, true)
end
