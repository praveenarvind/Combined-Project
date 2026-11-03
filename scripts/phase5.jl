using DistributedFilming,JSON3
options=Dict{String,String}()
for arg in ARGS
    startswith(arg,"--") || error("options must begin with --")
    key,value=occursin('=',arg) ? split(arg,'=';limit=2) : (arg,"true")
    options[key]=value
end
all(k -> k in ("--inventory","--batch","--summarize","--output","--catalog","--max-jobs","--max-seconds","--retry-failed","--recover-stale-lock","--fixture"),keys(options)) || error("unknown option")
output=get(options,"--output",haskey(options,"--fixture") ? "results/phase5-ci" : "results/phase5-final")
if haskey(options,"--inventory")
    catalog=haskey(options,"--fixture") ? phase5_fixture_catalog() : DistributedFilming._phase5_read(get(options,"--catalog","docs/phase5/scenario_catalog.json"))
    inventory=initialize_phase5(output,catalog;workers=Threads.nthreads(),purpose=haskey(options,"--fixture") ? "ci_functional_validation" : "published_final")
    println("INVENTORY_OK executions=$(inventory["expected_executions"]) quality_configurations=$(inventory["expected_quality_configurations"]) VI_calls=$(inventory["expected_vi_calls"])")
end
if haskey(options,"--batch")
    result=run_phase5_batch(output;max_jobs=parse(Int,get(options,"--max-jobs","1")),max_seconds=parse(Float64,get(options,"--max-seconds","600")),
        retry_failed=haskey(options,"--retry-failed"),recover_stale=haskey(options,"--recover-stale-lock"))
    JSON3.pretty(stdout,result);println()
    result.completion["counts"]["failed"]>0 && exit(1)
    result.attempted==0 && !result.completion["complete"] && exit(2)
end
if haskey(options,"--summarize")
    result=summarize_phase5(output);println("SUMMARY_OK complete=$(result["completion"]["complete"]) scenario_K_rows=$(length(result["summaries"]))")
end
