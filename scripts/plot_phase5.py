"""Research figures from complete, checksum-validated Phase 5 summaries; no planning."""
import argparse,json,pathlib,statistics as st
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
p=argparse.ArgumentParser();p.add_argument('input',type=pathlib.Path);p.add_argument('output',type=pathlib.Path);p.add_argument('--allow-fixture',action='store_true');p.add_argument('--completed-scenes',action='store_true');a=p.parse_args()
summary=json.load(open(a.input/'summary.json'));inv=json.load(open(a.input/'inventory.json'))
fixture=summary['purpose']=='ci_functional_validation'
if fixture and not a.allow_fixture:raise SystemExit('Synthetic CI data are not publication results; use --allow-fixture only to test plotting.')
if not summary['completion']['complete'] and not a.completed_scenes:raise SystemExit('Incomplete inventory. Use --completed-scenes to plot only entirely completed scenarios: '+str(summary['completion']['counts']))
names=[s['name'] for s in inv['catalog']['scenarios'] if summary['completion']['scenarios'][s['name']]['complete']]
if not names:raise SystemExit('No entirely completed scenarios; no plots generated.')
a.output.mkdir(parents=True,exist_ok=True)
records=[json.load(open(a.input/'records'/f'{j["id"]}.json')) for j in inv['jobs'] if j['scenario'] in names and j['sampling_method']!='supplemental_not_final_matrix']
assert all(r['status']=='successful' for r in records)
prefix='SYNTHETIC CI ONLY — ' if fixture else ''
if not summary['completion']['complete']:prefix+=f'INCOMPLETE STUDY: {len(names)}/{len(inv["catalog"]["scenarios"])} completed scenes — '
plt.rcParams.update({'font.size':9,'figure.dpi':180,'savefig.bbox':'tight','pdf.fonttype':42})
colors=['#426a8c','#559780','#bf873b','#96689c','#bd5e51']
def panels(title):
 rows=(len(names)+1)//2;fig,axs=plt.subplots(rows,2,figsize=(12,3.5*rows),squeeze=False)
 for ax,n in zip(axs.flat,names):ax.set_title(n.replace('_',' ').title());ax.grid(alpha=.2)
 for ax in list(axs.flat)[len(names):]:ax.set_visible(False)
 fig.suptitle(prefix+title,fontsize=12);return fig,list(axs.flat)
def save(fig,name):
 fig.tight_layout(rect=(0,0,1,.96))
 for ext in ['png','pdf']:fig.savefig(a.output/f'{name}.{ext}')
 plt.close(fig)
def group(n,k,mode='serial'):return [r for r in records if r['definition']['scenario']==n and r['definition']['configured_rounds']==k and r['definition']['mode']==mode]
def summaries(n):return sorted([s for s in summary['summaries'] if s['scenario']==n],key=lambda s:s['configured_rounds'])
ks=range(1,6);labels=['1 (single)','2 (E)','3 (E)','4 (S10)','5 (S10)']
fig,axs=panels('Partition count vs normalized joint SRPPA; E=exhaustive, S10=ten seeds')
for ax,n in zip(axs,names):
 ss=summaries(n);mean=[s['normalized_srppa']['mean'] for s in ss]
 ax.plot(ks,mean,'o-',color=colors[0]);ax.fill_between(list(ks),[s['normalized_srppa']['minimum'] for s in ss],[s['normalized_srppa']['maximum'] for s in ss],alpha=.15,label='Observed min–max, not CI')
 ax.axhline(1,color='black',ls='--',lw=.8,label='Greedy');ax.set_xticks(list(ks),labels);ax.set_ylabel('Joint SRPPA / greedy');ax.legend(fontsize=7)
save(fig,'partition_quality')
fig,axs=panels('Conditional SRPPA distributions; each assignment/seed retained once')
for ax,n in zip(axs,names):
 vals=[[r['normalized_srppa'] for r in group(n,k)] for k in ks]
 boxes=ax.boxplot(vals,labels=labels,patch_artist=True,showfliers=False)
 for b,c in zip(boxes['boxes'],colors):b.set_facecolor(c);b.set_alpha(.35)
 for k,v in zip(ks,vals):ax.scatter(np.full(len(v),k),v,s=7,alpha=.25,color=colors[k-1])
 ax.set_ylabel('Joint SRPPA / greedy')
