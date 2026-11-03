using JSON3
const C5=DistributedFilming
@testset "Phase 5 local selection, supplementary configurations and budget preflight" begin
    catalog=phase5_fixture_catalog();inv=phase5_inventory(catalog;purpose="ci_functional_validation")
    selected=select_phase5_jobs(inv;rounds=2,mode="threaded")
    @test length(selected.requested_ids)==4
    @test length(selected.jobs)==12
    @test all(id -> id in Set(j["id"] for j in selected.jobs),vcat([C5._phase5_dependencies(j) for j in selected.jobs]...))
    @test length(select_phase5_jobs(inv;planner="baselines").jobs)==5
    @test length(select_phase5_jobs(inv;rounds=4,seed=11,mode="serial").requested_ids)==1
    for kwargs in ((scenario="missing",),(rounds=6,),(planner="missing",),(mode="missing",),(seed=999,))
        @test_throws ArgumentError select_phase5_jobs(inv;kwargs...)
    end
    extras=[Dict("scenario"=>"synthetic_ci","rounds"=>4,"seed"=>nothing,"assignments"=>[4,1])]
    custom=phase5_inventory(catalog;purpose="ci_functional_validation",supplemental=extras)
    @test length(custom["jobs"])==75
    @test C5._phase5_validate_inventory(custom)==custom
    sel=select_phase5_jobs(custom;rounds=4,assignments=[4,1])
    @test length(sel.requested_ids)==2
    @test all(j -> j["round_groups"]==[Int[2],Int[],Int[],Int[1]],filter(j -> j["id"] in sel.requested_ids,sel.jobs))
    @test_throws ArgumentError phase5_inventory(catalog;purpose="ci_functional_validation",supplemental=[Dict("scenario"=>"synthetic_ci","rounds"=>4,"seed"=>11,"assignments"=>[4,1])])
    seeded=phase5_inventory(catalog;purpose="ci_functional_validation",supplemental=[Dict("scenario"=>"synthetic_ci","rounds"=>5,"seed"=>123,"assignments"=>nothing)])
    seeded_selection=select_phase5_jobs(seeded;rounds=5,seed=123)
    @test length(seeded_selection.requested_ids)==2
    @test all(j -> j["assignments"]==rsp_assignments(RSPPlanner(5;seed=123),2),filter(j -> j["id"] in seeded_selection.requested_ids,seeded_selection.jobs))
    mktempdir() do output
        initialize_phase5(output,catalog;purpose="ci_functional_validation",supplemental=extras)
        before=read(joinpath(output,"inventory.json"))
        plan=phase5_preflight(output;selection=sel,write_policy=true)
        @test length(plan["jobs"])==6
        @test !isdir(joinpath(output,"records"))
        @test read(joinpath(output,"inventory.json"))==before
        first_batch=run_phase5_batch(output;selection=sel,max_jobs=100,warmup=false)
        @test first_batch.attempted==6
        @test !first_batch.completion["complete"]
        @test all(C5._phase5_record(output,j)["status"]=="successful" for j in sel.jobs)
        @test run_phase5_batch(output;selection=sel,max_jobs=100,warmup=false).attempted==0
        @test run_phase5_batch(output;max_jobs=100,warmup=false,only_failed=true).attempted==0
        @test C5._phase5_record(output,last(sel.jobs))["correctness"]["serial_threaded_equal"]===true
    end
    mktempdir() do output
        initialize_phase5(output,catalog;purpose="ci_functional_validation")
        failed=run_phase5_batch(output;max_jobs=1,warmup=false,executor=(args...) -> error("test-only failure"))
        @test failed.completion["counts"]["failed"]==1
        retry=run_phase5_batch(output;max_jobs=100,warmup=false,only_failed=true)
        @test retry.attempted==1 && retry.completion["counts"]["successful"]==1
        @test C5._phase5_record(output,first(inv["jobs"]))["attempts"][1]["status"]=="failed"
        job=first(inv["jobs"]);record=C5._phase5_record(output,job)
        primary=record["result"];record["status"]="running";record["attempts"][end]["status"]="running"
        C5._phase5_save_record(C5._phase5_record_path(output,job["id"]),record)
        lock=joinpath(output,".batch.lock");mkdir(lock)
        C5._phase5_write(joinpath(lock,"owner.json"),Dict("boot"=>C5._phase5_boot(),"pid"=>typemax(Int32),"start"=>"dead-process"))
        recovered=run_phase5_batch(output;max_jobs=1,warmup=false,only_failed=true,recover_stale=true)
        @test recovered.attempted==1
        record=C5._phase5_record(output,job)
        @test record["attempts"][2]["partial_primary_result"]==primary
        @test record["status"]=="successful" && length(record["attempts"])==3
    end
    # No original models are loaded: use inventory metadata and a fabricated cost report.
    original=C5._phase5_read(joinpath(@__DIR__,"..","docs","phase5","scenario_catalog.json"))
    changed=deepcopy(original);changed["scenarios"][1]["robots"]=3
    @test_throws ErrorException phase5_inventory(changed)
    mktempdir() do output
        published=initialize_phase5(output,original)
        jobs=select_phase5_jobs(published;scenario="cluster",planner="greedy")
        C5._phase5_write(joinpath(output,"resources.json"),Dict("inventory_file_sha256"=>C5._phase5_file_sha(joinpath(output,"inventory.json")),
            "jobs"=>[Dict("id"=>only(jobs.jobs)["id"],"estimated_total_seconds"=>301.0)]))
        plan=phase5_preflight(output;selection=jobs,write_policy=true)
        @test plan["counts"]["skipped_resource_limit"]==1
        @test only(plan["jobs"])["estimated_total_seconds"]==301.0
        @test occursin("exceeds",only(plan["jobs"])["reason"])
        @test run_phase5_batch(output;selection=jobs,warmup=false).attempted==0
        @test !isdir(joinpath(output,"records"))
        @test_throws ArgumentError phase5_preflight(output;experiment_limit=0)
        @test !only(phase5_preflight(output;selection=jobs,experiment_limit=Inf)["jobs"])["fidelity_verified"]
    end
end
