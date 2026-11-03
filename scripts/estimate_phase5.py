"""Explicit resource extrapolation from a full-input single-block calibration; never experimental scores."""
import argparse,csv,json,pathlib,hashlib,shutil
p=argparse.ArgumentParser();p.add_argument('--inventory',type=pathlib.Path,required=True);p.add_argument('--calibration',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
inv=json.load(open(a.inventory));cal=json.load(open(a.calibration))
assert cal['status']=='successful' and cal['full_team_solution'] is False and cal['completed_vi_calls']==1
stages=cal['stages'];cache=sum(s['wall_seconds'] for s in stages if s['stage']=='reward_cache');vi=sum(s['wall_seconds'] for s in stages if s['stage']=='value_iteration')
base=cal['settings'];base_nonterminal=base['grid']['width']*base['grid']['height']*max(1,base['horizon']-1)
base_cache=base['grid']['width']*base['grid']['height']*base['horizon']*cal['actor_count']
rows=[]
for scene in inv['catalog']['scenarios']:
 jobs=[j for j in inv['jobs'] if j['scenario']==scene['name']];n=scene['robots'];h=scene['horizon'];g=scene['grid'];scale=g['width']*g['height']*(h-1)/base_nonterminal;cache_scale=g['width']*g['height']*h*scene['actors']/base_cache
 calls=sum(j['expected_planning_vi_calls'] for j in jobs);nonformation=[j for j in jobs if j['planner']!='formation_idealized']
 # VI work scales by nonterminal grid states, cache work also by actor count.
 planning=calls*(vi*scale+cache*cache_scale)
 certification=calls*cal['certificate_seconds']*scale
 # Preserved legacy objective rebuilds a whole reward cache at every path state.
 legacy=len(nonformation)*n*h*cache*cache_scale
 marginal_validation=len(nonformation)*n*cache*cache_scale
 estimate=2*(planning+legacy+marginal_validation)+certification
 disk=sum(15_000+j['expected_vi_calls']*2_000+n*h*250 for j in jobs)+len(jobs)*4_000
 rows.append(dict(scenario=scene['name'],robots=n,horizon=h,executions=len(jobs),validation_executions=len(nonformation),total_planner_passes=len(jobs)+len(nonformation),vi_calls=2*calls,planning_vi_calls=calls,validation_vi_calls=calls,
  estimated_planning_hours=planning/3600,estimated_replay_planning_hours=planning/3600,estimated_legacy_hours=2*legacy/3600,estimated_certification_hours=certification/3600,
  estimated_execution_hours=estimate/3600,illustrative_half_to_double_hours=[estimate/7200,estimate/1800],
  estimated_raw_bytes=2*disk,grid_state_count=g['width']*g['height']*8*h,
  grid_storage_scale_to_calibration=g['width']*g['height']*h/(base['grid']['width']*base['grid']['height']*base['horizon'])))
report=dict(inventory_file_sha256=hashlib.sha256(a.inventory.read_bytes()).hexdigest(),calibration_file_sha256=hashlib.sha256(a.calibration.read_bytes()).hexdigest(),kind='resource_extrapolation_not_measured_full_study',calibration_source=cal['context'],calibration_input_sha256=cal['input_sha256'],
 calibration_peak_rss_bytes=cal['process_peak_rss_bytes'],calibration_grid_storage_bytes=cal['grid_storage_bytes'],scenarios=rows,
 totals=dict(executions=sum(r['executions'] for r in rows),validation_executions=sum(r['validation_executions'] for r in rows),total_planner_passes=sum(r['total_planner_passes'] for r in rows),vi_calls=sum(r['vi_calls'] for r in rows),estimated_execution_hours=sum(r['estimated_execution_hours'] for r in rows),estimated_raw_bytes=sum(r['estimated_raw_bytes'] for r in rows)),
 assumptions=['Comparable VI sweep counts to the validated calibration, not a convergence guarantee.','Serial kernel costs extrapolated by state count; no assumed threaded speedup.','Cache cost scaled by grid, frames and actor count; assignment may differ.','Unprofiled primary pass and separate certification replay; both keep original legacy scoring. Independent Bellman checks follow the replay.','Half/double is an illustrative cost envelope, not a statistical confidence interval.','Peak RSS is measured only for the calibration; live memory of larger cases requires measurement.','Warmups, filesystem/checkpoint costs, retries and host contention add overhead.'])
a.output.mkdir(parents=True,exist_ok=True)
if a.calibration.resolve()!=(a.output/'resource_calibration.json').resolve():shutil.copyfile(a.calibration,a.output/'resource_calibration.json')
(a.output/'resources.json').write_text(json.dumps(report,indent=2)+'\n')
with open(a.output/'resources.csv','w',newline='') as f:
 fields=[k for k in rows[0] if k!='illustrative_half_to_double_hours'];w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore',lineterminator='\n');w.writeheader();w.writerows(rows)
print('RESOURCE_ESTIMATE_OK',report['totals'])