save(fig,'srppa_distributions')
fig,axs=panels('Planning time vs configured partitions; one timing observation/configuration/mode')
for ax,n in zip(axs,names):
 for mode,marker in [('serial','o'),('threaded','s')]:
  vals=[[r['result']['metrics']['planning_seconds'] for r in group(n,k,mode)] for k in ks]
  ax.plot(list(ks),[st.mean(v) for v in vals],marker+'-',label=mode+' mean');ax.plot(list(ks),[st.median(v) for v in vals],marker+'--',alpha=.5,label=mode+' median')
 ax.set_xticks(list(ks),labels);ax.set_ylabel('Warmed planning wall seconds');ax.legend(fontsize=7)
save(fig,'planning_time')
fig,axs=panels('Filming quality vs planning time; equivalent execution modes are paired')
for ax,n in zip(axs,names):
 for k in ks:
  for mode,mark in [('serial','o'),('threaded','x')]:
   rs=group(n,k,mode);ax.scatter([r['result']['metrics']['planning_seconds'] for r in rs],[r['normalized_srppa'] for r in rs],s=12,marker=mark,alpha=.4,color=colors[k-1],label=f'K={k} {mode}')
 ax.set_xlabel('Planning wall seconds');ax.set_ylabel('Joint SRPPA / greedy');ax.legend(fontsize=5,ncol=2)
save(fig,'quality_time_tradeoff')
fig,axs=panels('Selected-path empirical redundancy per robot; conditional means')
for ax,n in zip(axs,names):
 ax.plot(list(ks),[s['mean_redundancy_per_robot'] for s in summaries(n)],'o-',color=colors[1]);ax.set_xticks(list(ks),labels);ax.set_ylabel('[sum F(singleton) − F(team)] / N')
save(fig,'redundancy')
for n in names:
 fig,ax=plt.subplots(figsize=(13,4.5));ax.axis('off');table=[]
 for s in summaries(n):
  cells=[str(s['configured_rounds'])+(' E' if s['configured_rounds'] in [2,3] else ' S10' if s['configured_rounds'] in [4,5] else ' single')]
  for kind,value in [('best_partitions','maximum'),('worst_partitions','minimum')]:
   entries=s[kind];first=entries[0];groups='; '.join(f'r{i+1}: '+(','.join(map(str,g)) or '∅') for i,g in enumerate(first['round_groups']))
   cells.append(f"{s['srppa'][value]:.6f}\n{groups}\n{len(entries)} exact tie(s), first shown")
  table.append(cells)
 t=ax.table(cellText=table,colLabels=['K / method','Best observed grouping','Worst observed grouping'],loc='center',cellLoc='left',colWidths=[.12,.44,.44]);t.auto_set_font_size(False);t.set_fontsize(8);t.scale(1,3.2)
 fig.suptitle(prefix+n+' — exact ordered groups; sampled extremes are not global extrema');save(fig,'best_worst_'+n)
fig,ax=plt.subplots(figsize=(8,max(3,len(names)*.65)));matrix=np.array([[s['normalized_srppa']['mean'] for s in summaries(n)] for n in names])
im=ax.imshow(matrix,aspect='auto',cmap='viridis');ax.set_yticks(range(len(names)),names);ax.set_xticks(range(5),labels)
for i in range(len(names)):
 for j in range(5):ax.text(j,i,f'{matrix[i,j]:.4f}',ha='center',va='center',color='white' if matrix[i,j]<np.median(matrix) else 'black',fontsize=8)
fig.colorbar(im,ax=ax,label='Mean joint SRPPA / scenario greedy');ax.set_title(prefix+'Scenario comparison: fixed historical starts; E and S10 remain distinct');save(fig,'scenario_comparison')
# Original Formation is shown separately because initialization/motion constraints differ.
fig,axs=panels('Baseline quality; hatched Formation is an idealized, non-equivalent reference')
for ax,n in zip(axs,names):
 bs=[b for b in summary['baselines'] if b['scenario']==n];bars=ax.bar(range(len(bs)),[b['normalized_srppa'] for b in bs],color=colors)
 for bar,b in zip(bars,bs):
  if b['planner']=='formation_idealized':bar.set_hatch('//')
 ax.set_xticks(range(len(bs)),[b['planner'].replace('_','\n') for b in bs],rotation=20,ha='right');ax.set_ylabel('Joint SRPPA / greedy')
save(fig,'baseline_references')
print('PHASE5_PLOTS_OK',len(list(a.output.glob('*.pdf'))),'PDF/PNG pairs; fixture=',fixture)
