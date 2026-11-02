using TOML, SHA, Statistics, LinearAlgebra, Profile, JSON3

const BENCHMARK_PLANNERS = Set(["greedy","multiround","myopic","myopic_threaded","assignment","formation_idealized",
                               "rsp2_serial","rsp2_threaded","rsp4_serial","rsp4_threaded","rsp8_serial","rsp8_threaded"])

function benchmark_configuration(scenario::AbstractString; num_robots::Integer, horizon::Integer, start_frame::Integer=1)
    scenario in ("cluster","split_and_join","priority_speaker") || throw(ArgumentError("unsupported scenario"))
    path = normpath(joinpath(@__DIR__,"..","..","data","scenarios",scenario,"$(scenario)_data.json"))
    original = load_scenario(path;name=String(scenario))
    1 <= horizon <= original.horizon || throw(ArgumentError("horizon must be within original actor inputs"))
    1 <= start_frame <= original.horizon-horizon+1 || throw(ArgumentError("frame window exceeds original actor inputs"))
    num_robots > 0 || throw(ArgumentError("team size must be positive"))
    configs = MDMA.MultiDroneMultiActorConfigs(experiment_name=original.experiment_name,
        num_robots=num_robots,target_trajectories=original.target_trajectories[start_frame:start_frame+horizon-1,:],
        grid=MDMA.MDMA_Grid(original.grid.width,original.grid.height,horizon),sensor=original.sensor,
        horizon=horizon,move_dist=original.move_dist)
    provenance = (path=path,sha256=bytes2hex(sha256(read(path))),original_robots=original.num_robots,
                  original_horizon=original.horizon,original_frame_start=start_frame,original_frame_end=start_frame+horizon-1,camera_policy="unchanged upstream view-cone override")
    configs,provenance
end

function load_benchmark_config(path::AbstractString)
    config = TOML.parsefile(path)
    haskey(config,"case") && !isempty(config["case"]) || throw(ArgumentError("explicit [[case]] entries are required"))
    ids = String[]
    for c in config["case"]
        push!(ids,c["id"])
        c["repeats"] >= 1 || throw(ArgumentError("positive repeats required"))
        all(p -> p in BENCHMARK_PLANNERS,c["planners"]) || throw(ArgumentError("unknown planner"))
        "greedy" in c["planners"] || throw(ArgumentError("paired normalization requires greedy in every case"))
        length(unique(c["planners"])) == length(c["planners"]) || throw(ArgumentError("duplicate planners"))
        c["initial_seed"] >= 0 && c["partition_seed"] >= 0 || throw(ArgumentError("seeds must be nonnegative"))
        get(c,"gc_policy","full_before_run") in ("full_before_run","natural") || throw(ArgumentError("unknown GC policy"))
        benchmark_configuration(c["scenario"];num_robots=c["robots"],horizon=c["horizon"],start_frame=get(c,"start_frame",1))
    end
    length(unique(ids)) == length(ids) || throw(ArgumentError("case IDs must be unique"))
    config
end

function estimate_benchmark(config)
    calls = 0
    work_units = 0
    for c in config["case"]
        cfg,_ = benchmark_configuration(c["scenario"];num_robots=c["robots"],horizon=c["horizon"],start_frame=get(c,"start_frame",1))
        for p in c["planners"]
            n = p=="formation_idealized" ? 0 : p=="multiround" ? cfg.num_robots^2 : cfg.num_robots
            calls += n*c["repeats"]
            work_units += n*c["repeats"]*cfg.grid.width*cfg.grid.height*8*max(0,cfg.horizon-1)
        end
    end
    (measured_vi_calls=calls,nonterminal_state_visits_per_vi_sweep=work_units,
     note="No automatic matrix expansion. Warmups, diagnostic passes, legacy evaluation and validation add cost; calibrate before large runs.")
end

function _interval_union(intervals)
    isempty(intervals) && return 0.0
    sorted = sort(collect(intervals);by=first)
    start,finish = first(sorted)
    total = UInt64(0)
    for (a,b) in Iterators.drop(sorted,1)
        if a <= finish
            finish=max(finish,b)
        else
            total += finish-start; start,finish=a,b
        end
    end
    (total+finish-start)/1e9
end

