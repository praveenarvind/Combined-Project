"""Select frozen jobs and their transitive correctness/reference prerequisites; no planning."""
function select_phase5_jobs(inventory;scenario=nothing,planner=nothing,rounds=nothing,mode=nothing,
        seed=nothing,assignments=nothing,job_id=nothing,dependencies=true)
    scenarios=[s["name"] for s in inventory["catalog"]["scenarios"]]
    scenario===nothing || scenario in scenarios || throw(ArgumentError("unknown scenario: $scenario"))
    planner===nothing || planner in ("baselines","greedy","myopic","multiround","assignment","formation_idealized","rsp") || throw(ArgumentError("unknown planner: $planner"))
    rounds===nothing || 1<=rounds<=5 || throw(ArgumentError("rounds must be 1 through 5"))
    mode===nothing || mode in ("serial","threaded") || throw(ArgumentError("mode must be serial or threaded"))
    chosen=filter(inventory["jobs"]) do j
        (scenario===nothing || j["scenario"]==scenario) &&
        (planner===nothing || (planner=="baselines" ? j["configured_rounds"]===nothing : planner=="rsp" ? j["configured_rounds"]!==nothing : j["planner"]==planner)) &&
        (rounds===nothing || j["configured_rounds"]==rounds) &&
        (mode===nothing || j["mode"]==mode) &&
        (seed===nothing || j["partition_seed"]==seed) &&
        (assignments===nothing || j["assignments"]==assignments) &&
        (job_id===nothing || j["id"]==job_id)
    end
    if (seed!==nothing || assignments!==nothing) && any(j -> j["sampling_method"]=="supplemental_not_final_matrix",chosen)
        chosen=filter(j -> j["sampling_method"]=="supplemental_not_final_matrix",chosen)
    end
    isempty(chosen) && throw(ArgumentError("no matching frozen jobs; generate an inventory with --assignment/--seed for supplemental configurations"))
    ids=Set(j["id"] for j in chosen);requested=copy(ids)
    if dependencies
        byid=Dict(j["id"]=>j for j in inventory["jobs"]);queue=collect(ids)
        while !isempty(queue)
            for id in _phase5_dependencies(byid[pop!(queue)])
                haskey(byid,id) || error("missing prerequisite $id")
                if !(id in ids);push!(ids,id);push!(queue,id);end
            end
        end
    end
    (jobs=filter(j -> j["id"] in ids,inventory["jobs"]),requested_ids=requested)
end

function _phase5_costs(output,inventory)
    path=joinpath(output,"resources.json")
    isfile(path) || return Dict{String,Any}()
    report=_phase5_read(path)
    report["inventory_file_sha256"]==_phase5_file_sha(joinpath(output,"inventory.json")) || error("resource estimates refer to a different inventory")
    Dict(j["id"]=>j for j in get(report,"jobs",Any[]))
end

"""Cost policy overlay; immutable job definitions and completed checkpoints remain untouched.
Estimates include primary planning, certification replay/checks, legacy evaluation and overhead.
Nothing in this function loads an original planning model or executes a planner.
"""
function phase5_preflight(output;selection=nothing,experiment_limit=300.0,write_policy=false)
    experiment_limit>0 || throw(ArgumentError("positive experiment limit required"))
    inventory=_phase5_validate_inventory(_phase5_read(joinpath(output,"inventory.json")))
    chosen=selection===nothing ? (jobs=inventory["jobs"],requested_ids=Set(j["id"] for j in inventory["jobs"])) : selection
    costs=_phase5_costs(output,inventory);rows=Any[]
    fixture=inventory["purpose"]=="ci_functional_validation"
    for job in chosen.jobs
        scene=only(filter(s -> s["name"]==job["scenario"],inventory["catalog"]["scenarios"]))
        record=_phase5_record(output,job)
        cost=get(costs,job["id"],nothing)
        estimate=cost===nothing ? nothing : cost["estimated_total_seconds"]
        reason=nothing
        status=job["status"]
        if record!==nothing && record["status"]=="successful"
            status="successful"
        elseif !fixture && (estimate===nothing || estimate>experiment_limit)
            status="skipped_resource_limit"
            reason=estimate===nothing ? "No validated total-cost estimate available; planning not started." : "Estimated total $(round(estimate;digits=2)) s exceeds $(experiment_limit) s per-experiment limit; includes validation replay."
        elseif !_phase5_fidelity(inventory,scene)
            status="blocked";reason=job["blocked_reason"]
        elseif record!==nothing
            status=record["status"]
        else
            status="pending"
        end
        push!(rows,Dict("id"=>job["id"],"scenario"=>job["scenario"],"status"=>status,
            "requested"=>job["id"] in chosen.requested_ids,"estimated_total_seconds"=>estimate,
            "estimate_basis"=>fixture ? "synthetic_fixture_only" : "resource_extrapolation_not_measured_runtime",
            "reason"=>reason,"fidelity_verified"=>_phase5_fidelity(inventory,scene),
            "configured_rounds"=>job["configured_rounds"],"partition_seed"=>job["partition_seed"],
            "assignments"=>job["assignments"],"round_groups"=>job["round_groups"]))
    end
    result=Dict("inventory_sha256"=>_phase5_digest(inventory),"experiment_limit_seconds"=>isfinite(experiment_limit) ? experiment_limit : "unlimited_explicit_local_execution",
        "selected_executions"=>length(rows),"requested_executions"=>length(chosen.requested_ids),
        "estimated_total_seconds"=>any(r -> r["estimated_total_seconds"]===nothing,rows) ? nothing : sum(r["estimated_total_seconds"] for r in rows),
        "counts"=>Dict(s=>count(r -> r["status"]==s,rows) for s in ("successful","pending","failed","running","blocked","skipped_resource_limit")),"jobs"=>rows)
    if write_policy
        # Merge selections so an assessment of one scene does not erase other assessments.
        path=joinpath(output,"resource_policy.json");previous=isfile(path) ? _phase5_read(path) : nothing
        merged=Dict{String,Any}()
        if previous!==nothing
            previous["inventory_sha256"]==result["inventory_sha256"] || error("resource policy inventory mismatch")
            for row in previous["jobs"];merged[row["id"]]=row;end
        end
        for row in rows;merged[row["id"]]=row;end
        saved=copy(result);saved["jobs"]=[merged[k] for k in sort(collect(keys(merged)))];saved["counts"]=Dict(s=>count(r -> r["status"]==s,saved["jobs"]) for s in keys(result["counts"]))
        _phase5_write(path,saved)
        export_phase5_csv(output,inventory)
    end
    result
end

function _phase5_policy(output,inventory)
    path=joinpath(output,"resource_policy.json")
    isfile(path) || return Dict{String,Any}()
    value=_phase5_read(path)
    value["inventory_sha256"]==_phase5_digest(inventory) || error("resource policy inventory mismatch")
    Dict(row["id"]=>row for row in value["jobs"])
end
