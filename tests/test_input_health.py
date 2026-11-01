"""Current-stream rejection must revoke a receipt without claiming current game state."""
import base64,copy,hashlib,itertools,json,tempfile,unittest
from pathlib import Path
import test_evidence_verifier as evidence
from test_candidate_lease import receipt
from test_read_clock import slot
from verify_input_health import validate_input_health,verify_report
from verify_candidate_lease import validate_candidate_lease
from schema_contract import validate_document
from ci_execution_policy import execution_policy


def health(accepted=0,rejected=0,consecutive=0,retirements=0,reason=None):
    return dict(schema='trueplan.screen-read.input-health.v1',scope='CURRENT_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_PROOF',
        status='INPUT_HELD' if consecutive else 'READY_DELIVERY_ONLY' if accepted else 'NOT_OBSERVED',
        accepted_inputs=accepted,rejected_inputs=rejected,consecutive_rejections=consecutive,
        retirement_requests=retirements,last_reason=reason,capture_timestamp_calibrated=False,
        current_state_eligible=False,owner_certified=False,battle_advice_authorized=False)


def report_fixture():
    # PC fixture for the checker. This is not a Swift execution record.
    cases=[]
    for current,screen,valid,image in itertools.product((False,True),repeat=4):
        result='IGNORE_FOREIGN_OR_NONSCREEN' if not current or not screen else 'HOLD_INVALID_SAMPLE' if not valid else 'READY_INPUT_ONLY' if image else 'HOLD_MISSING_IMAGE'
        cases.append(dict(current_stream=current,screen=screen,valid=valid,image_available=image,result=result))
    snapshots=[dict(id=i,health=health(a,r,c,t,why)) for i,a,r,c,t,why in [
        ('none',0,0,0,0,None),('ready',1,0,0,0,None),('held_once',1,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'),
        ('held_1000_more',1,1001,1001,1,'CURRENT_STREAM_INGRESS_REJECTED'),('ready_again',2,1001,0,1,None),
        ('held_again',2,1002,1,2,'CURRENT_STREAM_CONTINUITY_REJECTED')]]
    held=receipt();held.update(scope_revision=2,pending=None,latest=None,last_reason='CAPTURE_INPUT_HELD',view_status='EMPTY')
    files=evidence.fixture();selected=json.loads(files['selected_evidence.json'])
    selected['r563_input_health']=snapshots[-1]['health'];selected['r554_candidate_leases']=dict(automatic_full_frame=held,paired_move_candidates=held)
    files['selected_evidence.json']=evidence.encoded(selected);files=evidence.indexed(files)
    index=json.loads(files['evidence_integrity.json']);index.update(app_version='0.5.63',app_build='563');files['evidence_integrity.json']=evidence.encoded(index)
    blob=evidence.archive(files)
    return dict(scope='SYNTHETIC_INPUT_HEALTH_LEASE_AND_WORK_SLOT_ONLY',checks=1025,preflight_cases=cases,snapshots=snapshots,
        held_lease=held,work_slots=[slot(1,1),slot(1),slot(2,2)],archive_base64=base64.b64encode(blob).decode(),
        archive_sha256=hashlib.sha256(blob).hexdigest(),Vision_executed=False,capture_age_certified=False,
        game_accuracy_certified=False,device_certified=False,full_app_CI_certified=False)


class InputHealthTests(unittest.TestCase):
    def reject(self,edit,value=None):
        value=copy.deepcopy(health() if value is None else value);edit(value)
        with self.assertRaises(ValueError):validate_input_health(value)
    def test_unobserved_ready_held_and_recovered_contracts(self):
        for row in report_fixture()['snapshots']:
            validate_input_health(row['health']);validate_document(row['health'])
    def test_boolean_counter_is_rejected(self):self.reject(lambda d:d.update(accepted_inputs=True))
    def test_float_counter_is_rejected(self):self.reject(lambda d:d.update(rejected_inputs=0.0))
    def test_negative_counter_is_rejected(self):self.reject(lambda d:d.update(retirement_requests=-1))
    def test_oversize_counter_is_rejected(self):self.reject(lambda d:d.update(accepted_inputs=2**63))
    def test_held_must_have_reason(self):self.reject(lambda d:d.update(last_reason=None),health(0,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_unknown_reason_is_rejected(self):self.reject(lambda d:d.update(last_reason='CERTIFIED'),health(0,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_unhashable_reason_is_rejected(self):self.reject(lambda d:d.update(last_reason=[]),health(0,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_unobserved_cannot_have_rejection_history(self):self.reject(lambda d:d.update(rejected_inputs=1,retirement_requests=1))
    def test_consecutive_rejections_cannot_exceed_all_rejections(self):self.reject(lambda d:d.update(consecutive_rejections=2),health(0,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_repeated_bad_inputs_cannot_claim_extra_episode_without_recovery(self):
        self.reject(lambda d:d.update(retirement_requests=2),health(0,2,2,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_rejection_cannot_claim_zero_retirement_requests(self):
        self.reject(lambda d:d.update(retirement_requests=0),health(1,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_held_cannot_claim_ready(self):self.reject(lambda d:d.update(status='READY_DELIVERY_ONLY'),health(1,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'))
    def test_recovery_cannot_keep_hold_reason(self):self.reject(lambda d:d.update(last_reason='CURRENT_SCREEN_IMAGE_MISSING'),health(2,1,0,1))
    def test_health_cannot_claim_selected_frame_timestamp(self):self.reject(lambda d:d.update(capture_timestamp_ms=1000))
    def test_health_cannot_promote_certification(self):
        for key in ('capture_timestamp_calibrated','current_state_eligible','owner_certified','battle_advice_authorized'):
            with self.subTest(key=key):self.reject(lambda d:d.update({key:True}))
    def test_input_held_lease_must_not_keep_prior_value(self):
        value=receipt();value['last_reason']='CAPTURE_INPUT_HELD'
        with self.assertRaisesRegex(ValueError,'INPUT_HELD_WITH_VALUE'):validate_candidate_lease(value)
    def test_legacy_archive_without_health_is_still_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'old.zip';path.write_bytes(evidence.archive(evidence.indexed(evidence.fixture())))
            self.assertEqual(evidence.verify_archive(path)['crc32'],'PASS')
    def test_both_sides_of_source_scope_are_not_game_owner_proof(self):
        self.assertFalse(validate_input_health(health(1))['capture_age_certified'])
    def test_old_sdk_remains_forbidden_for_ios_build(self):
        with self.assertRaisesRegex(ValueError,'SDK_TOO_OLD'):execution_policy('IOS27_NATIVE','Darwin','arm64','26.5','27.0.1')
    def test_old_sdk_is_allowed_only_in_nonbuilding_portable_role(self):
        result=execution_policy('PORTABLE_OCR','Darwin','x86_64','26.5','26.6.1')
        self.assertFalse(result['requires_iPhoneOS27_build']);self.assertEqual(result['iPhoneOS_build_scope'],'NOT_RUN_PORTABLE_ROLE')
    def test_former_combined_role_still_rejects_observed_sdk(self):
        with self.assertRaisesRegex(ValueError,'SDK_TOO_OLD'):execution_policy('MACOS26_BUILD_AND_OCR','Darwin','x86_64','26.5','26.6.1')


class InputHealthReportTests(unittest.TestCase):
    def verify(self,value):
        with tempfile.TemporaryDirectory() as directory:return verify_report(value,Path(directory)/'archive')
    def reject(self,edit):
        value=report_fixture();edit(value)
        with self.assertRaises(ValueError):self.verify(value)
    def test_pc_fixture_checks_validator_without_claiming_swift_execution(self):
        result=self.verify(report_fixture());self.assertEqual(result['preflight_cases'],16);self.assertFalse(result['capture_age_certified'])
    def test_foreign_callback_cannot_be_reported_as_hold(self):
        self.reject(lambda r:r['preflight_cases'][0].update(result='HOLD_INVALID_SAMPLE'))
    def test_missing_current_image_cannot_be_reported_as_ready(self):
        self.reject(lambda r:r['preflight_cases'][-2].update(result='READY_INPUT_ONLY'))
    def test_boolean_selector_is_required(self):self.reject(lambda r:r['preflight_cases'][0].update(current_stream=0))
    def test_duplicate_truth_table_row_is_rejected(self):self.reject(lambda r:r['preflight_cases'].__setitem__(0,r['preflight_cases'][1]))
    def test_1000_failures_do_not_request_1000_retirements(self):
        self.reject(lambda r:r['snapshots'][3]['health'].update(retirement_requests=1001))
    def test_old_completion_does_not_clear_new_work_slot(self):self.reject(lambda r:r['work_slots'].__setitem__(2,slot(2)))
    def test_archive_payload_must_match_health_report(self):self.reject(lambda r:r['snapshots'][-1]['health'].update(rejected_inputs=1003))
    def test_archive_sha_must_match_actual_bytes(self):self.reject(lambda r:r.update(archive_sha256='0'*64))
    def test_report_cannot_claim_uikit_capture_or_accuracy(self):self.reject(lambda r:r.update(device_certified=True))
    def test_incomplete_native_count_is_rejected(self):self.reject(lambda r:r.update(checks=1024))


if __name__=='__main__':unittest.main()
