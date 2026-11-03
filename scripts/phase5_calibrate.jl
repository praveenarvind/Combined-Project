# Resource calibration: one robot block from the full historical cluster configuration.
# This is not a team plan, a baseline comparison, or an outcome in the final matrix.
using DistributedFilming,JSON3,LinearAlgebra
const D=DistributedFilming
options=Dict(split(arg,'=';limit=2)[1]=>(occursin('=',arg) ? split(arg,'=';limit=2)[2] : "true") for arg in ARGS)
all(k -> k in ("--run-local","--dry-run","--catalog","--output","--estimated-total-seconds","--experiment-limit"),keys(options)) || error("unknown calibration option")
limit=get(options,"--experiment-limit","300");limit=limit=="unlimited" ? Inf : parse(Float64,limit)
limit>0 || error("positive experiment limit required")
estimate=parse(Float64,get(options,"--estimated-total-seconds","Inf"))
if haskey(options,"--dry-run")
    println("CALIBRATION_DRY_RUN one full-input Cluster robot block plus Bellman/marginal validation; estimated_total_seconds=$estimate limit=$limit; no planning")
    exit()
end
haskey(options,"--run-local") || error("Calibration is local-PC-only. Use --dry-run here; no original work is launched.")
out=get(options,"--output",joinpath(@__DIR__,"..","results","phase5-calibration"))
isfile(joinpath(out,"run.json")) && error("Calibration exists; preserve it and choose a new output directory")
if !isfinite(estimate) || estimate<=0 || estimate>limit
    D._phase5_write(joinpath(out,"status.json"),Dict("status"=>"skipped_resource_limit","estimated_total_seconds"=>isfinite(estimate) ? estimate : nothing,"reason"=>"Estimate missing or exceeds explicit total calibration budget; no original planning started."))
    println("CALIBRATION_SKIPPED_RESOURCE_LIMIT");exit(2)
end
BLAS.set_num_threads(1)
catalog=D._phase5_read(get(options,"--catalog",joinpath(@__DIR__,"..","docs","phase5","scenario_catalog.json")))
scene=only(filter(s -> s["name"]=="cluster",catalog["scenarios"]))
D._phase5_fidelity(Dict("purpose"=>"published_final","catalog"=>catalog),scene) || error("Complete the local-PDF fidelity review before calibration")
calibration_started=time()
configs,states=phase5_configuration(scene)
@assert (configs.num_robots,configs.horizon)==(4,60)
redirect_stdout(D._phase5_warm,devnull)
problem=D.MDMA.MultiRobotTargetCoverageProblem(copy(states),configs)
context=D.StageProfile(true)
GC.gc();cpu=D._process_cpu_seconds()
timed=redirect_stdout(devnull) do
    @timed D._with_profile(context) do
        D.SubmodularMaximization.solve_block(problem,1,D.SubmodularMaximization.empty(problem))
    end
end
cpu_seconds=D._process_cpu_seconds()-cpu
candidate=timed.value;robot,path=candidate
@assert robot==1 && length(path)==configs.horizon && first(path)==states[1]
mkpath(out)
D._phase5_write(joinpath(out,"progress.json"),Dict("status"=>"pending_validation","kind"=>"single_block_resource_calibration","full_team_solution"=>false,"planning_block_seconds"=>timed.time,"allocated_bytes"=>timed.bytes,"gc_seconds"=>timed.gctime))
println("CALIBRATION_BLOCK_DONE seconds=$(timed.time); independent validation follows");flush(stdout)
model,policy=only(context.policies)
certificate_start=time_ns();certificate=bellman_certificate(model,policy)
certificate_seconds=(time_ns()-certificate_start)/1e9
@assert certificate.converged
@assert all(i -> path[i+1] in D.MDMA.neighbors(model,path[i],Int(configs.move_dist)),1:length(path)-1)
empty_selection=Tuple{Int,D.MDMA.Trajectory}[]
gain=marginal_srppa(configs,empty_selection,candidate)
marginal_error=maximum(abs.([gain-joint_srppa(configs,[candidate]),gain-sum(D.MDMA.compute_single_agent_view_reward(model,s) for s in path)]))
@assert marginal_error<=1e-10
mkpath(out)
grid_storage=Base.summarysize(configs.grid)
record=Dict("id"=>"calibration-cluster-robot1-full60-serial-t$(Threads.nthreads())-$(time_ns())","manifest_sha256"=>D._phase5_file_sha(joinpath(D.PHASE5_ROOT,"Manifest.toml")),"status"=>"successful","kind"=>"single_block_full_input_resource_calibration","purpose"=>"not_a_full_team_experiment",
    "context"=>D._benchmark_source_context(),"scenario"=>scene["name"],"input_sha256"=>scene["input_sha256"],
    "robots_in_configuration"=>configs.num_robots,"horizon"=>configs.horizon,"actor_count"=>scene["actors"],
    "settings"=>D._planner_settings(configs),"historical_initial_states"=>scene["initial_states"],
    "completed_robot_blocks"=>1,"completed_vi_calls"=>1,"full_team_solution"=>false,
    "planning_block_seconds"=>timed.time,"allocated_bytes"=>timed.bytes,"gc_seconds"=>timed.gctime,
    "process_cpu_seconds"=>cpu_seconds,"process_peak_rss_bytes"=>Sys.maxrss(),"grid_storage_bytes"=>grid_storage,"stages"=>context.events,
    "certificate"=>certificate,"certificate_seconds"=>certificate_seconds,"max_marginal_error"=>marginal_error,
    "trajectory"=>candidate,"completed_at_utc"=>D._phase5_now(),
    "estimated_total_seconds"=>estimate,"total_wall_seconds"=>time()-calibration_started,
    "limitations"=>"One serial block, no legacy objective evaluation and no team reward. All 4 historical states/60 actor frames remain in the input. Paper review is recorded in the selected catalog. Runtime extrapolation is not a full-scenario measurement.")
D._phase5_write(joinpath(out,"run.json"),record)
println("RESOURCE_CALIBRATION_OK block_seconds=$(timed.time) allocated_bytes=$(timed.bytes) gc_seconds=$(timed.gctime) certificate=$(certificate.bellman_residual)")
