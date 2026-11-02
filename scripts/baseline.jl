using DistributedFilming
using JSON3
using Random

allowed = Set(["--smoke", "--planner=greedy", "--planner=myopic", "--planner=assignment", "--planner=formation", "--planner=multiround"])
all(a -> a in allowed, ARGS) || error("Usage: baseline.jl [--smoke] [--planner=greedy|myopic|assignment|formation|multiround]")
planner_arg = filter(a -> startswith(a, "--planner="), ARGS)
length(planner_arg) <= 1 || error("Choose one planner")
kind = isempty(planner_arg) ? "greedy" : split(only(planner_arg), "=")[2]
planners = Dict("greedy" => GreedyPlanner(), "myopic" => MyopicPlanner(),
                "assignment" => AssignmentPlanner(), "formation" => FormationPlanner(),
                "multiround" => MultipleRoundsGreedyPlanner())
configs = load_scenario()
smoke = "--smoke" in ARGS
smoke && (configs = smoke_configuration(configs))
seed = 2026
states = initial_states(configs; seed=seed)
println("Fresh cluster baseline: planner=$kind, robots=$(configs.num_robots), horizon=$(configs.horizon), reduced_smoke=$smoke")
solution = plan_baseline(configs, states, planners[kind])
@assert length(solution.elements) == configs.num_robots
@assert all(e -> length(last(e)) == configs.horizon, solution.elements)
@assert isfinite(solution.value)
scores = evaluate_solution(configs, solution)
out = joinpath(@__DIR__, "..", "results", smoke ? "smoke" : "cluster", kind)
mkpath(out)
# No plotting or rendering and no reads from precomputed solutions.
open(joinpath(out, "solution.json"), "w") do io
    JSON3.pretty(io, Dict("value" => legacy_value(solution), "legacy_value" => scores.legacy_value,
        "joint_srppa" => scores.joint_srppa, "heading_bonus" => scores.heading_bonus,
        "stationary_bonus" => scores.stationary_bonus, "score_schema_version" => 2,
        "value_kind" => "legacy", "elements" => solution.elements))
end
open(joinpath(out, "run.json"), "w") do io
    JSON3.pretty(io, Dict("scenario" => "cluster", "seed" => seed,
        "planner" => kind, "robots" => configs.num_robots, "horizon" => configs.horizon,
        "reduced_smoke" => smoke, "julia_version" => string(VERSION),
        "value_kind" => "upstream legacy value; separate joint_srppa is authoritative",
        "scores" => scores, "score_schema_version" => 2,
        "initial_states" => states))
end
println("BASELINE_OK joint_srppa=$(scores.joint_srppa), legacy_value=$(scores.legacy_value), heading_bonus=$(scores.heading_bonus), stationary_bonus=$(scores.stationary_bonus); output=$(abspath(out))")