function _schedule_metrics(measured,labels,threaded)
    blocks = vcat(measured.trace.history...)
    active = _interval_union([(b.started_ns,b.finished_ns) for b in blocks])
    outside = max(0.0,measured.planning_seconds-active)
    # This is completion-skew opportunity, not a claim of directly measured OS task parking.
    skew = 0.0
    if threaded && labels !== nothing
        for round in unique(labels)
            group = filter(b -> labels[b.robot_id]==round,blocks)
            round_end=maximum(b.finished_ns for b in group)
            for worker in unique(b.thread_id for b in group)
                last_end=maximum(b.finished_ns for b in group if b.thread_id==worker)
                skew += (round_end-last_end)/1e9
            end
        end
    end
    (active_block_wall_seconds=active,outside_block_wall_seconds=outside,
     completion_skew_wait_proxy_seconds=skew,
     block_wall_sum_seconds=sum((b.finished_ns-b.started_ns)/1e9 for b in blocks;init=0.0))
end

"""Independent all-state Bellman residual of an unchanged returned VI policy; run outside measured planning."""
function bellman_certificate(model,policy)
    residual=0.0
    count=0
    for state in MDMA.states(model)
        index=MDMA.stateindex(model,state)
        backup=0.0
        if !MDMA.isterminal(model,state)
            backup=-Inf
            for action in MDMA.actions(model,state)
                q=0.0
                for (next,probability) in MDMA.weighted_iterator(MDMA.transition(model,state,action))
                    probability==0 && continue
                    q += probability*(MDMA.reward(model,state,action,next)+MDMA.discount(model)*policy.util[MDMA.stateindex(model,next)])
                end
                backup=max(backup,q)
            end
        end
        residual=max(residual,abs(policy.util[index]-backup));count+=1
    end
    (bellman_residual=residual,converged=isfinite(residual) && residual<=1e-6,
     tolerance=1e-6,states_checked=count,method="independent_all_state_backup",iterations=nothing)
end

function _validate_benchmark_solution(configs,states,solution;idealized=false)
    max_error=0.0
    for candidate in solution.elements
        robot,path=candidate
        if !idealized
            first(path)==states[robot] || error("initial state changed")
        end
        prior=filter(e -> first(e)!=robot,solution.elements)
        coverage=MDMA.compute_prior_coverage(configs,MDMA.Trajectory[last(e) for e in prior])
        model=MDMA.SingleRobotMultiTargetViewCoverageProblem(configs.grid,configs.sensor,configs.horizon,
            configs.target_trajectories,Int(configs.move_dist),coverage,first(path))
        if !idealized
            all(i -> path[i+1] in MDMA.neighbors(model,path[i],Int(configs.move_dist)),1:length(path)-1) || error("invalid motion")
        end
        gain=marginal_srppa(configs,prior,candidate)
        independent=sum(MDMA.compute_single_agent_view_reward(model,s) for s in path)
        difference=joint_srppa(configs,solution)-joint_srppa(configs,prior)
        max_error=max(max_error,abs(gain-independent),abs(gain-difference))
    end
    max_error<=1e-10 || error("marginal inconsistency")
    (movement_checked=!idealized,initial_states_checked=!idealized,max_marginal_error=max_error,
     feasibility=idealized ? "idealized_reference_unconstrained" : "original_grid_and_motion")
end

