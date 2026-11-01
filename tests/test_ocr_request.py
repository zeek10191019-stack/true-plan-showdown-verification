"""Request-metadata/source tampering, independent of OCR accuracy."""
import json,unittest
import test_evidence_verifier as base
from test_layout_reading import unpack
from r553_fixture import source_update
from r558_fixture import request_fixture,request_metadata
from test_state_semantics import state_fixture
from verify_ocr_request import validate_ocr_request

def edited(edit,omissions=False):
    files=request_fixture(omissions);selected,packet=unpack(files);edit(packet,selected)
    return source_update(files,selected,packet)

class OCRRequestTests(unittest.TestCase):
    setUp=base.EvidenceVerifierTests.setUp
    tearDown=base.EvidenceVerifierTests.tearDown
    verify=base.EvidenceVerifierTests.verify
    reject=base.EvidenceVerifierTests.reject
    def tamper(self,**changes):
        return edited(lambda p,s:p['ocr_request_audit'].update(changes))
    def test_request_metadata_archive(self):self.verify(request_fixture())
    def test_truncated_and_omitted_observations_archive(self):self.verify(request_fixture(True))
    def test_empty_request_is_not_invented_text(self):
        files=state_fixture([]);s,p=unpack(files)
        p.update(ocr_engine_version='r558.full-frame.v1',ocr_request_audit=request_metadata(s,p,0))
        self.verify(source_update(files,s,p))
    def test_fast_supported_path(self):
        def change(p,s):p['ocr_request_audit'].update(requested_mode='AUTOMATIC_SPEED_PRIORITY',fast_language_check='SUPPORTED',
            fast_supported_languages=['en-US','ja-JP'],effective_recognition_level='fast')
        self.verify(edited(change))
    def test_fast_missing_japanese_falls_back_to_accurate(self):
        def change(p,s):p['ocr_request_audit'].update(requested_mode='AUTOMATIC_SPEED_PRIORITY',fast_language_check='UNSUPPORTED',
            fast_supported_languages=['en-US'])
        self.verify(edited(change))
    def test_fast_query_failure_falls_back_to_accurate(self):
        self.verify(edited(lambda p,s:p['ocr_request_audit'].update(requested_mode='AUTOMATIC_SPEED_PRIORITY',fast_language_check='QUERY_FAILED')))
    def test_image_hash_cannot_change(self):self.reject(self.tamper(image_sha256='0'*64))
    def test_frame_cannot_change(self):self.reject(self.tamper(frame_id=18))
    def test_epoch_cannot_change(self):self.reject(self.tamper(epoch=4))
    def test_receipt_cannot_change(self):self.reject(self.tamper(receipt_uptime_ms=1201))
    def test_session_cannot_change(self):self.reject(self.tamper(capture_session_id='other-capture'))
    def test_dimensions_cannot_change(self):self.reject(self.tamper(image_width=999))
    def test_boolean_identity_or_count_is_not_integer(self):
        for key in ['frame_id','epoch','receipt_uptime_ms','image_width','image_height','request_revision','maximum_regions',
                    'maximum_candidates_per_region','raw_region_count','examined_region_count','emitted_region_count','truncated_region_count','unbound_roi_count']:
            with self.subTest(field=key):self.reject(self.tamper(**{key:True}))
    def test_missing_english_cannot_be_claimed_supported(self):self.reject(self.tamper(effective_supported_languages=['ja-JP']))
    def test_language_order_is_explicit(self):self.reject(self.tamper(requested_languages=['en-US','ja-JP']))
    def test_duplicate_supported_language_is_rejected(self):self.reject(self.tamper(effective_supported_languages=['en-US','ja-JP','ja-JP']))
    def test_correction_cannot_silently_turn_on(self):self.reject(self.tamper(uses_language_correction=True))
    def test_manual_mode_cannot_claim_fast(self):self.reject(self.tamper(effective_recognition_level='fast'))
    def test_fast_mode_requires_both_languages(self):
        self.reject(self.tamper(requested_mode='AUTOMATIC_SPEED_PRIORITY',fast_language_check='SUPPORTED',
            fast_supported_languages=['en-US'],effective_recognition_level='fast'))
    def test_false_fallback_reason_is_rejected(self):
        self.reject(self.tamper(requested_mode='AUTOMATIC_SPEED_PRIORITY',fast_language_check='UNSUPPORTED',fast_supported_languages=['en-US','ja-JP']))
    def test_failed_query_cannot_contain_a_language_result(self):
        self.reject(self.tamper(requested_mode='AUTOMATIC_SPEED_PRIORITY',fast_language_check='QUERY_FAILED',fast_supported_languages=['en-US']))
    def test_unknown_mode_is_rejected(self):self.reject(self.tamper(requested_mode='AUTO_CERTIFIED'))
    def test_region_limit_cannot_expand(self):self.reject(self.tamper(maximum_regions=97))
    def test_candidate_limit_cannot_expand(self):self.reject(self.tamper(maximum_candidates_per_region=4))
    def test_examined_region_count_matches_limit(self):self.reject(self.tamper(examined_region_count=15))
    def test_emitted_region_count_matches_rows(self):self.reject(self.tamper(emitted_region_count=15))
    def test_truncation_cannot_be_hidden(self):
        self.reject(edited(lambda p,s:p['ocr_request_audit'].update(truncated_region_count=0),True))
    def test_omission_cannot_be_hidden(self):
        self.reject(edited(lambda p,s:p['ocr_request_audit']['omitted_observations'].pop(),True))
    def test_omission_index_cannot_duplicate_a_result(self):
        self.reject(edited(lambda p,s:p['ocr_request_audit']['omitted_observations'][0].update(observation_index=0),True))
    def test_omission_reason_is_bounded(self):
        self.reject(edited(lambda p,s:p['ocr_request_audit']['omitted_observations'][0].update(reason='CORRECTED_GAME_VALUE'),True))
    def test_row_index_is_required(self):self.reject(edited(lambda p,s:p['readings'][0].pop('ocr_observation_index')))
    def test_row_index_cannot_duplicate(self):self.reject(edited(lambda p,s:p['readings'][1].update(ocr_observation_index=0)))
    def test_row_index_must_be_in_examined_range(self):self.reject(edited(lambda p,s:p['readings'][0].update(ocr_observation_index=96)))
    def test_row_index_boolean_is_rejected(self):self.reject(edited(lambda p,s:p['readings'][0].update(ocr_observation_index=True)))
    def test_row_source_cannot_change(self):self.reject(edited(lambda p,s:p['readings'][0].update(source_image_sha256='0'*64)))
    def test_row_cannot_have_a_current_value_key(self):self.reject(edited(lambda p,s:p['readings'][0].update(key='own.hp')))
    def test_row_cannot_drop_alternatives(self):self.reject(edited(lambda p,s:p['readings'][0].pop('ocr_alternatives')))
    def test_geometry_source_cannot_be_promoted(self):self.reject(edited(lambda p,s:p['readings'][0].update(roi_owner_certified=True)))
    def test_unbound_count_cannot_be_forged(self):self.reject(self.tamper(unbound_roi_count=1))
    def test_unbound_geometry_is_counted_as_unbound_metadata_only(self):
        s,p=unpack(request_fixture());row=p['readings'][3];row.pop('roi_rect');row.pop('roi_source')
        p['ocr_request_audit']['unbound_roi_count']=1
        self.assertFalse(validate_ocr_request(p,s)['execution_attested'])
    def test_accuracy_or_device_or_owner_cannot_be_promoted(self):
        for field in ['ocr_accuracy_certified','device_certified','owner_certified','current_state_eligible','battle_advice_authorized']:
            with self.subTest(field=field):self.reject(self.tamper(**{field:True}))
    def test_request_is_not_an_execution_signature(self):self.reject(self.tamper(execution_attestation='CERTIFIED_BY_APPLE'))
    def test_missing_audit_is_rejected(self):self.reject(edited(lambda p,s:p.pop('ocr_request_audit')))
    def test_missing_engine_version_is_rejected(self):self.reject(edited(lambda p,s:p.pop('ocr_engine_version')))
    def test_indexed_rows_cannot_silently_be_legacy(self):
        def edit(p,s):p.pop('ocr_engine_version');p.pop('ocr_request_audit')
        self.reject(edited(edit))
    def test_unknown_audit_field_is_rejected(self):self.reject(self.tamper(capture_certified=True))

if __name__=='__main__':unittest.main()
