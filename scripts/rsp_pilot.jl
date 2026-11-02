# Small integration pilot, not a full experimental matrix. All results are freshly solved.
using DistributedFilming
using JSON3
using SHA
using LinearAlgebra

all(a -> a in ("--ci","--two-robot"), ARGS) || error("Usage: rsp_pilot.jl [--ci | --two-robot]")
length(ARGS) <= 1 || error("Choose only one workload")
Threads.nthreads() >= 2 || error("Run with julia --threads=4")
BLAS.set_num_threads(1)
const M = DistributedFilming.MDMA
ci = "--ci" in ARGS
small = "--two-robot" in ARGS
configs = small ? smoke_configuration(load_scenario()) : pilot_configuration(;horizon=ci ? 2 : 3)
initial_seed = 2026
partition_seeds = ci || small ? [11] : [11,22,33]
states = initial_states(configs;seed=initial_seed)
out = joinpath(@__DIR__,"..","results",ci ? "rsp-ci" : small ? "rsp-two-robot" : "rsp-five-robot")
mkpath(out)
quiet(f) = redirect_stdout(f,devnull)

# Outside timing: movement validation and the Phase 2 full-path marginal checks.
function validate_result(configs,states,result)
    elements = result.solution.elements
    @assert sort(first.(elements)) == collect(1:configs.num_robots)
    @assert result.metadata.vi_calls == configs.num_robots
    max_difference_error = max_single_robot_error = 0.0
    for candidate in elements
        robot,path = candidate
        @assert first(path) == states[robot]
        prior = filter(e -> first(e) != robot,elements)
        coverage = M.compute_prior_coverage(configs,M.Trajectory[last(e) for e in prior])
        model = M.SingleRobotMultiTargetViewCoverageProblem(configs.grid,configs.sensor,
            configs.horizon,configs.target_trajectories,Int(configs.move_dist),coverage,first(path))
        @assert length(path) == configs.horizon
        @assert all(t -> path[t+1] in M.neighbors(model,path[t],Int(configs.move_dist)),1:length(path)-1)
        marginal = marginal_srppa(configs,prior,candidate)
        difference = joint_srppa(configs,elements) - joint_srppa(configs,prior)
        single_robot = sum(M.compute_single_agent_view_reward(model,s) for s in path)
        @assert isapprox(marginal,difference;atol=1e-11,rtol=1e-12)
        @assert isapprox(marginal,single_robot;atol=1e-11,rtol=1e-12)
        max_difference_error = max(max_difference_error,abs(marginal-difference))
        max_single_robot_error = max(max_single_robot_error,abs(marginal-single_robot))
    end
    (max_difference_error=max_difference_error,max_single_robot_error=max_single_robot_error)
end

# Warm unconditioned and conditioned paths, empty/nonempty neighbor maps and all
# earlier-partition prefix lengths 0:7 before measurement. A same-round group of
# four engages every worker; another robot then exercises the threaded dependency path.
warm = pilot_configuration(;horizon=2)
warm_states = initial_states(warm;seed=initial_seed)
println("Warming sequential, conditioned serial RSP and concurrent/conditioned threaded RSP; $(Threads.nthreads()) Julia threads, one BLAS thread")
flush(stdout)
quiet(() -> measure_sequential(warm,warm_states))
quiet(() -> plan_rsp(warm,warm_states,RSPPlanner(8);assignments=[1,2,4,6,8]))
quiet(() -> plan_rsp(warm,warm_states,RSPPlanner(8);assignments=[1,3,5,7,8]))
quiet(() -> plan_rsp(warm,warm_states,RSPPlanner(2;threaded=true);assignments=[1,1,1,1,2]))

records = Any[]
for (replicate,seed) in enumerate(partition_seeds)
    GC.gc() # Outside measured boundaries, identically for greedy and RSP.
    greedy = quiet(() -> measure_sequential(configs,states))
    @assert greedy.scores.joint_srppa > 0
    checks = validate_result(configs,states,greedy)
    push!(records,(replicate=replicate,mode="serial",initial_seed=initial_seed,
        normalized_srppa=1.0,scores=greedy.scores,metadata=greedy.metadata,validation=checks,
        solution=(value=greedy.solution.value,elements=greedy.solution.elements)))
    println("replicate=$replicate greedy reward=$(greedy.scores.joint_srppa) planning_s=$(greedy.metadata.planning_seconds)")
    flush(stdout)
    for rounds in (2,4,8)
        paired = Dict{Bool,Any}()
        # Alternate order to reduce a systematic serial-first timing bias.
        for threaded in (isodd(replicate) ? (false,true) : (true,false))
            GC.gc()
            result = quiet(() -> plan_rsp(configs,states,RSPPlanner(rounds;seed=seed,threaded=threaded)))
            paired[threaded] = result
            checks = validate_result(configs,states,result)
            push!(records,(replicate=replicate,mode=threaded ? "threaded" : "serial",initial_seed=initial_seed,
                normalized_srppa=result.scores.joint_srppa/greedy.scores.joint_srppa,
                scores=result.scores,metadata=result.metadata,validation=checks,
                solution=(value=result.solution.value,elements=result.solution.elements)))
            println("replicate=$replicate RSP-$rounds threaded=$threaded reward=$(result.scores.joint_srppa) occupied=$(result.metadata.occupied_rounds) planning_s=$(result.metadata.planning_seconds)")
            flush(stdout)
        end
        @assert paired[false].solution.elements == paired[true].solution.elements
        @assert paired[false].scores == paired[true].scores
        @assert paired[false].metadata.assignments == paired[true].metadata.assignments
    end
