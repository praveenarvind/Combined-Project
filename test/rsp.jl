using Random

# A deterministic dependency-recording fixture exercises the actual traced upstream
# solve_dag concurrently, without involving VI, wall-clock speed or global log mutation.
struct ConditioningProblem <: S.PartitionProblem{Tuple{Int,Vector{Int}}}
    partition_matroid::Vector{Int}
end
S.solve_block(p::ConditioningProblem, id::Integer, prior::Vector{Tuple{Int,Vector{Int}}}) = begin
    sleep(0.02) # Yield so independent same-round calls visibly overlap in the trace.
    (Int(id), sort(first.(prior)))
end
S.objective(::ConditioningProblem, selections) = 0.0

@testset "Seeded RSP assignment and original DAG conditioning" begin
    @test Threads.nthreads() >= 2 # CI explicitly launches a multithreaded test worker.
    for rounds in (1,2,4,8)
        planner = RSPPlanner(rounds; seed=11)
        labels = rsp_assignments(planner,5)
        @test labels == rsp_assignments(planner,5)
        @test labels == rand(MersenneTwister(11),1:rounds,5)
        @test length(labels) == 5
        @test all(x -> 1 <= x <= rounds, labels)
        @test sort(S.sequence(S.PartitionSolver(labels))) == collect(1:5)
    end
    Random.seed!(812)
    first_draw = rand(); second_draw = rand()
    Random.seed!(812)
    @test rand() == first_draw
    rsp_assignments(RSPPlanner(8; seed=33),5)
    @test rand() == second_draw
    labels = [1,1,3,2,3]
    dag = S.PartitionSolver(labels)
    problem = ConditioningProblem(collect(1:5))
    measured = DistributedFilming._measure_schedule(p -> S.solve_dag(dag,p; threaded=true), problem)
    traces = measured.trace.blocks
    for id in 1:5
        expected = findall(r -> r < labels[id], labels)
        @test measured.solution.elements[id] == (id,expected)
        @test sort(traces[id].conditioned_on) == expected
        @test all(j -> traces[j].finished_ns <= traces[id].started_ns, expected)
    end
    @test isempty(traces[1].conditioned_on) && isempty(traces[2].conditioned_on)
    @test traces[1].started_ns < traces[2].finished_ns && traces[2].started_ns < traces[1].finished_ns
    @test length(unique(t.thread_id for t in traces)) > 1
    @test measured.trace.calls[] == 5
    @test_throws ArgumentError RSPPlanner(0)
    @test_throws ArgumentError RSPPlanner(2; seed=-1)
    @test_throws ArgumentError rsp_assignments(RSPPlanner(2),0)
end

@testset "Thread-local filming reward caches" begin
    configs = smoke_configuration(load_scenario())
    states = initial_states(configs)
    make_model(i) = M.SingleRobotMultiTargetViewCoverageProblem(configs.grid, configs.sensor,
        configs.horizon, configs.target_trajectories, Int(configs.move_dist),
        M.compute_prior_coverage(configs,M.Trajectory[]), states[i])
    tasks = [Threads.@spawn make_model(i) for i in 1:2]
    first_model, second_model = fetch.(tasks)
    @test first_model.view_reward_cache !== second_model.view_reward_cache
    @test first_model.coverage_data !== second_model.coverage_data
    saved_cache = copy(second_model.view_reward_cache)
    saved_coverage = copy(second_model.coverage_data)
    fill!(first_model.view_reward_cache,-100.0)
    fill!(first_model.coverage_data,100.0)
    @test second_model.view_reward_cache == saved_cache
    @test second_model.coverage_data == saved_coverage
end

@testset "Fresh RSP VI, replay, limiting cases and Phase 2 marginals" begin
    # Three robots / two original frames keep the test small; the pilot uses all five.
    configs = pilot_configuration(;horizon=2)
    configs.num_robots = 3
    states = initial_states(configs)
    before = copy(states)
    # Explicit same-round pair plus a later robot ensures both concurrency and conditioning.
    pair = plan_rsp(configs,states,RSPPlanner(2;seed=11,threaded=true);assignments=[1,1,2])
    serial_pair = plan_rsp(configs,states,RSPPlanner(2;seed=11);assignments=[1,1,2])
    @test pair.solution.elements == serial_pair.solution.elements
    @test pair.scores == serial_pair.scores
    traces = pair.metadata.block_observations
    @test traces[3].conditioned_on == [1,2]
    @test all(isempty(traces[i].conditioned_on) for i in 1:2)
    @test length(pair.metadata.worker_threads) > 1
    @test traces[1].started_ns < traces[2].finished_ns && traces[2].started_ns < traces[1].finished_ns
    results = Any[pair,serial_pair]
    for rounds in (4,8)
        serial = plan_rsp(configs,states,RSPPlanner(rounds;seed=22))
        threaded = plan_rsp(configs,states,RSPPlanner(rounds;seed=22,threaded=true))
        @test serial.metadata.assignments == threaded.metadata.assignments
        @test serial.solution.elements == threaded.solution.elements
        @test serial.scores == threaded.scores
        @test serial.metadata.configured_rounds == rounds
        @test serial.metadata.occupied_rounds == length(unique(serial.metadata.assignments))
        push!(results,serial,threaded)
    end
    one = plan_rsp(configs,states,RSPPlanner(1;seed=11,threaded=true))
    myopic = plan_baseline(configs,states,MyopicPlanner())
    @test one.solution.elements == myopic.elements
    @test one.scores == evaluate_solution(configs,myopic)
    singleton = plan_rsp(configs,states,RSPPlanner(3);assignments=[1,2,3])
    greedy = plan_baseline(configs,states,GreedyPlanner())
    @test singleton.solution.elements == greedy.elements
    @test singleton.scores == evaluate_solution(configs,greedy)
    @test singleton.metadata.assignment_source == "explicit_replay"
    measured_greedy = measure_sequential(configs,states)
    @test measured_greedy.solution.elements == greedy.elements
    push!(results,one,singleton,measured_greedy)
    for result in results
        @test result.metadata.vi_calls == configs.num_robots
        @test result.metadata.planning_seconds >= 0
        @test result.metadata.solver_seconds ≈ result.metadata.planning_seconds + result.metadata.legacy_evaluation_seconds
        check_vi_trajectory(result.solution,configs,states)
        check_joint_evaluation(result.solution,configs)
        @test result.scores.joint_srppa == joint_srppa(configs,result.solution)
    end
    @test states == before
    @test_throws ArgumentError plan_rsp(configs,states,RSPPlanner(2);assignments=[1,2])
    @test_throws ArgumentError plan_rsp(configs,states,RSPPlanner(2);assignments=[1,2,3])
    @test_throws ArgumentError plan_rsp(configs,states,RSPPlanner(2);assignments=[1,0,2])
end
