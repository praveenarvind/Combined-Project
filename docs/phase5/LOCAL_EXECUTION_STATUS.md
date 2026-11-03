# Phase 5 infrastructure readiness and resource-limited inventory

The Phase 5 deliverable is the software framework for later user execution on a PC. It is not conditional on finishing the research simulations in Codex. Continue from branch `feature/phase-5-final-evaluation`; the existing Phase 5 implementation, checkpoints and historical reports are preserved.

[RUN_EXPERIMENTS_ON_PC.md](RUN_EXPERIMENTS_ON_PC.md) is the primary installation/run/recovery guide. It recommends WSL2 Ubuntu; native Windows has not been tested. All eight exact historical inputs, complete actor sequences, original four/five robot teams, recovered initial states, camera/motion settings, VI settings, baselines and authoritative joint SRPPA are retained. Neither source repository was modified. Project/Manifest dependency versions are unchanged by this update.

## Implemented controls

- RSP-1..5 only; exact ordered RSP-2/3 enumeration (including empty rounds), ten fixed seeds per RSP-4/5, serial/threaded pairs and saved ordered groups.
- Scenario/planner/K/mode/seed/vector/job-ID selection with transitive reference/equality prerequisites. Extra explicit vectors/seeds use a separate supplemental inventory, remain labeled, and cannot contaminate required-study distributions.
- Inventory/dry-run/progress/resource assessment commands that never load original planning workloads. Default total-cost admission is 300 seconds per experiment; costs include primary, replay, legacy evaluation, independent checks and overhead. Missing or excessive estimates are `skipped_resource_limit`.
- Original execution additionally requires explicit `--run-local`, human local-PDF/source review and a matching local resource calibration. Deliberate unlimited local runs retain the scientific gates.
- Sealed atomic checkpoints, successful-result reuse, failed-only retry, attempt history, interrupted-primary preservation and Linux stale-lock checks. Reboot recovery is documented, with no claim of fsync-based power-loss durability.
- Automatic completed-scene statistics, all tied best/worst groups, CSV/JSON output, PNG/PDF plots, and explicit incomplete-study/synthetic labels. Partial assignment sets never become exhaustive final distributions.

## What was executed

Only metadata operations and lightweight tests are executed in this finalization update. No original full-horizon planner, original sweep, original certification replay, Blender rendering, new resource probe or performance optimization is run. Synthetic results verify the software and are not original filming performance evidence. Earlier measured single-block resource probes remain clearly historical in [EXECUTION_REPORT.md](EXECUTION_REPORT.md).

See [LOCAL_VALIDATION.txt](LOCAL_VALIDATION.txt) for actual validation outcomes and the CI link. All retained tests remain available through `Pkg.test()`; CI selects bounded groups so individual checks stay under five minutes.

## Complete original-study inventory under the provisional budget

The required inventory remains **2,996 primary executions / 1,518 quality configurations / 2,988 certification replays / 27,720 VI calls**. The complete per-ID inventory with exact groups/seeds, component estimates, status and reason is [resource-limited-inventory.csv](resource-limited-inventory.csv). [local-cost-summary.json](local-cost-summary.json) records the reference calibration/hash and assumptions. These are scheduling estimates, not new experimental observations.

| Scenario | Original N / frames | Completed here | `skipped_resource_limit` | Other blocked | Conservative estimated total hours |
| --- | ---: | ---: | ---: | ---: | ---: |
| cluster | 4 / 60 | 0 | 240 | 1 | 232.9 |
| cross_mix | 4 / 100 | 0 | 240 | 1 | 999.3 |
| four_split | 4 / 100 | 0 | 240 | 1 | 838.1 |
| priority_runners | 5 / 150 | 0 | 596 | 1 | 8,157.2 |
| priority_speaker | 5 / 60 | 0 | 596 | 1 | 1,387.6 |
| split_and_join | 4 / 80 | 0 | 240 | 1 | 619.7 |
| spreadout_group | 4 / 80 | 0 | 240 | 1 | 619.7 |
| track_runners | 5 / 150 | 0 | 596 | 1 | 7,433.0 |
| **Total** | — | **0** | **2,988** | **8** | **20,287.5** |

Every VI-based experiment exceeds 300 seconds under the reference model. Formation has no VI and is estimated at 70–161 seconds including cache-based marginal validation and overhead, but all eight Formation cases remain blocked by the pending human paper comparison (and require a fresh greedy normalization reference). All original execution is reserved for the user's PC regardless of apparent affordability here.

The estimate uses the preserved 106.1-second Cluster block / 58.9-second Bellman calibration, scales VI/checks by state count and caches by states/actors, includes both primary and replay costs, and applies a 2× workload allowance plus 60 seconds per job. No threaded speedup is assumed. This conservative capacity plan (~845 equivalent sequential days on the reference host) is not a measured study runtime, confidence interval or guaranteed upper bound. The old report's smaller central estimate is preserved as a historical model, not silently replaced with new measurements. Estimated base output remains ~0.964 GB; backups/retries/plots add storage. Peak memory for larger/threaded original cases is unmeasured.

## Remaining scientific work for the PC

Supply/read/hash the actual paper, document comparisons and unresolved differences, generate a new reviewed catalog and inventory, calibrate locally, inspect costs, and explicitly choose the long runs you can sustain. Start with synthetic checks, then Cluster references/RSP-1, selected paired configurations, and full scenes only as resources permit. The guide provides every requested matrix/selection command without Julia source edits. Full-horizon convergence checks remain mandatory; longer scenes may fail the unchanged max-90-iteration VI policy and must not be admitted by changing settings silently.

No original quality distributions, normalized quality claims, global best/worst partitions, speedup conclusions or theoretical guarantees are asserted. Absence of original measurements is an intentional execution boundary, not an unfinished infrastructure implementation. R-IRSP and new theory remain out of scope.
