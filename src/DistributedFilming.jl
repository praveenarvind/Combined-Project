"""Headless filming foundation imported from the attributed upstream research code."""
module DistributedFilming

include("profiling/stages.jl")
include("submodular/SubmodularMaximization.jl")
include("filming/MDMA.jl")
include("planners/baselines.jl")
include("evaluation/srppa.jl")
include("planners/rsp.jl")
include("benchmarking/runner.jl")
include("benchmarking/io.jl")
include("benchmarking/controls.jl")

export scheduling_control
export run_benchmarks, summarize_benchmarks
export benchmark_configuration, load_benchmark_config, estimate_benchmark, benchmark_plan, warm_benchmarks, bellman_certificate
export RSPPlanner, rsp_assignments, pilot_configuration, plan_rsp, measure_sequential
export joint_srppa, marginal_srppa, motion_bonuses, legacy_value, evaluate_solution
export SubmodularMaximization, MDMA
export load_scenario, cluster_scenario, initial_states, smoke_configuration, plan_baseline
export GreedyPlanner, MultipleRoundsGreedyPlanner, MyopicPlanner, FormationPlanner, AssignmentPlanner

end
