"""Headless filming foundation imported from the attributed upstream research code."""
module DistributedFilming

include("submodular/SubmodularMaximization.jl")
include("filming/MDMA.jl")
include("planners/baselines.jl")

export SubmodularMaximization, MDMA
export load_scenario, cluster_scenario, initial_states, smoke_configuration, plan_baseline
export GreedyPlanner, MultipleRoundsGreedyPlanner, MyopicPlanner, FormationPlanner, AssignmentPlanner

end
