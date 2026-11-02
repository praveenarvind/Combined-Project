# Distributed Multi-Drone Filming — Seeded RSP planning

A Julia package based on Hughes et al.'s multi-drone filming implementation.
The foundation imports the existing filming model, value iteration, baseline
planners, and a **single copy** of the upstream submodular/RSP scheduling framework.
Phase 2 adds one authoritative analytical joint SRPPA evaluator, separate legacy
values and transition bonuses. Phase 3 adds seeded serial/threaded RSP adapters and small pilots. R-IRSP,
full-scale experiments and theory remain out of scope.

## Sources and attribution

- Main foundation: [MultiDroneMultiActorFilming](https://github.com/praveenarvind/MultiDroneMultiActorFilming),
  branch `github/main`, commit `42f97540ff002651822a9bbd617bff3d68ab93e2`.
- Submodular/RSP lineage: [MultiAgentSensing](https://github.com/praveenarvind/MultiAgentSensing),
  branch `master`, commit `fe9162adbedb374fa0e9ca4739e398acc4704309`.
  The filming repository already contains this framework; it is imported from
  filming once, rather than copying both implementations.

See [third_party/SOURCES.toml](third_party/SOURCES.toml) for original-file hashes,
exact source references and adaptations; [docs/IMPORTS.md](docs/IMPORTS.md) for the
import boundary. Both original BSD-3-Clause notices are retained in
[third_party/licenses](third_party/licenses), with the filming notice in [LICENSE](LICENSE).
Research citations are in [CITATION.bib](CITATION.bib).

## Install

Use **Julia 1.8.5**, matching the upstream manifest and the pinned Docker image.
From the repository root:

```sh
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --threads=4 --startup-file=no --project=. -e 'using Pkg; Pkg.test(; julia_args=["--threads=4"])'
```

Commit and use `Manifest.toml`; do not run `Pkg.update()` for reproduction. The
used dependency closure retains upstream package content hashes and versions,
except a resolver normalization of the OpenSpecFun_jll label from 0.5.5+0 to
0.5.5+2 for the **same** source tree; no package content changed.
Direct external dependencies are:

| Package | Version |
| --- | --- |
| DiscreteValueIteration | 0.4.6 |
| POMDPs | 0.9.5 |
| POMDPModelTools | 0.3.13 |
| POMDPPolicies | 0.4.3 |
| JSON3 | 1.12.0 |

LinearAlgebra, Random and SparseArrays are Julia standard libraries. Tests also
use Test, SHA and TOML. Python, PyCall, Cairo, matplotlib, Jupyter, HistogramFilters
and Blender are not needed for this headless foundation. Rendering is outside this
phase; the original Dockerfile's Python/Blender compatibility issues are avoided
by excluding that optional pipeline rather than changing the planning model.

For a managed HTTPS proxy, retain its proxy variables and set
`JULIA_SSL_CA_ROOTS_PATH` to the provided combined CA bundle when required. Never
disable certificate or artifact verification. Use a task-local `JULIA_DEPOT_PATH`
if the default depot is not writable.

## Run a fresh minimal baseline

```sh
julia --startup-file=no --project=. scripts/baseline.jl --smoke
```

This **reduced integration check** runs sequential greedy with fresh value
iteration on the first **four original frames**, all **six actors**, and **two
robots** from `cluster`. The grid remains 20×20. Actor poses/weights, camera model,
movement rules, reward functions, and solver settings are unchanged. Only team
size and horizon are explicitly reduced for fast validation. This is not a claim
of reproducing a complete paper experiment.

The seed is 2026. The runner writes a newly computed `solution.json` and `run.json`
with separate `joint_srppa`, `legacy_value`, `heading_bonus` and `stationary_bonus`
fields (score schema version 2), under `results/smoke/greedy/`. Outputs are ignored by Git. No precomputed solutions
are imported or loaded. The original `cluster_data.json` and `cluster.blend` are
provided as inputs, with provenance hashes. Tests verify the JSON input hash.

Other retained baselines can be selected individually:

```sh
julia --startup-file=no --project=. scripts/baseline.jl --smoke --planner=myopic
julia --startup-file=no --project=. scripts/baseline.jl --smoke --planner=assignment
julia --startup-file=no --project=. scripts/baseline.jl --smoke --planner=multiround
julia --startup-file=no --project=. scripts/baseline.jl --smoke --planner=formation
```

Omit `--smoke` to explicitly request the full cluster input: five robots and 60
frames. That workload is much more expensive, particularly the legacy objective
calculation. No command starts all experiments or rendering.

Programmatic use:

```julia
using DistributedFilming
configs = smoke_configuration(load_scenario())
states = initial_states(configs; seed=2026)
solution = plan_baseline(configs, states, GreedyPlanner())
scores = evaluate_solution(configs, solution)
# scores.joint_srppa is the common quality metric for every baseline.
# solution.value and scores.legacy_value remain the unmodified upstream value.
prior = solution.elements[1:1]
candidate = solution.elements[2]
gain = marginal_srppa(configs, prior, candidate)
```

Submodular interfaces and existing scheduling functions remain available through
`DistributedFilming.SubmodularMaximization`. Filming internals live in
`DistributedFilming.MDMA`. No `LOAD_PATH` changes or source checkouts are required.

## Seeded RSP and small pilots

```julia
using DistributedFilming
configs = pilot_configuration() # all five original robots, first three frames
states = initial_states(configs; seed=2026)
result = plan_rsp(configs, states, RSPPlanner(4; seed=11, threaded=true))
result.scores.joint_srppa
result.metadata.assignments
```

The test suite includes mandatory concurrency checks; use the four-thread test
command above. Start Julia with `--threads=4`. RSP-2/4/8 reuse the existing partition/DAG scheduler;
robots in a round condition only on earlier rounds. Each VI call owns its reward
cache. The adapter saves assignments, seeds, configured/occupied rounds, worker
traces, observed VI calls and separate planning/legacy-evaluation timings.

```sh
julia --threads=4 --startup-file=no --project=. scripts/rsp_pilot.jl
julia --threads=4 --startup-file=no --project=. scripts/rsp_pilot.jl --two-robot
```

The main pilot uses five robots, three original cluster frames and three partition
seeds. The supplementary two-robot/four-frame run is a compatibility smoke check.
Both use fresh greedy comparisons and identical initial states, targets and camera
settings; modes replay the same assignments. Compilation warmup precedes timing.
These small pilots do not constitute a full experimental matrix. See
[docs/PHASE3.md](docs/PHASE3.md) for APIs, timing boundaries and replay instructions.
Measured rewards, wall times, occupied rounds, assignments and raw artifacts are in
[docs/PHASE3_RESULTS.md](docs/PHASE3_RESULTS.md).

## Docker

```sh
docker build -t distributed-filming:phase3 .
docker run --rm distributed-filming:phase3
docker run --rm distributed-filming:phase3 \
  julia --threads=4 --startup-file=no --project=. -e 'using Pkg; Pkg.test(; julia_args=["--threads=4"])'
```

The score-output CI check runs `test/score_output.jl` after the fresh greedy
smoke command.

The default container command runs only the reduced greedy baseline. The base
image is pinned by digest, Julia dependencies by the manifest. Four Julia
precompile workers are configured to limit resource use. No X server or GPU is
required.

For a managed proxy, supply its combined public CA bundle at build time:

```sh
docker build --secret id=proxy_ca,src=/etc/ssl/certs/ca-certificates.crt \
  -t distributed-filming:phase3 .
```

The certificate is mounted only for dependency installation, not copied into the
image. Runtime baseline execution needs no network. A later networked `Pkg` command
in a managed container also needs the current session's proxy/CA configuration.

## Joint SRPPA and separate legacy scores

`joint_srppa(configs, selections_or_solution)` accumulates the unchanged camera's
nonnegative densities across all selected robots **before** applying the square
root independently for each actor face and time step:

```text
sum(time, actor, face): weight * area * sqrt(sum(robot densities))
```

Empty selections score zero. Duplicate/out-of-range robot IDs, malformed state
sequences, inconsistent horizons, nonfinite positions and invalid face weights or
densities are rejected. Accumulation is in robot-ID order for repeatability.
`evaluate_solution(configs, solution)` uses this same objective for all five
baselines; it does not modify the supplied solution. Legacy JSON `value` remains
legacy for compatibility and is explicitly labeled `value_kind="legacy"`.

`marginal_srppa(configs, prior, candidate)` sums per-face reward increments; tests
compare it both with a difference of joint scores and with the original
single-robot marginal reward. `motion_bonuses` separately counts 0.02 per unchanged
heading and 0.01 per stationary position on actual adjacent transitions. It does
not add a fictitious self-transition at frame 1. No combined quality-plus-bonuses
score is silently substituted for SRPPA.

The quality objective includes all recorded frames. VI optimizes transitions into
frames 2:H; frame-1 view quality is fixed by the initial state. Tests account for
that initial-state constant when relating VI rewards to full-path marginals.
The old legacy objective instead evaluates each state against itself, so its
bonuses differ from actual transition bonuses. See [docs/PHASE2.md](docs/PHASE2.md)
for API details and numerical examples.

Scoring validates trajectory structure and geometry, not movement feasibility:
the preserved Formation reference uses continuous positions and may leave the VI
grid or violate movement limits. This permits one quality metric for every
baseline without changing any baseline's motion model.

## Preserved limitations

**`solution.value` is the original legacy value, not a corrected joint SRPPA
score.** The upstream objective independently sums robot rewards with empty prior
coverage; the single-robot planner does condition marginal rewards on prior robot
trajectories. No normalized performance comparisons should use the legacy value.

Other behavior intentionally retained:

- VI uses 90 maximum iterations, tolerance 1e-6 and discount 1.
- Motion rewards add 0.02 for unchanged heading and 0.01 for unchanged position.
- Myopic ignores other robots but still optimizes a complete trajectory.
- Multi-round greedy performs N sequential sweeps for N robots.
- Experiment loading uses the upstream view-cone override (π/2 FOV, cutoff 100),
  movement distance 3; the view-cone detection cutoff test remains disabled.
- Formation ignores the supplied initial states and VI movement constraints and
  returns the original placeholder value 1.0. It is an idealized reference, not a
  directly comparable feasible planner. Its random phase now has an explicit seed.
- The grid search neighborhood, hard-coded seven-face assumption, camera geometry,
  and assignment rules are unchanged.

Serialization is headless: `MDMA.save_solution` no longer invokes Cairo renders.
The empty upstream import-time testset is omitted; executable tests are in `test/`.

The analytical joint evaluator is implemented and tested in Phase 2. Rendered
metrics remain unweighted and have not been reconciled with weighted analytical
SRPPA. Phase 3 provides the RSP adapter and small pilots; Phase 4, R-IRSP and
full-scale experiments remain pending review.

Actual executed checks are recorded in [docs/VALIDATION.md](docs/VALIDATION.md).

## Layout

```text
src/DistributedFilming.jl        package entry point
src/submodular/                  reused interfaces and unchanged generic solvers
src/filming/                     imported cameras, actor model, VI and baseline algorithms
src/planners/baselines.jl        seeded initialization and baseline dispatch
src/planners/rsp.jl              upstream-scheduler adapter and execution metadata
src/evaluation/srppa.jl          common joint objective, marginals and separate bonuses
scripts/baseline.jl              one fresh baseline at a time
scripts/rsp_pilot.jl             controlled serial/threaded small pilots
data/scenarios/cluster/         original JSON and Blender scene inputs
third_party/                    source references, hashes and BSD notices
test/                           integration, compatibility and SRPPA unit checks
docs/                           import notes, validation and evaluator conventions
results/                        generated local outputs (ignored)
```
