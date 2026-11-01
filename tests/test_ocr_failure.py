"""Failure/image binding and canonical input bounds; no OCR accuracy claims."""
import copy,json,unittest
import test_evidence_verifier as base
from test_layout_reading import unpack
from r553_fixture import source_update
from r558_fixture import request_fixture
from verify_ocr_failures import validate_vision_input,validate_ocr_failure
from schema_contract import validate_document

def input_metadata(width,height):
    row=((width*4+63)//64)*64
    return dict(schema='trueplan.ocr.vision-input.v1',handler='CVPIXELBUFFER_BGRA8_UP',
        normalization='SRGB8_WHITE_COMPOSITE_NO_GEOMETRY_CHANGE',width=width,height=height,bytes_per_row=row,
        allocation_bytes=row*height,visible_pixel_bytes=width*height*4,visible_pixel_sha256='ab'*32,
        source_pixel_equality_certified=False)

def input_fixture(edit=None):
    files=request_fixture();s,p=unpack(files)
    a=p['ocr_request_audit'];a['engine_version']=p['ocr_engine_version']='r559.full-frame.v2'
    a['vision_input']=input_metadata(a['image_width'],a['image_height'])
    if edit:edit(a,p)
    return source_update(files,s,p)

def failure_fixture(edit=None,no_image=False):
    files=base.fixture();s=json.loads(files['selected_evidence.json']);image=s['analysis_image']
    s['research_candidate_envelope']=s['screen_read_state']=None
    f=dict(schema='trueplan.ocr.failure.v1',status='OCR_FAILED_NO_RESULT',capture_session_id='capture-test',frame_id=17,epoch=3,
        receipt_uptime_ms=1200,attempted_image_sha256=image['png_sha256'],attempted_image_width=image['width'],
        attempted_image_height=image['height'],error_codes=[dict(domain='TextRecognition.CRImageReaderError',code=0)],
        execution_attestation='SELF_REPORTED_NO_SIGNATURE',automatic_retry_count=0,raw_error_messages_included=False,
        current_state_eligible=False,owner_certified=False,ocr_accuracy_certified=False,battle_advice_authorized=False)
    if no_image:
        s['analysis_image']=None;f.update(attempted_image_sha256=None,attempted_image_width=0,attempted_image_height=0)
    s['r559_ocr_failure']=f
    if edit:edit(f,s)
    files['selected_evidence.json']=base.encoded(s);return files

class OCRFailureTests(unittest.TestCase):
    setUp=base.EvidenceVerifierTests.setUp
    tearDown=base.EvidenceVerifierTests.tearDown
    verify=base.EvidenceVerifierTests.verify
    reject=base.EvidenceVerifierTests.reject
    def input_edit(self,**changes):return input_fixture(lambda a,p:a['vision_input'].update(changes))
    def failure_edit(self,**changes):return failure_fixture(lambda f,s:f.update(changes))
    def test_new_input_route_archive(self):self.verify(input_fixture())
    def test_old_request_archive_still_verifies(self):self.verify(request_fixture())
    def test_new_request_requires_input(self):self.reject(input_fixture(lambda a,p:a.pop('vision_input')))
    def test_old_request_cannot_disguise_new_input(self):
        def edit(a,p):a['engine_version']=p['ocr_engine_version']='r558.full-frame.v1'
        self.reject(input_fixture(edit))
    def test_input_handler_is_declared(self):self.reject(self.input_edit(handler='CGIMAGE_UP'))
    def test_input_normalization_is_explicit(self):self.reject(self.input_edit(normalization='PIXEL_IDENTICAL'))
    def test_input_dimension_must_match_source(self):self.reject(self.input_edit(width=2))
    def test_input_cannot_claim_pixel_certification(self):self.reject(self.input_edit(source_pixel_equality_certified=True))
    def test_input_boolean_sizes_rejected(self):
        for k in ['width','height','bytes_per_row','allocation_bytes','visible_pixel_bytes']:
            with self.subTest(k=k):self.reject(self.input_edit(**{k:True}))
    def test_short_row_rejected(self):self.reject(self.input_edit(bytes_per_row=1))
    def test_unbounded_row_rejected(self):self.reject(self.input_edit(bytes_per_row=16385))
    def test_short_allocation_rejected(self):self.reject(self.input_edit(allocation_bytes=1))
    def test_large_allocation_rejected(self):self.reject(self.input_edit(allocation_bytes=20_000_001))
    def test_visible_bytes_count_rejected(self):self.reject(self.input_edit(visible_pixel_bytes=1))
    def test_input_digest_format_rejected(self):self.reject(self.input_edit(visible_pixel_sha256='z'*64))
    def test_input_unknown_fields_rejected(self):self.reject(self.input_edit(file_path='/private/foo'))
    def test_row_padding_is_allowed_but_not_counted_as_visible(self):
        m=input_metadata(7,5);self.assertTrue(validate_vision_input(m,7,5));self.assertEqual(m['visible_pixel_bytes'],140)
    def test_input_is_only_structural_metadata(self):
        s,p=unpack(input_fixture());validate_document(p['ocr_request_audit']);validate_document(p['ocr_request_audit']['vision_input'])
    def test_input_schema_also_rejects_promotions(self):
        m=input_metadata(7,5);m['source_pixel_equality_certified']=True
        with self.assertRaises(Exception):validate_document(m)
    def test_failure_archive_has_image_without_success(self):self.verify(failure_fixture())
    def test_pre_image_failure_is_explicit(self):self.verify(failure_fixture(no_image=True))
    def test_failure_cannot_hide_source_frame(self):self.reject(self.failure_edit(frame_id=18))
    def test_failure_cannot_hide_source_epoch(self):self.reject(self.failure_edit(epoch=4))
    def test_failure_cannot_hide_source_receipt(self):self.reject(self.failure_edit(receipt_uptime_ms=1201))
    def test_failure_cannot_hide_source_session(self):self.reject(self.failure_edit(capture_session_id='foreign'))
    def test_failure_requires_exact_image_hash(self):self.reject(self.failure_edit(attempted_image_sha256='0'*64))
    def test_failure_requires_exact_image_dimensions(self):self.reject(self.failure_edit(attempted_image_width=3))
    def test_failure_identity_and_sizes_are_not_boolean(self):
        for k in ['frame_id','epoch','receipt_uptime_ms','attempted_image_width','attempted_image_height','automatic_retry_count']:
            with self.subTest(k=k):self.reject(self.failure_edit(**{k:True}))
    def test_failure_does_not_allow_same_frame_success_packet(self):
        packet=json.loads(base.fixture()['selected_evidence.json'])['research_candidate_envelope']
        self.reject(failure_fixture(lambda f,s:s.update(research_candidate_envelope=packet)))
    def test_failure_does_not_allow_snapshot_without_packet(self):
        self.reject(failure_fixture(lambda f,s:s.update(screen_read_state={})))
    def test_failure_cannot_silently_drop_failed_png(self):
        self.reject(failure_fixture(lambda f,s:s.update(analysis_image=None)))
    def test_failed_png_still_requires_crc_sha_and_data(self):
        self.reject(failure_fixture(lambda f,s:s['analysis_image'].update(image_png_base64='AAAA')))
    def test_failed_png_bytes_cannot_change(self):
        self.reject(failure_fixture(lambda f,s:s['analysis_image'].update(png_bytes=1)))
    def test_failure_cannot_claim_success(self):self.reject(self.failure_edit(status='OCR_SUCCEEDED'))
    def test_failure_flags_cannot_promote_or_expose_details(self):
        for k in ['raw_error_messages_included','current_state_eligible','owner_certified','ocr_accuracy_certified','battle_advice_authorized']:
            with self.subTest(k=k):self.reject(self.failure_edit(**{k:True}))
    def test_failure_has_no_automatic_retry_loop(self):self.reject(self.failure_edit(automatic_retry_count=1))
    def test_failure_requires_one_to_four_error_codes(self):
        for v in [[],[dict(domain='error',code=1)]*5]:self.reject(self.failure_edit(error_codes=v))
    def test_failure_error_code_cannot_be_boolean(self):self.reject(self.failure_edit(error_codes=[dict(domain='error',code=True)]))
    def test_failure_error_domain_cannot_contain_path_or_messages(self):
        for v in ['file:/private/image.png','Vision private message','', 'a'*129,'Private_Sentinel']:
            with self.subTest(v=v):self.reject(self.failure_edit(error_codes=[dict(domain=v,code=0)]))
    def test_failure_user_info_is_not_saved(self):self.reject(self.failure_edit(error_codes=[dict(domain='error',code=0,user_info={})]))
    def test_failure_unknown_field_rejected(self):self.reject(self.failure_edit(localizedDescription='private'))
    def test_failure_is_not_execution_attestation(self):
        s=json.loads(failure_fixture()['selected_evidence.json']);self.assertFalse(validate_ocr_failure(s['r559_ocr_failure'],s)['execution_attested'])
    def test_failure_standard_schema_accepts_bounded_codes(self):
        s=json.loads(failure_fixture()['selected_evidence.json']);validate_document(s['r559_ocr_failure'])
    def test_redacted_unknown_error_domain_is_allowed(self):
        self.verify(self.failure_edit(error_codes=[dict(domain='OTHER_ERROR_DOMAIN',code=-7)]))
    def test_system_error_codes_survive_without_descriptions(self):
        self.verify(self.failure_edit(error_codes=[dict(domain='NSCocoaErrorDomain',code=640),
            dict(domain='NSPOSIXErrorDomain',code=28)]))

if __name__=='__main__':unittest.main()
