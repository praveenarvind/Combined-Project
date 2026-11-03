"""Export standalone plots from actual JSON artifacts; no benchmark execution."""
import argparse,json,pathlib,statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

p=argparse.ArgumentParser();p.add_argument('four_thread');p.add_argument('one_thread');p.add_argument('output');a=p.parse_args()
four=json.load(open(a.four_thread));one=json.load(open(a.one_thread));out=pathlib.Path(a.output);out.mkdir(parents=True,exist_ok=True)
assert four['context']['warmup_enabled'] and one['context']['warmup_enabled']
plt.rcParams.update({'font.size':10,'figure.dpi':150,'savefig.bbox':'tight'})
def save(fig,name):
 for ext in ('png','pdf'):fig.savefig(out/f'{name}.{ext}')
 plt.close(fig)
def chosen(run,case,planner):return [r for r in run['records'] if r['case_id']==case and r['result']['planner']==planner]
def avg(v):return statistics.mean(v)
def sd(v):return statistics.stdev(v) if len(v)>1 else 0
sets=[('1-thread runtime\nGreedy',chosen(one,'phase3-match','greedy')),('1-thread runtime\nRSP-2 serial',chosen(one,'phase3-match','rsp2_serial')),('4-thread runtime\nGreedy',chosen(four,'phase3-match','greedy')),('4-thread runtime\nRSP-2 serial',chosen(four,'phase3-match','rsp2_serial')),('4-thread runtime\nRSP-2 threaded',chosen(four,'phase3-match','rsp2_threaded'))]
fig,axs=plt.subplots(2,2,figsize=(11,8))
metrics=[('planning_seconds','Planning wall time (s)',1),('gc_seconds','Process-wide GC time (s)',1),('allocated_bytes','Cumulative allocation (GB)',1e9),('process_cpu_seconds','Process CPU time, all threads (s)',1)]
for ax,(key,label,scale) in zip(axs.flat,metrics):
 vals=[[r['result']['metrics'][key]/scale for r in rs] for _,rs in sets]
 ax.bar(range(len(sets)),[avg(v) for v in vals],yerr=[sd(v) for v in vals],capsize=3,color=['#657a9b','#6d9e91','#657a9b','#6d9e91','#c98257'])
 ax.set_xticks(range(len(sets)),[s[0] for s in sets],rotation=25,ha='right');ax.set_ylabel(label);ax.grid(axis='y',alpha=.2)
fig.suptitle('Controlled cluster study: five robots, three frames; mean ± sample SD (3 repeats)')
fig.tight_layout();save(fig,'runtime_gc_allocations')

profiles=four['diagnostic_passes'];fig,axs=plt.subplots(1,2,figsize=(11,4.5));stages=['prior_coverage','reward_cache','value_iteration','path_extraction']
for i,profile in enumerate(profiles):
 events=profile['result']['stages'];values=[avg([e['wall_seconds'] for e in events if e['stage']==stage]) for stage in stages]
 axs[0].bar([j+i*.35 for j in range(4)],values,width=.35,label=profile['planner'])
serial=next(z for z in profiles if z['planner']=='rsp2_serial')['result']['stages']
alloc=[sum(e['allocated_bytes'] for e in serial if e['stage']==stage) for stage in stages]
axs[1].bar(range(4),alloc,color='#6d9e91')
for ax in axs:
 ax.set_yscale('log');ax.set_xticks([j+.175 for j in range(4)] if ax is axs[0] else range(4),['Prior coverage','Reward cache','VI','Path'],rotation=25);ax.grid(axis='y',alpha=.2)
axs[0].set_ylabel('Mean per-block stage wall time (s, log scale)');axs[0].legend()
axs[1].set_ylabel('Allocated bytes, serial diagnostic (log scale)')
fig.suptitle('Separate diagnostic passes; concurrent worker times are not additive wall time')
fig.tight_layout();save(fig,'stage_diagnostics')

baseline=[r for r in four['records'] if r['case_id']=='baseline-functionality']
fig,axs=plt.subplots(1,2,figsize=(12,4.8));labels=[r['result']['planner'].replace('_','\n') for r in baseline]
for ax,key,label in [(axs[0],'normalized_srppa','Joint SRPPA / paired greedy'),(axs[1],'redundancy_per_robot','Empirical selected-path redundancy per robot')]:
 vals=[r[key] if key=='normalized_srppa' else r['result'][key] for r in baseline]
 bars=ax.bar(range(len(vals)),vals,color=['#bd9d68' if r['result']['planner']=='formation_idealized' else '#657a9b' for r in baseline])
 for bar,r in zip(bars,baseline):
  if r['result']['planner']=='formation_idealized':bar.set_hatch('//')
 ax.set_xticks(range(len(labels)),labels,rotation=35,ha='right');ax.set_ylabel(label);ax.grid(axis='y',alpha=.2)
axs[0].axhline(1,color='black',lw=.8,ls='--')
fig.suptitle('Two-robot/two-frame functionality condition, one observation; hatched Formation is idealized')
fig.tight_layout();save(fig,'quality_redundancy')
print('PLOTS_OK',out)
