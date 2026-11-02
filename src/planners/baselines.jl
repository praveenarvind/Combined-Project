using Random

# Planner tags and dispatch adapted from upstream MDMA_Experiment.jl (see SOURCES.toml).
struct GreedyPlanner end
struct MultipleRoundsGreedyPlanner end
struct MyopicPlanner end
struct FormationPlanner end
struct AssignmentPlanner end

cluster_scenario() = normpath(joinpath(@__DIR__, "..", "..", "data", "scenarios", "cluster", "cluster_data.json"))

"""Load scenario inputs with the same camera override and movement distance as upstream experiments."""
function load_scenario(path::AbstractString=cluster_scenario(); name="cluster")
    configs = MDMA.configs_from_file(String(path), String(name), 3)
    configs.sensor = MDMA.ViewConeSensor(pi / 2, 100.0)
    configs
end

"""Sample the upstream uniform initial-state distribution with an explicit RNG."""
function initial_states(configs; seed::Integer=2026)
    rng = MersenneTwister(seed)
    [MDMA.MDPState(MDMA.UAVState(rand(rng, 1:configs.grid.width),
                               rand(rng, 1:configs.grid.height),
                               rand(rng, MDMA.cardinaldir)), configs.horizon)
     for _ in 1:configs.num_robots]
end

"""Explicit test workload: first four original frames, two robots; no geometric or reward changes."""
function smoke_configuration(configs)
    horizon = min(4, configs.horizon)
    MDMA.MultiDroneMultiActorConfigs(
        experiment_name=configs.experiment_name,
        num_robots=min(2, configs.num_robots),
        target_trajectories=configs.target_trajectories[1:horizon, :],
        grid=MDMA.MDMA_Grid(configs.grid.width, configs.grid.height, horizon),
        sensor=configs.sensor, horizon=horizon, move_dist=configs.move_dist)
end

function plan_baseline(configs, states::Vector{MDMA.MDPState}, ::GreedyPlanner)
    check_states(configs, states)
    SubmodularMaximization.solve_sequential(MDMA.MultiRobotTargetCoverageProblem(copy(states), configs))
end

function plan_baseline(configs, states::Vector{MDMA.MDPState}, ::MultipleRoundsGreedyPlanner)
    check_states(configs, states)
    # Preserve upstream: N complete sequential replanning sweeps for N robots.
    SubmodularMaximization.solve_sequential_multiround(
        MDMA.MultiRobotTargetCoverageProblem(copy(states), configs), configs.num_robots)
end

function plan_baseline(configs, states::Vector{MDMA.MDPState}, ::MyopicPlanner)
    check_states(configs, states)
    SubmodularMaximization.solve_myopic(MDMA.MultiRobotTargetCoverageProblem(copy(states), configs))
end

function plan_baseline(configs, states::Vector{MDMA.MDPState}, ::AssignmentPlanner)
    check_states(configs, states)
    SubmodularMaximization.solve_sequential(MDMA.MultiRobotTargetAssignmentProblem(copy(states), configs))
end

"""Original idealized formation; deliberately does not enforce VI movement or initial-state constraints."""
function plan_baseline(configs, states::Vector{MDMA.MDPState}, ::FormationPlanner; seed::Integer=2026)
    check_states(configs, states)
    formation = MDMA.formation_from_multi(15.0, randn(MersenneTwister(seed)), configs)
    MDMA.solve_formation(formation)
end

function check_states(configs, states)
    length(states) == configs.num_robots || throw(ArgumentError("initial-state count must match team size"))
    all(s -> s.depth == 1 && s.horizon == configs.horizon, states) ||
        throw(ArgumentError("initial states must start at depth one with the configured horizon"))
    nothing
end
