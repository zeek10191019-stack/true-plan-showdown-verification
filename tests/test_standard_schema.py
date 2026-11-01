"""Pinned Draft-07 validator over real fixture contracts and adverse changes."""
import copy,json,unittest
from pathlib import Path
from unittest.mock import patch
import test_evidence_verifier
from r553_fixture import menu_fixture,alternative_fixture
from r557_fixture import screen_fixture,screen_conflict_fixture
from r558_fixture import request_fixture
from test_state_semantics import state_fixture
from test_layout_reading import unpack
from schema_contract import ROOT,DRAFT,compile_standard,validate_document,validators,verify_vendor
from audit_json_schemas import audit

class StandardSchemaTests(unittest.TestCase):
    def state(self,files):return unpack(files)[0]['screen_read_state']
    def reject(self,data):
        from _vendor.fastjsonschema import JsonSchemaException
        with self.assertRaises(JsonSchemaException):validate_document(data)
    def test_all_current_schema_documents_compile_as_draft7(self):
        self.assertEqual(set(validators()),{'trueplan.screen-read.png-replay.v1','trueplan.ocr.execution.v1','trueplan.ocr.failure.v1','trueplan.ocr.request-audit.v1','trueplan.ocr.vision-input.v1',
            'trueplan.screen-read.analysis-projection.v1','trueplan.screen-read.candidate-lease.v1','trueplan.screen-read.layout-candidates.v1',
            'trueplan.screen-read.screen-evidence.v1','trueplan.screen-read.snapshot.v1','trueplan.screen-read.clock-admission.v1','trueplan.screen-read.live-work-slot.v1','trueplan.screen-read.input-health.v1','trueplan.screen-read.source-bound-hints.v2'})
    def test_upstream_validator_source_bytes_are_pinned(self):
        self.assertEqual(len(verify_vendor()['files']),11)
    def test_structured_legacy_snapshot_contract(self):validate_document(self.state(state_fixture([('81%','hp_percent',81)])))
    def test_plain_legacy_menu_contract(self):validate_document(self.state(menu_fixture()))
    def test_ranked_alternative_conflict_contract(self):validate_document(self.state(alternative_fixture()))
    def test_new_plain_screen_contract(self):validate_document(self.state(screen_fixture(False)))
    def test_new_details_panel_contract_with_five_anchors(self):
        state=self.state(screen_fixture());self.assertEqual(len(state['layout_candidates']['anchors']),5);validate_document(state)
    def test_old_contract_reproduces_the_details_panel_schema_failure(self):
        old=json.loads((ROOT/'schema/history/r557_draft202012/screen-read.snapshot.v1.schema.json').read_text())
        def dialect_only(value):
            if isinstance(value,list):return [dialect_only(v) for v in value]
            if not isinstance(value,dict):return value
            result={}
            for key,child in value.items():
                if key=='$schema':child=DRAFT
                if key=='$ref':child=child.replace('#/$defs/','#/definitions/')
                result['definitions' if key=='$defs' else key]=dialect_only(child)
            return result
        validate=compile_standard(dialect_only(old))
        from _vendor.fastjsonschema import JsonSchemaException
        with self.assertRaises(JsonSchemaException):validate(self.state(screen_fixture()))
    def test_screen_conflict_and_unknown_contracts(self):
        validate_document(self.state(screen_conflict_fixture()));validate_document(self.state(screen_conflict_fixture(True)))
    def test_request_metadata_contract(self):
        selected,packet=unpack(request_fixture());validate_document(packet['ocr_request_audit'])
    def test_missing_required_new_classification_is_rejected(self):
        state=self.state(screen_fixture());state.pop('screen_classification');self.reject(state)
    def test_new_classification_cannot_be_a_legacy_snapshot(self):
        state=self.state(screen_fixture());state['screen_read_engine_version']='r553.snapshot.v1';self.reject(state)
    def test_unknown_engine_version_is_rejected(self):
        state=self.state(screen_fixture());state['screen_read_engine_version']='CERTIFIED';self.reject(state)
    def test_unknown_layout_profile_is_rejected(self):
        state=self.state(screen_fixture());state['layout_candidates']['profile_id']='ANY_LAYOUT';self.reject(state)
    def test_legacy_profile_cannot_claim_five_anchors(self):
        state=self.state(screen_fixture());state['layout_candidates']['profile_id']='LEGACY_VERTICAL_MOVES_216_V1';self.reject(state)
    def test_details_profile_has_bounded_anchors(self):
        state=self.state(screen_fixture());state['layout_candidates']['anchors']*=2;self.reject(state)
    def test_derived_seven_anchor_limit_matches_four_panel_labels(self):
        state=self.state(screen_fixture())
        state['layout_candidates']['anchors'].extend([dict(role_hint='overlay_命中'),dict(role_hint='overlay_効果範囲')])
        validate_document(state)  # Structural bound only, not source validity.
    def test_structural_acceptance_is_not_provenance_acceptance(self):
        state=self.state(screen_fixture());state['layout_candidates']['anchors'][0]['reading_index']=999
        validate_document(state)  # Independent archive verifier must still reject the source claim.
        from test_layout_reading import edited
        with test_evidence_verifier.tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'bad.zip'
            files=edited(screen_fixture(),lambda s,p:s['layout_candidates']['anchors'][0].update(reading_index=999))
            path.write_bytes(test_evidence_verifier.archive(test_evidence_verifier.indexed(files)))
            with self.assertRaises(test_evidence_verifier.EvidenceError):test_evidence_verifier.verify_archive(path)
    def test_screen_owner_promotion_is_rejected_by_schema(self):
        state=self.state(screen_fixture());state['screen_classification']['owner_certified']=True;self.reject(state)
    def test_request_accuracy_promotion_is_rejected_by_schema(self):
        s,p=unpack(request_fixture());p['ocr_request_audit']['ocr_accuracy_certified']=True;self.reject(p['ocr_request_audit'])
    def test_request_manual_fast_contradiction_is_rejected_by_schema(self):
        s,p=unpack(request_fixture());p['ocr_request_audit']['effective_recognition_level']='fast';self.reject(p['ocr_request_audit'])
    def test_remote_ref_cannot_trigger_network(self):
        with patch('urllib.request.urlopen',side_effect=AssertionError('NETWORK_FORBIDDEN')) as network:
            with self.assertRaisesRegex(ValueError,'ONLY_LOCAL_SCHEMA_REFERENCES'):
                compile_standard({'$schema':DRAFT,'$ref':'https://example.invalid/schema'})
            network.assert_not_called()
    def test_draft2020_cannot_silently_use_draft7(self):
        with self.assertRaisesRegex(ValueError,'DRAFT07_REQUIRED'):
            compile_standard({'$schema':'https://json-schema.org/draft/2020-12/schema','type':'object'})
    def test_defaults_are_not_injected(self):
        validate=compile_standard({'$schema':DRAFT,'type':'object','properties':{'x':{'type':'number','default':42}}})
        value={};validate(value);self.assertEqual(value,{})
    def test_validation_does_not_mutate_snapshot(self):
        state=self.state(screen_fixture());before=copy.deepcopy(state);validate_document(state);self.assertEqual(state,before)
    def test_schema_audit_receipts_are_not_reinterpreted_as_data(self):
        with test_evidence_verifier.tempfile.TemporaryDirectory() as directory:
            path=Path(directory);(path/'fixture.json').write_text(json.dumps(self.state(screen_fixture())))
            first=audit(path);(path/'R558_STANDARD_SCHEMA_AUDIT.json').write_text(json.dumps(first))
            self.assertEqual(audit(path),first)

if __name__=='__main__':unittest.main()
