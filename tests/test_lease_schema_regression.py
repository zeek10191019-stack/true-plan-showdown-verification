"""R571 native failure reproduced from a genuine Swift-generated receipt."""
import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from schema_contract import validate_document
from verify_candidate_lease import validate_candidate_lease

def fixture():return json.loads((ROOT/'fixtures/r571_swift_lease_snapshot.json').read_text())

class LeaseSchemaRegressionTests(unittest.TestCase):
    def reject(self,row):
        with self.assertRaises(Exception):validate_document(row)
    def test_actual_swift_receipt_passes_structure_and_semantics(self):
        row=fixture();self.assertIs(row['strict_retirement_on_new_request'],False)
        validate_document(row);validate_candidate_lease(row)
    def test_fixture_is_pinned_to_a_known_native_failure(self):
        meta=json.loads((ROOT/'fixtures/r571_swift_lease_snapshot_source.json').read_text())
        self.assertEqual(meta['run_id'],41162088651)
        self.assertEqual(hashlib.sha256((ROOT/'fixtures/r571_swift_lease_snapshot.json').read_bytes()).hexdigest(),meta['fixture_sha256'])
    def test_old_v1_without_mode_remains_readable(self):
        row=fixture();row.pop('strict_retirement_on_new_request');validate_document(row);validate_candidate_lease(row)
    def test_strict_mode_accepts_no_pending_old_result(self):
        row=fixture();row['strict_retirement_on_new_request']=True;validate_document(row);validate_candidate_lease(row)
    def test_strict_pending_and_latest_is_structurally_rejected(self):
        row=fixture();row['strict_retirement_on_new_request']=True
        row['pending']={k:v for k,v in row['latest'].items() if k!='image_sha256'}
        self.reject(row)
    def test_legacy_pending_and_latest_is_not_accidentally_banned(self):
        row=fixture();row['pending']={k:v for k,v in row['latest'].items() if k!='image_sha256'}
        validate_document(row) # Ordering is checked independently by the semantic verifier.
    def test_mode_does_not_accept_boolean_like_values(self):
        for value in [0,1,0.0,'true',None,[],{}]:
            row=fixture();row['strict_retirement_on_new_request']=value;self.reject(row)
    def test_arbitrary_additional_fields_still_fail_closed(self):
        row=fixture();row['invented_certification']=True;self.reject(row)
    def test_false_current_or_owner_claims_remain_rejected(self):
        for field in ['current_state_eligible','owner_certified','battle_advice_authorized']:
            row=fixture();row[field]=True;self.reject(row)

if __name__=='__main__':unittest.main()