end

# Serialization and summaries occur after ALL measurements.
function write_csv(path,records)
    open(path,"w") do io
        println(io,"replicate,planner,mode,initial_seed,partition_seed,assignments,configured_rounds,occupied_rounds,vi_calls,joint_srppa,normalized_srppa,planning_seconds,solver_seconds,legacy_evaluation_seconds,worker_threads,legacy_value,heading_bonus,stationary_bonus")
        for r in records
            m,s = r.metadata,r.scores
            println(io,join((r.replicate,m.planner,r.mode,r.initial_seed,
                m.partition_seed === nothing ? "" : m.partition_seed,join(m.assignments,";"),
                m.configured_rounds,m.occupied_rounds,m.vi_calls,s.joint_srppa,r.normalized_srppa,
                m.planning_seconds,m.solver_seconds,m.legacy_evaluation_seconds,join(m.worker_threads,";"),
                s.legacy_value,s.heading_bonus,s.stationary_bonus),","))
        end
    end
end
write_csv(joinpath(out,"results.csv"),records)
open(joinpath(out,"summary.csv"),"w") do io
    println(io,"planner,configured_rounds,mode,n,mean_joint_srppa,sd_joint_srppa,min_joint_srppa,max_joint_srppa,mean_normalized_srppa,mean_planning_seconds,sd_planning_seconds,min_planning_seconds,max_planning_seconds")
    for planner in ("greedy","rsp"), rounds in (planner == "greedy" ? (configs.num_robots,) : (2,4,8)), mode in (planner == "greedy" ? ("serial",) : ("serial","threaded"))
        selected = filter(r -> r.metadata.planner == planner && r.metadata.configured_rounds == rounds && r.mode == mode,records)
        quality = [r.scores.joint_srppa for r in selected]
        timing = [r.metadata.planning_seconds for r in selected]
        avg(x) = sum(x)/length(x)
        sd(x) = length(x)>1 ? sqrt(sum((v-avg(x))^2 for v in x)/(length(x)-1)) : ""
        println(io,join((planner,rounds,mode,length(selected),avg(quality),sd(quality),minimum(quality),maximum(quality),
            avg([r.normalized_srppa for r in selected]),avg(timing),sd(timing),minimum(timing),maximum(timing)),","))
    end
end
# Git metadata may be unavailable in a Docker context; retain a source digest there.
function git_text(args)
    try
        readchomp(pipeline(`git -C $(joinpath(@__DIR__,"..")) $args`;stderr=devnull))
    catch
        nothing
    end
end
source_commit = git_text(["rev-parse","HEAD"])
status = git_text(["status","--porcelain"])
source_dirty = status === nothing ? nothing : !isempty(status)
source_files = sort(filter(p -> endswith(p,".jl"),
    [joinpath(dir,f) for (dir,_,files) in walkdir(joinpath(@__DIR__,"..","src")) for f in files]))
source_tree_sha256 = bytes2hex(sha256(join(read.(source_files,String),"\n")))
context = (workload=ci ? "ci_five_robot_two_frame" : small ? "supplementary_two_robot_four_frame" : "five_robot_three_frame_pilot",
    scenario="cluster",scenario_sha256=bytes2hex(sha256(read(cluster_scenario()))),
    source_commit=source_commit,source_dirty=source_dirty,source_tree_sha256=source_tree_sha256,julia_version=string(VERSION),
    cpu_quota= isfile("/sys/fs/cgroup/cpu.max") ? strip(read("/sys/fs/cgroup/cpu.max",String)) : "unknown",
    available_threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads(),
    initial_seed=initial_seed,partition_seeds=partition_seeds,initial_states=states,
    settings=first(records).metadata.settings,warmup_runs=4,warmup_vi_calls=20,
    timing="warmed wall clock including VI/cache/coverage/scheduler/instrumentation/GC; excludes final legacy evaluation, joint scoring, validation, assignment generation, installation, rendering and result serialization; verbose solver output redirected to devnull",
    statistics="sample SD across three partition seeds with fixed initial states; single observations in CI/supplementary workloads; no full-scale or distributed-network claims")
open(joinpath(out,"run.json"),"w") do io
    JSON3.pretty(io,(context=context,records=records))
end
println("PILOT_OK fresh_records=$(length(records)) output=$(abspath(out))")
