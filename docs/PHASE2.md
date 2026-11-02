# Phase 2: Joint SRPPA evaluator correction

This phase adds `src/evaluation/srppa.jl` without modifying imported filming or
submodular source, model parameters, actor inputs, baseline algorithms or VI.
The public scoring API is shared by all baselines. It evaluates freshly generated
trajectories; it does not read or trust upstream precomputed scores.

## Objective

For trajectories X, camera contribution c is evaluated using the original
`detectTarget` and `compute_camera_coverage`, with `configs.sensor` unchanged:

    F(X) = sum_{time, actor, face} weight * area * sqrt(sum_{robot in X} c(robot))

The camera sum is inside the square root; the sum over faces/time is outside.
Both model-based and known-density entry points use one common reduction. Actor
weights and face areas stay outside the square root, matching the original
`face_view_quality` formula. Repeated physical views receive diminishing returns;
this is not binary or maximum coverage. Negative/nonfinite densities, areas and
weights are rejected rather than clamped or ignored.

The evaluator supports actual per-actor face counts; absent padded faces contribute
zero. The imported planner's seven-face assumption is unchanged. The configured
camera is used directly; cutoff behavior, occlusion assumptions and geometry are
not silently changed.

## API

- `joint_srppa(configs, selections_or_solution)` returns pure analytical quality.
- `joint_srppa(contributions, weights, areas)` accepts numerical fixtures with
  dimensions (time, actor, face, robot) and weights/areas of shape (time, actor, face).
- `marginal_srppa(configs, prior, (robot_id, trajectory))` computes the sum of
  per-face increments independently of subtracting total scores. Candidate IDs
  must be absent from prior selections.
- `motion_bonuses(configs, selections_or_solution)` returns separate
  `heading_bonus` and `stationary_bonus` on actual consecutive transitions.
- `legacy_value(solution)` returns the unchanged stored `solution.value`.
- `evaluate_solution(configs, solution)` returns a named tuple with `joint_srppa`,
  `legacy_value`, `heading_bonus` and `stationary_bonus`. It never mutates a solution
  or combines these fields into an ambiguous total.

Partial and empty selections are allowed. Robot IDs must be unique and in
1:num_robots. Every trajectory must contain horizon finite MDPState positions,
with depths exactly 1:horizon and matching state horizons. Actor/face geometry and
weights must be finite, and weights/areas nonnegative. Robot inputs are sorted by
ID before accumulation so input order does not change results.

These are structural/geometry checks, not feasibility claims: the original
Formation baseline can use continuous, off-grid positions and unconstrained
motions. Its camera views can still receive the same analytical quality score.
No projection onto the grid or new motion constraint is applied by the evaluator.

## Bonus and time conventions

Pure SRPPA uses frames 1:H. VI assigns view reward to the action/next state and
therefore optimizes frames 2:H; the initial-frame view is a constant for each
fixed initial state and prior selection. For one candidate trajectory:

    full-path marginal SRPPA
      = initial-frame marginal view
        + sum(actual VI transition rewards)
        - heading-preservation bonuses
        - stationary-position bonuses

Motion bonuses count only the H-1 recorded transitions. Heading contributes 0.02
when unchanged; position contributes 0.01 when both coordinates are unchanged.
The legacy objective calls reward(state,state), counting both bonuses once per
state irrespective of actual motion. Its value also sums independent robot
qualities instead of the joint quality. Assignment uses its own legacy objective;
Formation keeps its placeholder 1.0. None of these legacy values is relabeled as
corrected SRPPA.

## Output compatibility

`scripts/baseline.jl` writes score schema version 2. The old `value` key is retained
and labeled `value_kind="legacy"`; explicit `legacy_value`, `joint_srppa`,
`heading_bonus`, and `stationary_bonus` fields prevent mixing metrics. The run
metadata contains the same named scores. Original MDMA solution readers can still
read value/elements. Quality comparisons must use `joint_srppa`.

## Numerical checks

Two unit-density contributions on one unit-weight, unit-area face score
`sqrt(2) = 1.4142135623730951`, not 2. Disjoint unit-density faces score 2.
Weight 3 and area 2 give `6sqrt(2) = 8.485281374238571`. Empty robot selections
score 0. Multiple times/actors are reduced independently.

Tests additionally compare joint differences, independent per-face marginals and
the unchanged single-robot reward on fresh reduced-cluster solutions from every
baseline. Fresh validation outcomes are recorded in VALIDATION.md.

## Remaining boundary

The rendered image metric is unweighted and is not claimed to equal weighted
analytical SRPPA. The disabled view-cone cutoff, idealized Formation behavior,
legacy values and VI convergence settings remain unchanged and documented.
RSP experiments, R-IRSP, the full experimental matrix, rendering, performance
studies and theoretical guarantees are not implemented or run in this phase.
