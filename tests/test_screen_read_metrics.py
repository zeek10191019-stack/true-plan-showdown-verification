"""Scoring contracts, leakage rejection and genuine Swift ZIP adapter checks."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from screen_read_metrics import evaluate,prediction_from_archive,DATA_SCHEMA

def label(field='own_hp',value=170,side='own',visibility='PRESENT',slot=None):
    return dict(field=field,slot=slot,side=side,visibility=visibility,value=value)

def sample(identity='s0',image='a',group='clip0',split='development',labels=None):
    return dict(sample_id=identity,image_sha256=image*64,capture_group_id=group,split=split,
        label_origin='SYNTHETIC_CONTRACT',labels=labels or [label()])

def dataset(*samples):return dict(schema=DATA_SCHEMA,dataset_id='contract-set',samples=list(samples or [sample()]))

def prediction(identity='s0',image='a',value=170,side='UNKNOWN_OWNER',fields=None):
    return dict(sample_id=identity,image_sha256=image*64,source=dict(kind='SYNTHETIC_CONTRACT'),
        fields=fields if fields is not None else [dict(field='own_hp',slot=None,value=value,side=side,
            current_state_eligible=False,identity_certified=False)])

class RecognitionMetricsTests(unittest.TestCase):
    def test_correct_literal_does_not_prove_ownership(self):
        result=evaluate(dataset(),[prediction()]);m=result['overall']
        self.assertEqual(m['value_tp'],1);self.assertEqual(m['value_precision'],1)
        self.assertEqual(m['owner_coverage'],0);self.assertIsNone(m['owner_accuracy_among_assertions'])
        self.assertFalse(result['full_game_accuracy_certified']);self.assertFalse(result['device_certified'])
    def test_missing_prediction_is_abstention_and_false_negative(self):
        result=evaluate(dataset(),[]);m=result['overall']
        self.assertEqual(m['value_fn'],1);self.assertEqual(m['value_coverage'],0)
        self.assertIsNone(m['value_precision']);self.assertEqual(m['value_recall'],0)
        self.assertEqual(result['prediction_samples_missing'],1)
    def test_wrong_value_counts_false_positive_and_false_negative(self):
        m=evaluate(dataset(),[prediction(value=171)])['overall']
        self.assertEqual((m['value_tp'],m['value_fp'],m['value_fn']),(0,1,1))
        self.assertEqual(m['value_coverage'],1);self.assertEqual(m['value_recall'],0)
    def test_wrong_owner_is_scored_separately_from_correct_value(self):
        m=evaluate(dataset(),[prediction(side='opponent')])['overall']
        self.assertEqual(m['value_tp'],1);self.assertEqual(m['owner_returned'],1);self.assertEqual(m['owner_correct'],0)
    def test_correct_asserted_owner_is_only_a_label_comparison(self):
        result=evaluate(dataset(),[prediction(side='own')]);self.assertEqual(result['overall']['owner_correct'],1)
        self.assertFalse(result['label_correctness_certified'])
    def test_false_positive_on_explicitly_absent_field(self):
        d=dataset(sample(labels=[label(value=None,visibility='ABSENT')]))
        m=evaluate(d,[prediction()])['overall'];self.assertEqual(m['value_fp'],1)
        self.assertIsNone(m['value_recall']);self.assertIsNone(m['value_coverage'])
    def test_correct_absence_does_not_create_positive_accuracy(self):
        d=dataset(sample(labels=[label(value=None,visibility='ABSENT')]))
        m=evaluate(d,[prediction(value=None)])['overall'];self.assertEqual(m['value_tn'],1);self.assertIsNone(m['value_precision'])
    def test_absent_global_field_is_not_an_owner_assertion(self):
        d=dataset(sample(labels=[label(field='weather',value=None,side='field',visibility='ABSENT')]))
        p=prediction(fields=[dict(field='weather',slot=None,value=None,side='field',current_state_eligible=False,identity_certified=False)])
        m=evaluate(d,[p])['overall'];self.assertEqual(m['value_tn'],1);self.assertEqual(m['owner_labels'],0)
    def test_unknown_label_is_excluded_instead_of_fabricating_truth(self):
        d=dataset(sample(labels=[label(value=None,visibility='UNKNOWN')]))
        m=evaluate(d,[prediction()])['overall'];self.assertEqual(m['unknown_labels'],1)
        self.assertEqual(m['value_fp'],0);self.assertIsNone(m['value_precision'])
    def test_unlabelled_extra_field_is_reported_as_unscored(self):
        p=prediction();p['fields'].append(dict(field='opponent_hp',slot=None,value=81,side='UNKNOWN_OWNER',current_state_eligible=False,identity_certified=False))
        m=evaluate(dataset(),[p])['overall'];self.assertEqual(m['unlabelled_predictions'],1);self.assertEqual(m['value_fp'],0)
    def test_percent_int_and_float_agree_without_boolean_coercion(self):
        self.assertEqual(evaluate(dataset(),[prediction(value=170.0)])['overall']['value_tp'],1)
        self.assertEqual(evaluate(dataset(sample(labels=[label(value=1)])),[prediction(value=True)])['overall']['value_tp'],0)
    def test_zero_value_is_present_not_missing(self):
        self.assertEqual(evaluate(dataset(sample(labels=[label(value=0)])),[prediction(value=0)])['overall']['value_tp'],1)
    def test_duplicate_images_are_rejected_even_with_distinct_ids(self):
        with self.assertRaisesRegex(ValueError,'DUPLICATE_SAMPLE_OR_IMAGE'):evaluate(dataset(sample(),sample('s1',group='clip1')),[])
    def test_same_capture_cannot_leak_between_development_and_holdout(self):
        with self.assertRaisesRegex(ValueError,'CAPTURE_GROUP_SPLIT_LEAKAGE'):evaluate(dataset(sample(),sample('s1','b','clip0','sealed_holdout')),[])
    def test_correlated_frames_count_as_one_capture_group(self):
        result=evaluate(dataset(sample(),sample('s1','b','clip0')),[prediction(),prediction('s1','b')])
        self.assertEqual(result['samples'],2);self.assertEqual(result['capture_groups'],1)
    def test_macro_group_recall_does_not_overweight_longer_clip(self):
        d=dataset(sample(),sample('s1','b','clip0'),sample('s2','c','clip1'))
        result=evaluate(d,[prediction(),prediction('s1','b')]);self.assertAlmostEqual(result['overall']['value_recall'],2/3)
        self.assertEqual(result['macro_capture_group_value_recall'],.5)
    def test_declared_holdout_never_self_certifies_independence(self):
        result=evaluate(dataset(sample(split='sealed_holdout')),[prediction()])
        self.assertIn('NOT_ATTESTED',result['holdout_independence']);self.assertFalse(result['full_game_accuracy_certified'])
    def test_dataset_ids_and_image_hashes_are_not_interchangeable(self):
        with self.assertRaisesRegex(ValueError,'IMAGE_BINDING'):evaluate(dataset(),[prediction(image='b')])
    def test_duplicate_prediction_is_rejected(self):
        d=dataset(sample(),sample('s1','b','clip1'))
        with self.assertRaisesRegex(ValueError,'DUPLICATE_PREDICTION'):evaluate(d,[prediction(),prediction()])
    def test_wrong_or_unhashable_prediction_id_is_rejected(self):
        for value in ['other',{}]:
            p=prediction();p['sample_id']=value
            with self.assertRaises(ValueError):evaluate(dataset(),[p])
    def test_duplicate_label_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'DUPLICATE_LABEL'):evaluate(dataset(sample(labels=[label(),label()])),[])
    def test_duplicate_predicted_field_is_not_a_vote(self):
        p=prediction();p['fields']*=2
        with self.assertRaisesRegex(ValueError,'DUPLICATE_PREDICTED_FIELD'):evaluate(dataset(),[p])
    def test_nonfinite_values_are_rejected(self):
        for value in [float('nan'),float('inf'),-float('inf')]:
            with self.assertRaises(ValueError):evaluate(dataset(),[prediction(value=value)])
    def test_claim_flags_are_exact_booleans(self):
        p=prediction();p['fields'][0]['current_state_eligible']=1
        with self.assertRaisesRegex(ValueError,'CLAIM_TYPES'):evaluate(dataset(),[p])
    def test_owner_assertion_without_value_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'OWNER_WITHOUT_VALUE'):evaluate(dataset(),[prediction(value=None,side='own')])
    def test_current_and_identity_assertions_are_counted_without_certifying(self):
        p=prediction();p['fields'][0].update(current_state_eligible=True,identity_certified=True)
        result=evaluate(dataset(),[p]);self.assertEqual(result['overall']['current_state_assertions'],1)
        self.assertEqual(result['overall']['identity_assertions'],1);self.assertFalse(result['device_certified'])
    def test_domain_and_split_denominators_are_visible(self):
        result=evaluate(dataset(sample(),sample('s1','b','clip1','sealed_holdout')),[prediction()])
        self.assertEqual(result['per_domain']['own_hp']['positive_labels'],2)
        self.assertEqual(result['per_split']['sealed_holdout']['value_fn'],1)
    def test_results_do_not_mutate_labels_or_predictions(self):
        d=dataset();p=[prediction()];before=copy.deepcopy((d,p));evaluate(d,p);self.assertEqual((d,p),before)
    def test_different_reader_versions_cannot_be_merged_into_one_score(self):
        first=prediction();second=prediction('s1','b')
        for p,version in [(first,'571'),(second,'572')]:
            p['source']=dict(kind='APP_EVIDENCE_ZIP',archive_sha256='c'*64,app_version='0.5.'+version[-2:],app_build=version,engine_version='r571.snapshot.v1')
        with self.assertRaisesRegex(ValueError,'MIXED_READER_VERSIONS'):evaluate(dataset(sample(),sample('s1','b','clip1')),[first,second])
    def test_older_archive_without_structured_state_is_scored_as_missing_value(self):
        import test_evidence_verifier as base
        with tempfile.TemporaryDirectory() as td:
            files=base.fixture();selected=json.loads(files['selected_evidence.json'])
            selected.pop('screen_read_state');files['selected_evidence.json']=base.encoded(selected)
            path=Path(td)/'legacy.zip';path.write_bytes(base.archive(base.indexed(files)))
            p=prediction_from_archive(path,'s0');d=dataset();d['samples'][0]['image_sha256']=p['image_sha256']
            result=evaluate(d,[p]);self.assertEqual(result['overall']['value_fn'],1)
            self.assertEqual(p['reader_status'],'NO_STRUCTURED_STATE');self.assertEqual(result['prediction_samples_missing'],0)
    def test_recorded_ocr_failure_stays_in_the_recall_denominator(self):
        import test_evidence_verifier as base
        from test_ocr_failure import failure_fixture
        for no_image in [False,True]:
            with tempfile.TemporaryDirectory() as td:
                path=Path(td)/'failure.zip';path.write_bytes(base.archive(base.indexed(failure_fixture(no_image=no_image))))
                p=prediction_from_archive(path,'s0');d=dataset();d['samples'][0]['image_sha256']=p['image_sha256']
                result=evaluate(d,[p]);self.assertEqual(result['reader_failure_samples'],1)
                self.assertEqual(result['overall']['positive_labels'],1);self.assertEqual(result['overall']['value_fn'],1)
                self.assertEqual(result['per_sample'][0]['reader_status'],'OCR_FAILURE_RECORDED')
    def test_extreme_integer_and_missing_slot_are_rejected(self):
        with self.assertRaises(ValueError):evaluate(dataset(),[prediction(value=10**1000)])
        p=prediction();p['fields'][0].pop('slot')
        with self.assertRaisesRegex(ValueError,'SLOT'):evaluate(dataset(),[p])
    def test_actual_swift_archive_adapter_preserves_unknown_owner(self):
        p=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','s0')
        d=dataset(sample(image='a',labels=[label(value={'current':100,'maximum':200})]));d['samples'][0]['image_sha256']=p['image_sha256']
        result=evaluate(d,[p]);self.assertEqual(result['overall']['value_tp'],1)
        self.assertEqual(result['overall']['owner_coverage'],0);self.assertEqual(p['source']['app_build'],'571')
    def test_archive_adapter_rejects_corrupted_zip(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'bad.zip';p.write_bytes(b'not a ZIP')
            with self.assertRaises(ValueError):prediction_from_archive(p,'s0')
    def test_cli_consumes_archives_and_refuses_output_overwrite(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);source=ROOT/'fixtures/r571_source_value_baseline.zip';(root/'proof.zip').write_bytes(source.read_bytes())
            p=prediction_from_archive(source,'s0');d=dataset();d['samples'][0]['image_sha256']=p['image_sha256']
            d['samples'][0]['labels'][0]['value']={'current':100,'maximum':200}
            (root/'labels.json').write_text(json.dumps(d));(root/'archives.json').write_text(json.dumps([dict(sample_id='s0',path='proof.zip')]))
            command=[sys.executable,str(ROOT/'tools/screen_read_metrics.py'),str(root/'labels.json'),'--archives',str(root/'archives.json'),'--output',str(root/'score.json')]
            result=subprocess.run(command,capture_output=True,text=True);self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(json.loads((root/'score.json').read_text())['overall']['value_tp'],1)
            result=subprocess.run(command,capture_output=True,text=True);self.assertNotEqual(result.returncode,0)

if __name__=='__main__':unittest.main()
