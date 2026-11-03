function _benchmark_source_context()
    root=normpath(joinpath(@__DIR__,"..",".."))
    function git(args)
        try readchomp(pipeline(`git -C $root $args`;stderr=devnull)) catch; nothing end
    end
    paths=sort([joinpath(d,f) for (d,_,fs) in walkdir(joinpath(root,"src")) for f in fs if endswith(f,".jl")])
    status=git(["status","--porcelain"])
    (source_commit=git(["rev-parse","HEAD"]),source_dirty=status===nothing ? nothing : !isempty(status),
     source_sha256=bytes2hex(sha256(join(read.(paths,String),"\n"))),julia_version=string(VERSION),
     julia_threads=Threads.nthreads(),blas_threads=BLAS.get_num_threads(),
     cpu_quota=isfile("/sys/fs/cgroup/cpu.max") ? strip(read("/sys/fs/cgroup/cpu.max",String)) : "unknown",
     cpu_allowed=Sys.islinux() ? only(filter(x -> startswith(x,"Cpus_allowed_list:"),split(read("/proc/self/status",String),'\n'))) : "unknown",
     memory_limit=isfile("/sys/fs/cgroup/memory.max") ? strip(read("/sys/fs/cgroup/memory.max",String)) : "unknown")
end

function _csv_value(x)
    x===nothing && return ""
    s=string(x)
    occursin(r"[,\"\n]",s) ? "\""*replace(s,"\""=>"\"\"")*"\"" : s
end

function write_benchmark_csv(path,records)
    fields=[:case_id,:replicate,:scenario,:robots,:horizon,:start_frame,:initial_seed,:partition_seed,:planner,:mode,
        :configured_rounds,:occupied_rounds,:logical_dependency_depth,:vi_calls,:joint_srppa,:normalized_srppa,
        :planning_seconds,:solver_seconds,:legacy_evaluation_seconds,:serial_speedup,:allocated_bytes,:gc_seconds,
        :process_cpu_seconds,:outside_block_wall_seconds,:completion_skew_wait_proxy_seconds,
        :redundancy_per_robot,:feasibility,:assignments,:legacy_value,:heading_bonus,:stationary_bonus]
    open(path,"w") do io
        println(io,join(fields,","))
        for r in records
            row=merge((case_id=r.case_id,replicate=r.replicate,scenario=r.scenario,robots=r.robots,horizon=r.horizon,start_frame=r.start_frame,
                initial_seed=r.initial_seed,partition_seed=r.partition_seed,planner=r.result.planner,mode=r.result.mode,
                configured_rounds=r.result.configured_rounds,occupied_rounds=r.result.occupied_rounds,
                logical_dependency_depth=r.result.logical_dependency_depth,normalized_srppa=r.normalized_srppa,
                serial_speedup=r.serial_speedup,redundancy_per_robot=r.result.redundancy_per_robot,
                feasibility=r.result.validation.feasibility,assignments=r.result.assignments===nothing ? nothing : join(r.result.assignments,";")),
                r.result.scores,r.result.metrics)
            println(io,join((_csv_value(getproperty(row,f)) for f in fields),","))
        end
    end
end

function _bootstrap_initial_mean(by_initial;seed=741)
    units=collect(values(by_initial))
    length(units)>=10 || return (lower=nothing,upper=nothing,method="not_estimated_fewer_than_10_independent_initial_seeds")
    rng=MersenneTwister(seed)
    draws=sort([mean(rand(rng,units,length(units))) for _ in 1:5000])
    (lower=quantile(draws,0.025),upper=quantile(draws,0.975),method="initial_seed_cluster_bootstrap_5000")
end

function summarize_benchmarks(records)
    groups=Dict{Tuple,Vector{Any}}()
    for r in records
        key=(r.scenario,r.start_frame,r.robots,r.horizon,r.result.planner)
        push!(get!(groups,key,Any[]),r)
    end
    summaries=Any[]
    for (key,group) in sort(collect(groups);by=first)
        timing=[r.result.metrics.planning_seconds for r in group]
        quality=[r.result.scores.joint_srppa for r in group]
        units=unique((r.initial_seed,r.partition_seed) for r in group)
        quality_by_condition=Dict(u=>mean([r.result.scores.joint_srppa for r in group if (r.initial_seed,r.partition_seed)==u]) for u in units)
        normalized_by_condition=Dict(u=>mean([r.normalized_srppa for r in group if (r.initial_seed,r.partition_seed)==u]) for u in units)
        by_initial=Dict(i=>mean([v for (u,v) in normalized_by_condition if u[1]==i]) for i in unique(r.initial_seed for r in group))
        ci=_bootstrap_initial_mean(by_initial)
        push!(summaries,(scenario=key[1],start_frame=key[2],robots=key[3],horizon=key[4],planner=key[5],n_runs=length(group),
            n_initial_seeds=length(by_initial),n_seed_conditions=length(units),mean_joint_srppa=mean(collect(values(quality_by_condition))),
            sd_joint_srppa=length(units)>1 ? std(collect(values(quality_by_condition))) : nothing,
            mean_normalized_srppa=mean(collect(values(by_initial))),normalized_ci=ci,
            mean_planning_seconds=mean(timing),sd_planning_seconds=length(timing)>1 ? std(timing) : nothing,
            mean_allocated_bytes=mean(r.result.metrics.allocated_bytes for r in group),
            mean_gc_seconds=mean(r.result.metrics.gc_seconds for r in group),
            mean_redundancy_per_robot=mean(r.result.redundancy_per_robot for r in group)))
    end
    summaries
