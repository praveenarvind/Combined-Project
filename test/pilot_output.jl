# Validate a freshly generated pilot artifact, not a baseline score fixture.
using Test
using JSON3
using DistributedFilming

path = isempty(ARGS) ? joinpath(@__DIR__,"..","results","rsp-ci","run.json") : only(ARGS)
run = JSON3.read(read(path,String))
@testset "Fresh RSP pilot artifact and exact replay metadata" begin
    @test run.context.available_threads >= 2
    @test run.context.settings.num_robots == (run.context.workload == "supplementary_two_robot_four_frame" ? 2 : 5)
    @test run.context.initial_seed == 2026
    @test length(run.records) == 7length(run.context.partition_seeds)
    for r in run.records
        m = r.metadata
        @test m.vi_calls == run.context.settings.num_robots
        @test length(m.assignments) == m.settings.num_robots
        @test m.occupied_rounds == length(unique(m.assignments))
        @test all(x -> 1 <= x <= m.configured_rounds,m.assignments)
        @test r.validation.max_difference_error < 1e-10
        @test r.validation.max_single_robot_error < 1e-10
        @test m.planning_seconds >= 0
        @test m.solver_seconds ≈ m.planning_seconds + m.legacy_evaluation_seconds
        @test r.scores.joint_srppa > 0
        if m.planner == "rsp"
            @test collect(m.assignments) == rsp_assignments(RSPPlanner(m.configured_rounds;seed=m.partition_seed),m.settings.num_robots)
            partner = only(filter(p -> p.replicate == r.replicate && p.metadata.planner == "rsp" && p.metadata.configured_rounds == m.configured_rounds && p.mode != r.mode,run.records))
            @test r.solution.elements == partner.solution.elements
            @test r.scores == partner.scores
        end
    end
end
