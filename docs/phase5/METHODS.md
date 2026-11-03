# Phase 5 final-study methods and execution

The latest main is Phase 4 merge `38bafbc`. Phase 5 lives on
`feature/phase-5-final-evaluation`. Both original repositories remain read-only.
The fidelity audit is [SCENARIO_FIDELITY.md](SCENARIO_FIDELITY.md), with machine
readable evidence and exact recovered starting states in
[scenario_catalog.json](scenario_catalog.json).

## Mandatory gates

Every original scenario currently has `fidelity_status="blocked"`: the paper is
not accessible through the live network policy, so the mandatory source/paper
comparison is unfinished. Counts and historical starting states are established
from Git history, saved artifacts and read-only Blender inspection. These source
findings do not establish all published conditions. Apply the saved network
additions for `arxiv.org`/`export.arxiv.org`, retrieve/version/hash the paper and
compare its table, grid/units, motion, sensor, priorities, VI and initialization
protocol before changing the audited catalog to verified. Record the PDF SHA-256,
version and section/table evidence in the catalog's `paper` object. Only mark a
scenario verified after resolving its discrepancies. The final runner also requires
a successful calibration and matching inventory/dependency/environment resource
report; changing a status flag alone does not enable execution. No force flag bypasses the
gate. Regenerate a frozen inventory into a new output directory after any catalog
change; completed outputs from an older definition must be preserved.

The final runner supports **RSP-1 through RSP-5 only**. No RSP-6/7/8 execution is
part of this phase, including warmup and current CI commands. Historical Phase 3/4
scripts/configurations remain archival compatibility material and are not invoked.
Active regression cases previously using eight partitions now use five while
retaining the same conditioning/threading/limiting-case assertions.

## Inventory

Five four-robot scenarios and three five-robot scenarios yield:

| Team | Baselines | RSP-1 | RSP-2 exhaustive | RSP-3 exhaustive | RSP-4 seeds | RSP-5 seeds | Distinct quality configurations | Executions, paired modes | VI calls |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| N=4, per scenario | 5 | 1 | 16 | 81 | 10 | 10 | 123 | 241 | 1,944 |
| N=5, per scenario | 5 | 1 | 32 | 243 | 10 | 10 | 301 | 597 | 6,000 |
| All eight | 40 | 8 | 176 | 1,134 | 80 | 80 | **1,518** | **2,996** | **27,720** |

Baselines run once per scenario. Each RSP configuration runs serial and threaded
in a four-thread Julia process, with one timing observation per mode. There are 13,860 primary and 13,860 certification-replay VI calls, with 2,988
separately identified replays (5,984 total planner invocations). Compilation
warmup adds cost beyond those counts. No matrix of
extra initial states, horizons or team sizes is introduced.

Seeds are exactly **11,22,33,44,55,66,77,88,99,110**, shared across all scenes and
K=4/5. K=2/3 enumerate every vector lexicographically, last robot changing fastest.
K=1 uses the explicit all-ones vector. Empty rounds and equivalent dependencies
remain distinct tests. Seed IDs remain distinct even when assignment vectors
repeat. Every row has a stable quality ID and a unique execution ID. Ordered
`round_groups` includes every configured round, including empty arrays.

## Run and resume

Use Julia 1.8.5 and the committed Project/Manifest. Dates is the only new direct
standard-library dependency; external versions/content are unchanged. All camera,
actor, reward, motion, VI and baseline kernels retain their previous behavior.
`benchmark_plan` now accepts explicit assignments and RSP-1/3/5 tags; it reuses the
same `PartitionSolver`/`solve_dag`. The shared adapter validates label count/range
without regenerating supplied assignments.

```sh
julia --threads=4 --project=. scripts/phase5.jl --inventory --output=results/phase5-final
# Currently reports fidelity-blocked rows and executes nothing:
julia --threads=4 --project=. scripts/phase5.jl --batch --max-jobs=1 --max-seconds=600 --output=results/phase5-final
# After audited fidelity and resource admission, continue bounded batches.
julia --threads=4 --project=. scripts/phase5.jl --summarize --output=results/phase5-final
```

`--max-jobs` bounds attempted jobs, default one. `--max-seconds` is checked between
jobs, including after warmup; it is not a hard interruption of a VI call. Choose a
batch budget using measured per-job estimates. External job termination leaves
an interrupted attempt recoverable. Do not start an unexpectedly long job merely
because its job count is one. No counts/horizons, combinations or validation are
reduced to satisfy a budget.

A same-host directory lock prevents concurrent writers. `--recover-stale-lock`
requires a demonstrably dead PID/start token on the same boot; a live or foreign
owner is refused. `--retry-failed` explicitly revisits failed jobs. Every attempt
keeps start/end timestamps and errors. Successful checkpoints are never rerun or
overwritten. JSON replacement is atomic on Linux; the seal normalizes equivalent
JSON integral numeric encodings. Corruption, altered inventories and changed
implementation/Manifest/Julia/workers stop resume rather than mixing results.

Fresh greedy is the cached normalization reference; its verified score and saved
solution are reused across assignments. Fresh myopic precedes RSP-1. Both RSP-1
modes must match every full myopic trajectory/decision and joint score with empty
conditioning sets before later RSP jobs can run. Every threaded RSP result must
match its exact serial assignment/trajectory/score before a speedup is reported.
A failed correctness check stops the batch and keeps later dependencies pending.

## Timing and validation

BLAS threads are one; worker count, CPU affinity/quota and memory limit are
recorded. Run measured batches without competing local planning/test processes;
use consistent allowed CPU affinity. Warmup uses a clearly synthetic small model
to compile identical model/scheduler/diagnostic types for K<=5; it does not replace
an original-scenario experiment. Final batches cannot disable warmup or replace
the validating executor. Full GC occurs before each timed execution outside the
planning timer, with GC left enabled during planning.

