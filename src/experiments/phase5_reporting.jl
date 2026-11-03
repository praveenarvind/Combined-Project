function phase5_completion(output,inventory=_phase5_read(joinpath(output,"inventory.json")))
    counts=Dict(s=>0 for s in ("successful","failed","pending","blocked"));scenarios=Dict{String,Any}()
    for scene in inventory["catalog"]["scenarios"]
        local_counts=Dict(s=>0 for s in keys(counts))
        for job in filter(j -> j["scenario"]==scene["name"],inventory["jobs"])
            record=_phase5_record(output,job)
            status=record===nothing ? job["status"] : record["status"]=="running" ? "pending" : record["status"]
            local_counts[status]+=1;counts[status]+=1
        end
        scenarios[scene["name"]]=Dict("counts"=>local_counts,"complete"=>local_counts["successful"]==sum(values(local_counts)))
    end
    Dict("counts"=>counts,"scenarios"=>scenarios,"complete"=>counts["successful"]==length(inventory["jobs"]))
end

function export_phase5_csv(output,inventory=_phase5_read(joinpath(output,"inventory.json")))
    fields=["id","quality_id","scenario","planner","mode","workers","status","error","retry_count","completed_at_utc",
        "robots","actors","horizon","input_revision","input_sha256","initial_states","grid","camera","configured_rounds","occupied_rounds",
        "assignments","round_groups","all_rounds_occupied","partition_method","partition_seed","sampling_method","expected_vi_calls",
        "joint_srppa","normalized_srppa","legacy_value","heading_bonus","stationary_bonus","redundancy_per_robot",
        "planning_seconds","solver_seconds","legacy_evaluation_seconds","vi_calls","allocated_bytes","gc_seconds","process_cpu_seconds",
        "logical_dependency_depth","serial_speedup","execution_wall_seconds","trajectory_validation","correctness","code_revision","record_path","record_sha256"]
    mkpath(output);path=joinpath(output,"results.csv");temp=path*".tmp.$(getpid())"
    open(temp,"w") do io
        println(io,join(fields,","))
        for job in inventory["jobs"]
            scene=only(filter(s -> s["name"]==job["scenario"],inventory["catalog"]["scenarios"]))
            record=_phase5_record(output,job)
            row=copy(job)
            for key in ("robots","actors","horizon","input_revision","input_sha256","initial_states","grid","camera")
                row[key]=scene[key]
            end
            row["error"]=job["blocked_reason"]
            if record!==nothing
                for key in ("status","error","completed_at_utc","normalized_srppa","serial_speedup","execution_wall_seconds","correctness","record_sha256")
                    row[key]=get(record,key,nothing)
                end
                row["retry_count"]=max(0,length(record["attempts"])-1)
                row["code_revision"]=record["code_context"]["source_commit"]
                row["record_path"]=relpath(_phase5_record_path(output,job["id"]),output)
                if record["status"]=="successful"
                    result=record["result"];merge!(row,result["scores"]);merge!(row,result["metrics"])
                    row["redundancy_per_robot"]=result["redundancy_per_robot"]
                    row["logical_dependency_depth"]=result["logical_dependency_depth"]
                    row["trajectory_validation"]=result["validation"]
                end
            end
            cell(k)=begin
                v=get(row,k,nothing)
                _csv_value(v isa AbstractDict || v isa AbstractVector ? JSON3.write(v) : v)
            end
            println(io,join(cell.(fields),","))
        end
    end
    Base.Filesystem.rename(temp,path)
    _phase5_write(joinpath(output,"completion.json"),phase5_completion(output,inventory))
    path
end

function _phase5_distribution(values;exhaustive=false)
    Dict("mean"=>mean(values),"median"=>median(values),"sd"=>length(values)>1 ? std(values;corrected=!exhaustive) : exhaustive ? 0.0 : nothing,
        "minimum"=>minimum(values),"maximum"=>maximum(values),"sd_definition"=>exhaustive ? "finite_population" : "sample",
        "confidence_interval"=>nothing)
