using Dates
const PHASE5_SEEDS = [11,22,33,44,55,66,77,88,99,110]
const PHASE5_SCENARIOS = ["cluster","cross_mix","four_split","priority_runners","priority_speaker","split_and_join","spreadout_group","track_runners"]
const PHASE5_ROOT = normpath(joinpath(@__DIR__,"..",".."))
_phase5_plain(x::JSON3.Object)=Dict{String,Any}(string(k)=>_phase5_plain(v) for (k,v) in pairs(x))
_phase5_plain(x::AbstractVector)=Any[_phase5_plain(v) for v in x]
_phase5_plain(x)=x
_phase5_read(path)=_phase5_plain(JSON3.read(read(path,String)))
_phase5_now()=Dates.format(Dates.now(Dates.UTC),dateformat"yyyy-mm-ddTHH:MM:SS.sss")*"Z"
function _phase5_canonical(x)
    if x isa AbstractDict
        return "{"*join([JSON3.write(string(k))*":"*_phase5_canonical(x[k]) for k in sort(collect(keys(x));by=string)],",")*"}"
    elseif x isa AbstractVector
        return "["*join(_phase5_canonical.(x),",")*"]"
    elseif x isa AbstractFloat && isfinite(x) && isinteger(x)
        # JSON pretty-printing may encode 1.0 as 1; seals describe numeric values.
        return string(BigInt(x))
    end
    JSON3.write(x)
end
_phase5_digest(x)=bytes2hex(sha256(_phase5_canonical(x)))
_phase5_file_sha(path)=bytes2hex(sha256(read(path)))
function _phase5_write(path,data)
    mkpath(dirname(path));temp=path*".tmp.$(getpid())"
    open(temp,"w") do io
        JSON3.pretty(io,data);println(io);flush(io)
    end
    Base.Filesystem.rename(temp,path) # Same-directory atomic replacement on supported Linux hosts.
end

"""Every ordered assignment, including empties; last robot's label varies fastest."""
function ordered_rsp_assignments(n::Integer,k::Integer)
    n>0 || throw(ArgumentError("positive robot count required"))
    1<=k<=5 || throw(ArgumentError("final experiments permit RSP-1 through RSP-5 only"))
    total=big(k)^n
    total<=1_000_000 || throw(ArgumentError("materialization exceeds bounded inventory size"))
    [[1+Int(mod(div(i,big(k)^(n-r)),k)) for r in 1:n] for i in 0:Int(total)-1]
end

function phase5_configuration(scene)
    path=isabspath(scene["input_path"]) ? scene["input_path"] : joinpath(PHASE5_ROOT,scene["input_path"])
    _phase5_file_sha(path)==scene["input_sha256"] || error("scenario input hash mismatch")
    configs=load_scenario(path;name=scene["name"])
    (configs.num_robots,configs.horizon,size(configs.target_trajectories,2))==
        (scene["robots"],scene["horizon"],scene["actors"]) || error("original count/horizon changed")
    (configs.grid.width,configs.grid.height)==(scene["grid"]["width"],scene["grid"]["height"]) || error("grid changed")
    configs.sensor.fov==scene["camera"]["fov"] && configs.sensor.cutoff==scene["camera"]["cutoff"] && configs.move_dist==scene["move_dist"] || error("camera/motion changed")
    configs.grid.angle_divisions==scene["grid"]["headings"] || error("heading resolution changed")
    scene["vi"]==Dict("max_iterations"=>90,"belres"=>1e-6,"discount"=>1,"include_Q"=>false) || error("VI settings changed")
    entries=sort(scene["initial_states"];by=first)
    first.(entries)==collect(1:configs.num_robots) || error("incomplete historical starting states")
    states=[MDMA.MDPState(MDMA.UAVState(Float64(e[2]["state"]["x"]),Float64(e[2]["state"]["y"]),Symbol(e[2]["state"]["heading"])),Int(e[2]["depth"]),Int(e[2]["horizon"])) for e in entries]
    check_states(configs,states)
    configs,states
end

