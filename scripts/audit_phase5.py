"""Read-only upstream audit and exact historical-input import; never imports old scores as new results."""
import argparse, hashlib, json, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('--source-root',type=pathlib.Path,required=True);p.add_argument('--camera-report',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]; upstream=a.source_root
revision='42f97540ff002651822a9bbd617bff3d68ab93e2'
historical='0f12ff66597df791fa3840b7b1f7bb4fe724c088'
change='70d12ca86f9ea840f251617a4ea31f54012dfa2b'
names=['cluster','cross_mix','four_split','priority_runners','priority_speaker','split_and_join','spreadout_group','track_runners']
expected=[4,4,4,5,5,4,4,5]
sha=lambda b:hashlib.sha256(b).hexdigest()
def original(commit,path):return subprocess.check_output(['git','-C',str(upstream),'show',f'{commit}:{path}'])
assert subprocess.check_output(['git','-C',str(upstream),'rev-parse','HEAD'],text=True).strip()==revision
assert not subprocess.check_output(['git','-C',str(upstream),'diff',historical,revision,'--','src/mdma_greedy'])
camera={r['scenario']:r for r in json.loads(a.camera_report.read_text())}
scenarios=[]
for name,n in zip(names,expected):
 path=f'experiments/{name}/{name}_data.json';old_bytes=original(historical,path);old=json.loads(old_bytes);new_bytes=original(revision,path);new=json.loads(new_bytes)
 changed=sorted(k for k in set(old)|set(new) if old.get(k)!=new.get(k))
 assert changed==['num_robots','robot_fovs'] and old['num_robots']==n and new['num_robots']==n+1
 assert old['actor_positions']==new['actor_positions']
 assert old['num_frames']==len(old['actor_positions'])
 assert all(len(frame)==old['num_targets'] for frame in old['actor_positions'])
 artifacts=[];starts=[]
 for planner in ['greedy','multipleroundsgreedy','myopic','assignment','formation']:
  q=f'experiments/{name}/{planner}/solution.json';raw=original(revision,q);d=json.loads(raw);es=sorted(d['elements'])
  assert [r for r,_ in es]==list(range(1,n+1))
  assert all(len(t)==old['num_frames'] and [s['depth'] for s in t]==list(range(1,old['num_frames']+1)) and all(s['horizon']==old['num_frames'] for s in t) for _,t in es)
  initial=[[r,t[0]] for r,t in es]
  if planner!='formation':starts.append(initial)
  artifacts.append(dict(planner=planner,path=q,source_revision=revision,sha256=sha(raw),robots=len(es),horizon=old['num_frames'],initial_states=initial))
 assert all(s==starts[0] for s in starts)
 cam=camera[name];assert len([c for c in cam['camera_objects'] if c['name'].startswith('uav')])==n
 assert len(cam['camera_data'])==n+1
 target=root/'data/scenarios/published'/name/f'{name}_data.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(old_bytes)
 scene=dict(name=name,robots=n,actors=old['num_targets'],horizon=old['num_frames'],grid=dict(width=int(old['scene']['scale']['x']),height=int(old['scene']['scale']['y']),headings=8),
  input_path=str(target.relative_to(root)),input_sha256=sha(old_bytes),source_path=path,input_revision=historical,upstream_head=revision,
  head_input_sha256=sha(new_bytes),head_json_robots=new['num_robots'],changed_keys_since_input_revision=changed,
  initial_states=starts[0],initial_state_method='recovered_from_all_four_feasible_upstream_baselines',initial_state_seed=None,
  starting_states_sha256=sha(json.dumps(starts[0],sort_keys=True,separators=(',',':')).encode()),formation_seed=2026,
  camera=dict(model='ViewConeSensor',fov=1.5707963267948966,cutoff=100.0,cutoff_test_enabled=False,source='MDMA_Experiment.init_discrete_problem override'),move_dist=3,
  vi=dict(max_iterations=90,belres=1e-6,discount=1,include_Q=False),original_artifacts=artifacts,
  blend=dict(sha256=sha(original(revision,f'experiments/{name}/{name}.blend')),**cam),
  fidelity_status='blocked',blockers=['paper_not_independently_accessible_for_required_fidelity_comparison'],
  fidelity_note='Historical inputs/counts/starts corroborated; source-paper equivalence remains unverified. Old scores/paths are audit evidence only.')
 scenarios.append(scene)
