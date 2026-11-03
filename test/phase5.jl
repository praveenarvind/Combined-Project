using JSON3
const D5=DistributedFilming
@testset "Final ordered inventory and source recovery" begin
    for (n,k,total,occupied) in ((4,2,16,14),(4,3,81,36),(5,2,32,30),(5,3,243,150))
        assignments=ordered_rsp_assignments(n,k)
        @test length(assignments)==total
        @test length(unique(assignments))==total
        @test first(assignments)==ones(Int,n) && last(assignments)==fill(k,n)
        @test count(a -> length(unique(a))==k,assignments)==occupied
        independent=Set(Tuple(a) for a in Iterators.product((1:k for _ in 1:n)...))
        @test Set(Tuple.(assignments))==independent
    end
    @test_throws ArgumentError ordered_rsp_assignments(4,6)
    @test_throws ArgumentError ordered_rsp_assignments(0,2)
    @test_throws ArgumentError D5._rsp_labels(RSPPlanner(2),4,[1,2,1])
    @test_throws ArgumentError D5._rsp_labels(RSPPlanner(2),4,[1,2,1,3])
    @test_throws ArgumentError D5._rsp_labels(RSPPlanner(2),4,Any[true,2,1,2])
    @test D5._rsp_labels(RSPPlanner(2),4,[1,2,1,2])==[1,2,1,2]
    catalog=D5._phase5_read(joinpath(@__DIR__,"..","docs","phase5","scenario_catalog.json"))
    inv=phase5_inventory(catalog)
    @test inv["expected_executions"]==2996
    @test inv["expected_quality_configurations"]==1518
    @test inv["expected_vi_calls"]==27720
    @test inv["expected_planning_vi_calls"]==inv["expected_validation_vi_calls"]==13860
    @test inv["expected_validation_executions"]==2988
    @test length(unique(j["id"] for j in inv["jobs"]))==2996
    @test all(j -> j["configured_rounds"]===nothing || 1<=j["configured_rounds"]<=5,inv["jobs"])
    altered=deepcopy(inv);pop!(altered["jobs"])
    @test_throws ErrorException D5._phase5_validate_inventory(altered)
    for scene in catalog["scenarios"]
        raw=D5._phase5_read(joinpath(@__DIR__,"..",scene["input_path"]))
        @test bytes2hex(sha256(read(joinpath(@__DIR__,"..",scene["input_path"]))))==scene["input_sha256"]
        @test raw["num_robots"]==scene["robots"] && raw["num_frames"]==scene["horizon"]
        @test length(raw["actor_positions"])==scene["horizon"]
        @test length(scene["original_artifacts"])==5
        @test all(a -> a["initial_states"]==scene["initial_states"],filter(a -> a["planner"]!="formation",scene["original_artifacts"]))
        @test length(filter(c -> startswith(c["name"],"uav"),scene["blend"]["camera_objects"]))==scene["robots"]
        jobs=filter(j -> j["scenario"]==scene["name"],inv["jobs"])
        @test length(jobs)==(scene["robots"]==4 ? 241 : 597)
        for k in 2:3
            selected=filter(j -> j["configured_rounds"]==k && j["mode"]=="serial",jobs)
            @test Set(Tuple(j["assignments"]) for j in selected)==Set(Tuple.(ordered_rsp_assignments(scene["robots"],k)))
        end
        for k in 4:5
            selected=filter(j -> j["configured_rounds"]==k && j["mode"]=="serial",jobs)
            @test [j["partition_seed"] for j in selected]==D5.PHASE5_SEEDS
            @test all(j -> j["assignments"]==rsp_assignments(RSPPlanner(k;seed=j["partition_seed"]),scene["robots"]),selected)
            @test all(j -> length(j["round_groups"])==k && sort(vcat(j["round_groups"]...))==collect(1:scene["robots"]),selected)
        end
    end
    mktempdir() do output
        initialize_phase5(output,catalog)
        calls=Ref(0)
        bomb=(args...) -> (calls[]+=1;error("must not execute a fidelity-blocked scenario"))
        result=run_phase5_batch(output;max_jobs=1,warmup=false,executor=bomb)
        @test result.attempted==0 && calls[]==0
        @test result.completion["counts"]["blocked"]==2996
        @test isempty(summarize_phase5(output)["summaries"])
    end
end

