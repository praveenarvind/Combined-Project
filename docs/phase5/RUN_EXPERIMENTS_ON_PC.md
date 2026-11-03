# Run the Phase 5 experiments on a Windows PC

The framework is ready for local execution. Completing the software does **not** require completing the research matrix in Codex. Original-scene performance and quality results remain unmeasured. The eight scenarios, their full horizons, historical initial states, and camera/motion/VI settings are frozen; no faster substitute is used.

Use **WSL2 Ubuntu on Windows**. Native Windows execution has not been tested and is not supported by this guide: CPU timing uses POSIX `clock`, locks inspect Linux `/proc`, hardware provenance reads cgroups/CPU affinity, and checkpoints assume Linux atomic same-directory rename. Julia itself supports Windows, but that does not establish compatibility of this runner. Run Julia, Python and Git inside the same WSL distribution and keep the checkout on its Linux filesystem.

## A. Install once

In **Windows PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-22.04
# Restart Windows if requested, then create the Ubuntu user/password.
wsl --set-default-version 2
wsl --list --verbose
wsl -d Ubuntu-22.04
```

The remaining shell commands are **Ubuntu Bash**, not PowerShell. Install tools and clone:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates tar python3 python3-venv poppler-utils
mkdir -p ~/research
cd ~/research
git clone https://github.com/praveenarvind/Combined-Project.git
cd Combined-Project
git switch main
git pull --ff-only
# Before this feature is merged, use instead:
# git switch --track origin/feature/phase-5-final-evaluation
```

Private repository authentication requires your own GitHub credentials. No source-repository checkouts, Blender, Docker or historical saved outputs are needed for normal execution.

Install **Julia 1.8.5**, preserving the committed `Project.toml` and `Manifest.toml`:

```bash
mkdir -p ~/.local/opt ~/.local/bin
cd /tmp
curl -fLO https://julialang-s3.julialang.org/bin/linux/x64/1.8/julia-1.8.5-linux-x86_64.tar.gz
curl -fLO https://julialang-s3.julialang.org/bin/checksums/julia-1.8.5.sha256
rg 'julia-1.8.5-linux-x86_64.tar.gz$' julia-1.8.5.sha256 > julia-check.sha256 2>/dev/null || grep 'julia-1.8.5-linux-x86_64.tar.gz$' julia-1.8.5.sha256 > julia-check.sha256
sha256sum -c julia-check.sha256
# Continue only if the archive reports OK.
tar -xzf julia-1.8.5-linux-x86_64.tar.gz -C ~/.local/opt
ln -sfn ~/.local/opt/julia-1.8.5/bin/julia ~/.local/bin/julia
export PATH="$HOME/.local/bin:$PATH"
# Add that export line to ~/.bashrc for future terminals.
cd ~/research/Combined-Project
julia --version
```

These commands target x86-64 PCs (`uname -m` should show `x86_64`). Use the corresponding official Julia 1.8.5 Linux build/checksum on ARM; that platform has not been validated here.

Select one thread configuration and keep it fixed for an output directory:

```bash
nproc
lscpu
free -h
export JULIA_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=1
julia --startup-file=no --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --startup-file=no --project=. -e 'using DistributedFilming, LinearAlgebra; @assert VERSION==v"1.8.5"; @assert Threads.nthreads()>=2; BLAS.set_num_threads(1); println("INSTALL_OK Julia=",VERSION," threads=",Threads.nthreads()," BLAS=",BLAS.get_num_threads())'
git diff --exit-code -- Project.toml Manifest.toml
python3 -m venv .venv-plots
source .venv-plots/bin/activate
python -m pip install -r requirements-plots.txt
python -c 'import numpy,matplotlib; print("PLOTS_IMPORT_OK",numpy.__version__,matplotlib.__version__)'
```

Use Python 3.10–3.12 for the pinned plotting dependencies (Ubuntu 22.04 supplies 3.10). `.venv-plots` is ignored by Git. Do not run `Pkg.update()` for this study. A changed Manifest, source implementation, Julia version, thread count or CPU/memory configuration requires a new calibration/output directory. Installation/compilation is separate from measured planning time.

## B. Check the software with lightweight tests

All commands below use synthetic fixtures or retained small unit tests; none executes the original full-scenario matrix. Each group is separately bounded to five minutes. Run them sequentially to avoid competing Julia workloads:

