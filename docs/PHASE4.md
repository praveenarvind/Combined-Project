# Phase 4: controlled benchmarking and performance analysis

Base: merged Phase 3 main `a991909`. Phase 3 final-commit Actions run
https://github.com/praveenarvind/Combined-Project/actions/runs/41540743413 and
merge Actions run https://github.com/praveenarvind/Combined-Project/actions/runs/41542783805
were verified successful from the GitHub website. The API remains separately blocked.

## Explicit cases, not automatic matrix expansion

```sh
julia --threads=4 --project=. scripts/benchmark.jl --config=configs/benchmarks/initial-study.toml
# Estimate only; executing requires --run.
taskset -c 0-3 julia --threads=4 --project=. scripts/benchmark.jl \
  --config=configs/benchmarks/initial-study.toml --run --diagnostics \
  --output=results/phase4-four-thread
taskset -c 0-3 julia --threads=1 --project=. scripts/benchmark.jl \
  --config=configs/benchmarks/one-thread-control.toml --run \
  --output=results/phase4-one-thread
```

Each `[[case]]` specifies scenario, robots, horizon, original `start_frame` (default
1), initial-state seed, partition seed, repeats and planner tags. Supported tags:
`greedy`, `multiround`, `myopic`, `myopic_threaded`, `assignment`,
`formation_idealized`, and `rsp2_serial/threaded`, `rsp4_serial/threaded`,
`rsp8_serial/threaded`. Greedy is required in each case for paired normalization.
Cases are deliberately enumerated and capped at 100 measured VI calls by default;
large runs require an explicit configuration/budget change and user review.

The initial four-thread study has 94 measured VI calls; the one-thread control has
30. Warmup, separate diagnostic passes, final legacy scoring and validation add
cost. Calibration measured ~8.49 GB cumulative allocation for two robots/two
frames but ~0.97 GB process peak RSS, fitting the 32 GiB environment. The bounded
study keeps teams <=5 and measured horizons <=3; a separate one-robot/eight-frame
convergence check is not a full simulation. Estimated runtime is several minutes
per worker configuration, not a full Cartesian matrix.

Cluster is the first case. `split_and_join` and `priority_speaker` JSON inputs are
copied exactly from filming commit `42f97540ff002651822a9bbd617bff3d68ab93e2` with
SHA-256 entries in third_party/SOURCES.toml. No solutions or extra render assets
are imported. A configured frame window selects exact original actor rows in
order; it does not interpolate or change their poses/weights. Paired planners
share the same loaded scenario, initial-state vector and camera. Team count and
frame-window overrides are explicit, with original counts/ranges/input hashes
recorded. The original view-cone override, disabled cutoff test and movement
rules remain unchanged.

## Instrumentation boundary and fidelity

Only opt-in measurement hooks wrap existing calls in the imported C source:
prior-coverage construction, reward-cache initialization, VI, and path extraction.
They call the original function exactly once and return its value. No Bellman
backup, reward, camera geometry, action enumeration, tie breaking, VI limit or
baseline update rule changes. The original A/B repositories and generic scheduler
remain untouched. Non-diagnostic runs have no active stage context; diagnostic
contexts are task-local and block-owned. Repeated multi-round calls retain separate
per-robot histories. Tests compare profiled/unprofiled/parallel trajectories and
scores and retain all previous regression checks.

Primary timing and diagnostic passes are separate. Process-wide @timed counters
provide cumulative allocation and GC time across all workers. Final legacy
objective allocation/GC/CPU/wall counters are separately measured and excluded
from planning metrics. Full solver wall time remains available. `allocated_bytes`
is cumulative allocation, not live RAM. Peak RSS belongs to the whole process,
including warmup; it is not falsely assigned to one planner.

Diagnostic passes capture stage wall intervals, optional sampling stacks and
returned policies for an independent Bellman check after timing. Serial stage
allocation/GC deltas are attributable to nonoverlapping process windows. In
threaded diagnostics they are null because windows overlap. Worker wall times
must not be summed into parallel elapsed time. Sampling stacks cover the solver
(including its identifiable legacy-score phase), not post-run validation; stack
samples, especially parked threads, are not CPU-utilization percentages.

`outside_block_wall_seconds` is planning elapsed time outside the union of block
intervals. It is an observed dispatch/bookkeeping/barrier residual, not pure
scheduler CPU cost. `completion_skew_wait_proxy_seconds` sums the gap between each
used worker's last completion and its round's last completion; it estimates a
waiting opportunity, not directly measured OS parking. A separate no-op control
runs the unchanged scheduler with zero-work blocks to bound dispatch/tracing cost.
Hardware cache/bandwidth counters are unavailable here, so specific memory-system
contention cannot be uniquely identified from these counters alone.

## Controls and validation

BLAS threads are one. Julia workers are selected at process startup (initial study:
1 and 4). The controlled launches use the same CPU affinity 0–3 within the allowed
0–4 set and unchanged four-CPU quota. Effective affinity, quota, memory limit,
worker count and source/input hashes are saved. No other study/test process is run
concurrently on this machine during measurements. This is not an exclusive-host
claim. Full GC occurs before every run by default, outside the timer; GC stays
enabled and GC occurring inside planning is included. `gc_policy="natural"` is an
explicit alternative, not an implicit global change.

