"""Clock diagnostics are relative, typed and bounded; never selected-frame certification."""
import base64,copy,hashlib,json,tempfile,unittest
from pathlib import Path
import test_evidence_verifier as evidence
from test_candidate_lease import receipt
from verify_candidate_lease import validate_candidate_lease
from verify_read_clock import (MAX,VERDICTS,RETIRE,RELATIVE,MISSING,SEQUENCES,SLOT_PHASES,
    validate_decision,validate_slot,validate_diagnostics,verify_report)
from schema_contract import validate_document
from ci_execution_policy import execution_policy


def decision(verdict=RELATIVE,delivered=1100,previous=1000,action='ALLOW_RELATIVE_ONLY',
             reason='RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED'):
    return dict(schema='trueplan.screen-read.clock-admission.v1',policy_id='RELATIVE_PTS_FENCE_V1',
        scope='LAST_CALLBACK_CLOCK_DIAGNOSTICS_NOT_SELECTED_FRAME_CERTIFICATION',epoch=3,frame_id=17,
        delivered_uptime_ms=delivered,previous_delivered_uptime_ms=previous,
        delivery_delta_ms=delivered-previous if previous is not None else None,
        pts_verdict=verdict,action=action,reason=reason,allows_automatic_ocr=action=='ALLOW_RELATIVE_ONLY',
        requires_new_epoch=action=='RETIRE_READ_SCOPE',capture_timestamp_calibrated=False,
        owner_certified=False,current_state_eligible=False,battle_advice_authorized=False)


def slot(last=0,active=None):
    return dict(schema='trueplan.screen-read.live-work-slot.v1',scope='ONE_LIVE_OCR_WORKER_ACROSS_CAPTURE_EPOCHS',
        capacity=1,active_requests=0 if active is None else 1,last_ticket=last,active_ticket=active,
        available=active is None and last<MAX,owner_certified=False,current_state_eligible=False,battle_advice_authorized=False)


def diagnostic(value=None):
    return dict(scope='CAPTURE_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_CLOCK_PROOF',clock_decision=value,live_work_slot=slot())


def report_fixture():
    # Synthetic PC input for testing the report checker, not a native execution receipt.
    decisions=[]
    for verdict in sorted(VERDICTS):
        action='RETIRE_READ_SCOPE' if verdict in RETIRE else 'ALLOW_RELATIVE_ONLY' if verdict==RELATIVE else 'HOLD_AUTOMATIC_OCR'
        decisions.append(dict(id=verdict,decision=decision(verdict,action=action,
            reason='RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED' if verdict==RELATIVE else verdict)))
    extra=[('first_relative_stamp',RELATIVE,1000,None,'ALLOW_RELATIVE_ONLY','RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED'),
        ('delivery_gap_boundary',RELATIVE,3500,1000,'ALLOW_RELATIVE_ONLY','RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED'),
        ('delivery_gap_exceeded',RELATIVE,3501,1000,'RETIRE_READ_SCOPE','DELIVERY_GAP_EXCEEDS_2500MS'),
        ('missing_pts_after_delivery_gap',MISSING,3501,1000,'RETIRE_READ_SCOPE','DELIVERY_GAP_EXCEEDS_2500MS'),
        ('repeated_pts_after_delivery_gap','PTS_REPEATED_HOLD',3501,1000,'RETIRE_READ_SCOPE','DELIVERY_GAP_EXCEEDS_2500MS'),
        ('delivery_rollback_overrides_missing',MISSING,999,1000,'RETIRE_READ_SCOPE','DELIVERY_CLOCK_ROLLBACK'),
        ('maximum_positive_delivery',RELATIVE,MAX,MAX-1,'ALLOW_RELATIVE_ONLY','RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED')]
    for identity,verdict,delivered,previous,action,reason in extra:
        decisions.append(dict(id=identity,decision=decision(verdict,delivered,previous,action,reason)))
    sequences=[]
    for identity,events in SEQUENCES.items():
        rows=[dict(frame_id=i,delivered_ms=d,pts_ms=p,verdict=v) for i,(d,p,v) in enumerate(events,1)]
        accepted=[dict(epoch=3,frameID=i,deliveredMs=d,presentationMs=p) for i,(d,p,v) in enumerate(events,1) if v==RELATIVE]
        summary=dict(schema='trueplan.sample-clock-audit.v1',activeEpoch=3,lastValidPTSSample=accepted[-1],
            observed=len(events),relativeAccepted=len(accepted),relativeHeld=len(events)-len(accepted),lastVerdict=events[-1][2],
            streamBegins=1,epochRotations=0,presentationToUptimeOffsetVerified=False,liveBattleStateCertified=False,productionEnabled=False)
        sequences.append(dict(id=identity,events=rows,summary=summary))
    slots=[dict(id=i,slot=slot(last,active)) for i,last,active in SLOT_PHASES]
    lease=receipt();lease.update(latest=None,pending=None,view_status='EMPTY',last_reason='CAPTURE_CLOCK_HELD',scope_revision=2)
    diagnostics=diagnostic(decisions[0]['decision']);diagnostics['live_work_slot']=slots[-1]['slot']
    files=evidence.fixture();selected=json.loads(files['selected_evidence.json'])
    selected['r562_read_clock_diagnostics']=diagnostics
    selected['r554_candidate_leases']=dict(automatic_full_frame=lease,paired_move_candidates=lease)
    files['selected_evidence.json']=evidence.encoded(selected);files=evidence.indexed(files)
    index=json.loads(files['evidence_integrity.json']);index.update(app_version='0.5.62',app_build='562')
    files['evidence_integrity.json']=evidence.encoded(index);blob=evidence.archive(files)
    return dict(scope='SYNTHETIC_RELATIVE_CLOCK_AND_LIVE_WORKER_ONLY',checks=2065,decisions=decisions,sequences=sequences,
        work_slot_snapshots=slots,lease_snapshot=lease,invalidated_lease_snapshots=[copy.deepcopy(lease),copy.deepcopy(lease)],
        retired_clock_summary=dict(activeEpoch=4,streamBegins=1,epochRotations=1,lastVerdict=RELATIVE,
            lastValidPTSSample=dict(epoch=4,frameID=3,deliveredMs=1200,presentationMs=100)),
        diagnostics=diagnostics,archive_sha256=hashlib.sha256(blob).hexdigest(),archive_base64=base64.b64encode(blob).decode(),
        Vision_executed=False,capture_age_certified=False,game_accuracy_certified=False,device_certified=False,full_app_CI_certified=False)


