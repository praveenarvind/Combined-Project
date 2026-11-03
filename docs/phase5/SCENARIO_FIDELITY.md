# Phase 5 scenario-fidelity audit

Upstream HEAD `42f97540ff002651822a9bbd617bff3d68ab93e2`; historical exact JSON commit `0f12ff66597df791fa3840b7b1f7bb4fe724c088`.
Count-changing commit `70d12ca86f9ea840f251617a4ea31f54012dfa2b` (2024-09-11). Phase 4 main merge is `38bafbc`.

The historical JSON files are imported byte-for-byte into `data/scenarios/published/`; Phase 4 inputs are retained. No robot subset is selected and no JSON counts, poses, weights, horizons or FOV arrays are edited.

| Scenario | Historical / HEAD robots | Actors | Full frames | Grid | Feasible-baseline starting states | Fidelity |
| --- | --- | --- | --- | --- | --- | --- |
| cluster | 4 / 5 | 6 | 60 | 20×20 | all four agree, recovered | blocked: paper audit |
| cross_mix | 4 / 5 | 6 | 100 | 29×29 | all four agree, recovered | blocked: paper audit |
| four_split | 4 / 5 | 4 | 100 | 29×29 | all four agree, recovered | blocked: paper audit |
| priority_runners | 5 / 6 | 7 | 150 | 33×33 | all four agree, recovered | blocked: paper audit |
| priority_speaker | 5 / 6 | 10 | 60 | 25×25 | all four agree, recovered | blocked: paper audit |
| split_and_join | 4 / 5 | 4 | 80 | 29×29 | all four agree, recovered | blocked: paper audit |
| spreadout_group | 4 / 5 | 4 | 80 | 29×29 | all four agree, recovered | blocked: paper audit |
| track_runners | 5 / 6 | 6 | 150 | 33×33 | all four agree, recovered | blocked: paper audit |

## Count discrepancy and evidence

The only parsed differences between the historical JSON and HEAD are `num_robots` and one appended `robot_fovs` entry. All actor poses, weights, frame sequences, grid dimensions and other JSON fields match. Each saved feasible baseline has the historical count and full horizon. Their robot IDs are exactly 1:N and their complete initial states match across greedy, multi-round, myopic and assignment.

Read-only Blender 4.3.2 inspection, with auto-execution disabled and no rendering/saving, finds N `uav` camera objects plus the active overview camera. The exporter loops over all `bpy.data.cameras`, so it counts that overview camera as a robot. This establishes the extra-camera mechanism. The historical FOV arrays also include the overview FOV; the VI experiment loader explicitly overrides the camera with a π/2 view cone and cutoff 100. The cutoff test is disabled in the unchanged detector. Formation does not use that sensor to construct its trajectories; common quality evaluation uses the authoritative Phase 2 evaluator.

The scene Blend files are also unchanged between these revisions. The complete `src/mdma_greedy` source tree is identical between the historical input revision and audited HEAD, verified by an empty Git diff. Thus the older JSON is paired with the same filming model/baseline source used by the foundation.

## What is and is not established

Historical feasible starting states are recoverable, so no new initial-state sampling is needed. Exact states, source paths, revisions and hashes for all 40 saved artifacts are in `scenario_catalog.json`. The random generator protocol is uniform integer x/y and one of eight headings, shared between planners. The saved states establish historical states for this source snapshot; no unpublished experiment identity is invented.

Formation ignores those starting states and motion/grid constraints. Its Gaussian random phase is generated with the predeclared seed 2026 for new executions; the historical phase RNG seed is unavailable. It remains an idealized non-equivalent reference. Historical Formation initial states are kept only as audit evidence.

The paper URL returned HTTP 403 under the live environment network policy. Its table, camera/units, horizon and experimental-method text cannot yet be independently compared. The four/five counts agree with the user-provided paper description, but this is not a completed paper audit. Every original scenario is therefore BLOCKED for final experiments. Complete the auditable local-PDF workflow in [RUN_EXPERIMENTS_ON_PC.md](RUN_EXPERIMENTS_ON_PC.md) to finish the human comparison and generate a new reviewed catalog. No force/bypass flag is supplied by the final runner.

Original saved scores and trajectories are not new experimental results. They are used only for provenance and initial-state recovery. Fresh baselines and all requested RSP assignments must still be solved after fidelity is established. This also distinguishes the corrected analytical joint SRPPA comparison from legacy or rendered scores.

## Reproduce this audit

Run `scripts/audit_blend_cameras.py` with Blender in read-only background mode, then run `python scripts/audit_phase5.py --source-root=/path/to/MultiDroneMultiActorFilming --camera-report=/path/to/cameras.json`. The audit reads Git objects at fixed commits and asserts exact input differences, counts, full saved horizons and cross-baseline starting-state equality. It never changes the source checkout or renders frames.