Compilation is warmed with conditioned/unconditioned RSP prefixes 0:7,
concurrent work, baseline model types and diagnostic branches. Planner execution
order rotates by repetition. Installation, input loading, assignment generation,
root trace preallocation, scoring, validation, rendering and file serialization
are outside planning timing. Within-block coverage/cache/VI/path work and
instrumentation are included. Cold CI runs are labeled `ci_functional_validation`
and cannot be used by the performance plotting script.

Every solution receives authoritative joint SRPPA and separate legacy/bonus fields.
Initial states, horizon/depth, legal motion and Phase 2 marginal differences are
checked; repeated runs replay exactly, and serial/threaded RSP pairs must have
identical trajectories and scores. Formation is separately labeled
`idealized_reference_unconstrained`; its different starts/motions are never
claimed feasible under the VI constraints. Assignment ignores priors despite its
original serial wrapper; its logical information depth is 1 and RSP round fields
are null. Multi-round greedy keeps N sweeps and N^2 VI calls/dependency stages.
Myopic has information depth 1 even in serial execution. No logical-round metric
is presented as measured speedup.

A diagnostic policy is certified by an independent all-state Bellman backup with
the unchanged reward/transition/discount. Residual <=1e-6 is required. The library
does not expose iteration count, so it remains null instead of being invented.
`scripts/convergence_check.jl` checks a one-robot, eight-frame instance separately.

## Output and statistics

`results.csv` contains raw quality/normalization, configured/occupied rounds,
logical depth, VI calls, wall/CPU/GC/allocated bytes, paired serial speedup,
redundancy, assignments and feasibility. `run.json` adds full configurations,
initial states, exact actor frame ranges/hashes, source revision/digest, trajectories,
traces, diagnostic stages, certificates and summaries. Speedup is matched serial
RSP wall time / threaded RSP wall time, not greedy time / RSP time.

Empirical redundancy is `[sum_i F({trajectory_i}) - F(X)] / N`, not the theoretical
worst-case redundancy bound. Raw per-run values and descriptive means/SDs are
reported. Quality repetitions are collapsed within initial/partition seed conditions;
confidence intervals require at least ten independent initial seeds and use a
5,000-draw initial-seed cluster bootstrap. Partition seeds and timing repeats are
nested, not falsely counted as independent scene samples. The initial study has two partition seeds for the five-robot condition but
one initial condition per matched case: its CI fields are explicitly null. Three
timing repeats provide descriptive SD, not publication-ready uncertainty claims.

Optional standalone PNG/PDF plots use requirements-plots.txt:

```sh
python scripts/plot_benchmarks.py results/phase4-four-thread/run.json \
  results/phase4-one-thread/run.json results/phase4-plots
```

Measured evidence and a proposed larger matrix are in
[PHASE4_RESULTS.md](PHASE4_RESULTS.md). No full-scale run, R-IRSP, theoretical guarantee,
Blender rendering or Phase 5 is authorized by this phase.

## Reproduce controls, validators and exports

CPU numbering/availability varies by host; `taskset -c 0-3` above describes the
actual Linux launches here. Select and record a suitable allowed subset elsewhere.
Julia dependencies and installation are unchanged; four new direct dependencies
(Profile, Statistics, SHA, TOML) are Julia standard libraries. External manifest
package versions/content remain unchanged.

```sh
OPENBLAS_NUM_THREADS=1 taskset -c 0-3 julia --threads=4 --project=. scripts/scheduling_control.jl
OPENBLAS_NUM_THREADS=1 taskset -c 0-3 julia --threads=1 --project=. scripts/scheduling_control.jl
OPENBLAS_NUM_THREADS=1 taskset -c 0-3 julia --threads=4 --project=. scripts/convergence_check.jl
julia --threads=4 --project=. test/benchmark_output.jl results/phase4-four-thread/run.json
julia --threads=1 --project=. test/benchmark_output.jl results/phase4-one-thread/run.json
julia --threads=4 --project=. test/benchmark_pair_output.jl results/phase4-four-thread/run.json results/phase4-one-thread/run.json
python scripts/export_benchmark_summaries.py results/phase4-four-thread/run.json results/phase4-four-thread/summary.csv
python scripts/export_benchmark_summaries.py results/phase4-one-thread/run.json results/phase4-one-thread/summary.csv
python -m pip install -r requirements-plots.txt
MPLCONFIGDIR=/tmp/filming-mpl python scripts/plot_benchmarks.py results/phase4-four-thread/run.json results/phase4-one-thread/run.json results/phase4-plots
```

Do not run tests/other planning jobs concurrently with measured study processes.
The H=8 script is convergence-only; its cold timing must not be used as performance
evidence. The final Actions workflow runs all 11 planner tags on a cold N=1,H=2
case, then freshly replays greedy/RSP-2 serial in a one-thread process and validates
cross-process equality. These CI runs are explicitly labeled functional validation;
they are not included in performance plots or the initial-study statistics.
