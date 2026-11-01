"""CI enforcement, dependency closure, and bounded numerical-report transport."""
import ast
import base64
import hashlib
import io
import json
import sys
import unittest
import zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from run_r571_native import FLAGS,STATE_NAMES,REGRESSIONS
from verify_ci_publication import decode_report_log,expected_workflow

def log_with_report(data):
    encoded=base64.b85encode(data).decode()
    lines=['R571_REPORT_B85_BEGIN '+hashlib.sha256(data).hexdigest()+' '+str(len(data))]
    lines += ['R571_REPORT_B85 '+encoded[i:i+500] for i in range(0,len(encoded),500)]
    lines += ['R571_REPORT_B85_END']
    return '\n'.join('2026-10-30T20:00:00.0000000Z '+line for line in lines)

class CIEnforcementTests(unittest.TestCase):
    def test_current_publication_path_is_the_file_the_user_uploads(self):
        self.assertEqual(expected_workflow('R571',b'name: test\n')['path'],'.github/workflows/r571.yml')
        self.assertEqual(expected_workflow('R572',b'name: test\n')['path'],'.github/workflows/r572.yml')
    def test_optimized_native_checks_explicitly_enable_assertions(self):
        self.assertIn('-O',FLAGS);index=FLAGS.index('-assert-config');self.assertEqual(FLAGS[index+1],'Debug')
    def test_enforcement_canary_has_a_failure_path(self):
        source=(ROOT/'tools/run_r571_native.py').read_text()
        self.assertIn('guard evaluated else { fatalError("ASSERTS_DISABLED") }',source)
        self.assertIn("'PASS_EVALUATION_CANARY'",source)
    def test_old_receipt_harness_checks_fail_under_optimization(self):
        source=(ROOT/'tests/R570LeaseRetirementHarness.swift').read_text()
        self.assertIn('guard okay else {fatalError(',source);self.assertNotIn('assert(okay',source)
    def test_current_native_state_dependencies_exist(self):
        for name in STATE_NAMES:self.assertTrue((ROOT/'app/ios/ChampionsOnDevice'/name).is_file(),name)
        for name,_,_ in REGRESSIONS:self.assertTrue((ROOT/'tests'/name).is_file(),name)
        self.assertEqual(sum(count for _,_,count in REGRESSIONS),181)
    def test_broad_runner_qualifies_every_state_dependency(self):
        tree=ast.parse((ROOT/'tools/run_macos_checks.py').read_text())
        node=next(node.value for node in ast.walk(tree) if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='state_sources' for t in node.targets))
        self.assertIsInstance(node,ast.ListComp)
        self.assertEqual(ast.literal_eval(node.generators[0].iter),STATE_NAMES)
    def test_report_round_trip_does_not_certify_native_or_game(self):
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('R571_SUMMARY.json',json.dumps(dict(status='PASS_SYNTHETIC_ONLY')))
        receipt=decode_report_log(log_with_report(out.getvalue()),'R571')
        self.assertEqual(receipt['zip_bytes'],out.getvalue())
        self.assertFalse(receipt['native_CI_certified']);self.assertFalse(receipt['real_game_accuracy_certified'])
    def test_report_duplicate_begin_is_rejected(self):
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w') as archive:archive.writestr('result.json','{}')
        log=log_with_report(out.getvalue())
        with self.assertRaises(ValueError):decode_report_log(log+'\n'+log,'R571')
    def test_report_path_escape_is_rejected_before_extraction(self):
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w') as archive:archive.writestr('../result.json','{}')
        with self.assertRaisesRegex(ValueError,'REPORT_UNSAFE'):decode_report_log(log_with_report(out.getvalue()),'R571')
    def test_report_changed_hash_is_rejected(self):
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w') as archive:archive.writestr('result.json','{}')
        log=log_with_report(out.getvalue()).replace(hashlib.sha256(out.getvalue()).hexdigest(),'0'*64)
        with self.assertRaisesRegex(ValueError,'REPORT_SIZE_OR_SHA256'):decode_report_log(log,'R571')

if __name__=='__main__':unittest.main()
