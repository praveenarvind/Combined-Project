"""Seeded RSP scheduling adapter. Any positive round count is allowed, including test limits 1 and N."""
struct RSPPlanner
    rounds::Int
    seed::Int
    threaded::Bool
    function RSPPlanner(rounds::Integer; seed::Integer=11, threaded::Bool=false)
        rounds > 0 || throw(ArgumentError("configured rounds must be positive"))
        seed >= 0 || throw(ArgumentError("partition seed must be nonnegative"))
        new(Int(rounds), Int(seed), threaded)
    end
end

"""Independent uniform assignments; never consumes or seeds Julia's ambient RNG."""
function rsp_assignments(planner::RSPPlanner, num_robots::Integer)
    num_robots > 0 || throw(ArgumentError("RSP requires at least one robot"))
    rand(MersenneTwister(planner.seed), 1:planner.rounds, num_robots)
end

"""All original robots and actor poses on an explicitly truncated horizon; no camera/motion changes."""
function pilot_configuration(configs=load_scenario(); horizon::Integer=3)
    2 <= horizon <= configs.horizon || throw(ArgumentError("pilot horizon must lie in 2:original_horizon"))
    MDMA.MultiDroneMultiActorConfigs(experiment_name=configs.experiment_name,
        num_robots=configs.num_robots, target_trajectories=configs.target_trajectories[1:horizon, :],
        grid=MDMA.MDMA_Grid(configs.grid.width, configs.grid.height, horizon),
        sensor=configs.sensor, horizon=horizon, move_dist=configs.move_dist)
end

struct BlockObservation
    robot_id::Int
    conditioned_on::Vector{Int}
    thread_id::Int
    started_ns::UInt64
    finished_ns::UInt64
end

mutable struct PlanningTrace
    calls::Threads.Atomic{Int}
    # Each robot owns exactly one slot; no concurrent push!, dictionaries or shared caches.
    blocks::Vector{Union{Nothing,BlockObservation}}
    legacy_evaluation_ns::UInt64
end

struct ObservedProblem{T,P<:SubmodularMaximization.PartitionProblem{T}} <:
       SubmodularMaximization.PartitionProblem{T}
    problem::P
    trace::PlanningTrace
end

function ObservedProblem(problem::SubmodularMaximization.PartitionProblem{T}) where T
    n = SubmodularMaximization.get_num_agents(problem)
    trace = PlanningTrace(Threads.Atomic{Int}(0), fill!(Vector{Union{Nothing,BlockObservation}}(undef,n), nothing), 0)
    ObservedProblem{T,typeof(problem)}(problem, trace)
end

SubmodularMaximization.get_num_agents(p::ObservedProblem) = SubmodularMaximization.get_num_agents(p.problem)

function SubmodularMaximization.solve_block(p::ObservedProblem{T}, robot::Integer, selections::Vector{T}) where T
    conditioned_on = Int[first(e) for e in selections]
    started = time_ns()
    Threads.atomic_add!(p.trace.calls, 1)
    element = SubmodularMaximization.solve_block(p.problem, robot, selections)
    p.trace.blocks[robot] = BlockObservation(robot, conditioned_on, Threads.threadid(), started, time_ns())
    element
end

function SubmodularMaximization.objective(p::ObservedProblem, selections)
    started = time_ns()
    value = SubmodularMaximization.objective(p.problem, selections)
    # Called once after all scheduler barriers; this field is not concurrently written.
    p.trace.legacy_evaluation_ns += time_ns() - started
    value
end

# Measures the actual upstream solver. Its final legacy evaluation is separately timed
# and subtracted; authoritative Phase 2 scoring occurs after this timing boundary.
function _measure_schedule(solve, problem)
    observed = ObservedProblem(problem)
    started = time_ns()
    solution = solve(observed)
    solver_ns = time_ns() - started
    all(x -> x !== nothing, observed.trace.blocks) || error("scheduler left an unplanned robot")
    (solution=solution, trace=observed.trace,
     planning_seconds=(solver_ns - observed.trace.legacy_evaluation_ns) / 1e9,
     solver_seconds=solver_ns / 1e9,
     legacy_evaluation_seconds=observed.trace.legacy_evaluation_ns / 1e9)