```bash
for group in controls core rsp benchmark phase5; do
  FILMING_TEST_GROUP="$group" timeout 300 julia --startup-file=no --project=. test/runtests.jl || break
done
python -m unittest discover -s test -p test_phase5_tools.py -v
```

Success means every Julia test summary has `Pass == Total`, no `Fail`/`Error`, and Python prints `OK`. `FILMING_TEST_GROUP` only selects test groups; running `Pkg.test()` without it still runs **all** retained tests. The complete suite may take longer than five minutes; the separate commands are the recommended first check. A timeout is a failed/incomplete check, not a pass.

Run the complete **synthetic** CLI integration fixture in a new output directory:

```bash
julia --startup-file=no --project=. scripts/phase5.jl --fixture --inventory --batch --summarize --max-jobs=80 --max-seconds=300 --output=results/phase5-ci
julia --startup-file=no --project=. test/phase5_output.jl
julia --startup-file=no --project=. scripts/phase5.jl --fixture --batch --max-jobs=1 --output=results/phase5-ci
python scripts/plot_phase5.py results/phase5-ci results/phase5-ci/figures --allow-fixture
```

Expected inventory: **73 primary executions, 39 quality configurations, 292 total VI calls** including certification. Completion reports `successful: 73`, `complete: true`; the resume command reports `attempted: 0`. RSP-1/myopic and serial/threaded full paths and scores must match. The saved-output test expects that exact fixture path. Reuse the directory only with unchanged code/environment; preserve old runs and choose a new directory after an implementation change. Synthetic figures are explicitly marked **SYNTHETIC CI ONLY** and are not filming research results. Current CI covers this workflow and the retained tests in separate bounded steps.

## C. Prepare the original study without planning

### Review a locally supplied paper PDF

The repository's source-history audit is complete, but the paper was inaccessible in the cloud. The committed catalog remains blocked. Read [SCENARIO_FIDELITY.md](SCENARIO_FIDELITY.md), then supply the actual Hughes et al. paper PDF locally. Do not edit the original JSON, set fidelity booleans by hand, or use synthetic evidence.

Example Bash command to copy a downloaded PDF from Windows (replace the username/filename):

```bash
mkdir -p results/paper
cp '/mnt/c/Users/YOUR_WINDOWS_USER/Downloads/Hughes2024.pdf' results/paper/Hughes2024.pdf
python scripts/phase5_paper.py prepare --pdf=results/paper/Hughes2024.pdf --review=results/paper/review.json
```

This records the PDF and source-catalog SHA-256 and optionally extracts searchable text to `review.paper.txt`. **It does not verify the paper automatically.** Open the PDF, review JSON and source audit side by side. Fill:

- `paper_version`, reviewer identity and review date.
- Each section's `reviewed: true`, page/section or source-file references in `evidence`, and `differences` (use an explicit explanation even if none found).
- For every scenario, paper-observed robot count, horizon and actor count, with page/figure/section evidence. Use the literal `"not_specified"` for horizon/actors absent from the paper; robot-count comparison is mandatory. Do not manufacture unpublished numerical details.
- `source_conditions_accepted: true` and `unresolved_conflict: false` only after resolving the comparison. Document source-supported facts that the paper does not report. Recovered starts are supported by agreement among four historical feasible baselines, not automatically proof of the exact published run.

Explicitly review the original view-cone approximation versus rendered camera scoring, disabled cutoff test, historical extra overview-camera export, initial-state evidence, and Formation's different feasibility/unknown historical phase seed. Phase 2's corrected analytical joint SRPPA is the common metric; it does not imply exact equality to rendered paper values. An unresolved count/model/input conflict must remain blocked and be investigated before execution.

```bash
python scripts/phase5_paper.py apply --pdf=results/paper/Hughes2024.pdf --review=results/paper/review.json --output=results/paper/verified_catalog.json
```

The apply command rejects missing evidence, changed PDFs/catalogs, mismatching reported numbers, missing scenarios and unresolved conflicts. The resulting **new** catalog embeds your review; the committed catalog and all scenario inputs remain unchanged. This is an auditable human review, not a machine proof of historical identity. Keep the PDF, JSON, extracted text and their hashes with your research archive. If any fact conflicts, do not force acceptance; the framework can stay ready while that scientific comparison is unresolved.

