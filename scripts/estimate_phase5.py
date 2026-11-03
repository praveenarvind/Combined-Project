"""Cost estimates only: no Julia, input loading, planning or score generation."""
import argparse
import csv
import hashlib
import json
import pathlib
import shutil


def estimate(inv, cal, overhead=60.0, safety=2.0):
    if not (cal['status'] == 'successful' and cal['full_team_solution'] is False and cal['completed_vi_calls'] == 1):
        raise ValueError('A completed, certified single-block calibration is required')
    cache = sum(s['wall_seconds'] for s in cal['stages'] if s['stage'] == 'reward_cache')
    vi = sum(s['wall_seconds'] for s in cal['stages'] if s['stage'] == 'value_iteration')
    base = cal['settings']
    base_states = base['grid']['width'] * base['grid']['height'] * max(1, base['horizon'] - 1)
    base_cache = base['grid']['width'] * base['grid']['height'] * base['horizon'] * cal['actor_count']
    jobs, rows = [], []
    for scene in inv['catalog']['scenarios']:
        n, h, g = scene['robots'], scene['horizon'], scene['grid']
        scale = g['width'] * g['height'] * (h - 1) / base_states
        cache_scale = g['width'] * g['height'] * h * scene['actors'] / base_cache
        selected = [j for j in inv['jobs'] if j['scenario'] == scene['name']]
        local = []
        for job in selected:
            calls = job['expected_planning_vi_calls']
            passes = 2 if calls else 1
            planning = calls * (vi * scale + cache * cache_scale)
            certification = calls * cal['certificate_seconds'] * scale
            # benchmark_plan also evaluates the preserved legacy score and marginals.
            # Formation has no VI but still has evaluation cost; never estimate it as free.
            legacy = n * h * cache * cache_scale if calls else 0
            marginal = n * cache * cache_scale
            center = passes * (planning + legacy + marginal) + certification
            total = overhead + safety * center
            item = dict(id=job['id'], scenario=scene['name'], estimated_primary_planning_seconds=planning,
                        estimated_replay_planning_seconds=planning if calls else 0,
                        estimated_legacy_seconds=passes * legacy,
                        estimated_marginal_seconds=passes * marginal,
                        estimated_certification_seconds=certification,
                        fixed_setup_warmup_checkpoint_allowance_seconds=overhead,
                        safety_factor=safety, estimated_total_seconds=total,
                        default_limit_seconds=300, status='skipped_resource_limit' if total > 300 else 'estimated_within_limit',
                        reason='Conservative extrapolation, includes primary, replay, validation and overhead; not a measured runtime or upper bound.')
            jobs.append(item); local.append(item)
        total = sum(j['estimated_total_seconds'] for j in local)
        rows.append(dict(scenario=scene['name'], robots=n, horizon=h, executions=len(selected),
                         validation_executions=sum(j['validation_execution_id'] is not None for j in selected),
                         vi_calls=sum(j['expected_vi_calls'] for j in selected),
                         estimated_execution_hours=total / 3600,
                         estimated_raw_bytes=2 * sum(19000 + j['expected_vi_calls'] * 2000 + n*h*250 for j in selected),
                         grid_state_count=g['width']*g['height']*8*h,
                         grid_storage_scale_to_calibration=g['width']*g['height']*h/(base['grid']['width']*base['grid']['height']*base['horizon'])))
    return dict(kind='resource_extrapolation_not_measured_full_study', calibration_source=cal['context'],
                calibration_input_sha256=cal['input_sha256'], calibration_peak_rss_bytes=cal['process_peak_rss_bytes'],
                calibration_grid_storage_bytes=cal['grid_storage_bytes'], scenarios=rows, jobs=jobs,
                totals=dict(executions=len(jobs), validation_executions=sum(r['validation_executions'] for r in rows),
                            vi_calls=sum(r['vi_calls'] for r in rows),
                            estimated_execution_hours=sum(r['estimated_execution_hours'] for r in rows),
                            estimated_raw_bytes=sum(r['estimated_raw_bytes'] for r in rows)),
                assumptions=['Estimate includes both planner passes, original legacy evaluation, marginal checks, Bellman certification, setup/checkpoint allowance and safety factor.',
                             'State-count and actor-count scaling from one block; no assumed threaded speedup. Assignment and VI sweep counts may differ.',
                             'Safety factor is an allowance, not a statistical interval or guaranteed runtime bound.',
                             'Recorded peak RSS is only the calibration; allocation totals are not live RAM. Larger/threaded peak memory is unmeasured.',
                             'A reference calibration may inform dry-run skips. Execution additionally requires same implementation, Julia, Manifest and CPU/memory/thread settings via the resource gate.'])


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inventory',type=pathlib.Path,required=True)
    p.add_argument('--calibration',type=pathlib.Path,required=True)
    p.add_argument('--output',type=pathlib.Path,required=True)
    p.add_argument('--overhead-seconds',type=float,default=60)
    p.add_argument('--safety-factor',type=float,default=2)
    a=p.parse_args()
    if a.overhead_seconds < 0 or a.safety_factor < 1: p.error('nonnegative overhead and safety factor >=1 required')
    inv=json.loads(a.inventory.read_text());cal=json.loads(a.calibration.read_text())
    report=estimate(inv,cal,a.overhead_seconds,a.safety_factor)
    report.update(inventory_file_sha256=hashlib.sha256(a.inventory.read_bytes()).hexdigest(),
                  calibration_file_sha256=hashlib.sha256(a.calibration.read_bytes()).hexdigest())
    a.output.mkdir(parents=True,exist_ok=True)
    dest=a.output/'resource_calibration.json'
    if a.calibration.resolve()!=dest.resolve(): shutil.copyfile(a.calibration,dest)
    (a.output/'resources.json').write_text(json.dumps(report,indent=2)+'\n')
    for name, data in [('resources',report['scenarios']),('job_costs',report['jobs'])]:
        with open(a.output/(name+'.csv'),'w',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(data[0]),lineterminator='\n');w.writeheader();w.writerows(data)
    print('RESOURCE_ESTIMATE_OK',report['totals'])


if __name__=='__main__': main()
