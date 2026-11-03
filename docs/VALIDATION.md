# Phase 1 validation

Executed in the managed environment on 2026-11-02 with Julia 1.8.5.

| Check | Actual result |
| --- | --- |
| Locked dependency installation and precompile | Passed; 81 dependencies precompiled. |
| `julia --startup-file=no --project=. -e 'using Pkg; Pkg.test()'` | Passed: 83 assertions, zero failures/errors. |
| Scenario hash, camera override and deterministic initial states | 10/10 assertions passed. |
| Fresh greedy, myopic, multi-round, assignment and formation solves; trajectory constraints and serialization | 65/65 assertions passed. Formation is tested as its original idealized reference, not against VI motion constraints. |
| Legacy reward bonuses and camera APIs | 4/4 assertions passed. |
| Reused generic submodular core | 4/4 assertions passed. |
| Standalone `scripts/baseline.jl --smoke` | Passed; fresh greedy trajectories produced. |
| Pinned Docker build with mounted proxy CA | Passed. |
| Default Docker command with `--network=none` | Passed; fresh greedy solve without network access. |
| Source integrity audit | Generic solver byte-identical; imported VI, reward, assignment, formation and camera/detection algorithm bodies retained. All 15 source/configuration provenance hashes verified against upstream. |
| Original A/B working trees | Unchanged and clean. |

Native and Docker smoke runs used the same input: original cluster actor poses for
frames 1–4, all six actors, a 20×20 grid, two robots, seed 2026, view-cone FOV π/2,
configured cutoff 100, and movement distance 3. Both produced legacy value
`12.048784128677479`; each greedy VI solve reported residual zero on iteration 2.
This value is **not** corrected joint SRPPA and is not a comparison against paper
results. Fresh generated outputs remain under ignored `results/`; no precomputed
outputs were imported.

The original cluster input remains five robots and 60 frames. Full-size cluster,
all-experiment sweeps, rendering, RSP experiment runs, R-IRSP, performance studies,
and theoretical analysis were **not run**. The old POMDP helper packages emit
deprecation warnings; their versions were preserved. The GitHub Actions workflow
is supplied but its remote execution is not claimed as validated here.

The container installs its own dependencies from the lockfile; it does not mount
the native depot or source repositories. Its base is the official Julia 1.8.5
image pinned by digest. The Docker runtime check used no network, display or GPU.

At this Phase 1 checkpoint, the evaluator correction was unimplemented. Formation's
placeholder score and unconstrained initialization, disabled view-cone cutoff,
and the VI iteration cap remain documented upstream limitations.


# Phase 2 validation

Phase 2 starts from merged Phase 1 commit `d8d14e0` on main and adds only the
analytical evaluation/reporting layer, tests and documentation. Dependency locks,
scenario files, baseline dispatch, original filming source and generic solvers
are unchanged relative to that main branch. A and B remain untouched.

The same local commands used by CI are run for this phase: locked installation
plus `Pkg.test()`, a new `scripts/baseline.jl --smoke` solve, and
`test/score_output.jl` to validate the saved schema and legacy-reader compatibility.
Hosted GitHub Actions status is not claimed without API access. The Phase 1 Docker
checks above are historical; no additional rendering or full experiment is run.

Fresh two-robot, four-frame cluster results (seed 2026, all six original actors):

| Baseline | Joint SRPPA | Stored legacy value | Heading bonus | Stationary bonus |
| --- | --- | --- | --- | --- |
| Sequential greedy | 10.759347621832795 | 12.048784128677479 | 0.04 | 0.01 |
| Myopic | 10.574407402437688 | 12.247753996351435 | 0.06 | 0.02 |
| Multi-round greedy | 10.763891665120859 | 12.025423984038488 | 0.04 | 0.01 |
| Assignment | 10.574407402437688 | 6.244223214199251 | 0.06 | 0.02 |
| Original Formation | 12.672356825940978 | 1.0 | 0.12 | 0.06 |

These are tiny integration checks, not performance experiments or comparative
claims. In particular, Formation does not enforce the same initial/motion
constraints; its legacy value remains a placeholder. The separate heading and
stationary bonuses count actual recorded transitions, not legacy self-transitions.

