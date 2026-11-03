# Phase 5 execution report — original study incomplete

> Historical execution snapshot before the local-execution update. The current Phase 5 deliverable is the completed software framework, not completion of the research matrix. See [PC guide](RUN_EXPERIMENTS_ON_PC.md) and [current readiness/resource inventory](LOCAL_EXECUTION_STATUS.md). Measurements below are preserved historical evidence; their old estimates/statuses do not represent a new run.

**No required original-scenario experiment has been executed: 0 of 2,996 primary configurations.** All 2,988 certification replays also remain unexecuted. Every required assignment and seed is present with status `blocked`; the mandatory paper comparison cannot yet be completed because the live network policy returns HTTP 403 for arXiv. No partial or synthetic data are presented as original-scene research results.

## Fidelity findings

[The audit](SCENARIO_FIDELITY.md) traces the count discrepancy to `70d12ca`: the exporter counts all camera data blocks, including the overview camera. Read-only Blender inspection finds N UAV cameras plus one overview camera in every scene. Exact historical JSON at `0f12ff66597df791fa3840b7b1f7bb4fe724c088` has the four/five counts reported by the user from the paper. These files are imported without selecting robot subsets or editing JSON. Their actors, weights, full frame sequences and grids match HEAD; only robot counts and one appended FOV differ. The filming source tree and scene Blend files are unchanged between that input revision and HEAD `42f97540ff002651822a9bbd617bff3d68ab93e2`.

All four feasible saved baselines agree on complete initial states/headings in every scene. Those source-artifact states are frozen with hashes; old trajectories/scores are not fresh results. Exact identity with the published historical run cannot be claimed before the paper/provenance comparison. Formation retains exceptional initialization and unconstrained behavior; its historical phase RNG seed is unavailable, so new executions use the documented Gaussian phase with seed 2026 and remain an idealized non-equivalent reference.

## Complete inventory; every original case outstanding

| Scenario | Robots / actors | Full frames | RSP-2 / RSP-3 assignments | Quality configurations | Primary executions | Primary + replay VI calls | Completed / blocked |
| --- | --- | --- | --- | --- | --- | --- | --- |
| cluster | 4 / 6 | 60 | 16 / 81 | 123 | 241 | 972 + 972 | 0 / 241 |
| cross_mix | 4 / 6 | 100 | 16 / 81 | 123 | 241 | 972 + 972 | 0 / 241 |
| four_split | 4 / 4 | 100 | 16 / 81 | 123 | 241 | 972 + 972 | 0 / 241 |
| priority_runners | 5 / 7 | 150 | 32 / 243 | 301 | 597 | 3,000 + 3,000 | 0 / 597 |
| priority_speaker | 5 / 10 | 60 | 32 / 243 | 301 | 597 | 3,000 + 3,000 | 0 / 597 |
| split_and_join | 4 / 4 | 80 | 16 / 81 | 123 | 241 | 972 + 972 | 0 / 241 |
| spreadout_group | 4 / 4 | 80 | 16 / 81 | 123 | 241 | 972 + 972 | 0 / 241 |
| track_runners | 5 / 6 | 150 | 32 / 243 | 301 | 597 | 3,000 + 3,000 | 0 / 597 |
| **Total** | — | — | **176 / 1,134** | **1,518** | **2,996** | **13,860 + 13,860** | **0 / 2,996** |

Five baseline primary solutions are retained once per scenario and reused as references. Every RSP configuration has serial/threaded primary executions. Certification replays have separate IDs nested in the inventory/results and are excluded from quality sample counts and primary timing. There are **5,984 planner invocations** and **27,720 VI calls** before warmup. K=2/3 include every K^N vector, including empty/equivalent effective rounds. K=4/5 each use exactly 11,22,33,44,55,66,77,88,99,110; duplicate groupings are retained. RSP-6 and above are never executed in Phase 5 or its active CI.

Every ID, seed, assignment, ordered group list (including empties), input hash, exact recovered starting state and status is in [inventory.json](inventory.json) and [inventory.csv](inventory.csv). [completion.json](completion.json) identifies all incomplete scenes. The status reason is the unresolved paper audit; the resource estimate is an additional scheduling/capacity consideration.

## Timing separated from certification

Primary planning disables detailed profiling and retains no VI policies. Independent certification replays the same unchanged planner and exact assignment, outside the primary timing, collects every policy for an all-state Bellman check, and must match the complete primary trajectories and all scores. Both passes, their VI calls and costs are recorded. Primary results are checkpointed before certification; failures preserve partial results and retry history. Successful complete experiments are never repeated. This prevents validation-related policy retention from changing the heap during primary timing.

## Actual full-input resource probe

The final resource probe solves only **robot block 1** from the exact historical **four-robot**, six-actor Cluster configuration using **all 60 frames**. It is not a full-team solution or RSP quality result. Team count, actor sequence, priorities, grid, camera, motion and VI settings are unchanged. It completed within a 240-second external process cap, with no competing local planning/test job. Input loading and synthetic code-path warmup precede timing.

Clean measured commit `b11f1208cf576cb84da6d049432d49721aa74aa3`; source digest `0a19bb7969db0bcdd8bb5a8f391d5d77f6d22849e0dcaf4e76160e20c0fe2088`. Julia 1.8.5, four Julia threads, BLAS1, CPU affinity 0–3, four-CPU quota, 32 GiB memory limit. The block itself is serial; this is not a parallel-speedup or exclusive-host measurement.

