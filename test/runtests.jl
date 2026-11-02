using Test
using SHA
using TOML
using POMDPs
using DistributedFilming

const M = DistributedFilming.MDMA
const S = DistributedFilming.SubmodularMaximization
const provenance = TOML.parsefile(joinpath(@__DIR__, "..", "third_party", "SOURCES.toml"))

include("srppa.jl")

@testset "Scenario inputs and reproducible initialization" begin
    entry = only(filter(e -> endswith(e["destination"], "cluster_data.json"), provenance["files"]))
    @test bytes2hex(sha256(read(cluster_scenario()))) == entry["sha256"]
    configs = load_scenario()
    @test (configs.num_robots, configs.horizon, size(configs.target_trajectories, 2)) == (5, 60, 6)
    @test configs.sensor.fov == pi / 2
    @test configs.sensor.cutoff == 100.0
    @test configs.move_dist == 3
    @test initial_states(configs; seed=2026) == initial_states(configs; seed=2026)
    @test initial_states(configs; seed=2026) != initial_states(configs; seed=2027)
    reduced = smoke_configuration(configs)
    @test (reduced.num_robots, reduced.horizon) == (2, 4)
    @test reduced.target_trajectories == configs.target_trajectories[1:4, :]
    @test reduced.sensor === configs.sensor
end

function check_vi_trajectory(solution, configs, states)
    @test isfinite(solution.value)
    @test sort(first.(solution.elements)) == collect(1:configs.num_robots)
    for (robot, path) in solution.elements
        @test length(path) == configs.horizon
        @test first(path) == states[robot]
        @test [s.depth for s in path] == collect(1:configs.horizon)
        @test all(s -> s.horizon == configs.horizon, path)
        # Exercise the unchanged movement/turn constraints, not an approximate distance check.
        probe = M.SingleRobotMultiTargetViewCoverageProblem(configs.grid, configs.sensor,
            configs.horizon, configs.target_trajectories, Int(configs.move_dist),
            M.generate_empty_coverage_data(configs), states[robot])
        @test all(i -> path[i+1] in POMDPs.actions(probe, path[i]), 1:length(path)-1)
        @test POMDPs.isterminal(probe, last(path))
    end
end

@testset "Fresh baseline solves on a reduced cluster scenario" begin
    configs = smoke_configuration(load_scenario())
    states = initial_states(configs)
    before = copy(states)
    greedy = plan_baseline(configs, states, GreedyPlanner())
    check_vi_trajectory(greedy, configs, states)
    check_joint_evaluation(greedy, configs)
    @test greedy.value ≈ 12.048784128677479 atol=1e-11 rtol=1e-12
    @test states == before
    @test greedy.value == S.objective(M.MultiRobotTargetCoverageProblem(states, configs), greedy.elements)
    for planner in (MyopicPlanner(), MultipleRoundsGreedyPlanner(), AssignmentPlanner())
        solution = plan_baseline(configs, states, planner)
        check_vi_trajectory(solution, configs, states)
        check_joint_evaluation(solution, configs)
    end
    formation = plan_baseline(configs, states, FormationPlanner())
    @test length(formation.elements) == configs.num_robots
    @test all(e -> length(last(e)) == configs.horizon, formation.elements)
    check_joint_evaluation(formation, configs; check_transitions=false)
    @test formation.value == 1.0 # Preserve the upstream placeholder, not a quality claim.
    @test first(last(first(formation.elements))) != first(states)
    @test_throws ArgumentError plan_baseline(configs, states[1:1], GreedyPlanner())
    mktempdir() do dir
        M.save_solution("cluster", dir, "greedy", greedy, configs)
        restored = M.load_solution(joinpath(dir, "cluster", "greedy", "solution.json"))
        @test restored.value == greedy.value
        @test restored.elements == greedy.elements
    end
end

@testset "Preserved legacy reward and camera APIs" begin
    face = M.Face(1.0, 2.0, 2.0, 3.0, [0.0, 0.0, 1.0])
    @test M.face_view_quality(face, 4.0) == 12.0
    configs = smoke_configuration(load_scenario())
    state = first(initial_states(configs))
    model = M.SingleRobotMultiTargetViewCoverageProblem(configs.grid, configs.sensor,
        configs.horizon, configs.target_trajectories, Int(configs.move_dist),
        M.generate_empty_coverage_data(configs), state)
    @test POMDPs.reward(model, state) ≈ M.load_cached_reward(model, state) + 0.03
    pinhole = M.PinholeCameraModel([20.0,20.0], [3840.0,2160.0], [35.0,24.0], 0.0, -0.3490655, 100.0)
    @test size(pinhole.intrinsics) == (3, 3)
    @test M.detectTarget(state.state, configs.target_trajectories[1,1], pinhole) isa Bool
end

@testset "Single reused submodular core" begin
    agents = [S.Agent(Float64[], 0.0, [1.0, 2.0]) for _ in 1:2]
    problem = S.ExplicitPartitionProblem(xs -> sum(xs; init=0.0), agents)
    @test S.solve_sequential(problem).value == 4.0
    @test S.solve_sequential_multiround(problem, 2).value == 4.0
    dag = S.PartitionSolver([1,2])
    @test isempty(S.in_neighbors(dag, 1))
    @test S.in_neighbors(dag, 2) == [1]
end

include("rsp.jl")