end
function _phase5_summary_group(records,k;occupied=nothing)
    # One serial result per quality ID. Different assignments/seeds stay distinct even when scores match.
    exhaustive=k<=3
    scores=[r["result"]["scores"]["joint_srppa"] for r in records]
    extreme(value)=[Dict("id"=>r["definition"]["quality_id"],"assignments"=>r["definition"]["assignments"],
        "round_groups"=>r["definition"]["round_groups"],"seed"=>r["definition"]["partition_seed"]) for r in records if r["result"]["scores"]["joint_srppa"]==value]
    occupancy=Dict(string(o)=>count(r -> r["definition"]["occupied_rounds"]==o,records) for o in 1:k)
    Dict("configured_rounds"=>k,"occupied_rounds_filter"=>occupied,"sampling_method"=>records[1]["definition"]["sampling_method"],
        "quality_observations"=>length(records),"independent_initial_conditions"=>1,
        "srppa"=>_phase5_distribution(scores;exhaustive=exhaustive),
        "normalized_srppa"=>_phase5_distribution([r["normalized_srppa"] for r in records];exhaustive=exhaustive),
        "serial_planning_seconds"=>_phase5_distribution([r["result"]["metrics"]["planning_seconds"] for r in records];exhaustive=exhaustive),
        "mean_redundancy_per_robot"=>mean(r["result"]["redundancy_per_robot"] for r in records),
        "occupied_round_distribution"=>occupancy,"best_partitions"=>extreme(maximum(scores)),"worst_partitions"=>extreme(minimum(scores)),
        "unique_assignment_vectors"=>length(unique(JSON3.write(r["definition"]["assignments"]) for r in records)),
        "uncertainty_note"=>exhaustive ? "Complete finite ordered-assignment population conditional on one fixed scenario/start; no sampling CI." : "Ten fixed seeds conditional on one scenario/start; duplicate groupings retained; no cross-scene or starting-state CI.")
end

function summarize_phase5(output)
    inventory=_phase5_validate_inventory(_phase5_read(joinpath(output,"inventory.json")));completion=phase5_completion(output,inventory)
    summaries=Any[];occupied_summaries=Any[];baselines=Any[]
    for scene in inventory["catalog"]["scenarios"]
        name=scene["name"]
        completion["scenarios"][name]["complete"] || continue # Never report partial assignment sets as the final distribution.
        jobs=filter(j -> j["scenario"]==name,inventory["jobs"])
        records=[_phase5_record(output,j) for j in jobs]
        for k in 1:5
            serial=filter(r -> r["definition"]["configured_rounds"]==k && r["definition"]["mode"]=="serial",records)
            summary=_phase5_summary_group(serial,k);summary["scenario"]=name
            threaded=filter(r -> r["definition"]["configured_rounds"]==k && r["definition"]["mode"]=="threaded",records)
            summary["threaded_planning_seconds"]=_phase5_distribution([r["result"]["metrics"]["planning_seconds"] for r in threaded];exhaustive=k<=3)
            summary["paired_speedup"]=_phase5_distribution([r["serial_speedup"] for r in threaded];exhaustive=k<=3)
            push!(summaries,summary)
            for o in sort(unique(r["definition"]["occupied_rounds"] for r in serial))
                group=_phase5_summary_group(filter(r -> r["definition"]["occupied_rounds"]==o,serial),k;occupied=o)
                group["scenario"]=name;push!(occupied_summaries,group)
            end
        end
        for record in filter(r -> r["definition"]["configured_rounds"]===nothing,records)
            push!(baselines,Dict("scenario"=>name,"planner"=>record["definition"]["planner"],"id"=>record["id"],
                "normalized_srppa"=>record["normalized_srppa"],"result"=>record["result"]))
        end
    end
    report=Dict("schema_version"=>1,"purpose"=>inventory["purpose"],"completion"=>completion,"summaries"=>summaries,
        "by_occupied_rounds"=>occupied_summaries,"baselines"=>baselines,
        "limitations"=>"Quality uses one serial observation per configuration; threaded copies/timing repeats are not independent quality samples. Exhaustive and ten-seed distributions remain separate. Incomplete scenarios have no final aggregate estimates.")
    _phase5_write(joinpath(output,"summary.json"),report)
    fields=["scenario","configured_rounds","sampling_method","quality_observations","mean_srppa","median_srppa","sd_srppa","min_srppa","max_srppa","mean_normalized_srppa","median_normalized_srppa","mean_serial_seconds","median_serial_seconds","mean_threaded_seconds","median_threaded_seconds","mean_paired_speedup","mean_redundancy_per_robot"]
    open(joinpath(output,"summary.csv"),"w") do io
        println(io,join(fields,","))
        for s in summaries
            values=[s["scenario"],s["configured_rounds"],s["sampling_method"],s["quality_observations"],s["srppa"]["mean"],s["srppa"]["median"],s["srppa"]["sd"],s["srppa"]["minimum"],s["srppa"]["maximum"],s["normalized_srppa"]["mean"],s["normalized_srppa"]["median"],s["serial_planning_seconds"]["mean"],s["serial_planning_seconds"]["median"],s["threaded_planning_seconds"]["mean"],s["threaded_planning_seconds"]["median"],s["paired_speedup"]["mean"],s["mean_redundancy_per_robot"]]
            println(io,join(_csv_value.(values),","))
        end
    end
    report
end
