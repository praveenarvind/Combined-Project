"""Synthetic CI inputs only. Never eligible for the published-final inventory."""
function phase5_fixture_catalog()
    path=joinpath(PHASE5_ROOT,"test","fixtures","phase5_synthetic.json")
    states=Any[[i,Dict("state"=>Dict("x"=>x,"y"=>1,"heading"=>h),"depth"=>1,"horizon"=>2)] for (i,x,h) in ((1,1,"NE"),(2,3,"NW"))]
    scene=Dict{String,Any}("name"=>"synthetic_ci","robots"=>2,"actors"=>1,"horizon"=>2,"grid"=>Dict("width"=>3,"height"=>3,"headings"=>8),
        "input_path"=>path,"input_sha256"=>_phase5_file_sha(path),"input_revision"=>"synthetic_fixture_not_a_paper_scenario",
        "initial_states"=>states,"initial_state_method"=>"synthetic_test_fixture","initial_state_seed"=>nothing,"formation_seed"=>2026,
        "camera"=>Dict("model"=>"ViewConeSensor","fov"=>pi/2,"cutoff"=>100.0,"cutoff_test_enabled"=>false),"move_dist"=>3,
        "vi"=>Dict("max_iterations"=>90,"belres"=>1e-6,"discount"=>1,"include_Q"=>false),"fidelity_status"=>"ci_fixture","blockers"=>String[])
    Dict{String,Any}("schema_version"=>1,"partition_seeds"=>copy(PHASE5_SEEDS),"paper"=>Dict("independently_verified"=>false),"scenarios"=>[scene])
end