### Freeze and inspect the inventory

Choose the final directory only after review and thread selection:

```bash
export OUT=results/phase5-pc-t4
julia --startup-file=no --project=. scripts/phase5.jl --inventory --catalog=results/paper/verified_catalog.json --output="$OUT"
julia --startup-file=no --project=. scripts/phase5.jl --progress --output="$OUT"
julia --startup-file=no --project=. scripts/phase5.jl --dry-run --scenario=cluster --planner=rsp --rounds=2 --mode=threaded --output="$OUT" > results/cluster-rsp2-plan.json
python -m json.tool results/cluster-rsp2-plan.json | less
```

The immutable inventory has **2,996 primary executions, 1,518 quality configurations, 2,988 separate certification replays, 27,720 total VI calls**. Primary and replay are one experiment for cost budgeting; their timings/counts are separately recorded. No RSP count above five is selected. Initial states/sequences are not resampled.

| Scenario ID | Robots | Actors | Full frames | Ordered RSP-2 / RSP-3 vectors | Primary executions |
| --- | ---: | ---: | ---: | ---: | ---: |
| cluster | 4 | 6 | 60 | 16 / 81 | 241 |
| cross_mix | 4 | 6 | 100 | 16 / 81 | 241 |
| four_split | 4 | 4 | 100 | 16 / 81 | 241 |
| priority_runners | 5 | 7 | 150 | 32 / 243 | 597 |
| priority_speaker | 5 | 10 | 60 | 32 / 243 | 597 |
| split_and_join | 4 | 4 | 80 | 16 / 81 | 241 |
| spreadout_group | 4 | 4 | 80 | 16 / 81 | 241 |
| track_runners | 5 | 6 | 150 | 32 / 243 | 597 |

Inspect metadata without a model solve:

```bash
python - "$OUT" <<'PY'
import json,pathlib,sys
inv=json.load(open(pathlib.Path(sys.argv[1])/'inventory.json'))
print('Executions:',inv['expected_executions'],'Seeds:',inv['seeds'])
for s in inv['catalog']['scenarios']:
    print(s['name'],'N=',s['robots'],'H=',s['horizon'],'input=',s['input_sha256'])
    print('Original starts:',json.dumps(s['initial_states']))
for j in inv['jobs']:
    if j['scenario']=='cluster' and j['configured_rounds'] in (2,4) and j['mode']=='serial':
        print(j['id'], 'seed=',j['partition_seed'],'assignment=',j['assignments'],'groups=',j['round_groups'])
PY
```

Robot labels are in robot-ID order; `[1,1,3,2]` means round 1 has robots 1/2, round 2 robot 4, round 3 robot 3. Empty round lists are retained. Exhaustive RSP-2/3 includes **all K^N ordered vectors**, even empty rounds and equivalent effective schedules. RSP-4/5 each use seeds **11,22,33,44,55,66,77,88,99,110**; duplicate groupings remain separate seed observations. One initial-state condition is used per historical scene.

### Estimate cost and verify your machine

First obtain a **reference-only** estimate, without executing any original workload:

```bash
python scripts/estimate_phase5.py --inventory="$OUT/inventory.json" --calibration=docs/phase5/resource-calibration.json --output="$OUT"
julia --startup-file=no --project=. scripts/phase5.jl --assess-resources --output="$OUT" > "$OUT/preflight-300s.json"
python -m json.tool "$OUT/resources.json" | less
```

`job_costs.csv` has an estimate for every primary-plus-validation experiment. The default **300-second per-experiment** preflight records `skipped_resource_limit` before model loading. Missing estimates also skip. Reasons and estimates appear in `results.csv` and `resource_policy.json`; successful records are never replaced by skips. Dry-run/assessment never executes planning, warmup, calibration or rendering. Reference calibration does **not** authorize running on a different machine/code revision.

The measured reference (older clean implementation, four-CPU Linux host) took **106.1 s** for one Cluster robot block, **58.9 s** for its Bellman check, **0.629 GB** process peak RSS and **249 GB cumulative allocation**. This is neither a full team result nor an upper memory bound. The estimator scales by states/actors, includes original legacy evaluation, both planner passes and all validation, adds a default **60 s overhead per experiment**, then applies a **2× workload allowance**. It assumes no threaded speedup. These estimates are not timing observations, confidence intervals or guaranteed bounds. Check `resources.json` for current totals; the matrix can require many months of equivalent sequential computation on the reference host.

