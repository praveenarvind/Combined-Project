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
