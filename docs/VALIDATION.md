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

Phase 2's evaluator correction remains unimplemented; see PHASE2.md. Formation's
placeholder score and unconstrained initialization, disabled view-cone cutoff,
and the VI iteration cap remain documented upstream limitations.
