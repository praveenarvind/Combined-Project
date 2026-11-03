# Partition study: how many RSP partitions are enough?

This guide covers the partition study for Randomized Sequential Partitions
(RSP, Corah & Michael 2021) on the multi-drone multi-actor filming problem
(Hughes et al. 2024):

1. [What the study does](#1-what-the-study-does)
2. [How to run it, step by step](#2-how-to-run-it-step-by-step)
3. [Output files](#3-output-files)
4. [The generated graphs](#4-the-generated-graphs)
5. [Results and analysis](#5-results-and-analysis)
6. [How the code works](#6-how-the-code-works)

---

## 1. What the study does

The study measures how the number of sequential planning steps n_d affects
RSP's SRPPA reward on the nine scenarios of Hughes et al., keeping everything
else exactly as in the paper:

- **Scenarios:** the nine scenes from the paper (`cluster`, `cross_mix`,
  `four_split`, `heavy_mixing`, `priority_runners`, `priority_speaker`,
  `split_and_join`, `spreadout_group`, `track_runners`).
- **Robots:** the paper's team sizes (4 robots, or 5 for the two `priority_*`
  scenes and `track_runners`). The robots start at the paper's own starting
  states, which are the first states of the solutions bundled in
  `experiments/<scenario>/greedy/solution.json`. All planners start from these
  same states, and nothing is randomized.
- **Planning:** robots plan the whole scene at once with an unlimited camera
  range, as in the paper.

Each RSP partition assigns every robot to one of the n_d steps; steps may be
empty. Robots in step k plan knowing the decisions of every robot in steps
1…k−1, and nothing about robots in their own step or later. Tested partitions:

| planner | partitions tested | tests per 4-robot scene | tests per 5-robot scene |
|---|---|---|---|
| RSP-1 | the only partition (everyone in step 1); checked against myopic | 1 | 1 |
| RSP-2 | **every** assignment of robots to steps (2ⁿ) | 16 | 32 |
| RSP-3 | **every** assignment of robots to steps (3ⁿ) | 81 | 243 |
| RSP-4 | **every** assignment of robots to steps (4ⁿ) | 256 | 1,024 |
| RSP-5 | **every** assignment of robots to steps (5ⁿ) | 625 | 3,125 |

In total there are **19,149 tests**, and nothing goes above RSP-5. Under RSP,
each robot picks its step uniformly at random, so every assignment is equally
likely. The mean over all tests of an n_d is therefore the **exact expected
value** of RSP-n_d, not an estimate.

**Distinct planner graphs.** A partition's result depends only on its planner
graph: the non-empty groups of robots in step order. Empty steps and the step
numbers do not matter, so `step1={1,2} step2={3,4}` and
`step2={1,2} step5={3,4}` are the same graph. The 19,149 partitions form only
**2,073 distinct graphs**: 75 per 4-robot scene and 541 per 5-robot scene.
The script plans each graph once and records the result for every partition
that builds it. To check that this is exact, it also plans **300 randomly
chosen other partitions again, independently**. All 300 gave identical
trajectories (`verification.csv`).

## 2. How to run it, step by step

All commands run from the repository root
(`MultiDroneMultiActorFilming/`). They use the `airlab` Docker image, which
provides Julia 1.8 and the `MDMA` package.

**Step 1: build the image (once).**

```bash
docker-scripts/build      # or: docker build -t airlab .
```

**Step 2 (optional): check that the fast planner matches the paper's code.**
This confirms that the SRPPA evaluation and the planners reproduce the
original implementation and its bundled solutions.

```bash
docker run --rm -v $(pwd):/airlab -w /airlab airlab julia experiments/rsp/validate.jl
```

**Step 3: smoke test (about 1 minute).** This runs 2 scenarios with RSP-1 to
RSP-3 and 20 verification re-plans.

```bash
docker run --rm --memory 8g -e JULIA_NUM_THREADS=8 -v $(pwd):/airlab -w /airlab airlab \
    julia experiments/rsp/run_partitions.jl --quick
```

**Step 4: the full study.** This takes about 85 CPU-minutes, or roughly 15–20
minutes on 8 threads (2,073 planner graphs + 300 verification re-plans). The tests run in parallel on `JULIA_NUM_THREADS`
threads. Keep the thread count at or below the number of cores and give the
container enough memory: about 1–1.5 GB per thread is safe.

```bash
docker run --rm --memory 12g -e JULIA_NUM_THREADS=8 -v $(pwd):/airlab -w /airlab airlab \
    julia experiments/rsp/run_partitions.jl
```

The script prints:
- the baseline SRPPA values
- the number of tests and distinct planner graphs
- progress (`[100/2373]` …)
- the verification result
- the RSP-1 vs. myopic check

**It stops with an error if a re-planned partition differs from its graph's
result, or if RSP-1 differs from myopic.**

**Step 5: statistics and graphs (about 1 minute).**

```bash
docker run --rm --memory 4g -v $(pwd):/airlab -w /airlab airlab \
    julia experiments/rsp/plot_partitions.jl
```

**Step 6: read the results.**
- Open `experiments/rsp/results/partitions/summary.md` for every statistics
  table, including the worst and best partition of each scenario.
- The graphs are the PNG files in the same folder.

**Step 7 (optional): look at one partition robot by robot.** For example:

```bash
docker run --rm --memory 4g -v $(pwd):/airlab -w /airlab airlab \
    julia experiments/rsp/robot_breakdown.jl split_and_join 1
```

**Note on file ownership.** Containers run as root, so the files they write
are owned by root. Fix this with `sudo chown -R $USER experiments/rsp`.

**Inside an interactive container** (`docker-scripts/start`), drop the
`docker run … airlab` prefix and run `julia experiments/rsp/<script>.jl` from
`/airlab`.

## 3. Output files

Everything is written to `experiments/rsp/results/partitions/`.

| file | contents |
|---|---|
| `tests.csv` | **one row per test** (19,149 rows); columns below |
| `baselines.csv` | greedy, multi-round greedy, myopic and assignment from the paper starts |
| `rsp1_check.csv` | RSP-1 vs. our myopic planner and vs. the paper's bundled myopic solution |
| `verification.csv` | 300 partitions planned again independently, compared with the result recorded from their planner graph |
| `summary_pooled.csv` | statistics per n_d over all scenarios |
| `summary_by_scenario.csv` | statistics per scenario and n_d, with the worst and best partition |
| `summary_by_nonempty_steps.csv` | tests grouped by how many steps were actually used |
| `summary.md` | all of the above as Markdown tables |
| `*.png` | graphs (section 4) |
| `run.log` | console output of the full run |

Columns of `tests.csv`:

| column | meaning |
|---|---|
| `test_id` | running index |
| `scenario`, `num_robots` | scene and team size |
| `planner`, `num_partitions` | `RSP-k` and its n_d = k |
| `partition` | step of each robot, in robot order: `2,1,1,3` means robot 1 is in step 2, robots 2 and 3 are in step 1, and robot 4 is in step 3 |
| `groups` | the same partition as groups of robots per step, including empty steps, e.g. `step1={2,3} step2={1} step3={4}` |
| `graph` | the planner graph: non-empty groups in step order, e.g. `{2,3}{1}{4}` |
| `evaluated` | `true` for the test that ran the planner for this (scenario, graph) |
| `result_from_test` | `test_id` of that test (equal to `test_id` when `evaluated`) |
| `nonempty_steps` | number of steps that contain at least one robot |
| `sequential_steps` | longest chain in the planner graph, i.e. the number of rounds robots must wait for each other (equal to `nonempty_steps` for RSP) |
| `srppa` | SRPPA view reward of the executed trajectories over the whole scene |
| `ratio_greedy` | `srppa` / sequential greedy from the same starts |
| `ratio_myopic` | `srppa` / myopic from the same starts |
| `gap_closed` | (srppa − myopic) / (greedy − myopic): the share of the benefit of coordination that RSP recovers (0 = myopic, 1 = greedy) |
| `distributed_cost` | empirical cost of ignored decisions (Corah & Michael eq. 14), described in section 6 |
| `serial_time` | total single-robot planning time (s), measured for the graph |
| `parallel_time` | distributed planning time: the critical path of the measured solve times through the planner graph (s), measured for the graph |

## 4. The generated graphs

| file | what it shows | how to read it |
|---|---|---|
| `ratio_by_scenario.png` (+ `ratio_by_scenario_legend.png`) | One panel per scenario. Each dot is one tested partition (all of them). Red diamond = mean over partitions. Lines: black = greedy (1.0), green dashed = multi-round greedy, purple dotted = myopic. | The vertical spread of the dots is the spread over partitions; the diamond is the expected result. |
| `ratio_pooled.png` | All scenarios pooled per n_d: mean ± std (band), worst case (red ▼), best case (green ▲), and the mean of each scenario (gray lines). | How the expected value and the worst case improve with n_d. |
| `gap_closed.png` | Mean share of the greedy-vs-myopic gap that RSP recovers, per scenario (thin lines) and over all tests (thick black). | Normalizes away the fact that coordination matters more in some scenes than in others. |
| `ratio_by_nonempty_steps.png` | RSP-2 to RSP-5 tests grouped by the number of steps actually used. | Shows that the result depends on how many groups the robots end up in, not on n_d itself. |
| `histogram_exhaustive.png` | Distribution of the results of every RSP-2, RSP-3, RSP-4 and RSP-5 partition; red line = mean (the exact expectation). | Shape of the distribution: the left tail is the partitions where every robot landed in the same step. |
| `loss_vs_ignored_redundancy.png` | One point per distinct planner graph, colored by its number of groups: loss relative to greedy against the cost of the decisions it ignored (both normalized by greedy SRPPA). | Tests whether the quantity in RSP's guarantee predicts the actual loss. |
| `steps_and_time.png` | Mean number of sequential steps per n_d (with greedy for reference) and mean distributed planning time per n_d. | The cost side of the trade-off. The times are measured with 8 tests running in parallel, so compare them only with each other. |

## 5. Results and analysis

### 5.1 Sanity checks

**RSP-1 is exactly the myopic planner.** With one step, every robot plans
without seeing any other robot, which is the definition of myopic planning.
The trajectories are identical, robot by robot and frame by frame, to our
myopic planner and to the myopic solutions bundled with the paper
(`rsp1_check.csv`):

| scenario | RSP-1 | myopic (ours) | myopic (paper's bundled solution) | identical trajectories |
|---|---|---|---|---|
| cluster | 269.915 | 269.915 | 269.915 | yes |
| cross_mix | 313.414 | 313.414 | 313.414 | yes |
| four_split | 209.223 | 209.223 | 209.223 | yes |
| heavy_mixing | 512.668 | 512.668 | 512.668 | yes |
| priority_runners | 1375.49 | 1375.49 | 1375.49 | yes |
| priority_speaker | 463.55 | 463.55 | 463.55 | yes |
| split_and_join | 176.378 | 176.378 | 176.378 | yes |
| spreadout_group | 153.281 | 153.281 | 153.281 | yes |
| track_runners | 551.447 | 551.447 | 551.447 | yes |

**The baselines reproduce the paper.** Greedy SRPPA from the paper starts
matches Table I of Hughes et al. (×10²): for example cluster 2.80, cross_mix
3.74, priority_runners 17.77 and track_runners 6.98. See the baselines table
in `summary.md`.

**Recording one result per planner graph is exact.** Partitions with the same
planner graph call the single-robot planner on the same robots, in the same
order, with the same inputs. All 300 partitions that were planned again
independently produced trajectories identical to the recorded result
(`verification.csv`). In the earlier run, where all 1,416 RSP-1 to RSP-3
partitions were planned separately, partitions with the same graph also
never differed.

### 5.2 Performance per number of partitions (all scenarios pooled)

![pooled](results/partitions/ratio_pooled.png)

SRPPA as a fraction of sequential greedy. Every RSP row covers every
partition, so the mean is the exact expected value:

| planner | tests | mean | variance | std | worst | best | gap closed | seq. steps | all robots in one step |
|---|---|---|---|---|---|---|---|---|---|
| greedy | 9 | 1.0 | – | – | 1.0 | 1.0 | 1.0 | 4.33 | – |
| multi-round greedy | 9 | 1.0045 | – | – | – | – | – | 19.0 | – |
| RSP-1 (= myopic) | 9 | 0.8121 | 0.00387 | 0.0622 | 0.7544 | 0.9655 | 0.0 | 1.0 | 100% |
| RSP-2 | 192 | **0.9293** | 0.00227 | 0.0477 | 0.7544 | 0.9993 | 0.613 | 1.91 | 9.4% |
| RSP-3 | 1,215 | **0.9551** | 0.00107 | 0.0328 | 0.7544 | 1.0006 | 0.756 | 2.53 | 2.2% |
| RSP-4 | 4,608 | **0.9679** | 0.00072 | 0.0268 | 0.7544 | 1.0063 | 0.826 | 2.95 | 0.8% |
| RSP-5 | 13,125 | **0.9754** | 0.00055 | 0.0233 | 0.7544 | 1.0063 | 0.868 | 3.24 | 0.3% |

Findings:

- **Each extra partition helps, with diminishing returns.** The expected
  ratio rises from 0.812 (myopic) to 0.929, 0.955, 0.968 and 0.975. The
  improvements are +11.7, +2.6, +1.3 and +0.7 points. In terms of the
  coordination gap (how much of greedy's advantage over myopic RSP
  recovers), that is 61%, 76%, 83% and 87%.
- **The spread shrinks with n_d.** The std falls from 0.048 (RSP-2) to 0.033,
  0.027 and 0.023 (RSP-5), and the variance falls by about 4× from RSP-2 to
  RSP-5.
- **The worst case never improves: it is always 0.754 (`four_split`).** For
  every n_d, the worst partition puts all robots in the same step, which is
  exactly myopic. What changes is how likely it is. The probability is
  n_d^(1−n):

  | | RSP-2 | RSP-3 | RSP-4 | RSP-5 |
  |---|---|---|---|---|
  | 4 robots | 1/8 | 1/27 | 1/64 | 1/125 |
  | 5 robots | 1/16 | 1/81 | 1/256 | 1/625 |
  | pooled, measured | 9.4% | 2.2% | 0.8% | 0.3% |

  The share of partitions below 0.85 of greedy falls the same way: 8.3%, 2.0%,
  0.7% and 0.3%.
- **The best case beats greedy by up to 0.63%.** The best partitions of RSP-4
  and RSP-5 put one robot in each step, which is sequential greedy in a
  different robot order. For example, `split_and_join` with order 4, 3, 2, 1
  reaches 1.0063. Sequential greedy is not optimal, and the order matters. 2.4%
  of RSP-4 partitions and 5.0% of RSP-5 partitions beat greedy's fixed order
  1, 2, …, n. Multi-round greedy (1.0045 on average) shows the same headroom.
- **The earlier 10-seed estimate for RSP-4/5 was too optimistic.** The seeded
  run gave 0.978 and 0.979. The exact values are 0.968 and 0.975, because none
  of those 10 seeds drew the unlucky partitions in the left tail. The two
  samples were also correlated: 66 of 90 seed pairs gave RSP-4 and RSP-5 the
  same planner graph. Testing every partition removes both problems.

### 5.3 Per scenario

![every test](results/partitions/ratio_by_scenario.png)

![legend](results/partitions/ratio_by_scenario_legend.png)

Exact mean ratio to greedy. The full tables with variance, std, worst and best
partition (and how many partitions tie for them) are in `summary.md`.

| scenario | robots | RSP-1 | RSP-2 | RSP-3 | RSP-4 | RSP-5 |
|---|---|---|---|---|---|---|
| cluster | 4 | 0.966 | 0.977 | 0.982 | 0.986 | 0.988 |
| cross_mix | 4 | 0.838 | 0.928 | 0.951 | 0.963 | 0.969 |
| four_split | 4 | 0.754 | 0.924 | 0.954 | 0.966 | 0.973 |
| heavy_mixing | 4 | 0.800 | 0.913 | 0.943 | 0.957 | 0.965 |
| priority_runners | 5 | 0.774 | 0.920 | 0.953 | 0.968 | 0.975 |
| priority_speaker | 5 | 0.792 | 0.914 | 0.947 | 0.964 | 0.974 |
| split_and_join | 4 | 0.783 | 0.939 | 0.963 | 0.973 | 0.979 |
| spreadout_group | 4 | 0.813 | 0.923 | 0.947 | 0.959 | 0.967 |
| track_runners | 5 | 0.790 | 0.941 | 0.963 | 0.973 | 0.980 |

![gap closed](results/partitions/gap_closed.png)

- **The ordering is the same in every scenario.** RSP-1 < RSP-2 < RSP-3 <
  RSP-4 < RSP-5 in all nine. The biggest jump is always from RSP-1 to RSP-2.
- **`cluster` is the outlier.** All actors stay together, so even myopic
  robots get 96.6% of greedy and there is little to coordinate. It is also the
  only scenario with partitions that do worse than myopic: 165 tests from 9
  planner graphs, e.g. `{4}{1,2,3}` (0.9626 vs. 0.9655), `{1,2}{3,4}` and
  `{2}{1}{3,4}`. In all of them, the last step holds two or three robots that
  plan without seeing each other. The likely cause is that these robots react
  to the earlier plans in the same way and end up on overlapping views. Partial information can
  be worse than none when the robots that share a step make correlated
  choices.
- **In the other eight scenes, coordination is worth 16–25% of greedy.** The
  share of it that RSP recovers:

  | | RSP-2 | RSP-3 | RSP-4 | RSP-5 |
  |---|---|---|---|---|
  | share of the gap recovered | 55–72% | 70–83% | 77–88% | 81–90% |

- **The dots form horizontal bands.** Each band is a family of partitions
  with the same structure, e.g. "one robot first, three after" or "two then
  two". As n_d grows, the same bands remain, but more of the partitions fall
  in the upper bands.

### 5.4 What matters is how many groups the robots end up in

![non-empty steps](results/partitions/ratio_by_nonempty_steps.png)

| groups (non-empty steps) | mean | std | worst | best | share of RSP-4 partitions (4 robots) | share of RSP-5 partitions (4 robots) |
|---|---|---|---|---|---|---|
| 1 | 0.812 | 0.059 | 0.754 | 0.966 | 1.6% | 0.8% |
| 2 | 0.941 | 0.024 | 0.880 | 0.999 | 32.8% | 22.4% |
| 3 | 0.972 | 0.011 | 0.945 | 1.001 | 56.3% | 57.6% |
| 4 | 0.995 | 0.005 | 0.983 | 1.006 | 9.4% | 19.2% |
| 5 (5 robots only) | 1.000 | 0.002 | 0.997 | 1.005 | – | – |

- **For a given number of groups, the statistics are identical for every
  n_d.** For example, 2-group partitions average 0.941 whether they come from
  RSP-2, RSP-3, RSP-4 or RSP-5 (`summary.md`). The reason is that the same set
  of planner graphs appears, each equally often.
- **Raising n_d helps only by spreading the robots over more groups.** With 4
  robots, RSP-5 cannot use 5 groups, but it puts the robots in 4 separate
  groups twice as often as RSP-4 (19.2% vs. 9.4%). That is why RSP-5 still
  beats RSP-4 in the 4-robot scenes.
- **Four or five groups is essentially greedy.** With one robot per step, RSP
  is sequential greedy in a random order (mean 0.995–1.000). With 4 robots,
  four groups means one robot per step. With 5 robots, it means one pair
  shares a step.

### 5.5 Distribution of outcomes

![histograms](results/partitions/histogram_exhaustive.png)

| | RSP-2 | RSP-3 | RSP-4 | RSP-5 |
|---|---|---|---|---|
| partitions ≥ 0.95 of greedy | 32% | 69% | 84% | 90% |
| partitions ≥ 0.99 of greedy | 3.6% | 4.0% | 19% | 33% |
| partitions > greedy | 0% | 0.1% | 2.4% | 5.0% |
| partitions < 0.85 of greedy | 8.3% | 2.0% | 0.7% | 0.3% |

The distributions are skewed to the left:
- Most partitions sit close to greedy.
- The long thin tail is the all-in-one-step (myopic) partitions.
- The cluster around 0.88 comes from 2-group partitions in the 5-robot scenes
  where one robot plans first and the other four share the second step.

As n_d grows, the mass moves to the right and the tail gets thinner, but it
never disappears.

### 5.6 Ignored redundancy predicts the loss

![loss vs ignored redundancy](results/partitions/loss_vs_ignored_redundancy.png)

RSP's guarantee bounds the loss by the redundancy between robots that cannot
see each other's decisions.
- **Correlation:** over the 2,073 distinct planner graphs, the empirical
  version of that quantity (eq. 14) correlates with the measured loss with
  Pearson r = 0.71. Graphs that leave more redundancy unseen lose more.
- **Ordering by number of groups:** the colors show the same ordering as
  section 5.4. Myopic (1 group) ignores the most and loses 16–25%. Graphs with
  4–5 groups ignore almost nothing.
- **Points at x = 0:** these are full orderings (one robot per step), which
  ignore nothing. They range from 0.992 to 1.006 of greedy, and that
  difference comes only from the robot order.
- **Why the relationship is not exact:** eq. 14 measures what each robot
  thought it added, while the final loss also depends on how later robots
  adapted around it.

### 5.7 Cost: sequential steps and planning time

![steps and time](results/partitions/steps_and_time.png)

- **Sequential steps:** RSP needs on average 1.9 (RSP-2), 2.5 (RSP-3), 2.95
  (RSP-4) and 3.24 (RSP-5) sequential steps. Greedy needs 4.33 and multi-round
  greedy 19. The expected number of steps grows slowly with n_d, because empty
  steps cost nothing.
- **Planning time:** the critical-path time grows with the number of steps,
  from 0.49 s (RSP-1) to 1.62 s (RSP-5). These times were measured with 8
  tests running at once, so they are only comparable with each other and not
  with the greedy baseline, which ran alone.
- **Scaling:** with only 4–5 robots, RSP saves at most 1–3 sequential steps
  per plan. The benefit grows with team size, because the number of steps
  stays at most n_d while greedy needs n. The crowd and tiled scaling
  experiments in `results/report.md` show this with up to 128 robots.

### 5.8 Caveats

- **The scenes are small.** They have 4–5 robots, so RSP-4 and RSP-5 often
  give one robot per step, which is close to greedy. In larger teams the
  groups are larger and the loss for a given n_d is bigger; the crowd
  experiments in `results/report.md` show this.
- **Results come from one set of starting states per scenario.** These are
  the paper's. The spread reported here is over partitions only; different
  starts would add their own spread.
- **Distributed time is simulated.** It is computed from measured
  single-robot solve times, with no communication delays, and measured while
  other tests were running.

### 5.9 Conclusion

On the paper's scenarios, starting states and team sizes, testing every
partition:
- **RSP-1 is exactly the myopic planner.**
- **Every additional partition raises the exact expected result and shrinks
  its spread:** 0.812, 0.929, 0.955, 0.968 and 0.975 of sequential greedy
  (std 0.062, 0.048, 0.033, 0.027 and 0.023), with diminishing returns.
- **The worst case stays at myopic (0.754) for every n_d**, but becomes rare:
  9.4%, 2.2%, 0.8% and 0.3% of partitions.
- **A partition's result depends on how many groups the robots end up in, not
  on n_d itself:** 0.81, 0.94, 0.97, 0.995 and 1.00 for 1–5 groups. A larger
  n_d only makes more groups more likely.
- **For 4–5 robots, RSP-3 to RSP-5 give 95.5–97.5% of greedy in expectation**,
  with 2.5–3.2 sequential steps instead of 4.3.

## 6. How the code works

### 6.1 Files

| file | role |
|---|---|
| `src/mdma_greedy/MDMA_FastPlanning.jl` | scene representation, SRPPA evaluation, exact single-robot planner |
| `src/mdma_greedy/MDMA_Scenes.jl` | loads the paper's scenarios (`hughes_scene`), plus the larger generated scenes |
| `src/mdma_greedy/MDMA_RSP.jl` | the filming problem as a submodular partition problem; planner specs; partitions; planner graphs; `run_planner` |
| `src/solvers.jl` (SubmodularMaximization) | `PartitionSolver`, `solve_dag`, `in_neighbors`, `sequence` |
| `experiments/rsp/run_partitions.jl` | this study: builds every partition, plans each distinct planner graph in parallel, verifies, writes the CSVs, checks RSP-1 = myopic |
| `experiments/rsp/plot_partitions.jl` | statistics, `summary.md` and the graphs |
| `experiments/rsp/robot_breakdown.jl` | per-robot view of one trial |

### 6.2 The objective: SRPPA (Hughes et al.)

Each actor is modeled as a hexagonal prism with 7 faces (6 sides and the top).

1. For a robot at position p with heading h, filming at frame t, a face f with
   center c and normal n contributes a pixel density of
   `|d·h| · (−d·n) / |d|⁴`, where `d = c − p`. It counts only if the actor is
   inside the camera's 90° field of view and the face points towards the
   camera (`detects`, `face_density`).
2. Densities from all robots that see the face in that frame are added up.
3. The frame's reward is `Σ_faces w_f · A_f · √(total density)`
   (`frame_quality`), and SRPPA is the sum over frames (`srppa_series`,
   `srppa_total`).

The square root gives diminishing returns, because a second camera on the
same face adds less than the first. This makes the objective monotone
submodular, which is what greedy and RSP need for their guarantees.

### 6.3 Single-robot planner

Each robot chooses a trajectory over a grid with 8 headings. Each step it can
turn by 45° or keep its heading, and it can move to any cell within 3 grid
units, at most 2 along each axis (`move_offsets`). Given the trajectories of the robots it can see (`priors`):

1. `reward_table` computes, for every state (x, y, heading, t), the robot's
   marginal SRPPA gain given the prior robots' coverage.
2. `plan_on_table` runs **backward induction**: from the last frame back to
   the first, the value of a state is its reward plus the best value
   reachable at the next frame.
3. The best trajectory is then read off forwards from the start state.

This computes exactly the same plans as the paper's value iteration, with the
same tie-breaking (`validate.jl` checks this), but about 1,500× faster.

### 6.4 The filming problem as a partition problem

In `MDMA_RSP.jl`, `FilmingProblem <: PartitionProblem` connects the filming
problem to the SubmodularMaximization framework from MultiAgentSensing:
- Each robot ("block") chooses one trajectory, which is a partition-matroid
  constraint.
- `solve_block(p, robot, selections)` is the single-robot planner given the
  trajectories in `selections`.
- `objective` is SRPPA.

### 6.5 Planner graphs and RSP

A distributed greedy planner is a directed acyclic graph over robots:
robot i plans after, and conditioned on, its in-neighbors. `solve_dag` visits
robots in a topological order (`sequence`) and calls `solve_block` for each
with the decisions of its `in_neighbors`.

A partition `[s₁, …, sₙ]` (robot i in step sᵢ) becomes a graph through
`PartitionSolver`: the in-neighbors of robot i are all robots in steps
1…sᵢ−1. Special cases:

| partition | planner |
|---|---|
| `[1, 2, …, n]` | sequential greedy (`greedy_planner`) |
| `[1, 1, …, 1]` | myopic (`myopic_planner`) = RSP-1 |
| random `sᵢ ∈ 1…n_d` | RSP-n_d |

The partition code (`MDMA_RSP.jl`) supports both random and predetermined
partitions:

```julia
# RSP with a new random partition for every plan (seeded through run_planner)
rsp_planner(3)

# RSP with a fixed, predetermined partition: robots 2 and 3 in step 1,
# robot 1 in step 2, robot 4 in step 3
rsp_planner(3; partition = [2, 1, 1, 3])

# The partition a seed produces, recorded so it can be reported and replayed
random_partition(MersenneTwister(seed), num_robots, num_partitions)

# Every assignment of n robots to n_d steps (n_d^n of them), in lexicographic order
all_partitions(num_robots, num_partitions)

# Groups per step: [2, 1, 1, 3] => [[2, 3], [1], [4]]
partition_groups(partition, num_partitions)
```

`planner_graph` uses `spec.partition` when one is given and otherwise draws
`random_partition(rng, n, n_d)`. The fixed partition is checked to have one
entry per robot, with steps in 1…n_d. `run_partitions.jl` always passes the
partition explicitly, so the recorded `partition`/`groups` columns are exactly
the partitions that were evaluated.

### 6.6 Running one test: `run_planner`

`run_planner(scene, spec, starts)` plans the whole scene in a single epoch:
1. It builds the `FilmingProblem` from the starts.
2. It builds the planner graph and calls `solve_dag`.
3. It times every single-robot solve.
4. It returns the trajectories and a record of the epoch: objective, number
   of sequential steps (longest chain in the graph), serial time,
   critical-path time and distributed cost.

The same function also supports receding-horizon replanning, which the
scaling experiments use; with a fixed partition, the same partition is used
in every plan.

`graph_timing` computes the two cost metrics:
- **Sequential steps:** the depth of each robot, defined as 1 + the largest
  depth among its in-neighbors.
- **Distributed planning time:** the time at which each robot finishes, i.e.
  its own solve time + the latest finish time among its in-neighbors, with
  the maximum taken over robots.

### 6.7 Empirical cost of ignored decisions

`distributed_planning_cost` (Corah & Michael, eq. 14) goes through the robots
in planning order. For each robot, it compares:
- the gain the robot thought it added, given only its in-neighbors, and
- its true gain given every robot that planned before it.

The sum of the differences is the redundancy the partition made robots
ignore. Myopic ignores the most and greedy ignores none.

### 6.8 The study script and statistics

**`run_partitions.jl`:**
1. Loads each scenario and the paper's starting states, and checks the team
   size against `HUGHES_NUM_ROBOTS`.
2. Runs the four baselines.
3. Builds the 19,149 `PartitionTest`s with `all_partitions(n, n_d)` for
   n_d = 1–5. It labels each with its planner graph (`planner_graph_key`:
   non-empty groups in step order, e.g. `{2,3}{1}{4}`).
4. Picks the first test of each (scenario, graph) to be planned. It also
   picks 300 other tests at random (`MersenneTwister(2026)`) to be planned
   again for verification.
5. Runs those 2,373 plans on a thread pool. Each worker takes the next plan
   from an atomic counter.
6. Writes one row per partition, copying the result of its graph's planned
   test (`evaluated`, `result_from_test`).
7. Checks that every verification plan has exactly the same trajectories as
   its graph's result, and that RSP-1 matches myopic and the bundled
   solutions. It stops with an error otherwise.

The library still supports random partitions (`random_partition`,
`rsp_planner(n_d)`); the scaling experiments use them, drawing a new
partition every time the robots replan.

**`plot_partitions.jl`:**
- Groups tests by scenario and n_d, by n_d alone, and by the number of steps
  used.
- For each group, computes the mean, variance, std, worst (min) and best (max)
  of the SRPPA ratio and records the worst and best partition.
- Reports the number of distinct graphs, the verification result and the
  correlation between ignored redundancy and loss.
- Draws the graphs.

**Pooled statistics** take every test with equal weight. Because 5-robot
scenes have more exhaustive partitions (32 vs. 16, 243 vs. 81), the summary
also reports the mean of the per-scenario means, which weights scenarios
equally. The two differ by less than 0.002 (RSP-5: 0.9754 vs. 0.9744).
