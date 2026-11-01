"""Stratified denominators and processing latency are independent of game truth."""
import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from test_screen_read_metrics import dataset,sample,prediction,ROOT
from screen_read_metrics import evaluate,prediction_from_archive,attach_processing_times

class StrataAndProcessingTests(unittest.TestCase):
    def timed(self,value=100,scope='OCR_REQUEST'):
        p=prediction();p['processing_time']=dict(clock_basis='HOST_MONOTONIC_ELAPSED',scope=scope,elapsed_ms=value);return p
    def test_missing_prediction_stays_in_its_screen_class(self):
        a=sample();a['screen_class']='menu';b=sample('s1','b','clip1');b['screen_class']='result'
        r=evaluate(dataset(a,b),[prediction()])
        self.assertEqual(r['per_declared_screen_class']['menu']['value_tp'],1)
        self.assertEqual(r['per_declared_screen_class']['result']['value_fn'],1)
    def test_capture_domain_does_not_replace_recording_groups(self):
        a=sample();a['capture_domain']='CASUAL';b=sample('s1','b','clip1');b['capture_domain']='CASUAL'
        r=evaluate(dataset(a,b),[prediction()]);self.assertEqual(r['capture_groups'],2)
        self.assertEqual(r['per_declared_capture_domain']['CASUAL']['positive_labels'],2)
    def test_missing_context_is_explicitly_unspecified(self):
        r=evaluate(dataset(),[])
        self.assertEqual(set(r['per_declared_screen_class']),{'UNSPECIFIED'})
        self.assertEqual(set(r['per_declared_capture_domain']),{'UNSPECIFIED'})
    def test_context_requires_a_bounded_string(self):
        for name in ('screen_class','capture_domain'):
            for value in (None,{},[],True,'','a'*129):
                row=sample();row[name]=value
                with self.assertRaisesRegex(ValueError,'SAMPLE_'):evaluate(dataset(row),[])
    def test_annotation_context_does_not_manufacture_predictions(self):
        row=sample();row['screen_class']='menu';r=evaluate(dataset(row),[])
        self.assertEqual(r['overall']['value_fn'],1);self.assertEqual(r['prediction_samples_received'],0)
    def test_nearest_rank_percentiles_keep_tail_outliers(self):
        rows=[]
        for ident,img,t in [('s0','a',1),('s1','b',2),('s2','c',1000)]:
            p=self.timed(t);p.update(sample_id=ident,image_sha256=img*64);rows.append(p)
        r=evaluate(dataset(sample(),sample('s1','b'),sample('s2','c')),rows)['processing_time']['per_scope']['OCR_REQUEST']
        self.assertEqual(r['p50_ms'],2);self.assertEqual(r['p95_ms'],1000);self.assertAlmostEqual(r['mean_ms'],1003/3)
    def test_zero_measurement_is_present(self):
        r=evaluate(dataset(),[self.timed(0)])['processing_time']
        self.assertEqual(r['samples_with_measurement'],1);self.assertEqual(r['per_scope']['OCR_REQUEST']['p95_ms'],0)
    def test_no_timing_is_not_zero_latency(self):
        r=evaluate(dataset(),[prediction()])['processing_time']
        self.assertEqual(r['samples_without_measurement'],1);self.assertEqual(r['per_scope'],{})
    def test_missing_archive_is_missing_timing_too(self):
        r=evaluate(dataset(sample(),sample('s1','b')),[self.timed()])['processing_time']
        self.assertEqual(r['samples_with_measurement'],1);self.assertEqual(r['samples_without_measurement'],1)
    def test_failure_times_are_not_filtered_out(self):
        p=self.timed(2000);p.update(fields=[],reader_status='OCR_FAILURE_RECORDED');r=evaluate(dataset(),[p])
        self.assertEqual(r['reader_failure_samples'],1);self.assertEqual(r['overall']['value_fn'],1)
        self.assertEqual(r['processing_time']['per_scope']['OCR_REQUEST']['maximum_ms'],2000)
    def test_ocr_and_offline_pipeline_durations_stay_separate(self):
        p=self.timed(2500,'OFFLINE_FRAME_PIPELINE');p.update(sample_id='s1',image_sha256='b'*64)
        r=evaluate(dataset(sample(),sample('s1','b')),[self.timed(3),p])['processing_time']
        self.assertEqual(r['per_scope']['OCR_REQUEST']['mean_ms'],3)
        self.assertEqual(r['per_scope']['OFFLINE_FRAME_PIPELINE']['mean_ms'],2500)
    def test_boolean_negative_nonfinite_or_unbounded_times_are_rejected(self):
        for value in (True,False,-1,float('nan'),float('inf'),3_600_001,'100',{}):
            with self.assertRaisesRegex(ValueError,'PROCESSING_TIME_VALUE'):evaluate(dataset(),[self.timed(value)])
    def test_capture_and_compiler_scopes_are_rejected(self):
        for scope in ('CAPTURE_TO_DISPLAY','COMPILE','WALL_CLOCK_TIMESTAMP',[],None):
            with self.assertRaisesRegex(ValueError,'PROCESSING_TIME_SCOPE'):evaluate(dataset(),[self.timed(1,scope)])
    def test_clock_domains_are_never_subtracted(self):
        p=self.timed();p['processing_time']['clock_basis']='UTC'
        with self.assertRaisesRegex(ValueError,'PROCESSING_TIME_CLOCK'):evaluate(dataset(),[p])
    def test_unknown_timing_fields_are_rejected(self):
        p=self.timed();p['processing_time']['capture_ms']=1
        with self.assertRaisesRegex(ValueError,'PROCESSING_TIME_FIELDS'):evaluate(dataset(),[p])
        p['processing_time']=[]
        with self.assertRaisesRegex(ValueError,'PROCESSING_TIME_FIELDS'):evaluate(dataset(),[p])
    def test_self_reported_timings_never_certify_device_or_live_latency(self):
        r=evaluate(dataset(),[self.timed()])['processing_time']
        self.assertFalse(r['capture_to_display_latency_certified']);self.assertFalse(r['device_latency_certified'])
        self.assertEqual(r['attestation'],'SELF_REPORTED_NOT_ATTESTED')
    def test_zip_adapter_exports_the_bound_classification_candidate(self):
        p=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','s0')
        cls=[f for f in p['fields'] if f['field']=='screen_class'];self.assertEqual(len(cls),1)
        self.assertEqual(cls[0]['value'],'move_selection_with_move_details_overlay_candidate')
        self.assertEqual(cls[0]['side'],'field');self.assertFalse(cls[0]['current_state_eligible']);self.assertFalse(cls[0]['identity_certified'])
        self.assertNotIn('processing_time',p)
    def test_scoring_does_not_mutate_extended_records(self):
        d=dataset();d['samples'][0]['screen_class']='unknown';p=self.timed();before=copy.deepcopy((d,p))
        evaluate(d,[p]);self.assertEqual((d,p),before)

    def timing_row(self,p):
        return dict(sample_id=p['sample_id'],image_sha256=p['image_sha256'],archive_sha256=p['source']['archive_sha256'],
            processing_time=dict(clock_basis='HOST_MONOTONIC_ELAPSED',scope='OCR_REQUEST',elapsed_ms=42))
    def test_timing_sidecar_is_bound_to_exact_export_bytes(self):
        p=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','s0');row=self.timing_row(p)
        out=attach_processing_times([p],[row]);self.assertEqual(out[0]['processing_time']['elapsed_ms'],42)
        self.assertNotIn('processing_time',p)
    def test_timing_sidecar_rejects_wrong_image_or_archive(self):
        p=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','s0')
        for name in ('image_sha256','archive_sha256'):
            row=self.timing_row(p);row[name]='0'*64
            with self.assertRaisesRegex(ValueError,'TIMING_MAPPING_BINDING'):attach_processing_times([p],[row])
    def test_timing_sidecar_rejects_unknown_and_duplicate_samples(self):
        p=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','s0');q={**p,'sample_id':'s1'};row=self.timing_row(p)
        with self.assertRaisesRegex(ValueError,'TIMING_MAPPING_SAMPLE'):attach_processing_times([p,q],[row,row])
        row['sample_id']='other'
        with self.assertRaisesRegex(ValueError,'TIMING_MAPPING_SAMPLE'):attach_processing_times([p],[row])
    def test_null_or_extra_timing_sidecar_fields_are_rejected(self):
        p=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','s0');row=self.timing_row(p);row['processing_time']=None
        with self.assertRaisesRegex(ValueError,'TIMING_MAPPING_DURATION'):attach_processing_times([p],[row])
        row=self.timing_row(p);row['certified']=True
        with self.assertRaisesRegex(ValueError,'TIMING_MAPPING_FIELDS'):attach_processing_times([p],[row])
    def test_sidecar_cli_uses_bound_measurement_without_self_certification(self):
        source=ROOT/'fixtures/r571_source_value_baseline.zip';p=prediction_from_archive(source,'s0');d=dataset();d['samples'][0]['image_sha256']=p['image_sha256']
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'proof.zip').write_bytes(source.read_bytes())
            (root/'labels.json').write_text(json.dumps(d));(root/'archives.json').write_text(json.dumps([dict(sample_id='s0',path='proof.zip')]))
            (root/'timing.json').write_text(json.dumps([self.timing_row(p)]))
            r=subprocess.run([sys.executable,str(ROOT/'tools/screen_read_metrics.py'),str(root/'labels.json'),'--archives',str(root/'archives.json'),
                '--processing-times',str(root/'timing.json'),'--output',str(root/'score.json')],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr);result=json.loads((root/'score.json').read_text())
            self.assertEqual(result['processing_time']['per_scope']['OCR_REQUEST']['p95_ms'],42)
            self.assertFalse(result['processing_time']['device_latency_certified'])

if __name__=='__main__':unittest.main()
