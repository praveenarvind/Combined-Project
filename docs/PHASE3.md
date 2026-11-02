# Phase 3: RSP planner integration and small pilots

Based on main merge commit `6ccc3c8` (Phase 2 PR #2). The adapter calls the
existing `SubmodularMaximization.PartitionSolver` and `solve_dag`; neither generic
solver nor original filming/baseline source is modified. Phase 2's analytical
joint evaluator and all camera/motion/VI parameters are unchanged.

## Adapter and replay

```julia
using DistributedFilming
configs = pilot_configuration()  # five original robots, first three original frames
states = initial_states(configs; seed=2026)
planner = RSPPlanner(4; seed=11, threaded=true)
result = plan_rsp(configs, states, planner)
result.scores.joint_srppa
result.metadata.assignments
replay = plan_rsp(configs, states, RSPPlanner(4; seed=11);
                  assignments=result.metadata.assignments)
```

Run Julia with `--threads=4` for actual threaded execution. Threaded requests fail
with an explanatory error when only one Julia thread exists. Any positive number
of configured rounds is accepted; normal pilots use 2, 4 and 8. One and N support
limiting-case tests. Robots are independently and uniformly sampled with a local
`MersenneTwister(partition_seed)`; ambient/global randomness is never seeded or
consumed by the adapter. Partitions are not balanced, forced occupied, or repaired.

Each robot receives exactly the preceding rounds' trajectories through the
upstream scheduler. Same-round decisions are mutually invisible. The imported
`Threads.@threads` loop supplies actual shared-memory work and per-round barriers.
This is not physical distributed/network execution.

`result` contains the upstream solution (its value remains legacy), Phase 2 scores,
and metadata: configured/occupied rounds, full per-robot assignments, seed, RNG,
assignment source, worker IDs, conditioning sets, execution intervals, observed VI
call count, timing and settings. Explicit assignments are labeled as replay; the
recorded seed does not pretend to have generated those overridden labels.

Configured rounds are a budget. Occupied rounds count distinct sampled labels and
can be smaller; with five robots, at most five rounds are occupied even for RSP-8.
The upstream scheduler also omits unoccupied trailing labels internally. Explicit
ordered singleton partitions reproduce fixed-order sequential greedy; assigning
robots randomly to N rounds generally does not.

## Thread safety and instrumentation

The adapter forwards each block to the unchanged filming `solve_block`. Each call
allocates its own prior-coverage array, single-robot model, reward cache, VI solver,
value vector and policy. Configuration/grid/actor arrays and earlier trajectories
are shared for reading. Callers must not mutate inputs during planning. No cache
is stored globally or shared between block calls.

Instrumentation increments an atomic counter and writes one observation into each
robot's exclusive preallocated slot. There is no concurrent vector append or
shared dictionary mutation. The final legacy objective is evaluated once after
scheduler barriers. The VI-call count is the observed block-call count: the
preserved filming block invokes its single-robot VI solver exactly once.

Tests check actual dependency sets, barriers, overlapping execution on different
threads, independent cache storage/mutations, and equivalent fresh trajectories
and scores for serial/threaded modes. They also check one-round/myopic and ordered
singleton/sequential equivalence, legal trajectories and Phase 2 marginals.

## Pilot workloads

```sh
# Main pilot: five robots, three frames, partition seeds 11, 22, 33.
julia --threads=4 --startup-file=no --project=. scripts/rsp_pilot.jl

# Supplementary compatibility smoke: two robots, four frames, seed 11.
julia --threads=4 --startup-file=no --project=. scripts/rsp_pilot.jl --two-robot

# CI integration workload: five robots, two frames, one partition seed.
julia --threads=4 --startup-file=no --project=. scripts/rsp_pilot.jl --ci
julia --startup-file=no --project=. test/pilot_output.jl
```

All workloads use original cluster actor poses, six actors, the original 20×20
grid, view-cone camera override and movement distance 3. Only the documented robot
count/horizon changes. Initial-state seed 2026 is fixed across all planners and
partition seeds. Thus repeated seeds probe partition variability, not independent
scene or initial-condition variability. Greedy is freshly solved once per repeat.
Both execution modes use the same sampled assignment and must produce identical
trajectories and Phase 2 scores. All results undergo movement and full-path
marginal checks outside timing; source camera and reward functions are reused.

Results are written under ignored `results/rsp-five-robot`, `rsp-two-robot` or
`rsp-ci`: raw `results.csv`, descriptive `summary.csv`, and `run.json` containing
all trajectories, initial states, source revision, input hash, configuration,
assignments, seeds, execution traces, validation errors and scores. Committed pilot
evidence and observations are recorded in [PHASE3_RESULTS.md](PHASE3_RESULTS.md).

## Timing and interpretation

A dedicated process first warms sequential greedy, conditioned serial RSP and
concurrent/conditioned threaded RSP on five-robot/two-frame solves. Serial labels
[1,2,4,6,8] and [1,3,5,7,8] cover every earlier-partition prefix length 0:7;
threaded labels [1,1,1,1,2] engage all four workers and then condition a later robot.
Those four warmups (20 VI calls) are excluded from recorded trials. Use four Julia
threads and one BLAS thread. Installation, warmup, result serialization, rendering,
Phase 2 scoring and validation are outside planning timing. Explicit full GC
runs before each solve, outside the timing boundary. GC arising inside a measured
solve remains included. Solver verbosity/settings are unchanged, with output
redirected to devnull consistently in all measured runs.

`planning_seconds` is warmed wall time for the actual upstream scheduler, coverage
preparation, reward cache creation, VI, path extraction and instrumentation. The
upstream solver's final legacy objective is separately timed and subtracted;
`solver_seconds` includes it and `legacy_evaluation_seconds` is also saved.
Assignment generation and trace preallocation are outside this boundary. Greedy
uses the same observation/timing wrapper around its original sequential algorithm.
Serial/threaded order alternates by repetition. Replicates are run one at a time,
not concurrently with tests or other pilot jobs started by this task.

Summary SD uses n−1 across three partition seeds; single-observation CI/smoke SDs
are left empty. Raw per-run times, assignments and rewards are retained. These are
small integration pilots, not confidence intervals, speedup guarantees, a full
experimental matrix or paper-reproduction claims. More configured rounds may
improve information sharing while reducing parallel work; five robots cannot
populate eight rounds. Host CPU quotas, allocation/GC costs and scheduling affect
wall time. Do not infer distributed communication costs from shared-memory timing.

R-IRSP, theoretical bounds, full-scale studies, Blender rendering and Phase 4 are
outside this change and pending separate approval.
