from pathlib import Path
import unittest
class Case(unittest.TestCase):
    def setUp(self):
        self.s=Path(__file__).resolve().parents[1].joinpath('app/ios/ChampionsOnDevice/R607FrameProvenanceAudit.swift').read_text()
    def test_certification_disabled(self):
        for x in ['"owner_verified":false','"orientation_verified":false',
                  '"mega_verified":false','"full_frame_identity_verified":false']:
            self.assertIn(x,self.s)
    def test_hash_reverification(self):
        self.assertIn('original_r604_snapshot_sha256',self.s)
        self.assertIn('R598OneButtonFormAttachment.testDigest(entry.bytes)',self.s)
    def test_frame_reuse_guard(self):
        self.assertIn('HOLD_SHARED_BYTES_ACROSS_FRAME_IDS',self.s)
    def test_constrained_storage(self):
        self.assertIn('R548ResearchArchive.maximumMembers',self.s)
    def test_report_ambiguity(self):
        self.assertIn('HOLD_REPORT_INCONSISTENT',self.s)
if __name__=='__main__':unittest.main()