Before actual original execution, calibrate **on your PC**, after paper review. This solves one block from the full four-robot/60-frame Cluster configuration and certifies it. It is deliberately **not** a reduced scenario/team-performance result. Estimate its **total** cost before starting; if 300 seconds is implausible for your hardware, defer it or deliberately permit a longer local run. Example only, using a **600-second estimate** (revise based on your hardware; this is not a promise):

```bash
julia --startup-file=no --project=. scripts/phase5_calibrate.jl --dry-run --estimated-total-seconds=600
# LOCAL PC ONLY: explicit choice to permit a >300-second calibration.
julia --startup-file=no --project=. scripts/phase5_calibrate.jl --run-local --catalog=results/paper/verified_catalog.json --estimated-total-seconds=600 --experiment-limit=unlimited --output=results/calibration-pc-t4
python scripts/estimate_phase5.py --inventory="$OUT/inventory.json" --calibration=results/calibration-pc-t4/run.json --output="$OUT"
```

The resource gate compares code digest, Manifest hash, input hash, Julia version, Julia/BLAS threads, CPU affinity/quota and memory configuration. Do not copy an old calibration to bypass a mismatch. Commit implementation changes first; scientific source must be clean. Source/Manifest changes or different hardware require a new output/calibration. Setup/calibration time is excluded from planner timings but included in capacity planning. No automatic performance optimization is performed.

## D. Run original experiments on your PC

**Only after both review and matching local resource calibration.** The following commands explicitly opt into long local experiments with `--run-local --experiment-limit=unlimited`. They are intended for your PC and were not executed on original scenes by Codex. Keep the 300-second default if you do not want long jobs; those commands will record resource skips instead. Unlimited is not a gate bypass: paper, source, replay and resource checks remain mandatory.

Define a Bash function (redefine in each terminal):

```bash
export OUT=results/phase5-pc-t4
p5() { julia --startup-file=no --project=. scripts/phase5.jl --output="$OUT" "$@"; }
# All run commands below are resumable and reuse successful prerequisites.
# --max-jobs is a ceiling, not the requested number of new quality samples.
```

Inspect the selected workload first; this includes dependency closure:

```bash
p5 --dry-run --scenario=cluster --run-local --experiment-limit=unlimited > "$OUT/cluster-local-plan.json"
```

Commands for each requested scope:

```bash
# 1. Entire original Cluster: all five baselines plus RSP-1..5, both modes.
p5 --batch --scenario=cluster --run-local --experiment-limit=unlimited --max-jobs=241 --max-seconds=86400

# 2. Another original scene (replace with any scenario ID in the table).
p5 --batch --scenario=split_and_join --run-local --experiment-limit=unlimited --max-jobs=241 --max-seconds=86400

# 3. RSP-1 in both modes; greedy/myopic prerequisites are included automatically.
p5 --batch --scenario=cluster --planner=rsp --rounds=1 --run-local --experiment-limit=unlimited --max-jobs=4 --max-seconds=86400

# 4. All 16 ordered Cluster RSP-2 assignments, both modes, plus prerequisites.
p5 --batch --scenario=cluster --planner=rsp --rounds=2 --run-local --experiment-limit=unlimited --max-jobs=36 --max-seconds=86400

# 5. All 81 ordered Cluster RSP-3 assignments, both modes, plus prerequisites.
p5 --batch --scenario=cluster --planner=rsp --rounds=3 --run-local --experiment-limit=unlimited --max-jobs=166 --max-seconds=86400

# 6 and 7. Exactly ten predeclared configurations per K, both modes.
p5 --batch --scenario=cluster --planner=rsp --rounds=4 --run-local --experiment-limit=unlimited --max-jobs=24 --max-seconds=86400
p5 --batch --scenario=cluster --planner=rsp --rounds=5 --run-local --experiment-limit=unlimited --max-jobs=24 --max-seconds=86400

# 8. All five original baselines, with Formation separately identified as idealized.
p5 --batch --scenario=cluster --planner=baselines --run-local --experiment-limit=unlimited --max-jobs=5 --max-seconds=86400

# 9. Complete eight-scene matrix; rerun the same command in later sessions.
p5 --batch --run-local --experiment-limit=unlimited --max-jobs=2996 --max-seconds=86400
```

