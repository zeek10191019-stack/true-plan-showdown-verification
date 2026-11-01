"""Declared policy/source tampering and explicit CI role checks."""
import copy,json,unittest
import test_evidence_verifier as base
from test_ocr_failure import input_fixture,failure_fixture
from test_layout_reading import unpack
from r553_fixture import source_update
from verify_ocr_execution import validate_ocr_execution
from schema_contract import validate_document
from ci_execution_policy import execution_policy

def execution(cpu=False,failed=False,unsupported=False):
    error=[dict(domain='TextRecognition.CRImageReaderError',code=9)]
    primary=dict(mode='FRAMEWORK_DEFAULT',outcome='REQUEST_FAILED' if cpu else 'SUCCEEDED',configuration_accepted=True,
        request_performed=True,supported_stage_count=0,main_stage_present=False,cpu_assigned_stage_count=0,
        software_context_requested=False,error_codes=error if cpu else [])
    attempts=[primary]
    if cpu:
        attempts.append(dict(mode='CPU_SOFTWARE',outcome='CONFIGURATION_FAILED' if unsupported else ('REQUEST_FAILED' if failed else 'SUCCEEDED'),
            configuration_accepted=not unsupported,request_performed=not unsupported,supported_stage_count=2,
            main_stage_present=True,cpu_assigned_stage_count=0 if unsupported else 2,software_context_requested=True,
            error_codes=error if failed or unsupported else []))
    return dict(schema='trueplan.ocr.execution.v1',policy_id='DEFAULT_THEN_CPU_SOFTWARE_ON_IMAGE_ERROR_9_V1',
        status='FAILED' if failed or unsupported else 'SUCCEEDED',attempt_count=len(attempts),attempts=attempts,
        same_input_reused=True,configuration_only=True,compute_execution_attested=False,ocr_accuracy_certified=False,
        owner_certified=False,current_state_eligible=False,battle_advice_authorized=False)

def request_fixture(cpu=False,edit=None):
    files=input_fixture();s,p=unpack(files);p['ocr_engine_version']=p['ocr_request_audit']['engine_version']='r560.full-frame.v3'
    p['ocr_request_audit']['execution_audit']=execution(cpu)
    if edit:edit(p['ocr_request_audit']['execution_audit'],p)
    return source_update(files,s,p)

def failed_fixture(unsupported=False,edit=None):
    def change(f,s):
        f['recovery_audit']=execution(True,failed=True,unsupported=unsupported);f['automatic_retry_count']=1
        f['error_codes']=[code for row in f['recovery_audit']['attempts'] for code in row['error_codes']]
        if edit:edit(f,s)
    return failure_fixture(change)

