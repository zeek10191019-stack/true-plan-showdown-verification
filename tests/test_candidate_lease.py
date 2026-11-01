"""Adversarial receipt diagnostics; a digest alone is not image proof."""
import copy,json,unittest
import test_evidence_verifier as base
from verify_candidate_lease import validate_candidate_lease

def receipt():
    ticket=dict(scope_revision=1,request_id=1,capture_session_id='auto-test',epoch=2,frame_id=4,
                receipt_uptime_ms=1000,deadline_uptime_ms=3000,image_sha256='a'*64)
    return dict(schema='trueplan.screen-read.candidate-lease.v1',scope='HOST_RECEIPT_DIAGNOSTICS_ONLY',
        clock_basis='UNCALIBRATED_HOST_RECEIPT_UPTIME',host_now_ms=1200,last_clock_ms=1200,ttl_ms=2000,
        active=True,scope_revision=1,last_request_id=1,capture_session_id='auto-test',epoch=2,
        last_issued_frame_id=4,last_issued_receipt_ms=1000,pending=None,latest=ticket,
        view_status='FRESH_RECEIPT_ONLY',last_reason='FRESH_HOST_RECEIPT_ONLY',accepted_results=1,
        rejected_operations=0,duplicate_png_digests_not_refreshed=0,invalidations=1,
        source_image_attached=False,owner_certified=False,current_state_eligible=False,
        battle_advice_authorized=False,battle_id=None,turn=None,capture_timestamp_ms=None)

class CandidateLeaseTests(unittest.TestCase):
    def reject(self,edit):
        d=receipt();edit(d)
        with self.assertRaises(ValueError):validate_candidate_lease(d)
    def test_r570_strict_pending_retirement_must_not_publish_old_ticket(self):
        d=receipt();d['strict_retirement_on_new_request']=True
        d['pending']={k:v for k,v in d['latest'].items() if k!='image_sha256'}
        d['pending'].update(request_id=2,frame_id=5,receipt_uptime_ms=1100,deadline_uptime_ms=3100)
        d.update(last_request_id=2,last_issued_frame_id=5,last_issued_receipt_ms=1100)
        self.assertRaises(ValueError,validate_candidate_lease,d)
        d['latest']=None;d['view_status']='PENDING';d['last_reason']='OCR_PENDING'
        self.assertEqual(validate_candidate_lease(d)['view_status'],'PENDING')
    def test_r570_strict_flag_must_be_boolean(self):
        d=receipt();d['strict_retirement_on_new_request']='yes'
        self.assertRaises(ValueError,validate_candidate_lease,d)
    def test_unattached_digest_does_not_claim_frame_proof(self):
        r=validate_candidate_lease(receipt());self.assertEqual(r['source_image_proof'],'NOT_ATTACHED')
    def test_expired_view_is_explicit(self):
        d=receipt();d.update(host_now_ms=3000,last_clock_ms=3000,view_status='EXPIRED')
        self.assertEqual(validate_candidate_lease(d)['view_status'],'EXPIRED')
    def test_false_fresh_at_deadline(self):self.reject(lambda d:d.update(host_now_ms=3000,last_clock_ms=3000))
    def test_clock_is_not_capture_timestamp(self):self.reject(lambda d:d.update(capture_timestamp_ms=1000))
    def test_false_current_claim(self):self.reject(lambda d:d.update(current_state_eligible=True))
    def test_false_owner_claim(self):self.reject(lambda d:d.update(owner_certified=True))
    def test_false_attached_image_claim(self):self.reject(lambda d:d.update(source_image_attached=True))
    def test_game_battle_id_is_not_capture_scope(self):self.reject(lambda d:d.update(battle_id='battle'))
    def test_turn_cannot_be_filled(self):self.reject(lambda d:d.update(turn=1))
    def test_boolean_ttl(self):self.reject(lambda d:d.update(ttl_ms=True))
    def test_excessive_ttl(self):self.reject(lambda d:d.update(ttl_ms=30001))
    def test_zero_ttl(self):self.reject(lambda d:d.update(ttl_ms=0))
    def test_boolean_frame(self):self.reject(lambda d:d['latest'].update(frame_id=True))
    def test_stale_scope_revision(self):self.reject(lambda d:d['latest'].update(scope_revision=0))
    def test_foreign_session(self):self.reject(lambda d:d['latest'].update(capture_session_id='other'))
    def test_foreign_epoch(self):self.reject(lambda d:d['latest'].update(epoch=1))
    def test_deadline_not_extended_from_last_result(self):self.reject(lambda d:d['latest'].update(deadline_uptime_ms=3200))
    def test_image_digest_not_well_formed(self):self.reject(lambda d:d['latest'].update(image_sha256='A'*64))
    def test_stopped_cannot_retain_eligible_value(self):self.reject(lambda d:d.update(active=False,view_status='STOPPED'))
    def test_pending_watermark_must_match(self):
        def edit(d):
            d['pending']={k:v for k,v in d['latest'].items() if k!='image_sha256'}
            d['pending']['request_id']=2;d['last_request_id']=3
        self.reject(edit)
    def test_clock_rewind_invalidates_current_and_pending(self):
        d=receipt();d.update(host_now_ms=900,last_clock_ms=1200,active=False,latest=None,view_status='STOPPED',last_reason='HOST_CLOCK_REWIND',scope_revision=2)
        self.assertEqual(validate_candidate_lease(d)['view_status'],'STOPPED')
    def test_forged_clock_rewind_fresh(self):self.reject(lambda d:d.update(last_reason='HOST_CLOCK_REWIND'))
    def test_receipt_after_host_now(self):self.reject(lambda d:d['latest'].update(receipt_uptime_ms=1300,deadline_uptime_ms=3300))
    def test_lease_diagnostics_integrate_with_indexed_archive(self):
        files=base.fixture();selected=json.loads(files['selected_evidence.json'])
        selected['r554_candidate_leases']={k:receipt() for k in ('automatic_full_frame','paired_move_candidates')}
        files['selected_evidence.json']=base.encoded(selected)
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory)/'evidence.zip';p.write_bytes(base.archive(base.indexed(files)))
            self.assertEqual(base.verify_archive(p)['crc32'],'PASS')
            selected['r554_candidate_leases']['automatic_full_frame']['current_state_eligible']=True
            files['selected_evidence.json']=base.encoded(selected);p.write_bytes(base.archive(base.indexed(files)))
            with self.assertRaises(base.EvidenceError):base.verify_archive(p)

if __name__=='__main__':unittest.main()