Primary timing runs with detailed profiling disabled and does not retain VI
policies. A separate replay on identical inputs collects policies for independent
Bellman checks and must reproduce the complete primary solution and all scores.
Its ID, status, VI calls and metrics are stored in `validation_run`; its timing is
excluded from primary performance comparisons. Partial primary results are
checkpointed before certification, and failed attempts retain those results.

Planning metrics retain the Phase 4 boundary: cache/prior/VI/path and scheduler
work are timed; final legacy evaluation is separately timed/subtracted. Full
solver time and outer execution time (including scoring/certification and result
conversion) are also recorded. Installation, warmup, rendering and checkpoint
file writes are excluded from planning time. No Blender rendering is performed.

Every successful result preserves full trajectories and initial states, source
revisions/hashes, settings, partitions, VI calls, wall/CPU/allocation/GC counters,
separate joint SRPPA/legacy/heading/stationary scores, redundancy, validation and
status. CSV references the full JSON trajectory checkpoint and its seal. Final
legacy scoring is intentionally not optimized despite its large runtime cost.

The validating executor checks complete robot IDs/horizons, exact initial states,
original legal actions, all earlier-round conditioning sets, Phase 2 marginal
consistency, and independent all-state Bellman residuals for every returned VI
policy. Tolerance/max iterations remain 1e-6/90. No convergence is presumed for a
long horizon. Formation remains an idealized reference: it ignores supplied starts
and VI feasibility, uses its Gaussian phase with seed 2026, and receives common
quality evaluation without inventing feasibility.

## Statistics and figures

Aggregate results are produced only for a scenario with every required outcome.
Incomplete scenarios retain their full status inventory and have no final SRPPA
distribution. One serial observation per quality ID is used; neither threaded
copies nor timing repeats become extra quality samples. All enumerated assignments
and all ten seeds remain included, even with identical trajectories/rewards.

Outputs include mean/median/SD/min/max raw and normalized quality, exact tied
best/worst groupings, occupancy histograms, serial/threaded time distributions,
paired speedup and mean selected-path redundancy per robot. K=2/3 SD is finite
population SD, K=4/5 SD is sample SD; K=1 is one fixed configuration. Statistics
are conditional on one fixed historical start set per scene. No cross-initial-state
or cross-scene confidence intervals are invented. A second grouping reports actual
occupied rounds. Saved summary JSON retains all ties and exact groups.

```sh
python -m pip install -r requirements-plots.txt
MPLCONFIGDIR=/tmp/filming-mpl python scripts/plot_phase5.py results/phase5-final results/phase5-final/figures
```

The plotting script rejects incomplete inventories and synthetic CI data by
default. It generates PNG/PDF quality-versus-K, distributions, time-versus-K,
quality/time, redundancy, exact best/worst grouping tables, scenario heatmaps and
separately labeled idealized Formation baseline plots. Observed min–max shading is
not a CI. Exhaustive and ten-seed results have distinct labels. Full-study figures
cannot be generated yet because the required experiments are blocked.

## Functional CI is separate from research

```sh
julia --threads=4 --project=. -e 'using Pkg; Pkg.test(; julia_args=["--threads=4"])'
julia --threads=4 --project=. scripts/phase5.jl --fixture --inventory --batch --summarize --max-jobs=80 --output=results/phase5-ci
julia --threads=4 --project=. test/phase5_output.jl
MPLCONFIGDIR=/tmp/filming-mpl python scripts/plot_phase5.py results/phase5-ci results/phase5-ci/figures --allow-fixture
```

The fixture is a synthetic 3×3, two-robot/two-frame model with one actor. It runs
all 73 required fixture executions (146 primary + 146 certification VI calls), tests serialization and resume,
and explicitly watermarks its plots. It is not a reduced reproduction of any
original scene, nor evidence of published-scene quality or speedup. CI also
checks enumeration counts, provenance, failures/retries, live locks, corruption,
RSP-1 discrepancy gating and preservation of completed work. The full eight-scene
inventory is generated in CI but never automatically executed there.

## Resource probe and admission

After committing a clean implementation, run the bounded resource probe alone:

```sh
OPENBLAS_NUM_THREADS=1 timeout --kill-after=10s 240s taskset -c 0-3 julia --threads=4 --project=. scripts/phase5_calibrate.jl
python scripts/estimate_phase5.py --inventory=results/phase5-final/inventory.json --calibration=results/phase5-calibration/run.json --output=results/phase5-final
```

The probe solves only robot block 1 from the exact historical **four-robot**, six-
actor, **60-frame** Cluster configuration. It does not change the team count or
horizon in that configuration and does not produce a full-team reward. It checks
all-state Bellman convergence, the complete returned path's original legal moves
and marginal SRPPA. A timeout leaves progress explicitly unvalidated; it is not a
successful experiment or usable resource admission. The hard timeout is outside
the algorithm and does not change VI settings.

`estimate_phase5.py` writes checksummed calibration/resource files alongside the
frozen inventory. Final batches require a successful probe, matching input/code/
Manifest/Julia/workers/BLAS/affinity/quota/memory settings and matching inventory
counts/hashes. Estimates distinguish VI, unchanged legacy-cache rebuilding and
Bellman checks. Runtime scaling is a planning model, not a measured full-study
result; the half/double envelope is not a confidence interval. Peak RSS is measured
only for the probe, not assumed to scale linearly or to validate every scene.

Use the same allowed affinity for future measured batches (0–3 here), for example
`taskset -c 0-3 julia --threads=4 --project=. scripts/phase5.jl --batch ...`.
Review per-job/runtime/disk estimates before starting long batches. No complete
matrix is launched automatically by the probe, estimator, CI or inventory command.
