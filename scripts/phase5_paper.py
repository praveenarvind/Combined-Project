"""Register a local PDF and validate a human paper/source fidelity review. Never infers paper facts."""
import argparse
import copy
import hashlib
import json
import pathlib
import subprocess

SECTIONS=('camera_and_units','motion_and_grid','actor_trajectories_and_priorities','vi_and_horizon',
          'historical_starting_states','formation_and_metric_differences')


def digest(path): return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def review_template(catalog, pdf):
    if not pdf.read_bytes().startswith(b'%PDF-'): raise ValueError('Expected a PDF file')
    return dict(schema_version=1, paper_pdf_sha256=digest(pdf), paper_version=None, reviewer=None,
                reviewed_at=None, source_catalog_sha256=None,
                instructions='Read the local PDF and source audit. Fill observations, page/section references, and any differences. Use not_specified for facts the paper does not report; never invent paper parameters. All unsupported equivalence claims remain blocked.',
                sections={k:dict(reviewed=False,evidence=None,differences=None) for k in SECTIONS},
                scenarios=[dict(name=s['name'],paper_robots=None,paper_horizon=None,paper_actors=None,
                                evidence=None,source_conditions_accepted=False,unresolved_conflict=True)
                           for s in catalog['scenarios']])


def apply_review(catalog, review, pdf, catalog_path):
    if digest(pdf)!=review['paper_pdf_sha256']: raise ValueError('PDF checksum changed')
    if digest(catalog_path)!=review['source_catalog_sha256']: raise ValueError('Source catalog checksum changed')
    for k in ('paper_version','reviewer','reviewed_at'):
        if not isinstance(review.get(k),str) or not review[k].strip(): raise ValueError('Missing '+k)
    for name in SECTIONS:
        section=review['sections'][name]
        if section['reviewed'] is not True or not isinstance(section['evidence'],str) or not section['evidence'].strip():
            raise ValueError('Missing paper/source evidence for '+name)
        if not isinstance(section['differences'],str) or not section['differences'].strip():
            raise ValueError('Document differences (or none found) for '+name)
    observed={s['name']:s for s in review['scenarios']}
    if len(observed)!=len(review['scenarios']) or set(observed)!={s['name'] for s in catalog['scenarios']}:
        raise ValueError('Review must cover each original scenario exactly once')
    result=copy.deepcopy(catalog)
    for scene in result['scenarios']:
        row=observed[scene['name']]
        if row['source_conditions_accepted'] is not True or row['unresolved_conflict'] is not False:
            raise ValueError('Unresolved paper/source comparison: '+scene['name'])
        if not isinstance(row['evidence'],str) or not row['evidence'].strip(): raise ValueError('Missing scenario paper reference')
        for key,target in [('paper_robots','robots'),('paper_horizon','horizon'),('paper_actors','actors')]:
            if row[key]!='not_specified' and (type(row[key]) is not int or row[key]!=scene[target]):
                raise ValueError('Paper/source mismatch: '+scene['name']+' '+key)
        if row['paper_robots']=='not_specified': raise ValueError('Robot-count paper comparison is mandatory')
        scene.update(fidelity_status='verified',blockers=[],fidelity_note='Human local-PDF/source review accepted with documented scope; see paper.review. Unreported facts are supported by fixed upstream artifacts, not asserted as paper facts.')
    result['paper'].update(independently_verified=True,access_status='locally_supplied_pdf_human_review',
                           pdf_sha256=digest(pdf),review=review,
                           verification_scope='Human paper/source review; not an automated proof of historical run identity.')
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['prepare','apply']);p.add_argument('--pdf',type=pathlib.Path,required=True)
    p.add_argument('--catalog',type=pathlib.Path,default=pathlib.Path('docs/phase5/scenario_catalog.json'))
    p.add_argument('--review',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path)
    a=p.parse_args();catalog=json.loads(a.catalog.read_text())
    if a.action=='prepare':
        if a.review.exists(): p.error('Review exists; preserve it and choose a different path')
        review=review_template(catalog,a.pdf);review['source_catalog_sha256']=digest(a.catalog)
        a.review.parent.mkdir(parents=True,exist_ok=True);a.review.write_text(json.dumps(review,indent=2)+'\n')
        text=a.review.with_suffix('.paper.txt')
        try: subprocess.run(['pdftotext','-layout',str(a.pdf),str(text)],check=True)
        except FileNotFoundError: print('Optional pdftotext missing; read PDF directly or install poppler-utils.')
        print('PAPER_REVIEW_TEMPLATE',a.review,'Fill by reading PDF and source audit; nothing is verified yet.')
    else:
        if a.output is None: p.error('--output is required for apply')
        if a.output.exists(): p.error('Refusing to overwrite catalog; choose a new output')
        result=apply_review(catalog,json.loads(a.review.read_text()),a.pdf,a.catalog)
        a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2)+'\n')
        print('PAPER_REVIEW_ACCEPTED',a.output,'Human review retained with PDF/catalog hashes; original inputs unchanged.')


if __name__=='__main__': main()
