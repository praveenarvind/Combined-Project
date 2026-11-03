@testset "Explicit benchmark cases and scenario provenance" begin
    for scenario in ("cluster","split_and_join","priority_speaker")
        cfg,input=benchmark_configuration(scenario;num_robots=2,horizon=2)
        @test cfg.num_robots==2 && cfg.horizon==2
        @test cfg.sensor.fov==pi/2 && cfg.move_dist==3
        entry=only(filter(e -> endswith(e["destination"],"$(scenario)_data.json"),provenance["files"]))
        @test input.sha256==entry["sha256"]
    end
    @test_throws ArgumentError benchmark_configuration("unknown";num_robots=2,horizon=2)
    @test_throws ArgumentError benchmark_configuration("cluster";num_robots=0,horizon=2)
    @test_throws ArgumentError benchmark_configuration("cluster";num_robots=2,horizon=1000)
    window,input=benchmark_configuration("cluster";num_robots=2,horizon=2,start_frame=10)
    @test input.original_frame_start==10 && input.original_frame_end==11
    @test window.target_trajectories[1,1].x==load_scenario().target_trajectories[10,1].x
    @test_throws ArgumentError benchmark_configuration("cluster";num_robots=2,horizon=2,start_frame=60)
    config=load_benchmark_config(joinpath(@__DIR__,"..","configs","benchmarks","calibration.toml"))
    @test estimate_benchmark(config).measured_vi_calls==6
    @test DistributedFilming._bootstrap_initial_mean(Dict(1=>1.0)).lower === nothing
    ci=DistributedFilming._bootstrap_initial_mean(Dict(i=>Float64(i) for i in 1:10))
    @test ci.lower < 5.5 < ci.upper
end

