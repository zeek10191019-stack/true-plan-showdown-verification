"""Image integrity, provisional labels, grouping and atomic corpus conversion."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from test_evidence_verifier import fixture
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from screen_read_corpus import import_legacy
from screen_read_metrics import evaluate

class CorpusImportTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        (self.root/'fixtures').mkdir();self.png=fixture()['frames/frame_17.png']
        (self.root/'fixtures/sample.png').write_bytes(self.png)
        self.frame=dict(path='fixtures/sample.png',sha256=hashlib.sha256(self.png).hexdigest(),width=2,height=2,
            own_hp=170,own_max_hp=185,opponent_hp_percent=81,moves=['テスト甲','テスト乙','テスト丙','テスト丁'],
            pp_current_maximum=[[10,10],[0,5],[14,16],[1,20]],screen_kind='move_selection_candidate',
            mega_form=None,major_status=None,field_state=None,battle_id=None,turn=None,
            label_source='DIRECT_VISUAL_REVIEW_IN_THIS_SESSION',current_app_Vision_prediction=None)
        self.labels=dict(current_app_accuracy_certified=False,frames=[self.frame])
        self.manifest=dict(fixtures=[dict(path='sample.png',sha256=self.frame['sha256'],domain='SYNTHETIC_CONTRACT',timestamp_ms=100)])
        self.groups={self.frame['path']:'recording0'};self.save()
    def save(self):
        (self.root/'R551_VISUAL_GROUND_TRUTH.json').write_text(json.dumps(self.labels,ensure_ascii=False))
        (self.root/'FIXTURE_MANIFEST.json').write_text(json.dumps(self.manifest))
    def run_import(self):self.save();return import_legacy(self.root,self.groups)
    def test_verified_images_produce_only_provisional_development_labels(self):
        d,a=self.run_import();self.assertEqual(a['positive_labels'],11);self.assertEqual(a['unknown_labels'],5)
        self.assertEqual(d['samples'][0]['split'],'development');self.assertEqual(d['samples'][0]['label_origin'],'LEGACY_PROVISIONAL_VISUAL_REVIEW')
        self.assertEqual(d['samples'][0]['image_sha256'],self.frame['sha256'])
    def test_null_legacy_state_becomes_unknown_instead_of_absent(self):
        d,_=self.run_import();r=evaluate(d,[])
        self.assertEqual(r['overall']['negative_labels'],0);self.assertEqual(r['overall']['unknown_labels'],5)
    def test_zero_hp_and_zero_pp_are_visible_values(self):
        self.frame['own_hp']=0;d,_=self.run_import();f={(x['field'],x['slot']):x for x in d['samples'][0]['labels']}
        self.assertEqual(f[('own_hp',None)]['value']['current'],0);self.assertEqual(f[('move_pp',1)]['value']['current'],0)
    def test_partial_recording_map_is_rejected(self):
        self.groups={}
        with self.assertRaisesRegex(ValueError,'GROUP_MAP_COVERAGE'):self.run_import()
    def test_group_requires_explicit_string_identity(self):
        self.groups[self.frame['path']]=True
        with self.assertRaisesRegex(ValueError,'GROUP_ID'):self.run_import()
    def test_changed_image_cannot_keep_old_label_sha(self):
        (self.root/'fixtures/sample.png').write_bytes(self.png+b'x')
        with self.assertRaisesRegex(ValueError,'IMAGE_SHA'):self.run_import()
    def test_manifest_and_label_hashes_must_agree(self):
        self.manifest['fixtures'][0]['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'IMAGE_SHA'):self.run_import()
    def test_correct_hash_does_not_hide_corrupt_png(self):
        raw=self.png[:-5];(self.root/'fixtures/sample.png').write_bytes(raw)
        self.frame['sha256']=self.manifest['fixtures'][0]['sha256']=hashlib.sha256(raw).hexdigest()
        with self.assertRaises(ValueError):self.run_import()
    def test_label_dimensions_must_match_image(self):
        self.frame['width']=3
        with self.assertRaises(ValueError):self.run_import()
    def test_bool_hp_pp_or_timestamp_is_rejected(self):
        self.frame['own_hp']=True
        with self.assertRaisesRegex(ValueError,'HP_LABEL'):self.run_import()
        self.frame['own_hp']=170;self.frame['pp_current_maximum'][0][0]=False
        with self.assertRaisesRegex(ValueError,'PP_LABEL'):self.run_import()
        self.frame['pp_current_maximum'][0][0]=10;self.manifest['fixtures'][0]['timestamp_ms']=True
        with self.assertRaisesRegex(ValueError,'TIMESTAMP'):self.run_import()
    def test_legacy_label_cannot_claim_current_app_prediction(self):
        self.frame['current_app_Vision_prediction']={}
        with self.assertRaisesRegex(ValueError,'LEGACY_LABEL_SCOPE'):self.run_import()
    def test_legacy_certification_is_rejected(self):
        self.labels['current_app_accuracy_certified']=True
        with self.assertRaisesRegex(ValueError,'NO_LEGACY_APP_CERTIFICATION'):self.run_import()
    def test_unreviewed_game_state_cannot_be_filled(self):
        self.frame['mega_form']='メガテスト'
        with self.assertRaisesRegex(ValueError,'UNREVIEWED_LEGACY_VALUE'):self.run_import()
    def test_absolute_and_parent_paths_are_rejected(self):
        for path in ('../escape.png','/tmp/sample.png','fixtures/../sample.png'):
            self.frame['path']=path;self.groups={path:'recording0'};self.manifest['fixtures'][0]['path']=path.removeprefix('fixtures/')
            with self.assertRaises(ValueError):self.run_import()
    def test_symlink_cannot_escape_corpus(self):
        p=self.root/'fixtures/sample.png';p.unlink();other=self.root.parent/(self.root.name+'_outside.png')
        other.write_bytes(self.png);self.addCleanup(lambda:other.unlink(missing_ok=True));p.symlink_to(other)
        with self.assertRaisesRegex(ValueError,'PATH_ESCAPE_OR_MISSING'):self.run_import()
    def test_identical_bytes_are_not_independent_samples(self):
        (self.root/'fixtures/second.png').write_bytes(self.png);f=copy.deepcopy(self.frame);f['path']='fixtures/second.png';self.labels['frames'].append(f)
        self.manifest['fixtures'].append(dict(path='second.png',sha256=self.frame['sha256'],domain='SYNTHETIC_CONTRACT',timestamp_ms=300));self.groups[f['path']]='recording1'
        with self.assertRaisesRegex(ValueError,'DUPLICATE_SAMPLE_OR_IMAGE'):self.run_import()
    def test_impossible_fraction_labels_are_rejected(self):
        for a,b in ((171,170),(0,0),(-1,185)):
            self.frame['own_hp']=a;self.frame['own_max_hp']=b
            with self.assertRaisesRegex(ValueError,'HP_LABEL'):self.run_import()
    def test_import_does_not_certify_game_device_or_holdout(self):
        _,a=self.run_import();self.assertEqual(a['sealed_holdout_images'],0)
        for f in ('current_app_executed','game_accuracy_certified','owner_certified','identity_certified','device_certified'):self.assertIs(a[f],False)
    def test_cli_writes_complete_output_and_refuses_overwrite(self):
        groups=self.root/'groups.json';groups.write_text(json.dumps(self.groups));out=self.root/'output'
        cmd=[sys.executable,str(ROOT/'tools/screen_read_corpus.py'),'--legacy-root',str(self.root),'--groups',str(groups),'--output',str(out)]
        r=subprocess.run(cmd,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(set(p.name for p in out.iterdir()),{'labels.json','CORPUS_AUDIT.json'})
        r=subprocess.run(cmd,capture_output=True,text=True);self.assertNotEqual(r.returncode,0)

if __name__=='__main__':unittest.main()
