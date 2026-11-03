using DistributedFilming,JSON3
const D=DistributedFilming
options=Dict{String,String}()
for arg in ARGS
    startswith(arg,"--") || error("options must begin with --")
    key,value=occursin('=',arg) ? split(arg,'=';limit=2) : (arg,"true")
    haskey(options,key) && error("duplicate option $key")
    options[key]=value
end
allowed=("--inventory","--batch","--summarize","--progress","--dry-run","--assess-resources","--help",
    "--output","--catalog","--max-jobs","--max-seconds","--retry-failed","--only-failed","--recover-stale-lock","--fixture",
    "--scenario","--planner","--rounds","--mode","--seed","--assignment","--job-id","--experiment-limit","--run-local")
all(k -> k in allowed,keys(options)) || error("unknown option; use --help")
if haskey(options,"--help")
    println("""
Phase 5: original inputs are never reduced. No planning in --inventory, --dry-run, --progress or --assess-resources.
Actions: --inventory | --dry-run | --batch | --progress | --summarize
Selection: --scenario=NAME --planner=baselines|greedy|myopic|multiround|assignment|formation_idealized|rsp
           --rounds=1..5 --mode=serial|threaded --seed=INT --assignment=1,2,1,2 --job-id=ID
Selection automatically includes required greedy/myopic/RSP-1/serial prerequisites.
Create supplemental seed/assignment configurations with --inventory and --scenario/--rounds.
Execution: --max-jobs=1 --max-seconds=300 --retry-failed | --only-failed --recover-stale-lock
Resources: --experiment-limit=300 (estimated total/job, including certification); --assess-resources records skips.
Original execution requires --run-local plus paper and calibrated resource gates.
On your PC only, --run-local --experiment-limit=unlimited explicitly permits long experiments.
--max-seconds is checked between jobs and cannot interrupt a running VI call.
Files: --output=DIR --catalog=JSON. Synthetic validation: --fixture.
See docs/phase5/RUN_EXPERIMENTS_ON_PC.md.
""")
    exit()
end
haskey(options,"--seed") && haskey(options,"--assignment") && error("choose --seed or --assignment")
output=get(options,"--output",haskey(options,"--fixture") ? "results/phase5-ci" : "results/phase5-final")
rounds=haskey(options,"--rounds") ? parse(Int,options["--rounds"]) : nothing
seed=haskey(options,"--seed") ? parse(Int,options["--seed"]) : nothing
labels=haskey(options,"--assignment") ? parse.(Int,split(options["--assignment"],',')) : nothing
limit=get(options,"--experiment-limit","300")
limit=limit=="unlimited" ? (haskey(options,"--run-local") ? Inf : error("unlimited requires explicit --run-local")) : parse(Float64,limit)
if haskey(options,"--inventory")
    catalog=haskey(options,"--fixture") ? phase5_fixture_catalog() : D._phase5_read(get(options,"--catalog","docs/phase5/scenario_catalog.json"))
    extras=Any[]
    if seed!==nothing || labels!==nothing
        haskey(options,"--scenario") && rounds!==nothing || error("supplemental inventory needs --scenario and --rounds")
        push!(extras,Dict("scenario"=>options["--scenario"],"rounds"=>rounds,"seed"=>seed,"assignments"=>labels))
    end
    inventory=initialize_phase5(output,catalog;workers=Threads.nthreads(),purpose=haskey(options,"--fixture") ? "ci_functional_validation" : "published_final",supplemental=extras)
    println("INVENTORY_OK executions=$(inventory["expected_executions"]) quality_configurations=$(inventory["expected_quality_configurations"]) VI_calls=$(inventory["expected_vi_calls"])")
end
if any(haskey(options,k) for k in ("--dry-run","--assess-resources","--batch"))
    inv=D._phase5_read(joinpath(output,"inventory.json"))
    selection=select_phase5_jobs(inv;scenario=get(options,"--scenario",nothing),planner=get(options,"--planner",nothing),
        rounds=rounds,mode=get(options,"--mode",nothing),seed=seed,assignments=labels,job_id=get(options,"--job-id",nothing))
    if haskey(options,"--dry-run") || haskey(options,"--assess-resources")
        result=phase5_preflight(output;selection=selection,experiment_limit=limit,write_policy=haskey(options,"--assess-resources"))
        JSON3.pretty(stdout,result);println()
    end
    haskey(options,"--dry-run") && haskey(options,"--batch") && error("--dry-run cannot be combined with --batch")
    if haskey(options,"--batch")
        result=run_phase5_batch(output;selection=selection,max_jobs=parse(Int,get(options,"--max-jobs","1")),
            max_seconds=parse(Float64,get(options,"--max-seconds","300")),experiment_limit=limit,run_local=haskey(options,"--run-local"),
            retry_failed=haskey(options,"--retry-failed"),only_failed=haskey(options,"--only-failed"),recover_stale=haskey(options,"--recover-stale-lock"))
        JSON3.pretty(stdout,result);println()
        result.completion["counts"]["failed"]>0 && exit(1)
        result.attempted==0 && !result.completion["complete"] && exit(2)
    end
end
if haskey(options,"--progress")
    JSON3.pretty(stdout,phase5_completion(output));println()
end
if haskey(options,"--summarize")
    result=summarize_phase5(output);println("SUMMARY_OK complete=$(result["completion"]["complete"]) scenario_K_rows=$(length(result["summaries"]))")
end
