# Opt-in, task-local diagnostics. No algorithm/model parameters are changed.
using Profile
const _PROFILE_KEY = :DistributedFilming_stage_profile
mutable struct StageProfile
    attributable_allocations::Bool
    events::Vector{NamedTuple}
    policies::Vector{Any}
end
StageProfile(allocations::Bool) = StageProfile(allocations,NamedTuple[],Any[])

@inline function _profile_stage(f, stage::Symbol, model=nothing)
    context = get(task_local_storage(), _PROFILE_KEY, nothing)
    context === nothing && return f()
    start = time_ns()
    if context.attributable_allocations
        timed = @timed f()
        value = timed.value
        push!(context.events,(stage=stage,started_ns=start,finished_ns=time_ns(),
            wall_seconds=timed.time,allocated_bytes=timed.bytes,gc_seconds=timed.gctime))
    else
        value = f()
        finish = time_ns()
        push!(context.events,(stage=stage,started_ns=start,finished_ns=finish,
            wall_seconds=(finish-start)/1e9,allocated_bytes=nothing,gc_seconds=nothing))
    end
    # Retained only in diagnostic passes for an independent post-solve Bellman check.
    stage == :value_iteration && model !== nothing && push!(context.policies,(model=model,policy=value))
    value
end

_with_profile(f, context::StageProfile) = task_local_storage(f,_PROFILE_KEY,context)

# POSIX process CPU time includes all Julia threads; never attributed to one worker.
_process_cpu_seconds() = Float64(ccall(:clock,Clong,())) / 1_000_000
