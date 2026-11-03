_phase5_record_path(output,id)=joinpath(output,"records","$id.json")
function _phase5_save_record(path,record)
    pop!(record,"record_sha256",nothing)
    record["record_sha256"]=_phase5_digest(record)
    _phase5_write(path,record)
end
function _phase5_record(output,job)
    path=_phase5_record_path(output,job["id"])
    isfile(path) || return nothing
    record=_phase5_read(path);seal=pop!(record,"record_sha256",nothing)
    seal==_phase5_digest(record) || error("corrupt checkpoint for $(job["id"]); preserved for investigation")
    record["record_sha256"]=seal
    record["definition"]==job || error("checkpoint experiment definition changed")
    record
end
function _phase5_states(elements)
    [(Int(e[1]),[MDMA.MDPState(MDMA.UAVState(Float64(s["state"]["x"]),Float64(s["state"]["y"]),Symbol(s["state"]["heading"])),Int(s["depth"]),Int(s["horizon"])) for s in e[2]]) for e in elements]
end
function _phase5_dependencies(job)
    name=job["scenario"];workers=job["workers"];result=String[]
    job["planner"]!="greedy" && push!(result,"$name-greedy-serial-t$workers")
    if job["configured_rounds"]!==nothing
        push!(result,"$name-myopic-serial-t$workers")
        if job["configured_rounds"]>1
            for mode in ("serial","threaded")
                push!(result,"$name-rsp1-enumerated-0001-$mode-t$workers")
            end
        end
        job["mode"]=="threaded" && push!(result,replace(job["id"],"-threaded-t"=>"-serial-t"))
    end
    unique(result)
end
function _phase5_ready(inventory,output,job)
    for id in _phase5_dependencies(job)
        other=only(filter(j -> j["id"]==id,inventory["jobs"]));record=_phase5_record(output,other)
        record!==nothing && record["status"]=="successful" || return false
    end
    true
end
function _phase5_fidelity(inventory,scene)
    inventory["purpose"]=="ci_functional_validation" && scene["fidelity_status"]=="ci_fixture" && return true
    paper=inventory["catalog"]["paper"]
    scene["fidelity_status"]=="verified" && get(paper,"independently_verified",false) &&
        get(paper,"access_status",nothing)=="locally_supplied_pdf_human_review" &&
        get(paper,"pdf_sha256",nothing)!==nothing && haskey(paper,"review") &&
        paper["review"]["paper_pdf_sha256"]==paper["pdf_sha256"]
end