The 24-hour batch value is an **example session boundary**, not a promise that a scene/matrix will finish. It is checked between jobs. None of these commands reduces frames/robots. A selection does not redefine the full required matrix. Dependencies ensure normalization/equivalence checks: greedy before other planners; myopic and both RSP-1 modes before K>1; serial before its threaded partner. Thus selecting only threaded execution can also run serial reference jobs. Successful dependencies are reused, never recomputed.

Choose a particular frozen seed or assignment:

```bash
p5 --dry-run --scenario=cluster --planner=rsp --rounds=4 --seed=11 --mode=threaded
p5 --dry-run --scenario=cluster --planner=rsp --rounds=3 --assignment=1,1,3,2 --mode=serial
# Replace --dry-run with --batch --run-local --experiment-limit=unlimited
# and specify --max-jobs / --max-seconds after inspecting prerequisites.
```

For an arbitrary seed or predetermined vector outside the required matrix, create a **separate supplemental output** before freezing it:

```bash
julia --startup-file=no --project=. scripts/phase5.jl --inventory --catalog=results/paper/verified_catalog.json --scenario=cluster --rounds=4 --assignment=4,1,4,2 --output=results/phase5-custom
# Alternative: --seed=123 instead of --assignment (never both).
python scripts/estimate_phase5.py --inventory=results/phase5-custom/inventory.json --calibration=results/calibration-pc-t4/run.json --output=results/phase5-custom
julia --startup-file=no --project=. scripts/phase5.jl --dry-run --scenario=cluster --planner=rsp --rounds=4 --assignment=4,1,4,2 --output=results/phase5-custom
julia --startup-file=no --project=. scripts/phase5.jl --batch --scenario=cluster --planner=rsp --rounds=4 --assignment=4,1,4,2 --run-local --experiment-limit=unlimited --max-jobs=6 --max-seconds=86400 --output=results/phase5-custom
```

These supplemental configurations are explicitly labeled `supplemental_not_final_matrix`, do not replace the ten required seeds, and do not enter final quality distributions or determine required-matrix completion. The output still carries the full immutable standard inventory plus supplemental jobs. Use `--job-id=...` to select a specific ID from a dry-run. Existing inventories cannot be extended in place; preserve them and use a new directory.

## E. Checkpoints, interruption and resume

One Julia batch process may write an output directory at a time. Do not launch concurrent planners/calibration in the same process space for timing comparisons. The runner takes an atomic `.batch.lock`, writes JSON via same-directory rename and seals every experiment with SHA-256. It writes the primary result before the certification replay. Only a fully validated experiment is `successful`; failed/replayed partial primaries cannot enter statistics.

- **Normal stop:** set `--max-jobs=1` or a bounded `--max-seconds`; allow the current experiment to finish. Ctrl+C/terminal close can interrupt work and lose the current uncheckpointed phase. Completed records survive.
- **Resume:** repeat the same batch command, with identical output directory, code, inventory, Julia threads and resource settings. Successful assignments and dependencies are not rerun or rewritten. The primary and validation are deliberately repeated if an interrupted experiment has not reached a sealed successful checkpoint; partial results and prior attempts are retained.
- **Progress:** `p5 --progress`; inspect `completion.json`, `results.csv`, `records/*.json` and `resource_policy.json`. Exit code 1 means a failed experiment; exit 2 means no runnable work and the required matrix is incomplete (for example budget/fidelity/dependency blocks); exit 0 with `attempted: 0` on a complete inventory is a successful no-op.
- **Failed-only retry:** `p5 --batch --only-failed --run-local --experiment-limit=unlimited --max-jobs=10 --max-seconds=86400`. Add the previous scenario/planner selectors if desired. It will not start unrelated pending jobs; unresolved failed prerequisites must be retried first. `--retry-failed` instead allows both pending jobs and failed retries. Investigate correctness failures before retrying; do not modify trajectories or seals.
- **Resource skips:** these are preflight decisions, not failed trajectories. After accepting longer **local** jobs and refreshing calibration/estimates, the same selections with explicit unlimited re-assess the policy and permit pending work. An actual successful result always takes precedence over a policy skip.