class RecoveryTests(unittest.TestCase):
    setUp=base.EvidenceVerifierTests.setUp
    tearDown=base.EvidenceVerifierTests.tearDown
    verify=base.EvidenceVerifierTests.verify
    reject=base.EvidenceVerifierTests.reject
    def audit_edit(self,edit,cpu=True):return request_fixture(cpu,lambda a,p:edit(a))
    def attempt_edit(self,**changes):return self.audit_edit(lambda a:a['attempts'][1].update(changes))
    def test_successful_primary_request(self):self.verify(request_fixture())
    def test_successful_declared_cpu_retry(self):self.verify(request_fixture(True))
    def test_failure_with_two_attempts(self):self.verify(failed_fixture())
    def test_cpu_unavailable_failure_is_preserved(self):self.verify(failed_fixture(True))
    def test_v3_requires_execution_audit(self):
        def edit(a,p):p['ocr_request_audit'].pop('execution_audit')
        self.reject(request_fixture(True,edit))
    def test_v2_cannot_silently_claim_v3_execution(self):
        def edit(a,p):p['ocr_engine_version']=p['ocr_request_audit']['engine_version']='r559.full-frame.v2'
        self.reject(request_fixture(True,edit))
    def test_retry_limit_cannot_expand(self):self.reject(self.audit_edit(lambda a:a.update(attempt_count=3,attempts=a['attempts']+[a['attempts'][1]])))
    def test_count_cannot_hide_second_request(self):self.reject(self.audit_edit(lambda a:a.update(attempt_count=1)))
    def test_count_is_not_boolean(self):self.reject(self.audit_edit(lambda a:a.update(attempt_count=True)))
    def test_unknown_execution_field_is_rejected(self):self.reject(self.audit_edit(lambda a:a.update(verified=True)))
    def test_policy_cannot_change(self):self.reject(self.audit_edit(lambda a:a.update(policy_id='RETRY_UNTIL_MATCH')))
    def test_different_image_retry_is_rejected(self):self.reject(self.audit_edit(lambda a:a.update(same_input_reused=False)))
    def test_execution_attestation_cannot_be_claimed(self):self.reject(self.audit_edit(lambda a:a.update(configuration_only=False)))
    def test_all_false_flags_remain_false(self):
        for field in ['compute_execution_attested','ocr_accuracy_certified','owner_certified','current_state_eligible','battle_advice_authorized']:
            with self.subTest(field=field):self.reject(self.audit_edit(lambda a:a.update(**{field:True})))
    def test_result_cannot_be_adopted_after_failed_final_attempt(self):
        self.reject(self.attempt_edit(outcome='REQUEST_FAILED',error_codes=[dict(domain='NSCocoaErrorDomain',code=640)]))
    def test_final_status_cannot_contradict_attempt(self):self.reject(self.audit_edit(lambda a:a.update(status='FAILED')))
    def test_cpu_is_not_first_attempt(self):self.reject(self.audit_edit(lambda a:a['attempts'].reverse()))
    def test_success_does_not_allow_another_attempt(self):
        self.reject(self.audit_edit(lambda a:a['attempts'][0].update(outcome='SUCCEEDED',error_codes=[])))
    def test_different_error_code_does_not_authorize_retry(self):
        self.reject(self.audit_edit(lambda a:a['attempts'][0]['error_codes'][0].update(code=8)))
    def test_different_error_domain_does_not_authorize_retry(self):
        self.reject(self.audit_edit(lambda a:a['attempts'][0]['error_codes'][0].update(domain='NSCocoaErrorDomain')))
    def test_retry_requires_primary_error(self):self.reject(self.audit_edit(lambda a:a['attempts'][0].update(error_codes=[])))
    def test_boolean_error_code_is_rejected(self):self.reject(self.audit_edit(lambda a:a['attempts'][0]['error_codes'][0].update(code=True)))
    def test_error_domain_must_be_a_safe_known_string(self):
        for domain in [['private'],{},'private/path']:
            with self.subTest(domain=domain):self.reject(self.audit_edit(lambda a:a['attempts'][0]['error_codes'][0].update(domain=domain)))
    def test_cpu_requires_main_stage(self):self.reject(self.attempt_edit(main_stage_present=False))
    def test_cpu_requires_supported_stages(self):self.reject(self.attempt_edit(supported_stage_count=0,cpu_assigned_stage_count=0))
    def test_cpu_requires_every_stage_assigned(self):self.reject(self.attempt_edit(cpu_assigned_stage_count=1))
    def test_cpu_stage_queries_are_bounded_before_execution(self):self.reject(self.attempt_edit(supported_stage_count=17,cpu_assigned_stage_count=17))
    def test_more_assigned_stages_than_supported_is_rejected(self):self.reject(self.attempt_edit(cpu_assigned_stage_count=3))
    def test_stage_counts_cannot_be_boolean(self):
        for k in ['supported_stage_count','cpu_assigned_stage_count']:
            with self.subTest(k=k):self.reject(self.attempt_edit(**{k:True}))
    def test_software_context_is_explicit(self):self.reject(self.attempt_edit(software_context_requested=False))
    def test_configuration_must_be_accepted_before_perform(self):self.reject(self.attempt_edit(configuration_accepted=False))
    def test_success_requires_perform(self):self.reject(self.attempt_edit(request_performed=False))
    def test_success_cannot_carry_error_codes(self):self.reject(self.attempt_edit(error_codes=[dict(domain='OTHER_ERROR_DOMAIN',code=0)]))
    def test_attempt_boolean_fields_are_strict(self):
        for k in ['configuration_accepted','request_performed','main_stage_present','software_context_requested']:
            with self.subTest(k=k):self.reject(self.attempt_edit(**{k:1}))
    def test_attempt_unknown_field_is_rejected(self):self.reject(self.attempt_edit(userInfo='private'))
    def test_first_attempt_does_not_claim_cpu_assignment(self):
        self.reject(self.audit_edit(lambda a:a['attempts'][0].update(supported_stage_count=1,cpu_assigned_stage_count=1)))
    def test_failure_retry_count_matches_audit(self):self.reject(failed_fixture(edit=lambda f,s:f.update(automatic_retry_count=0)))
    def test_failure_error_codes_match_attempts(self):self.reject(failed_fixture(edit=lambda f,s:f['error_codes'].pop()))
    def test_failure_cannot_attach_successful_recovery(self):self.reject(failed_fixture(edit=lambda f,s:f.update(recovery_audit=execution(True))))
    def test_unsupported_cpu_cannot_partially_assign(self):
        self.reject(failed_fixture(True,lambda f,s:f['recovery_audit']['attempts'][1].update(cpu_assigned_stage_count=1)))
    def test_unsupported_cpu_cannot_claim_it_performed(self):
        self.reject(failed_fixture(True,lambda f,s:f['recovery_audit']['attempts'][1].update(request_performed=True)))
    def test_standard_schemas_cover_execution_and_request_and_failure(self):
        for files in [request_fixture(),request_fixture(True)]:
            s,p=unpack(files);validate_document(p['ocr_request_audit']);validate_document(p['ocr_request_audit']['execution_audit'])
        s=json.loads(failed_fixture()['selected_evidence.json']);validate_document(s['r559_ocr_failure'])
    def test_failed_metadata_is_not_hardware_attestation(self):
        self.assertFalse(validate_ocr_execution(execution(True,failed=True))['compute_execution_attested'])
    def test_single_unrelated_error_stops_without_retry(self):
        a=execution();a.update(status='FAILED');a['attempts'][0].update(outcome='REQUEST_FAILED',error_codes=[dict(domain='NSCocoaErrorDomain',code=640)])
        validate_ocr_execution(a,success=False)
    def test_known_error_cannot_be_reported_as_stopped_without_attempting_cpu(self):
        a=execution(True,failed=True);a['attempts'].pop();a['attempt_count']=1
        with self.assertRaises(ValueError):validate_ocr_execution(a)