catalog=dict(schema_version=1,purpose='published_scenario_audit',source_repository='https://github.com/praveenarvind/MultiDroneMultiActorFilming',source_revision=revision,historical_input_revision=historical,count_change_revision=change,
 paper=dict(url='https://arxiv.org/abs/2404.03103',access_status='blocked_live_network_HTTP_403',independently_verified=False,user_reported_counts=dict(zip(names,expected))),
 partition_seeds=[11,22,33,44,55,66,77,88,99,110],allowed_partition_counts=[1,2,3,4,5],scenarios=scenarios)
out=root/'docs/phase5/scenario_catalog.json';out.write_text(json.dumps(catalog,indent=2)+'\n')
lines=['# Phase 5 scenario-fidelity audit','',f'Upstream HEAD `{revision}`; historical exact JSON commit `{historical}`.',f'Count-changing commit `{change}` (2024-09-11). Phase 4 main merge is `38bafbc`.','',
 'The historical JSON files are imported byte-for-byte into `data/scenarios/published/`; Phase 4 inputs are retained. No robot subset is selected and no JSON counts, poses, weights, horizons or FOV arrays are edited.', '',
 '| Scenario | Historical / HEAD robots | Actors | Full frames | Grid | Feasible-baseline starting states | Fidelity |','| --- | --- | --- | --- | --- | --- | --- |']
for s in scenarios:lines.append(f"| {s['name']} | {s['robots']} / {s['head_json_robots']} | {s['actors']} | {s['horizon']} | {s['grid']['width']}×{s['grid']['height']} | all four agree, recovered | blocked: paper audit |")
lines+=['','## Count discrepancy and evidence','',
 'The only parsed differences between the historical JSON and HEAD are `num_robots` and one appended `robot_fovs` entry. All actor poses, weights, frame sequences, grid dimensions and other JSON fields match. Each saved feasible baseline has the historical count and full horizon. Their robot IDs are exactly 1:N and their complete initial states match across greedy, multi-round, myopic and assignment.', '',
 'Read-only Blender 4.3.2 inspection, with auto-execution disabled and no rendering/saving, finds N `uav` camera objects plus the active overview camera. The exporter loops over all `bpy.data.cameras`, so it counts that overview camera as a robot. This establishes the extra-camera mechanism. The historical FOV arrays also include the overview FOV; the VI experiment loader explicitly overrides the camera with a π/2 view cone and cutoff 100. The cutoff test is disabled in the unchanged detector. Formation does not use that sensor to construct its trajectories; common quality evaluation uses the authoritative Phase 2 evaluator.', '',
 'The complete `src/mdma_greedy` source tree is identical between the historical input revision and audited HEAD, verified by an empty Git diff. Thus the older JSON is paired with the same filming model/baseline source used by the foundation.', '', '## What is and is not established','',
 'Historical feasible starting states are recoverable, so no new initial-state sampling is needed. Exact states, source paths, revisions and hashes for all 40 saved artifacts are in `scenario_catalog.json`. The random generator protocol is uniform integer x/y and one of eight headings, shared between planners. The saved states establish historical states for this source snapshot; no unpublished experiment identity is invented.', '',
 'Formation ignores those starting states and motion/grid constraints. Its Gaussian random phase is generated with the predeclared seed 2026 for new executions; the historical phase RNG seed is unavailable. It remains an idealized non-equivalent reference. Historical Formation initial states are kept only as audit evidence.', '',
 'The paper URL returned HTTP 403 under the live environment network policy. Its table, camera/units, horizon and experimental-method text cannot yet be independently compared. The four/five counts agree with the user-provided paper description, but this is not a completed paper audit. Every original scenario is therefore BLOCKED for final experiments. Applying the saved arXiv network additions or providing the paper is necessary to finish this comparison. No force/bypass flag is supplied by the final runner.', '',
 'Original saved scores and trajectories are not new experimental results. They are used only for provenance and initial-state recovery. Fresh baselines and all requested RSP assignments must still be solved after fidelity is established. This also distinguishes the corrected analytical joint SRPPA comparison from legacy or rendered scores.', '',
 '## Reproduce this audit','',
 'Run `scripts/audit_blend_cameras.py` with Blender in read-only background mode, then run `python scripts/audit_phase5.py --source-root=/path/to/MultiDroneMultiActorFilming --camera-report=/path/to/cameras.json`. The audit reads Git objects at fixed commits and asserts exact input differences, counts, full saved horizons and cross-baseline starting-state equality. It never changes the source checkout or renders frames.']
(root/'docs/phase5/SCENARIO_FIDELITY.md').write_text('\n'.join(lines)+'\n')
print('AUDIT_OK',len(scenarios),'scenarios; full-study fidelity blocked pending paper verification')