function execute_phase5_job(inventory,output,job,scene)
    cfg,states=phase5_configuration(scene)
    labels=job["assignments"]
    if job["configured_rounds"]!==nothing
        k=job["configured_rounds"];1<=k<=5 || error("RSP partition limit exceeded")
        _rsp_labels(RSPPlanner(k),cfg.num_robots,labels)==labels || error("assignments changed")
        if job["partition_method"]=="random"
            rsp_assignments(RSPPlanner(k;seed=job["partition_seed"]),cfg.num_robots)==labels || error("seeded assignment replay mismatch")
        end
    end
    plan(detailed)=benchmark_plan(cfg,states,job["planner"];assignments=labels,
        partition_seed=something(job["partition_seed"],11),initial_seed=scene["formation_seed"],detailed=detailed)
    result=plan(false) # Primary timing retains no policies or per-stage diagnostic contexts.
    sort(first.(result.solution.elements))==collect(1:cfg.num_robots) || error("missing/duplicate planned robot")
    result.metrics.vi_calls==job["expected_planning_vi_calls"] || error("unexpected planning VI call count")
    primary=_phase5_plain(JSON3.read(JSON3.write(result)))
    checkpoint=_phase5_record(output,job)
    checkpoint["result"]=primary;checkpoint["primary_completed_at_utc"]=_phase5_now()
    checkpoint["planning_vi_calls"]=result.metrics.vi_calls
    checkpoint["validation_run"]=job["validation_execution_id"]===nothing ? nothing : Dict("id"=>job["validation_execution_id"],"status"=>"running","result"=>nothing)
    _phase5_save_record(_phase5_record_path(output,job["id"]),checkpoint)
    validation_run=nothing
    if job["validation_execution_id"]!==nothing
        GC.gc() # Outside the primary timing; certification replay cannot perturb that timing.
        validation=plan(true)
        validation.solution==result.solution && validation.scores==result.scores || error("primary/certification replay mismatch")
        validation.metrics.vi_calls==job["expected_validation_vi_calls"] || error("unexpected certification VI call count")
        length(validation.convergence)==job["expected_validation_vi_calls"] || error("missing VI convergence certificates")
        validation_run=Dict("id"=>job["validation_execution_id"],"status"=>"successful","completed_at_utc"=>_phase5_now(),
            "purpose"=>"certification_replay_excluded_from_primary_timing",
            "result"=>_phase5_plain(JSON3.read(JSON3.write(validation))))
    end
    checkpoint=_phase5_record(output,job);checkpoint["validation_run"]=validation_run
    checkpoint["validation_vi_calls"]=validation_run===nothing ? 0 : validation_run["result"]["metrics"]["vi_calls"]
    checkpoint["total_vi_calls"]=checkpoint["planning_vi_calls"]+checkpoint["validation_vi_calls"]
    _phase5_save_record(_phase5_record_path(output,job["id"]),checkpoint)
    if labels!==nothing
        result.assignments==labels || error("explicit assignment was not preserved")
        for trace in result.traces
            sort(trace.conditioned_on)==findall(x -> x<labels[trace.robot_id],labels) || error("incorrect partition conditioning")
        end
    end
    equality=Dict{String,Any}("rsp1_myopic_equal"=>nothing,"serial_threaded_equal"=>nothing,"validation_replay_equal"=>validation_run===nothing ? nothing : true)
    if job["configured_rounds"]==1
        other=only(filter(j -> j["scenario"]==job["scenario"] && j["planner"]=="myopic",inventory["jobs"]))
        baseline=_phase5_record(output,other)
        result.solution.elements==_phase5_states(baseline["result"]["solution"]["elements"]) || error("RSP-1/myopic full trajectory mismatch")
        result.scores.joint_srppa==baseline["result"]["scores"]["joint_srppa"] || error("RSP-1/myopic joint SRPPA mismatch")
        all(t -> isempty(t.conditioned_on),result.traces) || error("RSP-1 cross-robot conditioning")
        equality["rsp1_myopic_equal"]=true
    end
    speedup=nothing
    if job["mode"]=="threaded"
        other=only(filter(j -> j["id"]==replace(job["id"],"-threaded-t"=>"-serial-t"),inventory["jobs"]))
        serial=_phase5_record(output,other)
        result.solution.elements==_phase5_states(serial["result"]["solution"]["elements"]) || error("serial/threaded full trajectory mismatch")
        result.scores.joint_srppa==serial["result"]["scores"]["joint_srppa"] || error("serial/threaded score mismatch")
        equality["serial_threaded_equal"]=true
        speedup=serial["result"]["metrics"]["planning_seconds"]/result.metrics.planning_seconds
    end
    reference=if job["planner"]=="greedy"
        result.scores.joint_srppa
    else
        other=only(filter(j -> j["scenario"]==job["scenario"] && j["planner"]=="greedy",inventory["jobs"]))
        _phase5_record(output,other)["result"]["scores"]["joint_srppa"]
    end
    reference>0 || error("zero greedy reference cannot be normalized")
    (result=primary,normalized_srppa=result.scores.joint_srppa/reference,
        serial_speedup=speedup,correctness=equality,validation_run=validation_run,
        planning_vi_calls=result.metrics.vi_calls,validation_vi_calls=validation_run===nothing ? 0 : validation_run["result"]["metrics"]["vi_calls"])
end

# A synthetic fixture warms code paths only; it is never a substitute for a full original scene.
function _phase5_warm()
    scene=only(phase5_fixture_catalog()["scenarios"]);cfg,states=phase5_configuration(scene)
    for planner in ("greedy","myopic","multiround","assignment","formation_idealized","rsp1_serial","rsp2_serial","rsp2_threaded")
        for detailed in (false,true)
            benchmark_plan(cfg,states,planner;detailed=detailed,assignments=startswith(planner,"rsp1") ? [1,1] : startswith(planner,"rsp2") ? [1,2] : nothing)
        end
    end
    for detailed in (false,true)
        benchmark_plan(cfg,states,"rsp2_threaded";detailed=detailed,assignments=[1,1])
    end
    nothing
end

_phase5_boot()=isfile("/proc/sys/kernel/random/boot_id") ? strip(read("/proc/sys/kernel/random/boot_id",String)) : "unknown"
_phase5_process_start(pid)=isfile("/proc/$pid/stat") ? split(read("/proc/$pid/stat",String))[22] : nothing