class ReadClockTests(unittest.TestCase):
    def reject(self,edit,value=None,verify=validate_decision):
        value=copy.deepcopy(decision() if value is None else value);edit(value)
        with self.assertRaises(ValueError):verify(value)
    def test_relative_admission_does_not_certify_capture_age(self):
        self.assertFalse(validate_decision(decision())['capture_age_certified']);validate_document(decision())
    def test_missing_clock_holds(self):validate_decision(decision(MISSING,action='HOLD_AUTOMATIC_OCR',reason=MISSING))
    def test_delivery_gap_boundary(self):validate_decision(decision(delivered=3500))
    def test_long_gap_retires_even_when_pts_missing(self):
        validate_decision(decision(MISSING,3501,1000,'RETIRE_READ_SCOPE','DELIVERY_GAP_EXCEEDS_2500MS'))
    def test_long_gap_cannot_allow(self):self.reject(lambda d:d.update(delivered_uptime_ms=3501,delivery_delta_ms=2501))
    def test_clock_rollback_retires_without_overflow(self):
        validate_decision(decision(MISSING,1,MAX,'RETIRE_READ_SCOPE','DELIVERY_CLOCK_ROLLBACK'))
    def test_maximum_positive_clock_is_valid(self):validate_decision(decision(delivered=MAX,previous=MAX-1))
    def test_boolean_stamp_is_rejected(self):self.reject(lambda d:d.update(epoch=True))
    def test_float_stamp_is_rejected(self):self.reject(lambda d:d.update(frame_id=17.0))
    def test_zero_delivery_is_rejected(self):self.reject(lambda d:d.update(delivered_uptime_ms=0))
    def test_boolean_previous_is_rejected(self):self.reject(lambda d:d.update(previous_delivered_uptime_ms=True))
    def test_false_delivery_delta_is_rejected(self):self.reject(lambda d:d.update(delivery_delta_ms=101))
    def test_boolean_delta_is_rejected(self):self.reject(lambda d:d.update(delivery_delta_ms=True))
    def test_missing_previous_key_is_rejected(self):self.reject(lambda d:d.pop('previous_delivered_uptime_ms'))
    def test_unknown_verdict_is_rejected(self):self.reject(lambda d:d.update(pts_verdict='CERTIFIED'))
    def test_unhashable_verdict_is_rejected(self):self.reject(lambda d:d.update(pts_verdict=[]))
    def test_wrong_action_flags_are_rejected(self):self.reject(lambda d:d.update(requires_new_epoch=True))
    def test_numeric_boolean_flag_is_rejected(self):self.reject(lambda d:d.update(allows_automatic_ocr=1))
    def test_clock_diagnostics_cannot_fill_game_identity(self):self.reject(lambda d:d.update(battle_id='game'))
    def test_clock_cannot_claim_certification(self):
        for key in ('capture_timestamp_calibrated','owner_certified','current_state_eligible','battle_advice_authorized'):
            with self.subTest(key=key):self.reject(lambda d:d.update({key:True}))
    def test_idle_and_running_slot(self):
        for value in (slot(),slot(1,1),slot(1),slot(MAX)):
            validate_slot(value);validate_document(value)
    def test_two_active_workers_are_rejected(self):self.reject(lambda s:s.update(active_requests=2),slot(2,2),validate_slot)
    def test_wrong_token_cannot_identify_current_worker(self):self.reject(lambda s:s.update(active_ticket=1),slot(2,2),validate_slot)
    def test_running_worker_cannot_claim_available(self):self.reject(lambda s:s.update(available=True),slot(1,1),validate_slot)
    def test_boolean_slot_capacity_is_rejected(self):self.reject(lambda s:s.update(capacity=True),slot(),validate_slot)
    def test_boolean_work_ticket_is_rejected(self):self.reject(lambda s:s.update(last_ticket=True),slot(),validate_slot)
    def test_exhausted_ticket_space_cannot_claim_available(self):self.reject(lambda s:s.update(available=True),slot(MAX),validate_slot)
    def test_slot_cannot_promote_owner(self):self.reject(lambda s:s.update(owner_certified=True),slot(),validate_slot)
    def test_clock_held_lease_cannot_keep_old_value(self):
        value=receipt();value['last_reason']='CAPTURE_CLOCK_HELD'
        with self.assertRaisesRegex(ValueError,'CLOCK_HELD_WITH_VALUE'):validate_candidate_lease(value)
    def test_unavailable_clock_still_allows_diagnostic_record(self):validate_diagnostics(diagnostic())
    def test_diagnostics_are_explicitly_separate_from_selected_frame_clock(self):
        value=decision();value.update(epoch=99,frame_id=9876)
        files=evidence.fixture();selected=json.loads(files['selected_evidence.json'])
        selected['r562_read_clock_diagnostics']=diagnostic(value);files['selected_evidence.json']=evidence.encoded(selected)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'diagnostic.zip';path.write_bytes(evidence.archive(evidence.indexed(files)))
            self.assertFalse(evidence.verify_archive(path)['ocr_accuracy_certified'])
    def test_indexed_archive_rejects_forged_clock_promotion(self):
        files=evidence.fixture();selected=json.loads(files['selected_evidence.json']);value=decision();value['owner_certified']=True
        selected['r562_read_clock_diagnostics']=diagnostic(value);files['selected_evidence.json']=evidence.encoded(selected)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'bad.zip';path.write_bytes(evidence.archive(evidence.indexed(files)))
            with self.assertRaises(evidence.EvidenceError):evidence.verify_archive(path)