List failures and inspect attempts:

```bash
python - "$OUT" <<'PY'
import csv,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
for r in csv.DictReader(open(root/'results.csv')):
    if r['status']=='failed':
        record=json.load(open(root/r['record_path']))
        print(r['id'],record['error'],json.dumps(record['attempts'],indent=2))
PY
```

After a crash **on the same WSL boot**, verify that the old process ended (`ps -ef | grep '[j]ulia'`), then add `--recover-stale-lock` to the exact resume command. Recovery checks PID **and process start time**, refuses a live owner, and never rewrites completed records.

After a Windows/WSL reboot/power failure the boot ID differs, so automatic recovery deliberately refuses to remove the lock. Confirm no Julia writer is running, back up the entire output, inspect `.batch.lock/owner.json`, and move only the stale lock directory out of the way:

```bash
# SPECIAL CARE: only after confirming this output has no live writer.
cp -a "$OUT" "${OUT}-recovery-backup"
cat "$OUT/.batch.lock/owner.json"
mv "$OUT/.batch.lock" "$OUT/stale-lock-$(date +%s)"
```

Then repeat the exact batch command. Never delete `records`, `inventory.json`, `run_manifest.json`, attempts or checksum fields to force resume. Corrupt seals/environment mismatches fail loudly and preserve evidence. Atomic rename protects against partial file replacement, but there is no fsync-based guarantee against all power-loss/storage failures; maintain backups. Do not resume a copied directory on different hardware as if it were the same timing study.

## F. Results, statistics, figures and export

| File | Contents |
| --- | --- |
| `inventory.json` | All exact job definitions, groups (including empty rounds), seeds, inputs, starts, source revisions and paper review |
| `resources.json`, `resources.csv`, `job_costs.csv` | Per-job/scenario cost estimates and calibration context; not measured quality |
| `resource_policy.json` | Resource skip/admission assessments, estimates and reasons |
| `run_manifest.json` | Immutable environment/source/Manifest/inventory identity |
| `records/ID.json` | Sealed result, trajectories, groups, attempts, primary timing, separate certification execution and correctness flags |
| `results.csv` | One row per primary ID; actual completed scores/timings only, resource and fidelity status for missing work |
| `completion.json` | Global/per-scene progress, including `skipped_resource_limit` |
| `summary.json`, `summary.csv` | Automatic statistics for **entirely completed scenarios**; all tied best/worst partitions in JSON |
| `figures/*.png`, `figures/*.pdf` | Exportable figures generated only from completed scenario populations |

Read one completed record:

```bash
python - "$OUT" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);inv=json.load(open(root/'inventory.json'))
job=next(j for j in inv['jobs'] if j['scenario']=='cluster' and j['configured_rounds']==1 and j['mode']=='threaded')
r=json.load(open(root/'records'/(job['id']+'.json')))
print('groups:',r['definition']['round_groups'],'seed:',r['definition']['partition_seed'])
print('scores:',r['result']['scores'],'normalized SRPPA:',r['normalized_srppa'])
print('primary metrics:',r['result']['metrics'],'all-phase wall:',r['execution_wall_seconds'])
print('correctness:',r['correctness'],'primary + validation VI:',r['total_vi_calls'])
assert r['correctness']['rsp1_myopic_equal'] is True
assert r['correctness']['serial_threaded_equal'] is True
PY
```

`joint_srppa` is the authoritative common quality measure. `legacy_value`, `heading_bonus`, and `stationary_bonus` remain separate. Normalized SRPPA divides by the **fresh same-scene greedy** result. `planning_seconds` is warmed primary planning only; legacy evaluation, certification replay and validation are outside it. `execution_wall_seconds` includes the experiment's main work but not installation or per-process warmup; the estimate adds overhead. Logical occupied rounds are not a measured speedup. Speedup is paired serial primary time / threaded primary time. Single timing observations per configuration do not justify hardware-speedup confidence claims.

Generate summaries and plots:

```bash
p5 --summarize
# After the entire matrix:
python scripts/plot_phase5.py "$OUT" "$OUT/figures"
# While other scenes remain incomplete: include ONLY wholly completed scenes.
python scripts/plot_phase5.py "$OUT" "$OUT/figures-completed-scenes" --completed-scenes
```

