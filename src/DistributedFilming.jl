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
include("experiments/phase5_inventory.jl")
include("experiments/phase5_execution.jl")
include("experiments/phase5_reporting.jl")
include("experiments/phase5_fixture.jl")
include("experiments/phase5_controls.jl")

export ordered_rsp_assignments, phase5_configuration, phase5_inventory, initialize_phase5
export select_phase5_jobs, phase5_preflight
export run_phase5_batch, phase5_completion, summarize_phase5, phase5_fixture_catalog

export scheduling_control
export run_benchmarks, summarize_benchmarks
export benchmark_configuration, load_benchmark_config, estimate_benchmark, benchmark_plan, warm_benchmarks, bellman_certificate
export RSPPlanner, rsp_assignments, pilot_configuration, plan_rsp, measure_sequential
export joint_srppa, marginal_srppa, motion_bonuses, legacy_value, evaluate_solution
export SubmodularMaximization, MDMA
export load_scenario, cluster_scenario, initial_states, smoke_configuration, plan_baseline
export GreedyPlanner, MultipleRoundsGreedyPlanner, MyopicPlanner, FormationPlanner, AssignmentPlanner

end