class CIRoleTests(unittest.TestCase):
    def test_ios27_build_role(self):self.assertTrue(execution_policy('IOS27_NATIVE','Darwin','arm64','27.1')['requires_iPhoneOS27_build'])
    def test_portable_role_never_claims_ios27_build(self):
        p=execution_policy('PORTABLE_OCR','Darwin','x86_64','26.2');self.assertFalse(p['requires_iPhoneOS27_build']);self.assertEqual(p['iPhoneOS_build_scope'],'NOT_RUN_PORTABLE_ROLE')
    def test_unknown_role_is_rejected(self):
        with self.assertRaises(ValueError):execution_policy('PAID_LARGE','Darwin','arm64','27.1')
    def test_native_role_rejects_old_sdk(self):
        with self.assertRaises(ValueError):execution_policy('IOS27_NATIVE','Darwin','arm64','26.2')
    def test_native_role_rejects_intel(self):
        with self.assertRaises(ValueError):execution_policy('IOS27_NATIVE','Darwin','x86_64','27.1')
    def test_portable_role_rejects_arm(self):
        with self.assertRaises(ValueError):execution_policy('PORTABLE_OCR','Darwin','arm64','27.1')
    def test_non_apple_system_is_rejected(self):
        with self.assertRaises(ValueError):execution_policy('IOS27_NATIVE','Linux','arm64','27.1')
    def test_invalid_sdk_is_rejected(self):
        for v in ['invalid',None,'']:
            with self.subTest(v=v),self.assertRaises(ValueError):execution_policy('PORTABLE_OCR','Darwin','x86_64',v)
    def test_portable_still_requires_modern_apple_sdk(self):
        with self.assertRaises(ValueError):execution_policy('PORTABLE_OCR','Darwin','x86_64','16.4')

if __name__=='__main__':unittest.main()