For every freshly generated baseline and each robot, tests compare:

- independent per-face marginal SRPPA;
- the difference of joint scores with/without the robot;
- the unchanged single-robot marginal-view calculation.

For VI baselines, tests additionally relate full-path marginal to transition
rewards after subtracting bonuses and restoring the fixed initial-frame view.
The greedy legacy value is regression-checked against Phase 1. Input reordering
leaves joint scores unchanged, and scoring does not mutate stored legacy values.
Numerical fixtures cover sqrt(2) overlapping views, disjoint faces, distinct actor
weights, multiple time steps and empty selections; malformed trajectories and
invalid numeric inputs are rejected.


Final local CI results: **174/174 assertions passed in `Pkg.test()`**, plus
**8/8 assertions passed in `test/score_output.jl`** after a new CLI smoke solve.
The test groups passed 15 density-reduction, 27 model-validation, 10 scenario,
114 fresh-baseline integration, 4 legacy-camera/reward and 4 reused-core assertions.
No failures, errors, skipped checks or expected failures were reported. VI solves
in the reduced workload reached residual zero; this does not establish convergence
for unrun full-horizon scenarios. The existing dependency deprecation warnings
remain; no package versions were changed.


# Phase 3 adapter validation

Phase 3 starts from Phase 2 merge commit `6ccc3c8` on main. The final four-thread
`Pkg.test()` run passed **582 assertions**: the prior 174, 45 assignment/conditioning
checks, 4 independent-cache checks, and 359 fresh VI/replay/limiting-case/marginal
checks. The existing standalone greedy smoke and its 8 score-schema assertions
also passed. An initial test-only heterogeneous-result container issue was fixed
before the passing run; it did not require changing the imported algorithms.

A five-robot/two-frame CI pilot freshly ran greedy and RSP-2/4/8 in both modes.
The CI workflow now launches four Julia threads, runs this pilot and its metadata
checks, and uploads the small raw artifact. Hosted Actions status is not claimed
without GitHub API access. Full-scale experiments and rendering remain unrun.

The three-seed five-robot pilot (21 measured runs) and supplementary two-robot
smoke (7 measured runs) both completed from clean implementation commit `337a156`.
Their raw CSVs, replay metadata, trajectories, trace summaries and interpretation
are committed under docs/pilots/phase3 and documented in PHASE3_RESULTS.md. Timing definitions and replay
instructions are in PHASE3.md. Original source, baseline dispatch, camera/motion
settings, dependency locks and Phase 2 objective code remain unchanged.


Final Phase 3 pilot/output checks: five-robot artifact **247/247** assertions;
supplementary two-robot artifact **85/85**; latest CI pilot artifact **85/85**.
Every pilot solution additionally passed movement and independent Phase 2 marginal
assertions before serialization. Per-run VI counts were five for main/CI and two
for supplementary runs. Four warmups (20 VI calls) preceded each workload and were
excluded. The first main timing pass was discarded after a warm-up coverage gap
was found; only the fully warmed rerun is committed. Reward/trajectory correctness
was unchanged. Normalized scores and recorded conditioning/barrier traces were
independently checked from the persisted artifacts.

Main five-robot mean planning seconds (serial/threaded) were 15.381/20.123 for
RSP-2, 15.438/23.748 for RSP-4, and 15.197/25.890 for RSP-8; fixed-order greedy
was 15.147 seconds. These observations establish no speedup on this host for this
tiny workload. Raw values and sample SDs are retained. All source repositories,
original solver/VI/camera/motion code, baseline behavior, Phase 2 score definitions
and dependency locks remain unchanged.

# Phase 4 controlled benchmarking validation

Executed 2026-11-02/03 UTC with Julia 1.8.5. Primary measurements use clean source
commit `3f646d655fa90e82bcd459e8c65f2dec36c8091d`; measured source digest and input
hashes are saved in every run. No precomputed trajectories were loaded. The
[Phase 4 report](PHASE4_RESULTS.md) contains actual timing/quality tables, figures,
raw CSV/JSON and a proposed larger study. Original A/B checkouts remain untouched.

