# Compare separate Julia processes; no planning or performance timing occurs here.
using Test, JSON3
length(ARGS)==2 || error("Usage: benchmark_pair_output.jl FOUR_THREAD_JSON ONE_THREAD_JSON")
four,one=map(p -> JSON3.read(read(p,String)),ARGS)
@testset "Cross-runtime paired replay" begin
    @test four.context.julia_threads==4 && one.context.julia_threads==1
    @test four.context.source_commit==one.context.source_commit
    @test four.context.source_sha256==one.context.source_sha256
    @test !four.context.source_dirty && !one.context.source_dirty
    @test four.context.cpu_allowed==one.context.cpu_allowed
    @test four.context.cpu_quota==one.context.cpu_quota
    @test four.context.blas_threads==one.context.blas_threads==1
    @test four.context.warmup_enabled==one.context.warmup_enabled
    @test four.context.purpose==one.context.purpose
    for r in one.records
        paired=only(filter(x -> x.case_id==r.case_id && x.replicate==r.replicate &&
            x.initial_seed==r.initial_seed && x.partition_seed==r.partition_seed &&
            x.result.planner==r.result.planner,four.records))
        @test paired.input.sha256==r.input.sha256
        @test paired.start_frame==r.start_frame
        @test paired.initial_states==r.initial_states
        @test paired.result.settings==r.result.settings
        @test paired.result.assignments==r.result.assignments
        @test paired.result.solution==r.result.solution
        @test paired.result.scores==r.result.scores
    end
end
