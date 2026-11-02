# Phase 3 pilot results

Fresh measurements from implementation commit `337a156`, Julia 1.8.5, four Julia
threads, one BLAS thread, and cgroup CPU quota `400000 100000` (four CPU-equivalents).
Source working tree was clean during both workloads. Input hashes, source digest,
exact settings, all trajectories and traces are retained in the raw JSON artifacts.
These are small integration pilots, not full-scale or paper-reproduction results.

## Five original robots, three original frames

All six actors, original 20×20 grid/camera/motion parameters; initial-state seed
2026 is fixed. Partition seeds are 11, 22 and 33. Both execution modes replay each
assignment and produce identical trajectories and Phase 2 scores. Every recorded
solution passed movement and marginal-SRPPA consistency checks. Greedy is freshly
solved for every repeat with the same initial states and actor inputs.

Reward SD and timing SD below are sample SDs over three runs. Reward samples are
three partition seeds; serial/threaded pairs are not treated as independent quality
samples. The normalized score is joint SRPPA divided by the corresponding fixed-order
greedy joint SRPPA. All algorithms make exactly five VI calls per recorded run.

| Planner | Configured rounds | Occupied rounds | Joint SRPPA mean ± SD | Mean normalized SRPPA | Serial planning s mean ± SD | Threaded planning s mean ± SD | VI calls/run |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Sequential greedy | 5 | 5 | 10.730734237 ± 0.000000000 | 1.000000 | 15.147 ± 0.034 | — | 5 |
| RSP-2 | 2 | 2 | 10.728517814 ± 0.014339685 | 0.999793 | 15.381 ± 0.204 | 20.123 ± 0.537 | 5 |
| RSP-4 | 4 | 3–4 | 10.725809757 ± 0.022352952 | 0.999541 | 15.438 ± 0.417 | 23.748 ± 1.190 | 5 |
| RSP-8 | 8 | 4–5 | 10.738443442 ± 0.035708614 | 1.000718 | 15.197 ± 0.567 | 25.890 ± 1.859 | 5 |

Timings exclude four warm-up solves (20 VI calls), installation, initial-state and
assignment generation, rendering, final legacy scoring, Phase 2 scoring/validation,
and serialization. Full upstream solver time and separately measured legacy-score
time are retained in CSV. See [PHASE3.md](PHASE3.md) for the complete timing boundary.
The first timing pass had incomplete conditioned-path warmup; its timings were
discarded. Only the rerun with prefix lengths 0:7 and concurrent/conditioned warmup
is committed here. All trajectory scores matched that earlier correctness run.

Threaded execution was slower on this host for these tiny workloads, despite
verified overlapping planning blocks. No speedup or scalability guarantee is
established. Allocation/GC and scheduler costs have not been profiled here.
Configured rounds are not guaranteed occupied. Five robots cannot occupy eight
rounds; singleton occupied partitions offer no same-round concurrency. RSP may
score above or below fixed-order greedy because robot ordering and ignored
same-round decisions vary; no monotonic reward claim follows from these samples.

## Assignments and per-seed rewards

Robot IDs run from 1 to 5 in each assignment vector. The assignments are iid
uniform round labels from a dedicated MersenneTwister, not balanced partitions.

| Partition seed | Configured rounds | Assignments by robot ID | Occupied rounds | Joint SRPPA | Normalized SRPPA |
| --- | --- | --- | --- | --- | --- |
| 11 | 2 | [2, 2, 1, 1, 2] | 2 | 10.712121493082 | 0.998265473 |
| 11 | 4 | [3, 4, 1, 2, 4] | 4 | 10.699998791478 | 0.997135756 |
| 11 | 8 | [5, 7, 2, 3, 8] | 5 | 10.702599705252 | 0.997378135 |
| 22 | 2 | [2, 2, 1, 2, 1] | 2 | 10.738715239864 | 1.000743752 |
| 22 | 4 | [3, 4, 2, 3, 2] | 3 | 10.738715239864 | 1.000743752 |
| 22 | 8 | [6, 7, 4, 5, 4] | 4 | 10.738715239864 | 1.000743752 |
| 33 | 2 | [1, 2, 1, 2, 1] | 2 | 10.734716710113 | 1.000371128 |
| 33 | 4 | [2, 4, 1, 3, 1] | 4 | 10.738715239864 | 1.000743752 |
| 33 | 8 | [3, 8, 1, 5, 2] | 5 | 10.774015381065 | 1.004033381 |

## Supplementary two-robot/four-frame smoke

Seed 11, the same initial-state seed 2026, all six actors. This is a compatibility
check with one observation per mode; no variability estimate is inferred. It is
not used to establish meaningful four/eight-round parallelism.

| Planner | Configured rounds | Occupied rounds | Assignment | Joint SRPPA | Normalized SRPPA | Serial planning s | Threaded planning s | VI calls/run |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Sequential greedy | 2 | 2 | [1, 2] | 10.759347622 | 1.000000 | 9.101 | — | 2 |
| RSP-2 | 2 | 1 | [2, 2] | 10.574407402 | 0.982811 | 8.971 | 12.240 | 2 |
| RSP-4 | 4 | 2 | [3, 4] | 10.759347622 | 1.000000 | 9.526 | 16.729 | 2 |
| RSP-8 | 8 | 2 | [5, 7] | 10.759347622 | 1.000000 | 10.458 | 16.485 | 2 |

## Raw evidence and replay

- Five robots: [raw CSV](pilots/phase3/five-robot/results.csv), [summary CSV](pilots/phase3/five-robot/summary.csv), [metadata and trajectories](pilots/phase3/five-robot/run.json), [trace summary](pilots/phase3/five-robot/trace_summary.csv).
- Two robots: [raw CSV](pilots/phase3/two-robot/results.csv), [summary CSV](pilots/phase3/two-robot/summary.csv), [metadata and trajectories](pilots/phase3/two-robot/run.json), [trace summary](pilots/phase3/two-robot/trace_summary.csv).

Trace summaries derive peak overlapping **planning blocks**, not a claim of CPU
utilization or network concurrency. Each block calls VI once. Preceding-round
completion and exact conditioning sets were also checked from recorded timestamps.
No original precomputed solution was used. Legacy values and actual motion bonuses
remain separate from analytical joint SRPPA in every artifact.

Fixed actor/initial conditions and n=3 partition seeds cannot establish broader
statistical or scaling conclusions. Full experiments, R-IRSP, theoretical bounds,
Blender rendering and Phase 4 remain pending approval.