end

function run_benchmarks(config,output;diagnostics=false,warmup=get(config,"purpose","benchmark")!="ci_functional_validation")
    BLAS.set_num_threads(1)
    mkpath(output)
    source=_benchmark_source_context()
    estimate=estimate_benchmark(config)
    estimate.measured_vi_calls<=get(config,"max_measured_vi_calls",100) || error("VI-call budget exceeded; explicit review/config change required")
    warmup && redirect_stdout(warm_benchmarks,devnull)
    records=Any[]
    replay=Dict{Tuple{String,String},Any}()
    for c in config["case"]
        cfg,input=benchmark_configuration(c["scenario"];num_robots=c["robots"],horizon=c["horizon"],start_frame=get(c,"start_frame",1))
        states=initial_states(cfg;seed=c["initial_seed"])
        for replicate in 1:c["repeats"]
            planners=circshift(c["planners"],mod(replicate-1,length(c["planners"])))
            fresh=Dict{String,Any}()
            for planner in planners
                get(c,"gc_policy","full_before_run")=="full_before_run" && GC.gc()
                result=redirect_stdout(devnull) do
                    benchmark_plan(cfg,states,planner;partition_seed=c["partition_seed"],initial_seed=c["initial_seed"])
                end
                key=(c["id"],planner)
                if haskey(replay,key)
                    result.solution==replay[key].solution && result.scores==replay[key].scores || error("deterministic replay failed")
                else
                    replay[key]=(solution=result.solution,scores=result.scores)
                end
                fresh[planner]=result
                println("BENCH case=$(c["id"]) repeat=$replicate planner=$planner wall=$(result.metrics.planning_seconds) gc=$(result.metrics.gc_seconds) bytes=$(result.metrics.allocated_bytes)")
                flush(stdout)
            end
            reference=fresh["greedy"].scores.joint_srppa
            reference>0 || error("cannot normalize zero greedy score")
            for planner in c["planners"]
                result=fresh[planner]
                serial_name=planner=="myopic_threaded" ? "myopic" : replace(planner,"_threaded"=>"_serial")
                paired=endswith(planner,"_threaded") && haskey(fresh,serial_name)
                if paired
                    result.solution.elements==fresh[serial_name].solution.elements || error("serial/threaded trajectory mismatch")
                    result.scores==fresh[serial_name].scores || error("serial/threaded score mismatch")
                end
                speedup=paired ? fresh[serial_name].metrics.planning_seconds/result.metrics.planning_seconds : nothing
                push!(records,(case_id=c["id"],replicate=replicate,scenario=c["scenario"],robots=c["robots"],horizon=c["horizon"],
                    start_frame=get(c,"start_frame",1),initial_seed=c["initial_seed"],partition_seed=c["partition_seed"],input=input,initial_states=states,
                    gc_policy=get(c,"gc_policy","full_before_run"),normalized_srppa=result.scores.joint_srppa/reference,
                    serial_speedup=speedup,result=result))
            end
        end
    end
    profiles=Any[]
    if diagnostics
        c=first(config["case"])
        cfg,input=benchmark_configuration(c["scenario"];num_robots=c["robots"],horizon=c["horizon"],start_frame=get(c,"start_frame",1))
        states=initial_states(cfg;seed=c["initial_seed"])
        for planner in filter(x -> startswith(x,"rsp"),c["planners"])
            GC.gc();Profile.clear();Profile.init(n=5_000_000,delay=0.005)
            result=redirect_stdout(devnull) do
                benchmark_plan(cfg,states,planner;partition_seed=c["partition_seed"],detailed=true,sampling=true)
            end
            prior=first(filter(r -> r.case_id==c["id"] && r.result.planner==planner,records)).result
            result.solution.elements==prior.solution.elements || error("profiling changed trajectories")
            result.scores==prior.scores || error("profiling changed quality")
            open(joinpath(output,"profile-$(planner).txt"),"w") do io
                Profile.print(io;C=true,maxdepth=18,groupby=:thread,sortedby=:count)
            end
            open(joinpath(output,"profile-$(planner)-flat.txt"),"w") do io
                Profile.print(io;format=:flat,C=true,groupby=:thread,sortedby=:count)
            end
            push!(profiles,(case_id=c["id"],planner=planner,input=input,result=result))
            println("PROFILE planner=$planner VI certificates=$(length(result.convergence))")
            flush(stdout)
        end
    end
    summaries=summarize_benchmarks(records)
    write_benchmark_csv(joinpath(output,"results.csv"),records)
    open(joinpath(output,"run.json"),"w") do io
        JSON3.pretty(io,(schema_version=1,context=merge(source,(process_peak_rss_bytes=Sys.maxrss(),warmup_enabled=warmup,purpose=get(config,"purpose","benchmark"),)),config=config,estimate=estimate,records=records,
            diagnostic_passes=profiles,summaries=summaries,
            limitations="Stage allocations/GC attributable only in serial diagnostic passes; threaded windows overlap. Stage and worker wall times cannot be added into parallel wall time. Completion skew is a wait proxy; outside-block residual is not pure scheduler cost."))
    end
    println("BENCHMARK_OK records=$(length(records)) output=$(abspath(output))")
    (records=records,profiles=profiles,summaries=summaries)
end
