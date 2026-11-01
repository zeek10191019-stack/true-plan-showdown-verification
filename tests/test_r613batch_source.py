import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'app/ios/ChampionsOnDevice'
class Source(unittest.TestCase):
    def test_source_fails_closed(self):
        s=(S/'R613R616IntegratedReadiness.swift').read_text()
        for token in ['HOLD_NEEDS_LABELED_UI_CALIBRATION','HOLD_FRAME_OR_IMAGE_LINEAGE_CONTRADICTION',
                      'HOLD_SOURCE_MISSING_OR_CONTRADICTORY','HOLD_OCR_RECT_OR_HYPOTHESIS_CONTRADICTION',
                      '"certified_for_battle":false','"owner_verified":false','"mega_verified":false']:
            self.assertIn(token,s)
    def test_archive_single_writer(self):
        s=(S/'CaptureCoordinator.swift').read_text()
        self.assertEqual(s.count('R613R616IntegratedReadiness.beforeZip('),1)
        self.assertEqual(s.count('R548ResearchArchive.write('),1)
        self.assertIn('let r613Entries = R613R616IntegratedReadiness.beforeZip(r612Entries)',s)
    def test_no_automated_ownership_claim(self):
        s=(S/'R613R616IntegratedReadiness.swift').read_text()
        for token in ['"owner_verified":true','"mega_verified":true','"certified_for_battle":true']:
            self.assertNotIn(token,s)
    def test_old_test_decoupled_from_final_writer(self):
        s=(ROOT/'tests/test_r611batch_integration.py').read_text()
        self.assertNotIn("'r612Entries, to: zipURL, work: exportWork'",s)
        self.assertIn('let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)',s)
if __name__=='__main__':unittest.main()
