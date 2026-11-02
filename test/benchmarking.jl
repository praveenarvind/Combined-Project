include("benchmark_config.jl")

@testset "Profile hooks preserve algorithm behavior and counters" begin
    cfg,_=benchmark_configuration("cluster";num_robots=2,horizon=2)
    states=initial_states(cfg)
    primary=benchmark_plan(cfg,states,"rsp2_serial")
    profiled=benchmark_plan(cfg,states,"rsp2_serial";detailed=true)
    threaded=benchmark_plan(cfg,states,"rsp2_threaded";detailed=true)
    @test primary.solution==profiled.solution==threaded.solution
    @test primary.scores==profiled.scores==threaded.scores
    @test isempty(primary.stages) && isempty(primary.convergence)
    @test length(profiled.convergence)==length(threaded.convergence)==2
    @test all(c -> c.converged && c.states_checked==6400,profiled.convergence)
    @test Set(e.stage for e in profiled.stages)==Set([:prior_coverage,:reward_cache,:value_iteration,:path_extraction])
    @test all(e -> e.allocated_bytes!==nothing,profiled.stages)
    @test all(e -> e.allocated_bytes===nothing && e.gc_seconds===nothing,threaded.stages)
    @test primary.metrics.allocated_bytes > 0
    @test primary.metrics.gc_seconds >= 0
    @test primary.metrics.outside_block_wall_seconds >= 0
    @test primary.metrics.process_cpu_seconds > 0
    @test primary.validation.max_marginal_error <= 1e-10
    multi=benchmark_plan(cfg,states,"multiround";detailed=true)
    @test multi.metrics.vi_calls==4
    @test length(multi.traces)==4
    @test length(multi.convergence)==4
    @test multi.configured_rounds==multi.occupied_rounds==4
    assignment=benchmark_plan(cfg,states,"assignment";detailed=true)
    @test assignment.metrics.vi_calls==2
    @test assignment.configured_rounds===nothing
    @test assignment.logical_dependency_depth==1
    @test all(c -> c.converged,assignment.convergence)
    @test :reward_cache in [e.stage for e in assignment.stages]
    formation=benchmark_plan(cfg,states,"formation_idealized")
    @test formation.metrics.vi_calls==0
    @test !formation.validation.movement_checked
    @test formation.validation.feasibility=="idealized_reference_unconstrained"
end
