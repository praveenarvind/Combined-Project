# Proposed Phase 2: evaluator correction (not implemented)

The imported `MDMA.objective` sums rewards from independently constructed
single-robot problems with empty prior coverage. Therefore the stored legacy
`Solution.value` does not equal joint SRPPA and includes motion bonuses. Formation
also retains the original constant value 1.0.

A future, separately reviewed change should:

1. Implement one joint evaluator accumulating camera density by actor, face and
   time, then applying face weight × face area × square root(total density).
2. Use that evaluator consistently for solution quality across all baselines;
   preserve legacy values under a distinct name for compatibility.
3. Verify that the single-robot marginal equals the difference in joint quality
   when a trajectory is added, with movement bonuses recorded separately.
4. Test empty selections, weighted actors, duplicate/invalid robot IDs, overlapping
   views, disjoint faces, trajectory ordering and time/length validation. Two
   unit-density views on a unit face contribute sqrt(2), not 2 and not 1.
5. Reconcile camera configuration and rendered metrics explicitly; do not silently
   change the current model or present unweighted rendered scores as identical to
   weighted analytical SRPPA.
6. Recompute scores from fresh validated trajectories, not bundled upstream results.

RSP experiments, R-IRSP and theoretical bounds remain separate later work. This
phase makes no optimality, scalability, parallel speedup or paper-reproduction claim.
