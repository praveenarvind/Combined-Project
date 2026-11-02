# Distributed Multi-Drone Filming — Phase 1 foundation

A Julia package based on Hughes et al.'s multi-drone filming implementation.
This phase imports the existing filming model, value iteration, baseline planners,
and a **single copy** of the upstream submodular/RSP scheduling framework. It does
not implement RSP experiments, R-IRSP, evaluator corrections, or theoretical claims.

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
julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
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
under `results/smoke/greedy/`. Outputs are ignored by Git. No precomputed solutions
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
```

Submodular interfaces and existing scheduling functions remain available through
`DistributedFilming.SubmodularMaximization`. Filming internals live in
`DistributedFilming.MDMA`. No `LOAD_PATH` changes or source checkouts are required.

## Docker

```sh
docker build -t distributed-filming:phase1 .
docker run --rm distributed-filming:phase1
docker run --rm distributed-filming:phase1 \
  julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'
```

The default container command runs only the reduced greedy baseline. The base
image is pinned by digest, Julia dependencies by the manifest. Four Julia
precompile workers are configured to limit resource use. No X server or GPU is
required.

For a managed proxy, supply its combined public CA bundle at build time:

```sh
docker build --secret id=proxy_ca,src=/etc/ssl/certs/ca-certificates.crt \
  -t distributed-filming:phase1 .
```

The certificate is mounted only for dependency installation, not copied into the
image. Runtime baseline execution needs no network. A later networked `Pkg` command
in a managed container also needs the current session's proxy/CA configuration.

## Preserved limitations and Phase 2 boundary

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

Phase 2 requires a separately reviewed authoritative joint SRPPA evaluator,
consistent marginal checks, separation of motion bonuses, and tests for overlap,
face weights and order invariance. See [docs/PHASE2.md](docs/PHASE2.md). Those changes
have **not** been implemented here.

Actual executed checks are recorded in [docs/VALIDATION.md](docs/VALIDATION.md).

## Layout

```text
src/DistributedFilming.jl        package entry point
src/submodular/                  reused interfaces and unchanged generic solvers
src/filming/                     imported cameras, actor model, VI and baseline algorithms
src/planners/baselines.jl        seeded initialization and baseline dispatch
scripts/baseline.jl              one fresh baseline at a time
data/scenarios/cluster/         original JSON and Blender scene inputs
third_party/                    source references, hashes and BSD notices
test/runtests.jl                 executable integration and compatibility checks
docs/                           import notes, validation and Phase 2 boundary
results/                        generated local outputs (ignored)
```
