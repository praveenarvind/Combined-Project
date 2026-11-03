"""Fast metadata/tool tests; fake PDF/costs are never original experimental evidence."""
import copy,importlib.util,json,pathlib,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
P=module('phase5_paper');E=module('estimate_phase5')
class Tools(unittest.TestCase):
    def test_review_is_explicit_and_hash_bound(self):
        catalog_path=ROOT/'docs/phase5/scenario_catalog.json';catalog=json.loads(catalog_path.read_text())
        with tempfile.TemporaryDirectory() as d:
            pdf=pathlib.Path(d)/'fixture.pdf';pdf.write_bytes(b'%PDF-1.4\nSYNTHETIC TEST ONLY')
            review=P.review_template(catalog,pdf);review['source_catalog_sha256']=P.digest(catalog_path)
            with self.assertRaises(ValueError):P.apply_review(catalog,review,pdf,catalog_path)
            review.update(paper_version='synthetic',reviewer='test',reviewed_at='test')
            for s in review['sections'].values():s.update(reviewed=True,evidence='synthetic test evidence',differences='test only')
            for row,scene in zip(review['scenarios'],catalog['scenarios']):
                row.update(paper_robots=scene['robots'],paper_horizon='not_specified',paper_actors=scene['actors'],
                           evidence='synthetic test only',source_conditions_accepted=True,unresolved_conflict=False)
            result=P.apply_review(catalog,review,pdf,catalog_path)
            self.assertTrue(result['paper']['independently_verified']);self.assertFalse(catalog['paper']['independently_verified'])
            for scene,old in zip(result['scenarios'],catalog['scenarios']):
                self.assertEqual(scene['input_sha256'],old['input_sha256']);self.assertEqual(scene['initial_states'],old['initial_states'])
            bad=copy.deepcopy(review);bad['scenarios'][0]['paper_robots']=99
            with self.assertRaises(ValueError):P.apply_review(catalog,bad,pdf,catalog_path)
            pdf.write_bytes(b'%PDF-changed')
            with self.assertRaises(ValueError):P.apply_review(catalog,review,pdf,catalog_path)
    def test_per_job_cost_includes_replay_and_overhead(self):
        inv=json.loads((ROOT/'docs/phase5/inventory.json').read_text())
        cal=json.loads((ROOT/'docs/phase5/resource-calibration.json').read_text())
        r=E.estimate(inv,cal)
        self.assertEqual(len(r['jobs']),2996)
        self.assertEqual(sum(j['status']=='skipped_resource_limit' for j in r['jobs']),2988)
        for j in r['jobs']:
            self.assertGreaterEqual(j['estimated_total_seconds'],60)
            if j['estimated_replay_planning_seconds']:
                self.assertEqual(j['estimated_primary_planning_seconds'],j['estimated_replay_planning_seconds'])
                self.assertGreater(j['estimated_total_seconds'],2*j['estimated_primary_planning_seconds'])
        self.assertEqual(r['totals']['vi_calls'],27720)
if __name__=='__main__':unittest.main()
