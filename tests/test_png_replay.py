"""Replay contracts use scripted OCR metadata. They are not native OCR results."""
import copy
import base64
from unittest import mock
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile
import test_evidence_verifier as base
from test_ocr_recovery import request_fixture
from test_ocr_failure import failure_fixture
from test_layout_reading import unpack
from r553_fixture import source_update
from verify_source_bound_hints import source_bound_report
from png_replay_inputs import prepare_inputs,validate_inputs,SCHEMA as INPUT_SCHEMA
from verify_png_replay import verify_replay_archive,verify_native_report,SCHEMA,POLICY
from screen_read_metrics import prediction_from_archive,evaluate,DATA_SCHEMA
ROOT=Path(__file__).resolve().parents[1]

def files_fixture(failed=False,identity='sample0',elapsed=20):
    files=failure_fixture() if failed else request_fixture()
    selected=json.loads(files['selected_evidence.json'])
    if not failed:
        packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json']);state=selected['screen_read_state']
        state['screen_read_engine_version']='r571.snapshot.v1'
        state['owner_position_hints']=source_bound_report(packet,state['layout_candidates'],1000,462,'capture-test',17,3,packet['image_sha256'])
        files=source_update(files,selected,packet)
    selected['source']='offline_exact_png_replay'
    selected['png_replay']=dict(schema=SCHEMA,policy_id=POLICY,reader_policy_version='r574.png-replay.v1',sample_id=identity,
        source_kind='OFFLINE_EXACT_PNG',input_sha256=selected['png_sha256'],input_png_bytes=selected['png_bytes'],
        image_width=selected['image_width'],image_height=selected['image_height'],app_version='0.5.74',app_build='574',status='FAILED' if failed else 'SUCCESS',
        processing_time=dict(clock_basis='HOST_MONOTONIC_ELAPSED',scope='OCR_REQUEST',elapsed_ms=elapsed),
        capture_time_calibrated=False,owner_certified=False,identity_certified=False,current_state_eligible=False,
        battle_advice_authorized=False,game_accuracy_certified=False,device_certified=False)
    files['selected_evidence.json']=base.encoded(selected)
    manifest=json.loads(files['capture_manifest.json']);manifest.update(source='OFFLINE_EXACT_PNG_NO_CAPTURE_TIMING',capture_sample_spacing_ms=None)
    hints=manifest['frames'][0]['mega_scene_ocr_hints'];hints.update(rotations_completed=[],rotations_failed=[],rotations_skipped=[0,90,180,270],orientation_evidence=[])
    files['capture_manifest.json']=base.encoded(manifest)
    return files

def package(files):
    indexed=base.indexed(files);index=json.loads(indexed[base.INDEX]);index.update(app_version='0.5.74',app_build='574');indexed[base.INDEX]=base.encoded(index)
    return base.archive(indexed)

class PNGReplayArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name);self.path=self.root/'replay.zip'
    def verify(self,files=None):
        self.path.write_bytes(package(files or files_fixture()));return verify_replay_archive(self.path)
    def altered(self,edit,failed=False):
        files=files_fixture(failed);selected=json.loads(files['selected_evidence.json']);edit(selected);files['selected_evidence.json']=base.encoded(selected);return files
    def test_successful_archive_preserves_exact_input_and_current_shared_reader_metadata(self):
        r=self.verify();self.assertEqual(r['replay']['status'],'SUCCESS');self.assertEqual(r['archive']['captured_frames'],1)
        self.assertFalse(r['actual_execution_attested']);self.assertFalse(r['game_accuracy_certified'])
    def test_failure_still_has_original_png_and_no_result(self):
        r=self.verify(files_fixture(True));self.assertEqual(r['replay']['status'],'FAILED')
        p=prediction_from_archive(self.path,'sample0');self.assertEqual(p['reader_status'],'OCR_FAILURE_RECORDED');self.assertEqual(p['fields'],[])
    def test_adapter_exposes_replay_source_and_declared_policy_even_for_failure(self):
        self.verify(files_fixture(True));p=prediction_from_archive(self.path,'sample0')
        self.assertEqual(p['source']['kind'],'PNG_REPLAY_ZIP');self.assertEqual(p['source']['engine_version'],'r574.png-replay.v1')
        self.assertEqual(p['processing_time']['elapsed_ms'],20)
    def test_actual_request_engine_cannot_be_replaced_by_older_metadata(self):
        def edit(s):
            wrapper=json.loads(s['research_candidate_envelope']);p=json.loads(wrapper['payload_json']);p['ocr_engine_version']='r558.full-frame.v1'
            payload=base.encoded(p);wrapper.update(payload_json=payload.decode(),payload_sha256=base.sha(payload));s['research_candidate_envelope']=base.encoded(wrapper).decode()
        with self.assertRaises(ValueError):self.verify(self.altered(edit))
    def test_sample_mapping_cannot_rename_an_export(self):
        self.verify()
        with self.assertRaisesRegex(ValueError,'REPLAY_SAMPLE_ID'):prediction_from_archive(self.path,'different')
    def test_wrong_original_digest_is_rejected_even_with_rebuilt_index(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(input_sha256='0'*64)))
    def test_wrong_original_size_is_rejected(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(input_png_bytes=1)))
    def test_wrong_original_dimensions_are_rejected(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(image_width=2)))
    def test_app_version_is_bound_to_integrity_index(self):
        with self.assertRaisesRegex(ValueError,'APP_VERSION'):self.verify(self.altered(lambda s:s['png_replay'].update(app_build='575')))
    def test_false_or_numeric_certification_flags_do_not_pass(self):
        for flag in ('owner_certified','current_state_eligible','capture_time_calibrated','device_certified','identity_certified'):
            for value in (True,0,1):
                with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update({flag:value})))
    def test_unknown_replay_field_is_rejected(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(guessed_turn=3)))
    def test_success_cannot_relabel_failed_ocr(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(status='SUCCESS'),True))
    def test_failure_cannot_keep_a_successful_result(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(status='FAILED')))
    def test_missing_replay_metadata_does_not_fall_back_to_normal_capture(self):
        files=self.altered(lambda s:s.pop('png_replay'));self.path.write_bytes(package(files))
        with self.assertRaisesRegex(ValueError,'REPLAY_RECORD_REQUIRED'):prediction_from_archive(self.path,'sample0')
    def test_live_or_compile_timing_cannot_enter_replay_stats(self):
        for scope in ('CAPTURE_TO_DISPLAY','COMPILE'):
            with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay']['processing_time'].update(scope=scope)))
    def test_bad_processing_times_are_rejected(self):
        for value in (True,-1,float('inf')):
            with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay']['processing_time'].update(elapsed_ms=value)))
    def test_future_snapshot_policy_cannot_silently_replace_current_policy(self):
        with self.assertRaises(ValueError):self.verify(self.altered(lambda s:s['png_replay'].update(reader_policy_version='future-policy')))
    def test_offline_manifest_cannot_claim_capture_spacing_or_rotation_runs(self):
        for field,value in [('capture_sample_spacing_ms',4000),('source','LIVE_CAPTURE')]:
            files=files_fixture();m=json.loads(files['capture_manifest.json']);m[field]=value;files['capture_manifest.json']=base.encoded(m)
            with self.assertRaisesRegex(ValueError,'OFFLINE_MANIFEST'):self.verify(files)
        files=files_fixture();m=json.loads(files['capture_manifest.json']);m['frames'][0]['mega_scene_ocr_hints'].update(rotations_completed=[0],rotations_skipped=[90,180,270],orientation_evidence=[dict(orientation_degrees=0,status='OCR_CANDIDATES_ONLY',observations=[])])
        files['capture_manifest.json']=base.encoded(m)
        with self.assertRaisesRegex(ValueError,'ROTATIONS_NOT_REQUESTED'):self.verify(files)
    def test_expected_input_mapping_is_checked_against_bytes(self):
        r=self.verify();expected=dict(sample_id='wrong',sha256=r['replay']['input_sha256'],bytes=r['replay']['input_png_bytes'],width=1000,height=462)
        with self.assertRaisesRegex(ValueError,'EXPECTED_INPUT'):verify_replay_archive(self.path,expected)
    def test_trusted_archive_hash_is_not_a_filename_check(self):
        self.verify()
        with self.assertRaisesRegex(ValueError,'TRUSTED_ARCHIVE_SHA'):verify_replay_archive(self.path,expected_sha256='0'*64)
    def test_failed_and_successful_same_policy_stay_in_one_denominator(self):
        a=self.root/'a.zip';b=self.root/'b.zip';a.write_bytes(package(files_fixture(identity='a')));b.write_bytes(package(files_fixture(True,'b',2000)))
        predictions=[prediction_from_archive(a,'a'),prediction_from_archive(b,'b')]
        samples=[dict(sample_id=p['sample_id'],image_sha256=p['image_sha256'],capture_group_id='clip'+str(i),split='development',label_origin='SYNTHETIC_CONTRACT',
            labels=[dict(field='own_hp',slot=None,side='own',visibility='PRESENT',value=dict(current=100,maximum=200))]) for i,p in enumerate(predictions)]
        r=evaluate(dict(schema=DATA_SCHEMA,dataset_id='replay-contract',samples=samples),predictions)
        self.assertEqual(r['reader_failure_samples'],1);self.assertEqual(r['overall']['positive_labels'],2);self.assertEqual(r['overall']['value_fn'],1)
        self.assertEqual(r['processing_time']['per_scope']['OCR_REQUEST']['maximum_ms'],2000);self.assertFalse(r['full_game_accuracy_certified'])
    def test_png_replay_cannot_be_mixed_with_another_source_kind(self):
        self.verify(files_fixture(identity='a'));a=prediction_from_archive(self.path,'a');b=prediction_from_archive(ROOT/'fixtures/r571_source_value_baseline.zip','b')
        # Change only the annotation digest to remain distinct; version/source mismatch must reject first.
        b['image_sha256']='f'*64
        ds=dict(schema=DATA_SCHEMA,dataset_id='mixed',samples=[dict(sample_id=p['sample_id'],image_sha256=p['image_sha256'],capture_group_id=p['sample_id'],split='development',label_origin='SYNTHETIC_CONTRACT',labels=[dict(field='own_hp',slot=None,side='own',visibility='PRESENT',value=1)]) for p in (a,b)])
        with self.assertRaisesRegex(ValueError,'MIXED_READER_VERSIONS'):evaluate(ds,[a,b])

    def native_header(self,rows):
        return dict(status='EXPORTED_UNVERIFIED_OFFLINE_PNGS',scope='EXACT_PNG_SHARED_APP_READER_OFFLINE_ONLY',app_version='0.5.74',app_build='574',
            expected_inputs=len(rows),results=rows,game_accuracy_certified=False,device_certified=False,iOS_runtime_executed=False)
    def expected_row(self,files,identity='sample0'):
        s=json.loads(files['selected_evidence.json']);return dict(sample_id=identity,sha256=s['png_sha256'],bytes=s['png_bytes'],width=s['image_width'],height=s['image_height'])
    def test_native_report_recovers_bytes_and_matches_the_original_input(self):
        files=files_fixture();raw=package(files);row=dict(sample_id='sample0',status='SUCCESS',archive_base64=base64.b64encode(raw).decode(),archive_sha256=base.sha(raw))
        result=verify_native_report(self.native_header([row]),self.root/'verified',[self.expected_row(files)],'0.5.74','574')
        self.assertEqual((self.root/'verified/replay_0.zip').read_bytes(),raw);self.assertEqual(len(result['archives']),1)
        self.assertFalse(result['game_accuracy_certified'])
    def test_native_header_cannot_change_version_count_or_certifications(self):
        files=files_fixture();raw=package(files);row=dict(sample_id='sample0',status='SUCCESS',archive_base64=base64.b64encode(raw).decode(),archive_sha256=base.sha(raw))
        for key,value in [('app_build','575'),('expected_inputs',True),('game_accuracy_certified',True),('iOS_runtime_executed',True)]:
            report=self.native_header([row]);report[key]=value
            with self.assertRaises(ValueError):verify_native_report(report,self.root/'rejected',[self.expected_row(files)],'0.5.74','574')
    def test_driver_retains_verified_failure_archives_in_the_scoring_map(self):
        from run_png_replay import finalize_results
        output=self.root/'driver';(output/'archives').mkdir(parents=True);rows=[];expected=[]
        for index,failed in enumerate([False,True]):
            identity='sample'+str(index);files=files_fixture(failed,identity);raw=package(files);name='replay_'+str(index+1)+'.zip'
            (output/'archives'/name).write_bytes(raw);rows.append(dict(sample_id=identity,status='FAILED' if failed else 'SUCCESS',archive_file=name,archive_sha256=base.sha(raw)))
            expected.append(self.expected_row(files,identity))
        (output/'REPLAY_REPORT.json').write_text(json.dumps(self.native_header(rows)))
        r=finalize_results(self.root,dict(samples=expected),output,'0.5.74','574')
        self.assertEqual(r['status'],'EVIDENCE_READY_WITH_READING_FAILURES');self.assertEqual(r['reading_failures'],1)
        self.assertEqual(len(json.loads((output/'archives.json').read_text())),2)
    def test_non_apple_host_stops_before_download_or_output_creation(self):
        from run_png_replay import run
        with mock.patch('run_png_replay.platform.system',return_value='Linux'):
            with self.assertRaisesRegex(ValueError,'APPLE_SDK_REQUIRED_NO_AUTOMATIC_DOWNLOAD'):run(ROOT,self.root,self.root/'not_read.json',self.root/'not_created')
        self.assertFalse((self.root/'not_created').exists())

class PNGReplayInputTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.png=base.png();(self.root/'one.png').write_bytes(self.png)
        self.row=dict(sample_id='one',path='one.png',sha256=base.sha(self.png),bytes=len(self.png),width=2,height=2)
    def test_manifest_has_no_labels_predictions_or_owner_fields(self):
        r=prepare_inputs(self.root,[self.row]);self.assertEqual(set(r),{'schema','samples'});self.assertEqual(r['samples'],[self.row]);validate_inputs(self.root,r)
    def test_label_fields_are_rejected_instead_of_used_as_predictions(self):
        row={**self.row,'own_hp':170}
        with self.assertRaisesRegex(ValueError,'FIELDS'):prepare_inputs(self.root,[row])
    def test_different_input_bytes_cannot_keep_old_sha(self):
        (self.root/'one.png').write_bytes(self.png+b'x')
        with self.assertRaises(ValueError):prepare_inputs(self.root,[self.row])
    def test_boolean_dimensions_and_sizes_are_rejected(self):
        for key in ('bytes','width','height'):
            with self.assertRaises(ValueError):prepare_inputs(self.root,[{**self.row,key:True}])
    def test_duplicate_images_cannot_inflate_replay_count(self):
        (self.root/'two.png').write_bytes(self.png)
        with self.assertRaisesRegex(ValueError,'SHA_OR_DUPLICATE_IMAGE'):prepare_inputs(self.root,[self.row,{**self.row,'sample_id':'two','path':'two.png'}])
    def test_parent_absolute_and_symlink_escape_are_rejected(self):
        for name in ('../one.png','/tmp/one.png'):
            with self.assertRaises(ValueError):prepare_inputs(self.root,[{**self.row,'path':name}])
        (self.root/'link.png').symlink_to(self.root/'one.png')
        with self.assertRaises(ValueError):prepare_inputs(self.root,[{**self.row,'path':'link.png'}])
    def test_corrupt_png_does_not_pass_with_correct_sha_and_size(self):
        data=self.png[:-1];(self.root/'one.png').write_bytes(data);row={**self.row,'sha256':base.sha(data),'bytes':len(data)}
        with self.assertRaises(ValueError):prepare_inputs(self.root,[row])
    def test_manifest_schema_and_extra_top_fields_are_rejected(self):
        for data in [dict(schema='other',samples=[self.row]),dict(schema=INPUT_SCHEMA,samples=[self.row],labels=[])]:
            with self.assertRaises(ValueError):validate_inputs(self.root,data)

    def test_cli_prepares_only_metadata_and_refuses_overwrite(self):
        audit=self.root/'audit.json';audit.write_text(json.dumps(dict(schema='trueplan.screen-read.corpus-audit.v1',frames=[self.row],positive_labels=123)))
        out=self.root/'inputs.json';cmd=[sys.executable,str(ROOT/'tools/png_replay_inputs.py'),'--root',str(self.root),'--corpus-audit',str(audit),'--output',str(out)]
        r=subprocess.run(cmd,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
        doc=json.loads(out.read_text());self.assertEqual(set(doc),{'schema','samples'});self.assertEqual(doc['samples'],[self.row])
        r=subprocess.run(cmd,capture_output=True,text=True);self.assertNotEqual(r.returncode,0)

if __name__=='__main__':unittest.main()
