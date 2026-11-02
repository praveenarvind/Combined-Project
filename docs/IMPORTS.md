# Import and compatibility record

All source is from filming commit `42f97540ff002651822a9bbd617bff3d68ab93e2`.
The original submodular framework's sensing reference is
`fe9162adbedb374fa0e9ca4739e398acc4704309`. Both repositories remain untouched.

| Source | Destination / adaptation |
| --- | --- |
| `SubmodularMaximization.jl` | `src/submodular/`; generic interfaces retained; removed eager Python plotting imports and unrelated coverage/tracking/communication application includes. |
| `src/solvers.jl` | Copied byte-for-byte to `src/submodular/solvers.jl`. Includes sequential, myopic, multi-round, partition/DAG/RSP, adaptive and range scheduling. |
| `MDMA_States`, `MDMA_Detection`, `MDMA_SharedTypes` | `src/filming/`; camera, geometry and state definitions retained; unused drawing demonstration omitted. |
| `MDMA_MultiAgent`, `MDMA_Single_Robot` | `src/filming/`; reward, prior coverage, VI, transitions and trajectory extraction unchanged. |
| `MDMA_AssignmentPlanner`, `MDMA_FormationPlanner` | `src/filming/`; baseline algorithms unchanged. |
| `MDMA_Interface` | `src/filming/`; JSON loaders/serialization retained; removed Cairo render call from save. |
| `MDMA_Experiment` | Planner tags and solver dispatch extracted into `src/planners/baselines.jl`; same N-sweep multi-round default and formation construction. Explicit RNGs replace ambient/global initialization. |
| `juliapackages/Project.toml`, `Manifest.toml` | Root Julia environment; retained only the used dependency closure with upstream versions and tree hashes; project identity/hash regenerated. |
| `experiments/cluster/cluster_data.json`, `cluster.blend` | Original scenario inputs; copied byte-for-byte. No original solution/evaluation files. |
| `LICENSE` | Root BSD notice and original notices in `third_party/licenses/`. |

Imports now use package-relative module paths. Unused `Base.parsed_toml` imports
and unused `Test` imports were removed. The single-robot source's assertion-free
import-time testset was omitted so importing the package does not run a fake test.
No reward, camera, movement, VI convergence setting or baseline update rule was
corrected during these adaptations. A headless baseline adapter replaces the
upstream all-experiment runner, shared global starting-state dictionary and
plot/render coupling. There is no second implementation of RSP scheduling.

The full image evaluator, rendering toolchain, experiment sweeps, old results,
notebooks, target tracking, sensor-coverage demonstrations and developer profiling
tools are intentionally not imported. These are not needed to validate filming
planning and would add many unrelated dependencies.

Original-file SHA-256 values and exact revisions are in `SOURCES.toml`. It also
records dependency configuration lineage. The root license preserves the combined
AirLab (2024) and Resilient Intelligent Systems Lab (2020) copyrights.

Julia Pkg normalized OpenSpecFun_jll metadata from version 0.5.5+0 to 0.5.5+2
while retaining git tree `13652491f6856acfd2db29360e1bbcd4565d04f1`. All 117 retained
manifest entries keep their upstream source-tree hashes; all other versions match.

Phase 4 adds only opt-in measurement wrappers around prior coverage, reward-cache
construction, VI and path extraction in imported C source. The delegated calls,
settings and mathematical kernels are unchanged; profiling equivalence and
regression tests cover this boundary. See PHASE4.md. Additional scenario JSON
inputs retain original hashes/revision in SOURCES.toml; A/B remain untouched.