| Check | Actual result |
| --- | --- |
| Full four-thread `Pkg.test` | 625 assertions passed, zero failures/errors; all 582 earlier assertions retained plus 43 new checks. |
| Explicit frame windows and scenario provenance | 18 configuration/provenance assertions passed, including all three exact input hashes. |
| Profiled/unprofiled/threaded equivalence, VI certificates and multi-round histories | 25 assertions passed. |
| Fresh bounded four-thread study | 29 primary plans, 94 observed VI calls; all structural/marginal/feasible movement checks passed. |
| Fresh matched one-thread control | 6 primary plans, 30 calls; all checks passed. |
| Saved-output schemas, counters, normalizations, occupancy and marginal validation | 267 assertions (four-thread) and 56 (one-thread) passed. |
| Separate-process deterministic replay | 51 assertions passed, including full trajectory/score/input/settings equality. |
| Profiled policy convergence | Ten policies, zero independent Bellman residual over 9,600 states each. |
| Longer horizon check | N=1,H=8: zero Bellman residual over all 25,600 states; movement/marginal validation passed. Cold timing is not used as a benchmark. |
| No-op scheduler control | 100 warmed repetitions for RSP-2/4/8 serial/threaded in a four-thread runtime and serial in a one-thread runtime; all nine controls completed. |
| Summary CSV export and plots | Actual JSON summaries exported; three PNG/PDF comparison figures generated and inspected using Python 3.12.14, NumPy 1.26.4, Matplotlib 3.7.5. |
| GitHub Actions implementation | [41549004992](https://github.com/praveenarvind/Combined-Project/actions/runs/41549004992) succeeded on `3f646d6`. Final workflow additionally checks fresh cross-runtime cold CI replay. |

The local summary log is [benchmarks/phase4/VALIDATION.txt](benchmarks/phase4/VALIDATION.txt).
Source measurement hooks delegate the original calls; no camera, reward, movement,
VI setting or baseline update rule changed. All normalized quality uses Phase 2
joint SRPPA; legacy value and motion bonuses remain separate. Formation is an
idealized differently constrained reference. CIs are null for this study's single
initial condition per matched case; timing SD is descriptive. Full matrices,
Blender, R-IRSP, theoretical guarantees and Phase 5 were not run.

# Phase 5 validation and incomplete-study status

Phase 4 main merge `38bafbc` was confirmed before creating the new feature branch.
The [Phase 5 report](phase5/EXECUTION_REPORT.md) explicitly records **0/2,996**
required original-scene primary configurations completed. All 2,988 certification
replays are also blocked by the unfinished paper audit; no original quality
statistics or research figures are manufactured.

The local full package suite passed 807 assertions before three added SD/resource
gate checks. With the final timing/certification separation, the focused Phase 5
suite passed 190 assertions; the retained regression suite has 625, for an active
815-assertion package suite validated by Actions. A fresh standalone synthetic CLI
run passed 1,050 saved-output assertions and completed 73 primary configurations,
72 certification replays and 292 VI calls. Its eight PNG/PDF plot pairs are
explicitly synthetic functional checks.

Two full-input single-block resource probes completed, preserving the historical
four-robot Cluster input and all 60 frames. The final clean-source probe (`b11f120`)
measured 106.071 s, 249.313 GB cumulative allocation, 0.629 GB peak RSS and zero
Bellman residual over 192,000 states. It is not a complete team experiment.
Marginal discrepancy was 7.11e-14. Original moves/full 60-state path passed.

The actual checksummed resource-admission test passed; requesting the original
matrix then executed zero jobs and preserved all 2,996 fidelity-blocked statuses.
Every historical scenario input is copied exactly from `0f12ff6`, with per-file
commit/hash provenance. Source model code and Blend files are unchanged through
foundation HEAD `42f9754`. Historical feasible starting states agree across all
four original feasible baselines in every scenario.

[VALIDATION.txt](phase5/VALIDATION.txt) records local outputs. The resource estimate
includes 13,860 primary plus 13,860 certification VI calls and is explicitly an
extrapolation, not measured full-study performance. No RSP>5, full matrix,
R-IRSP, theoretical guarantee or Blender rendering was run in Phase 5.