| Measurement | Actual result |
| --- | --- |
| Completed blocks / VI calls | 1 / 1 |
| Planning block wall | 106.071459 s |
| Cumulative allocation | 249,312,689,540 bytes (249.313 GB) |
| GC time | 14.047382 s |
| Whole-process peak RSS, including warmup/validation | 629,321,728 bytes (0.629 GB) |
| Grid storage, summarysize | 19,940,896 bytes |
| Independent Bellman check | 58.948094 s; 192,000 states; residual **0** |
| Full 60-state path and original legal actions | Passed |
| Maximum marginal discrepancy | 7.11e-14 |
| Full-team SRPPA / normalized quality | **Not computed; no team solution** |
| Stage: prior_coverage | 0.000345 s; 314,080 bytes |
| Stage: reward_cache | 1.268565 s; 993,897,712 bytes |
| Stage: value_iteration | 104.799660 s; 248,318,357,888 bytes |
| Stage: path_extraction | 0.000349 s; 18,688 bytes |

Raw data are in [resource-calibration.json](resource-calibration.json). An earlier source-version probe is retained separately as [resource-calibration-first.json](resource-calibration-first.json); it measured 102.520 s and zero residual. These are two resource probes, not independent filming-quality observations. Neither completes Cluster or validates all H=100/150 policies. Cumulative allocation is not live RAM.

## Resource extrapolation — not measured full-study runtime

The [estimator](../../scripts/estimate_phase5.py) scales measured VI/Bellman work by nonterminal state count and cache work by grid/frames/actors. It includes both primary and certification planner passes, unchanged legacy scoring in both passes, and all mandatory trajectory/marginal/Bellman validation. The legacy objective rebuilds a full reward cache at every robot path state. Comparable VI sweep counts and no threaded speedup are assumed. Assumptions and components are explicit in [resources.json](resources.json) and [resources.csv](resources.csv).

| Scenario | Estimated total execution hours |
| --- | --- |
| cluster | 114.5 |
| cross_mix | 497.7 |
| four_split | 417.0 |
| priority_runners | 4,073.6 |
| priority_speaker | 688.8 |
| split_and_join | 307.8 |
| spreadout_group | 307.8 |
| track_runners | 3,711.5 |
| **Total** | **10,118.7 h (~422 sequential days)** |

This is an order-of-magnitude plan, not an observed scalability result. A half/double envelope is illustrative, not a CI. Warmup, retries, checkpoint I/O and host variation add cost; assignment cache costs may differ. Larger-scene peak memory is unmeasured; the probe does not establish a memory upper bound. Estimated raw output is **964,468,000 bytes (~0.964 GB)** plus additional retries/plots.

This is unsuitable as an automatic short-session job on the current four-CPU host. After fidelity is resolved, execution needs sustained compute scheduling and bounded checkpoints, with resource validation before the longest jobs. No algorithms, legacy score calculations or validation were weakened to fit a budget. Cross-process/HPC sharding would need an explicit execution layout; the current runner serializes writers to one output directory.

## Validation and implemented analysis

The earlier full local package run passed 807 assertions; three additional SD/resource-gate checks passed. After timing/certification separation, the focused Phase 5 suite passed **190 assertions**, together with the 625 retained regression assertions forming an active **815-assertion** package suite. Implementation [Actions 41567768357](https://github.com/praveenarvind/Combined-Project/actions/runs/41567768357) passed on `b11f120`, including the full suite. The final reporting commit is checked separately. Standalone saved-output checks run on a fresh synthetic CLI inventory; all **1,050 saved-output assertions passed**, recorded in VALIDATION.txt.

The synthetic 3×3/two-robot/two-frame fixture completes all **73 primary executions, 72 certification replays and 292 VI calls**. Its RSP-1/myopic, primary/certification and serial/threaded complete trajectories/scores match. It is not a reduced original-scenario reproduction or performance result. Tests cover enumeration, empty/occupied rounds, predetermined labels, seed replay, provenance, bounded resume, preserving completed files, failures/retries, live locks, corruption, discrepancy gates and statistics.

The real calibration/resource gate is tested against checksums/settings. The full original inventory still executes **zero** jobs under the fidelity gate. Eight PNG/PDF figure pairs are tested on the complete synthetic fixture, with SYNTHETIC CI ONLY titles and representative visual inspection. Plotting rejects incomplete inventories and synthetic data by default. No original-scene quality distribution, best/worst partition result, speedup or publication figure is produced from incomplete data.

The analysis pipeline emits requested mean/median/SD/min/max, normalized scores, exact tied best/worst assignments, occupancy groups, primary serial/threaded time distributions, paired speedup and redundancy only for complete scenes. It preserves every assignment/seed; certification and execution-mode copies are not extra quality observations. Exhaustive SD is finite-population SD; ten-seed SD is sample SD. A singleton sample SD is null. No cross-initial-state or cross-scene CIs are invented.

## Required results pending

| Result | Status |
| --- | --- |
| Independent published-condition audit | Paper access blocked; source history/counts/starts recovered |
| RSP-1/myopic equality on original scenarios | **0/8**; synthetic correctness verified |
| Original RSP-2 / RSP-3 exhaustive configurations | **0/176**, **0/1,134** |
| Original RSP-4 / RSP-5 seed configurations | **0/80**, **0/80** |
| Fresh original baseline configurations | **0/40** |
| Original statistical summaries and research figures | Not produced; completion gates reject incomplete scenes |
| Quality/grouping/redundancy/speedup conclusions | Not established |

No monotonic quality improvement, filming-quality retention, full-scene speedup, scalability or theoretical guarantee is claimed. Phase 4 pilots and original saved outputs are not substituted for this historically matched full-horizon study. R-IRSP and rendering were not implemented or executed. [METHODS.md](METHODS.md) describes installation, fixed seeds, checkpoints, strict gates and reproduction.