function _phase5_resource_gate(output,inventory,context)
    reportpath=joinpath(output,"resources.json");calpath=joinpath(output,"resource_calibration.json")
    isfile(reportpath) && isfile(calpath) || error("a validated calibration and resource report are required before final experiments")
    report=_phase5_read(reportpath);cal=_phase5_read(calpath)
    report["inventory_file_sha256"]==_phase5_file_sha(joinpath(output,"inventory.json")) || error("resource report inventory mismatch")
    report["calibration_file_sha256"]==_phase5_file_sha(calpath) || error("calibration checksum mismatch")
    cal["status"]=="successful" && cal["completed_vi_calls"]==1 && cal["full_team_solution"]===false || error("calibration did not complete validation")
    cal["context"]["source_sha256"]==context.source_sha256 || error("calibration implementation differs")
    cal["manifest_sha256"]==_phase5_file_sha(joinpath(PHASE5_ROOT,"Manifest.toml")) || error("calibration dependencies differ")
    for key in ("julia_version","julia_threads","blas_threads","cpu_quota","cpu_allowed","memory_limit")
        cal["context"][key]==getproperty(context,Symbol(key)) || error("calibration environment differs: $key")
    end
    cal["input_sha256"]==only(filter(s -> s["name"]==cal["scenario"],inventory["catalog"]["scenarios"]))["input_sha256"] || error("calibration input differs")
    report["totals"]["vi_calls"]==inventory["expected_vi_calls"] && report["totals"]["executions"]==inventory["expected_executions"] || error("resource inventory counts differ")
    true
end
function _phase5_lock(output;recover_stale=false)
    lock=joinpath(output,".batch.lock");mkpath(output)
    if isdir(lock)
        recover_stale || error("batch lock exists; use recover_stale only after verifying the earlier process ended")
        ownerpath=joinpath(lock,"owner.json");isfile(ownerpath) || error("lock owner unavailable; refusing automatic removal")
        owner=_phase5_read(ownerpath)
        owner["boot"]==_phase5_boot() || error("foreign/rebooted lock owner cannot be verified; refusing automatic removal")
        live=owner["start"]==_phase5_process_start(owner["pid"])
        live && error("another batch process is still running")
        rm(lock;recursive=true)
    end
    mkdir(lock) # Atomic; concurrent batch starters cannot both acquire this directory.
    _phase5_write(joinpath(lock,"owner.json"),Dict("pid"=>getpid(),"start"=>_phase5_process_start(getpid()),"boot"=>_phase5_boot()))
    lock
end

