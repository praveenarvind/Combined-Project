# Deliberately no-op blocks isolate dispatch/partition/barrier cost. These are NOT
# filming plans, VI calls, or SRPPA measurements; the original scheduler is reused.
struct SchedulingControl <: SubmodularMaximization.PartitionProblem{Tuple{Int,Vector{Int}}}
    partition_matroid::Vector{Int}
end
SubmodularMaximization.solve_block(::SchedulingControl,id::Integer,prior::Vector{Tuple{Int,Vector{Int}}}) = (Int(id),Int[])
SubmodularMaximization.objective(::SchedulingControl,selection) = 0.0

function scheduling_control(;num_robots=5,seed=11,repeats=50)
    result=Any[]
    problem=SchedulingControl(collect(1:num_robots))
    for rounds in (2,4,8), threaded in (Threads.nthreads()>1 ? (false,true) : (false,))
        labels=rsp_assignments(RSPPlanner(rounds;seed=seed),num_robots)
        dag=SubmodularMaximization.PartitionSolver(labels)
        run=() -> _measure_schedule(p -> SubmodularMaximization.solve_dag(dag,p;threaded=threaded),problem)
        run();run() # Fixture compilation is not measured.
        times=Float64[]
        for _ in 1:repeats
            push!(times,run().planning_seconds)
        end
        push!(result,(kind="no_op_scheduler_control",configured_rounds=rounds,occupied_rounds=length(unique(labels)),
            assignments=labels,threaded=threaded,available_threads=Threads.nthreads(),repeats=repeats,
            mean_seconds=mean(times),sd_seconds=std(times),min_seconds=minimum(times),max_seconds=maximum(times),
            note="Includes tracing overhead; no VI/model computation. Not a physical synchronization wait measurement."))
    end
    result
end