If Cluster is incomplete, its partial assignments remain in raw CSV/JSON but no final Cluster mean/extreme distribution is emitted. No completed scenes means no figures. Partial-study figures carry an **INCOMPLETE STUDY** label; do not present them as an eight-scene result. Synthetic data require `--allow-fixture` and explicit synthetic labels. Final statistics retain one **serial** quality observation per assignment/seed; threaded copies and certification replays are not extra quality samples. RSP-2/3 use finite-population SD over all ordered vectors; RSP-4/5 use sample SD over ten fixed seeds. No cross-initial-state or cross-scene confidence interval is asserted. Best/worst sampled seed results are not global extrema. Formation is hatched/labeled as an idealized reference with different initialization/feasibility.

Export the **whole output directory**, paper evidence, Git commit and dependency files, not just screenshots:

```bash
git rev-parse HEAD > "$OUT/export-source-commit.txt"
cp Project.toml Manifest.toml "$OUT/"
cp -a results/paper "$OUT/paper-evidence"
tar -czf results/phase5-pc-export.tar.gz "$OUT"
# Example Windows access: explorer.exe .
```

Keep the original frozen source revisions and BSD attribution in any release. Saved upstream trajectories and synthetic figures are never substituted for fresh original results.

## G. CPU, memory, disk and execution order

Choose at least **two Julia threads** (the paired serial/threaded inventory requires them). Four threads is the validated configuration; use at most the WSL-available CPU capacity and usually no more than the largest occupied partition width. Hyperthreads are not equivalent to physical cores. Serial mode still records available Julia threads. BLAS remains **one**. Different thread-count studies need separate output directories and calibrations.

WSL limits can be configured in Windows `%UserProfile%\.wslconfig`, for example:

```ini
[wsl2]
processors=4
memory=12GB
swap=8GB
```

This is an example, not a RAM requirement or optimal setting. Leave ample RAM for Windows. After changing it, use PowerShell `wsl --shutdown`, reopen Ubuntu and recalibrate. Within WSL inspect `nproc`, `free -h`, `cat /sys/fs/cgroup/cpu.max` if present, and `df -h .`. Keep the PC plugged in, prevent sleep during a batch, and avoid competing CPU jobs. Do not change affinity/WSL allocation between calibration and runs.

The reference's ~249 GB allocation per block is **cumulative garbage**, not 249 GB resident RAM. Each concurrent VI task owns its reward cache; certification retains policies for independent checks. Larger grids/horizons and wide partitions can need substantially more RAM than the single serial calibration. The estimator reports grid-storage scaling, not a validated peak-memory bound. Start one job at a time, observe `top`/`free -h`, and leave headroom; paging invalidates useful timing comparisons. GC is explicitly run before primary/replay outside primary measurement, and GC during planning remains included. No GC disabling or reward/model shortcuts are used. Keep calibration, JSON, CSV, retry histories and exports; estimated base matrix output is approximately a gigabyte, but retries/backups can multiply it.

Suggested order: synthetic tests → PDF/source review → reference cost dry-run → deliberate local single-block calibration → fresh cost estimate → Cluster greedy/myopic/RSP-1 validation → a selected RSP-2 paired configuration → full Cluster baselines/RSP-2/3 → Cluster ten-seed RSP-4/5 → other scenarios as resources permit. H=100/150 certification can fail the unchanged max-90-iteration VI convergence check; failure is recorded, not silently corrected by increasing iterations. Investigate and document any such inconsistency before admitting those results.

`--max-seconds` is a **soft batch boundary** checked between experiments. It does **not** interrupt an individual VI call, legacy evaluation or certification replay. `--experiment-limit=300` is a **preflight estimate policy**, not a hard runtime guarantee. Under the default policy, do not start a job estimated above five minutes; record a skip and move on. An OS command such as `timeout --signal=TERM 300 ...` can enforce a process cap for lightweight testing, but may interrupt an experiment and leave a recoverable lock; it does not produce a completed result. For long local research runs, explicitly accepting unlimited experiments is your choice. Reassess estimates after observing completed runs; never claim skipped runs were reproduced through shortened substitutes.

Use `julia --project=. scripts/phase5.jl --help` for all selectors. The full matrix is scientifically useful only when its inputs, correctness checks, coverage and computational limitations are reported alongside its actual completed results.