end

function _planner_settings(configs)
    (horizon=configs.horizon, num_robots=configs.num_robots,
     grid=(width=configs.grid.width, height=configs.grid.height, headings=configs.grid.angle_divisions),
     camera=(model=string(typeof(configs.sensor)), fov=configs.sensor.fov, cutoff=configs.sensor.cutoff),
     move_dist=configs.move_dist,
     vi=(max_iterations=90, belres=1e-6, include_Q=false, discount=1, verbose=true))
end

function _planning_result(measured, configs; planner, assignments, configured_rounds,
                          partition_seed, assignment_source, threaded)
    scores = evaluate_solution(configs, measured.solution)
    blocks = BlockObservation[x for x in measured.trace.blocks]
    metadata = (planner=planner, configured_rounds=configured_rounds,
        occupied_rounds=length(unique(assignments)), assignments=copy(assignments),
        partition_seed=partition_seed, assignment_source=assignment_source,
        rng="MersenneTwister", threaded=threaded, available_threads=Threads.nthreads(),
        worker_threads=sort(unique(x.thread_id for x in blocks)),
        vi_calls=measured.trace.calls[], planning_seconds=measured.planning_seconds,
        solver_seconds=measured.solver_seconds, legacy_evaluation_seconds=measured.legacy_evaluation_seconds,
        block_observations=blocks, settings=_planner_settings(configs))
    (solution=measured.solution, scores=scores, metadata=metadata)
end

"""
    plan_rsp(configs, states, planner; assignments=nothing)

Use the imported PartitionSolver/solve_dag without reimplementing its schedule.
Return solution, authoritative Phase 2 scores and reproducibility/execution metadata.
Explicit assignments permit exact replay and limiting-case tests. Threaded requests
require multiple Julia threads. Callers must not mutate configs during planning.
Every upstream filming block constructs its own prior coverage, reward cache and VI
solver; only read-only model inputs and earlier-round trajectories are shared.
"""
function plan_rsp(configs, states::Vector{MDMA.MDPState}, planner::RSPPlanner; assignments=nothing)
    check_states(configs, states)
    planner.threaded && Threads.nthreads() < 2 &&
        throw(ArgumentError("threaded RSP requires Julia --threads=2 or more"))
    configs.num_robots > 0 || throw(ArgumentError("RSP requires at least one robot"))
    source = assignments === nothing ? "seeded_independent_uniform" : "explicit_replay"
    labels = assignments === nothing ? rsp_assignments(planner, configs.num_robots) : collect(assignments)
    length(labels) == configs.num_robots || throw(ArgumentError("one round assignment is required per robot"))
    all(x -> x isa Integer && 1 <= x <= planner.rounds, labels) ||
        throw(ArgumentError("round assignments must lie in 1:configured_rounds"))
    labels = Int[labels...]
    dag = SubmodularMaximization.PartitionSolver(copy(labels))
    problem = MDMA.MultiRobotTargetCoverageProblem(copy(states), configs)
    measured = _measure_schedule(p -> SubmodularMaximization.solve_dag(dag,p; threaded=planner.threaded), problem)
    _planning_result(measured, configs; planner="rsp", assignments=labels,
        configured_rounds=planner.rounds, partition_seed=planner.seed,
        assignment_source=source, threaded=planner.threaded)
end

"""Time the original sequential greedy with the same accounting as RSP; baseline algorithms are unchanged."""
function measure_sequential(configs, states::Vector{MDMA.MDPState})
    check_states(configs, states)
    measured = _measure_schedule(SubmodularMaximization.solve_sequential,
        MDMA.MultiRobotTargetCoverageProblem(copy(states), configs))
    _planning_result(measured, configs; planner="greedy", assignments=collect(1:configs.num_robots),
        configured_rounds=configs.num_robots, partition_seed=nothing,
        assignment_source="ordered_singletons", threaded=false)
end
