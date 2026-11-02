module MDMA

using ..DistributedFilming: _profile_stage

include("MDMA_States.jl")
include("MDMA_Detection.jl")
include("MDMA_SharedTypes.jl")
include("MDMA_MultiAgent.jl")
include("MDMA_Single_Robot.jl")
include("MDMA_AssignmentPlanner.jl")
include("MDMA_FormationPlanner.jl")
include("MDMA_Interface.jl")

end
