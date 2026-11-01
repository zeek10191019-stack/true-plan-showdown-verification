import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1] / 'tools'))
from r599_source_audit import audit

class SourceAuditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'app/ios/ChampionsOnDevice'
        self.path.mkdir(parents=True)

    def test_absent_parent_is_hold(self):
        self.assertEqual(audit(self.path.parents[2])['production_hook'], 'HOLD_PARENT_R595_MISSING')

    def test_no_production_callsite_false_positive(self):
        (self.path/'R595FormReferenceMatcher.swift').write_text('struct R595FormReferenceMatcher {}')
        (self.path/'R599BoundOneButton.swift').write_text('struct R599BoundOneButton {}')
        report = audit(self.path.parents[2])
        self.assertTrue(report['r595_present'])
        self.assertTrue(report['new_r599_binding_adapter_present'])
        self.assertFalse(report['one_button_production_invocation_verified'])
        self.assertFalse(report['ready'])
        self.assertEqual(report['candidate_production_files'], [])

    def test_collect_declarations_not_proof(self):
        (self.path/'R595FormReferenceMatcher.swift').write_text('struct R595FormReferenceMatcher {}')
        (self.path/'OneButtonCapture.swift').write_text('func collectDiagnosticZIP() {}\nfunc foo() {}')
        report = audit(self.path.parents[2])
        self.assertIn('OneButtonCapture.swift', [r['file'] for r in report['candidate_production_files']])
        self.assertFalse(report['one_button_production_invocation_verified'])

    def test_ignores_r598_research_adapter_as_entrypoint(self):
        (self.path/'R595FormReferenceMatcher.swift').write_text('struct R595FormReferenceMatcher {}')
        (self.path/'R598OneButtonFormAttachment.swift').write_text('func collectResearchZip() {}')
        self.assertFalse(audit(self.path.parents[2])['candidate_production_files'])

if __name__ == '__main__': unittest.main()
