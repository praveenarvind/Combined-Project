# A longer-than-pilot horizon check; not a full scenario or timing study.
using DistributedFilming,JSON3
configs,input=benchmark_configuration("cluster";num_robots=1,horizon=8)
states=initial_states(configs;seed=2026)
result=redirect_stdout(devnull) do
    benchmark_plan(configs,states,"greedy";detailed=true)
end
@assert length(result.convergence)==1
@assert only(result.convergence).converged
out=joinpath(@__DIR__,"..","results","phase4-convergence")
mkpath(out)
open(joinpath(out,"run.json"),"w") do io
    JSON3.pretty(io,(context=DistributedFilming._benchmark_source_context(),input=input,initial_states=states,result=result))
end
println("CONVERGENCE_OK ",only(result.convergence))