function benchmark_plan(configs,states,planner::String;partition_seed=11,initial_seed=2026,detailed=false,sampling=false)
    planner in BENCHMARK_PLANNERS || throw(ArgumentError("unknown planner"))
    check_states(configs,states)
    threaded=endswith(planner,"_threaded")
    threaded && Threads.nthreads()<2 && throw(ArgumentError("threaded benchmark needs at least two Julia threads"))
    idealized=planner=="formation_idealized"
    labels=nothing
    configured=occupied=nothing
    depth=0
    if startswith(planner,"rsp")
        rounds=parse(Int,match(r"^rsp(\d+)_",planner).captures[1])
        labels=rsp_assignments(RSPPlanner(rounds;seed=partition_seed),configs.num_robots)
        dag=SubmodularMaximization.PartitionSolver(labels)
        solve=p -> SubmodularMaximization.solve_dag(dag,p;threaded=threaded)
        problem=MDMA.MultiRobotTargetCoverageProblem(copy(states),configs)
        configured=rounds;occupied=length(unique(labels));depth=occupied
    elseif planner=="assignment"
        solve=SubmodularMaximization.solve_sequential
        problem=MDMA.MultiRobotTargetAssignmentProblem(copy(states),configs)
        depth=1 # Assignment block ignores priors although its original execution wrapper is serial.
    elseif !idealized
        problem=MDMA.MultiRobotTargetCoverageProblem(copy(states),configs)
        if planner=="greedy"
            solve=SubmodularMaximization.solve_sequential
            configured=occupied=depth=configs.num_robots
        elseif planner=="multiround"
            solve=p -> SubmodularMaximization.solve_sequential_multiround(p,configs.num_robots)
            configured=occupied=depth=configs.num_robots^2
        else
            solve=p -> SubmodularMaximization.solve_myopic(p;threaded=threaded)
            configured=occupied=depth=1
            labels=ones(Int,configs.num_robots)
        end
    end
    if idealized
        cpu=_process_cpu_seconds()
        timed=@timed plan_baseline(configs,states,FormationPlanner();seed=initial_seed)
        solution=timed.value
        metrics=(planning_seconds=timed.time,solver_seconds=timed.time,legacy_evaluation_seconds=0.0,
            allocated_bytes=timed.bytes,gc_seconds=timed.gctime,process_cpu_seconds=_process_cpu_seconds()-cpu,
            vi_calls=0,active_block_wall_seconds=0.0,outside_block_wall_seconds=nothing,
            completion_skew_wait_proxy_seconds=nothing,block_wall_sum_seconds=0.0)
        traces=BlockObservation[];profiles=NamedTuple[];certificates=NamedTuple[]
    else
        measured=_measure_schedule(solve,problem;detailed=detailed,attributable_allocations=detailed && !threaded,sampling=sampling)
        solution=measured.solution
        schedule=_schedule_metrics(measured,labels,threaded)
        metrics=merge((planning_seconds=measured.planning_seconds,solver_seconds=measured.solver_seconds,
            legacy_evaluation_seconds=measured.legacy_evaluation_seconds,allocated_bytes=measured.planning_allocated_bytes,
            gc_seconds=measured.planning_gc_seconds,process_cpu_seconds=measured.planning_cpu_seconds,
            vi_calls=measured.trace.calls[]),schedule)
        traces=vcat(measured.trace.history...)
        profiles=NamedTuple[];certificates=NamedTuple[]
        for robot in eachindex(measured.trace.profiles), (call,context) in enumerate(measured.trace.profiles[robot])
            for event in context.events
                push!(profiles,merge((robot=robot,call=call),event))
            end
            for item in context.policies
                certificate=bellman_certificate(item.model,item.policy)
                certificate.converged || error("VI failed independent convergence check")
                push!(certificates,merge((robot=robot,call=call),certificate))
            end
        end
    end
    scores=evaluate_solution(configs,solution)
    validation=_validate_benchmark_solution(configs,states,solution;idealized=idealized)
    standalone=sum(joint_srppa(configs,[e]) for e in solution.elements;init=0.0)
    redundancy=(standalone-scores.joint_srppa)/configs.num_robots
    (planner=planner,mode=threaded ? "threaded" : "serial",scores=scores,metrics=metrics,
     redundancy_per_robot=redundancy,configured_rounds=configured,occupied_rounds=occupied,
     logical_dependency_depth=depth,assignments=labels,settings=_planner_settings(configs),validation=validation,
     detailed=detailed,stages=profiles,convergence=certificates,traces=traces,
     solution=(value=solution.value,elements=solution.elements))
end

function warm_benchmarks()
    cfg=pilot_configuration(;horizon=2);states=initial_states(cfg)
    # Warm exact original scheduler paths plus diagnostic modes and all baseline model types.
    measure_sequential(cfg,states)
    plan_rsp(cfg,states,RSPPlanner(8);assignments=[1,2,4,6,8])
    plan_rsp(cfg,states,RSPPlanner(8);assignments=[1,3,5,7,8])
    Threads.nthreads()>1 && plan_rsp(cfg,states,RSPPlanner(2;threaded=true);assignments=[1,1,1,1,2])
    small=smoke_configuration(load_scenario());small.horizon=2
    small.target_trajectories=small.target_trajectories[1:2,:]
    small.grid=MDMA.MDMA_Grid(small.grid.width,small.grid.height,2)
    initial=initial_states(small)
    for planner in ("multiround","myopic","assignment","formation_idealized","rsp2_serial","rsp2_threaded")
        endswith(planner,"_threaded") && Threads.nthreads()<2 && continue
        benchmark_plan(small,initial,planner;detailed=startswith(planner,"rsp"))
    end
    nothing
end