class NativeClockReportTests(unittest.TestCase):
    def verify(self,value):
        with tempfile.TemporaryDirectory() as directory:return verify_report(value,Path(directory)/'recovered')
    def reject(self,edit):
        value=report_fixture();edit(value)
        with self.assertRaises(ValueError):self.verify(value)
    def test_pc_fixture_exercises_report_checker_without_claiming_native_execution(self):
        result=self.verify(report_fixture());self.assertEqual(result['sequences'],8);self.assertFalse(result['capture_age_certified'])
    def test_missing_reference_regression_cannot_be_hidden(self):
        self.reject(lambda r:r['sequences'][0]['events'][-1].update(verdict=RELATIVE))
    def test_last_valid_pts_must_survive_missing_sample(self):
        self.reject(lambda r:r['sequences'][0]['summary'].update(lastValidPTSSample=None))
    def test_old_completion_cannot_clear_new_worker(self):
        self.reject(lambda r:r['work_slot_snapshots'][5].update(slot=slot(2)))
    def test_multiple_epoch_offers_cannot_issue_extra_workers(self):
        self.reject(lambda r:r['work_slot_snapshots'][2].update(slot=slot(1001,1001)))
    def test_fabricated_native_count_is_rejected(self):self.reject(lambda r:r.update(checks=1))
    def test_duplicate_case_is_rejected(self):self.reject(lambda r:r['decisions'].__setitem__(0,r['decisions'][1]))
    def test_native_scope_cannot_claim_game_or_device_accuracy(self):self.reject(lambda r:r.update(device_certified=True))
    def test_native_archive_hash_must_match(self):self.reject(lambda r:r.update(archive_sha256='0'*64))
    def test_native_archive_diagnostics_must_match_report(self):
        self.reject(lambda r:r['diagnostics']['clock_decision'].update(epoch=4))


class MacOS26RoleTests(unittest.TestCase):
    def test_role_requires_cross_build_current_source(self):
        self.assertTrue(execution_policy('MACOS26_BUILD_AND_OCR','Darwin','x86_64','27.1','26.0.1')['requires_iPhoneOS27_build'])
    def test_wrong_host_os_is_rejected(self):
        for host in (None,'27.0.1','15.7',''):
            with self.subTest(host=host),self.assertRaises(ValueError):execution_policy('MACOS26_BUILD_AND_OCR','Darwin','x86_64','27.1',host)
    def test_old_sdk_is_rejected(self):
        with self.assertRaises(ValueError):execution_policy('MACOS26_BUILD_AND_OCR','Darwin','x86_64','26.4','26.0.1')
    def test_wrong_architecture_is_rejected(self):
        with self.assertRaises(ValueError):execution_policy('MACOS26_BUILD_AND_OCR','Darwin','arm64','27.1','26.0.1')


if __name__=='__main__':unittest.main()