@testset "Numeric checkpoint seals, bounded resume and complete fixture statistics" begin
    @test D5._phase5_distribution([1.0];exhaustive=false)["sd"]===nothing
    @test D5._phase5_distribution([1.0];exhaustive=true)["sd"]==0.0
    mktempdir() do output
        @test_throws ErrorException D5._phase5_resource_gate(output,Dict(),D5._benchmark_source_context())
    end
    mktempdir() do output
        value=Dict("integral_float"=>1.0,"zero"=>0.0,"fraction"=>1e-9)
        D5._phase5_write(joinpath(output,"number.json"),value)
        @test D5._phase5_digest(D5._phase5_read(joinpath(output,"number.json")))==D5._phase5_digest(value)
        inv=initialize_phase5(output,phase5_fixture_catalog();purpose="ci_functional_validation")
        @test (inv["expected_executions"],inv["expected_quality_configurations"],inv["expected_vi_calls"])==(73,39,292)
        first_batch=run_phase5_batch(output;max_jobs=1)
        @test first_batch.attempted==1
        greedy=first(inv["jobs"]);path=D5._phase5_record_path(output,greedy["id"]);original=read(path)
        incomplete=summarize_phase5(output)
        @test !incomplete["completion"]["complete"] && isempty(incomplete["summaries"])
        rest=run_phase5_batch(output;max_jobs=100,warmup=false)
        @test rest.attempted==72 && rest.completion["complete"]
        @test read(path)==original # Completed work was not executed or rewritten.
        replay=run_phase5_batch(output;max_jobs=100,warmup=false)
        @test replay.attempted==0
        report=summarize_phase5(output)
        @test length(report["summaries"])==5
        @test [r["quality_observations"] for r in report["summaries"]]==[1,4,9,10,10]
        @test all(s -> s["normalized_srppa"]["confidence_interval"]===nothing,report["summaries"])
        records=[D5._phase5_record(output,j) for j in inv["jobs"]]
        @test sum(r["result"]["metrics"]["vi_calls"] for r in records)==146
        @test sum(r["total_vi_calls"] for r in records)==292
        @test all(r -> isempty(r["result"]["stages"]) && isempty(r["result"]["convergence"]),records)
        @test all(r -> r["validation_run"]===nothing || r["correctness"]["validation_replay_equal"]===true,records)
        @test all(r -> r["result"]["validation"]["max_marginal_error"]<=1e-10,records)
        @test all(r -> r["correctness"]["rsp1_myopic_equal"]===true,filter(r -> r["definition"]["configured_rounds"]==1,records))
        @test all(r -> r["correctness"]["serial_threaded_equal"]===true,filter(r -> r["definition"]["mode"]=="threaded",records))
        @test all(r -> r["validation_run"]===nothing || all(c -> c["converged"],r["validation_run"]["result"]["convergence"]),records)
        # The checksum must fail on edited content; completed files are preserved.
        corrupt=replace(String(original),"\"successful\""=>"\"changed\"";count=1);write(path,corrupt)
        @test_throws ErrorException D5._phase5_record(output,greedy)
        @test read(path,String)==corrupt
    end
end

@testset "Failure/retry history and RSP-1 correctness gate" begin
    mktempdir() do output
        inv=initialize_phase5(output,phase5_fixture_catalog();purpose="ci_functional_validation")
        failed=run_phase5_batch(output;max_jobs=2,warmup=false,executor=(args...) -> error("injected test failure"))
        @test failed.attempted==1 && failed.completion["counts"]["failed"]==1
        @test run_phase5_batch(output;max_jobs=1,warmup=false).attempted==0
        retried=run_phase5_batch(output;max_jobs=1,warmup=false,retry_failed=true)
        @test retried.attempted==1
        record=D5._phase5_record(output,first(inv["jobs"]))
        @test record["status"]=="successful" && length(record["attempts"])==2
        @test record["attempts"][1]["status"]=="failed"
        lock=D5._phase5_lock(output)
        @test_throws ErrorException run_phase5_batch(output;max_jobs=1,warmup=false,recover_stale=true)
        rm(lock;recursive=true)
    end
    mktempdir() do output
        inv=initialize_phase5(output,phase5_fixture_catalog();purpose="ci_functional_validation")
        @test run_phase5_batch(output;max_jobs=5,warmup=false).attempted==5
        job=only(filter(j -> j["planner"]=="myopic",inv["jobs"]))
        record=D5._phase5_record(output,job)
        record["result"]["solution"]["elements"][1][2][1]["state"]["heading"]="E"
        D5._phase5_save_record(D5._phase5_record_path(output,job["id"]),record)
        gate=run_phase5_batch(output;max_jobs=100,warmup=false)
        @test gate.attempted==1 && gate.completion["counts"]["failed"]==1
        rsp1=only(filter(j -> j["configured_rounds"]==1 && j["mode"]=="serial",inv["jobs"]))
        @test occursin("RSP-1/myopic full trajectory mismatch",D5._phase5_record(output,rsp1)["error"])
        @test all(j -> !isfile(D5._phase5_record_path(output,j["id"])),filter(j -> something(j["configured_rounds"],0)>1,inv["jobs"]))
    end
end