"""Run at most max_jobs, checkpoint each attempt, and stop starting jobs after max_seconds.
The wall budget is checked between jobs; it does not change/interrupt a VI algorithm.
"""
function run_phase5_batch(output;max_jobs=1,max_seconds=300.0,retry_failed=false,recover_stale=false,warmup=true,executor=execute_phase5_job,
        selection=nothing,experiment_limit=300.0,run_local=false,only_failed=false)
    max_jobs>0 && max_seconds>0 || throw(ArgumentError("positive batch limits required"))
    inventory=_phase5_validate_inventory(_phase5_read(joinpath(output,"inventory.json")))
    Threads.nthreads()==inventory["workers"] || error("worker count must match the frozen inventory")
    lock=_phase5_lock(output;recover_stale=recover_stale)
    count=0;started=time();warmed=false
    try
        selected=selection===nothing ? (jobs=inventory["jobs"],requested_ids=Set(j["id"] for j in inventory["jobs"])) : selection
        definitions=Dict(j["id"]=>j for j in inventory["jobs"])
        all(j -> get(definitions,j["id"],nothing)==j,selected.jobs) || error("selection differs from frozen inventory")
        preflight=phase5_preflight(output;selection=selected,experiment_limit=experiment_limit,write_policy=true)
        admitted=Set(r["id"] for r in preflight["jobs"] if !(r["status"] in ("blocked","skipped_resource_limit","successful")))
        isempty(admitted) && return (attempted=0,completion=phase5_completion(output,inventory))
        if inventory["purpose"]=="published_final"
            run_local || error("Original scenarios require explicit --run-local on your PC; use --dry-run here.")
        end
        if inventory["purpose"]=="published_final"
            warmup || error("compilation warmup is required for final performance measurements")
            executor===execute_phase5_job || error("final experiments require the validating executor")
        end
        BLAS.set_num_threads(1);context=_benchmark_source_context()
        inventory["purpose"]=="published_final" && context.source_dirty && error("commit the scientific implementation before running final experiments")
        inventory["purpose"]=="published_final" && _phase5_resource_gate(output,inventory,context)
        manifest=Dict("source_sha256"=>context.source_sha256,"julia_version"=>string(VERSION),"workers"=>Threads.nthreads(),
            "blas_threads"=>1,"manifest_sha256"=>_phase5_file_sha(joinpath(PHASE5_ROOT,"Manifest.toml")),"inventory_sha256"=>_phase5_digest(inventory))
        path=joinpath(output,"run_manifest.json")
        if isfile(path)
            _phase5_read(path)==manifest || error("resume environment/code/inventory mismatch; preserve completed work")
        else
            _phase5_write(path,manifest)
        end
        for job in selected.jobs
            job["id"] in admitted || continue
            count>=max_jobs && break
            time()-started>=max_seconds && break
            scene=only(filter(s -> s["name"]==job["scenario"],inventory["catalog"]["scenarios"]))
            _phase5_fidelity(inventory,scene) || continue
            record=_phase5_record(output,job)
            record!==nothing && record["status"]=="successful" && continue
            only_failed && !(record!==nothing && record["status"] in ("failed","running")) && continue
            if record!==nothing && record["status"]=="running"
                record["attempts"][end]["status"]="failed"
                record["attempts"][end]["error"]="interrupted before an atomic successful checkpoint"
                record["attempts"][end]["completed_at_utc"]=_phase5_now()
                record["result"]===nothing || (record["attempts"][end]["partial_primary_result"]=record["result"])
                get(record,"validation_run",nothing)===nothing || (record["attempts"][end]["partial_validation_run"]=record["validation_run"])
                record["status"]="pending"
                _phase5_save_record(_phase5_record_path(output,job["id"]),record)
            end
            record!==nothing && record["status"]=="failed" && !(retry_failed || only_failed) && continue
            _phase5_ready(inventory,output,job) || continue
            if warmup && !warmed
                redirect_stdout(_phase5_warm,devnull);warmed=true
            end
            time()-started>=max_seconds && break
            attempts=record===nothing ? Any[] : record["attempts"]
            push!(attempts,Dict{String,Any}("attempt"=>length(attempts)+1,"started_at_utc"=>_phase5_now(),"status"=>"running"))
            fields=["name","robots","actors","horizon","grid","camera","move_dist","vi","input_path","input_sha256","input_revision","initial_states","initial_state_method","initial_state_seed","formation_seed"]
            record=Dict{String,Any}("schema_version"=>1,"id"=>job["id"],"definition"=>job,"scenario_info"=>Dict(k=>scene[k] for k in fields),
                "code_context"=>_phase5_plain(JSON3.read(JSON3.write(context))),"warmup_enabled"=>warmup,"gc_policy"=>"full_before_run",
                "status"=>"running","attempts"=>attempts,"result"=>nothing,"error"=>nothing,"completed_at_utc"=>nothing)
            recordpath=_phase5_record_path(output,job["id"]);_phase5_save_record(recordpath,record)
            GC.gc();execution_start=time_ns()
            try
                value=redirect_stdout(devnull) do
                    executor(inventory,output,job,scene)
                end
                record=_phase5_record(output,job)
                record["execution_wall_seconds"]=(time_ns()-execution_start)/1e9
                record["result"]=value.result;record["normalized_srppa"]=value.normalized_srppa
                record["serial_speedup"]=value.serial_speedup;record["correctness"]=value.correctness
                record["validation_run"]=value.validation_run
                record["planning_vi_calls"]=value.planning_vi_calls;record["validation_vi_calls"]=value.validation_vi_calls
                record["total_vi_calls"]=value.planning_vi_calls+value.validation_vi_calls
                record["status"]="successful"
            catch err
                record=_phase5_record(output,job)
                record["status"]="failed";record["error"]=sprint(showerror,err,catch_backtrace())
                if get(record,"validation_run",nothing)!==nothing && record["validation_run"]["status"]=="running"
                    record["validation_run"]["status"]="failed"
                    record["validation_run"]["error"]=record["error"]
                end
            end
            attempts=record["attempts"]
            record["status"]=="failed" && record["result"]!==nothing && (attempts[end]["partial_primary_result"]=record["result"])
            record["completed_at_utc"]=_phase5_now()
            merge!(attempts[end],Dict("status"=>record["status"],"completed_at_utc"=>record["completed_at_utc"],"error"=>record["error"]))
            _phase5_save_record(recordpath,record);count+=1
            export_phase5_csv(output,inventory)
            println("PHASE5_JOB $(job["id"]) status=$(record["status"])");flush(stdout)
            record["status"]=="failed" && break # Investigate correctness failures before proceeding.
        end
        export_phase5_csv(output,inventory)
    finally
        rm(lock;recursive=true)
    end
    (attempted=count,completion=phase5_completion(output,inventory))
end
