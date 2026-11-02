using Test,JSON3,DistributedFilming
path=isempty(ARGS) ? joinpath(@__DIR__,"..","results","benchmark-ci","run.json") : only(ARGS)
run=JSON3.read(read(path,String))
@testset "Controlled benchmark output and scheduler-control schema" begin
    @test run.schema_version==1
    @test run.context.blas_threads==1
    @test !isempty(run.records)
    @test run.estimate.measured_vi_calls==sum(r.result.metrics.vi_calls for r in run.records)
    for r in run.records
        z=r.result
        reference=only(filter(x -> x.case_id==r.case_id && x.replicate==r.replicate && x.result.planner=="greedy",run.records))
        @test r.normalized_srppa ≈ z.scores.joint_srppa/reference.result.scores.joint_srppa
        @test z.metrics.allocated_bytes>=0 && z.metrics.gc_seconds>=0
        @test z.metrics.process_cpu_seconds>=0
        @test z.validation.max_marginal_error<=1e-10
        @test z.redundancy_per_robot>=-1e-12
        @test length(z.solution.elements)==r.robots
        if startswith(z.planner,"rsp")
            @test z.occupied_rounds==length(unique(z.assignments))
            @test z.metrics.vi_calls==r.robots
            @test all(v -> 1<=v<=z.configured_rounds,z.assignments)
        elseif z.planner=="multiround"
            @test z.metrics.vi_calls==r.robots^2
            @test length(z.traces)==r.robots^2
        elseif z.planner=="formation_idealized"
            @test z.metrics.vi_calls==0
            @test z.validation.feasibility=="idealized_reference_unconstrained"
        else
            @test z.metrics.vi_calls==r.robots
        end
    end
    for summary in run.summaries
        summary.n_initial_seeds<10 && @test summary.normalized_ci.lower===nothing
    end
    controls=scheduling_control(;repeats=5)
    @test length(controls)==(Threads.nthreads()>1 ? 6 : 3)
    @test all(x -> x.min_seconds>=0 && x.kind=="no_op_scheduler_control",controls)
end