function phase5_inventory(catalog;workers=4,purpose="published_final")
    workers>=2 || throw(ArgumentError("paired final inventory requires at least two available threads"))
    catalog["partition_seeds"]==PHASE5_SEEDS || error("the ten predeclared partition seeds must be preserved")
    purpose in ("published_final","ci_functional_validation") || error("unknown purpose")
    if purpose=="published_final"
        [s["name"] for s in catalog["scenarios"]]==PHASE5_SCENARIOS || error("all eight original scenarios are required")
    end
    jobs=Any[]
    for scene in catalog["scenarios"]
        n=scene["robots"];name=scene["name"]
        configurations=Any[]
        for k in 1:5
            if k<=3
                for (index,labels) in enumerate(ordered_rsp_assignments(n,k))
                    push!(configurations,(k=k,labels=labels,method="predetermined",seed=nothing,
                        sampling=k==1 ? "single_independent_configuration" : "exhaustive_ordered_assignments",tag="enumerated-$(lpad(string(index),4,'0'))"))
                end
            else
                for seed in PHASE5_SEEDS
                    labels=rsp_assignments(RSPPlanner(k;seed=seed),n)
                    push!(configurations,(k=k,labels=labels,method="random",seed=seed,
                        sampling="ten_predeclared_seeds",tag="seed-$(lpad(string(seed),3,'0'))"))
                end
            end
        end
        function add_job(planner,mode;k=nothing,labels=nothing,method=nothing,seed=nothing,sampling="baseline",tag="baseline")
            qid=k===nothing ? "$name-$planner" : "$name-rsp$k-$tag"
            id="$qid-$mode-t$workers"
            groups=labels===nothing ? nothing : [findall(==(r),labels) for r in 1:k]
            blocked=scene["fidelity_status"]!="verified" && !(purpose=="ci_functional_validation" && scene["fidelity_status"]=="ci_fixture")
            push!(jobs,Dict{String,Any}("id"=>id,"quality_id"=>qid,"scenario"=>name,"planner"=>planner,
                "mode"=>mode,"workers"=>workers,"replicate"=>1,"configured_rounds"=>k,"assignments"=>labels,
                "occupied_rounds"=>labels===nothing ? nothing : length(unique(labels)),"round_groups"=>groups,
                "all_rounds_occupied"=>labels===nothing ? nothing : length(unique(labels))==k,
                "partition_method"=>method,"partition_seed"=>seed,"sampling_method"=>sampling,
                "expected_vi_calls"=>planner=="formation_idealized" ? 0 : planner=="multiround" ? n^2 : n,
                "status"=>blocked ? "blocked" : "pending","blocked_reason"=>blocked ? join(scene["blockers"],"; ") : nothing))
        end
        for baseline in ("greedy","myopic","multiround","assignment","formation_idealized")
            add_job(baseline,"serial")
        end
        for c in configurations, mode in ("serial","threaded")
            add_job("rsp$(c.k)_$mode",mode;k=c.k,labels=c.labels,method=c.method,seed=c.seed,sampling=c.sampling,tag=c.tag)
        end
    end
    length(unique(j["id"] for j in jobs))==length(jobs) || error("duplicate experiment IDs")
    Dict{String,Any}("schema_version"=>1,"purpose"=>purpose,"workers"=>workers,"seeds"=>copy(PHASE5_SEEDS),
        "catalog_sha256"=>_phase5_digest(catalog),"catalog"=>catalog,"jobs"=>jobs,
        "expected_executions"=>length(jobs),"expected_quality_configurations"=>length(unique(j["quality_id"] for j in jobs)),
        "expected_vi_calls"=>sum(j["expected_vi_calls"] for j in jobs))
end

function _phase5_validate_inventory(inventory)
    expected=phase5_inventory(inventory["catalog"];workers=inventory["workers"],purpose=inventory["purpose"])
    _phase5_digest(expected)==_phase5_digest(inventory) || error("frozen inventory was altered or is incomplete; regenerate from the audited catalog")
    inventory
end

function initialize_phase5(output,catalog;workers=4,purpose="published_final")
    inventory=phase5_inventory(catalog;workers=workers,purpose=purpose)
    path=joinpath(output,"inventory.json")
    if isfile(path)
        _phase5_digest(_phase5_read(path))==_phase5_digest(inventory) || error("inventory already exists with different definitions; preserve it and use a new output directory")
    else
        _phase5_write(path,inventory)
    end
    export_phase5_csv(output,inventory)
    inventory
end
