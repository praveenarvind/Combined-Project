using Test,JSON3,DistributedFilming
const D=DistributedFilming
output=isempty(ARGS) ? "results/phase5-ci" : only(ARGS)
inv=D._phase5_validate_inventory(D._phase5_read(joinpath(output,"inventory.json")))
@testset "Saved synthetic Phase 5 CLI results (not paper experiments)" begin
    @test inv["purpose"]=="ci_functional_validation"
    @test inv["expected_executions"]==73 && inv["expected_quality_configurations"]==39
    @test phase5_completion(output)["complete"]
    cfg,states=phase5_configuration(only(inv["catalog"]["scenarios"]))
    records=[D._phase5_record(output,j) for j in inv["jobs"]]
    reference=only(filter(r -> r["definition"]["planner"]=="greedy",records))["result"]["scores"]["joint_srppa"]
    @test sum(r["result"]["metrics"]["vi_calls"] for r in records)==146
    for r in records
        job=r["definition"];z=r["result"]
        @test r["status"]=="successful" && r["completed_at_utc"]!==nothing
        @test r["warmup_enabled"]
        @test r["scenario_info"]["initial_states"]==only(inv["catalog"]["scenarios"])["initial_states"]
        @test r["normalized_srppa"] ≈ z["scores"]["joint_srppa"]/reference
        @test z["metrics"]["vi_calls"]==job["expected_vi_calls"]
        @test z["validation"]["max_marginal_error"]<=1e-10
        @test z["metrics"]["allocated_bytes"]>=0 && z["metrics"]["gc_seconds"]>=0
        elements=D._phase5_states(z["solution"]["elements"])
        @test joint_srppa(cfg,elements)==z["scores"]["joint_srppa"]
        if job["configured_rounds"]!==nothing
            @test 1<=job["configured_rounds"]<=5
            @test length(job["round_groups"])==job["configured_rounds"]
            @test sort(vcat(job["round_groups"]...))==[1,2]
            @test job["occupied_rounds"]==length(unique(job["assignments"]))
            job["configured_rounds"]==1 && @test r["correctness"]["rsp1_myopic_equal"]
            job["mode"]=="threaded" && @test r["correctness"]["serial_threaded_equal"] && r["serial_speedup"]>0
        else
            @test z["validation"]["movement_checked"]==(job["planner"]!="formation_idealized")
        end
    end
    summary=D._phase5_read(joinpath(output,"summary.json"))
    @test [s["quality_observations"] for s in summary["summaries"]]==[1,4,9,10,10]
    @test all(s -> s["srppa"]["confidence_interval"]===nothing,summary["summaries"])
end
