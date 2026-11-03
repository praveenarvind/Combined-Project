using DistributedFilming

options=Dict{String,String}()
for arg in ARGS
    if arg in ("--run","--diagnostics")
        options[arg]="true"
    elseif startswith(arg,"--config=") || startswith(arg,"--output=")
        key,value=split(arg,"=";limit=2);options[key]=value
    else
        error("Usage: benchmark.jl --config=FILE [--output=DIR] [--run] [--diagnostics]")
    end
end
path=get(options,"--config",joinpath(@__DIR__,"..","configs","benchmarks","calibration.toml"))
config=load_benchmark_config(path)
println("RESOURCE_ESTIMATE ",estimate_benchmark(config))
if haskey(options,"--run")
    run_benchmarks(config,get(options,"--output",joinpath(@__DIR__,"..","results","benchmark-calibration")) ;
                   diagnostics=haskey(options,"--diagnostics"))
else
    println("Estimate only. Add --run to execute the explicit cases; no full matrix is started automatically.")
end
