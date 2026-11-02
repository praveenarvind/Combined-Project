using DistributedFilming,JSON3
out=joinpath(@__DIR__,"..","results","scheduler-control-t$(Threads.nthreads())")
mkpath(out)
control=scheduling_control(;num_robots=5,seed=11,repeats=100)
open(joinpath(out,"run.json"),"w") do io
    JSON3.pretty(io,(context=DistributedFilming._benchmark_source_context(),controls=control))
end
println("SCHEDULER_CONTROL_OK ",control)
