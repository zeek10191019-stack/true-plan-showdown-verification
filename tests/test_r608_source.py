import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class R608SourceContract(unittest.TestCase):
    def setUp(self):
        self.swift=(ROOT/'app/ios/ChampionsOnDevice/R608FramePixelEvidence.swift').read_text()
        self.coordinator=(ROOT/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift').read_text()
    def test_existing_r607_seam_and_next_wrapper(self):
        self.assertEqual(self.coordinator.count('R607FrameProvenanceAudit.beforeZip('),1)
        self.assertEqual(self.coordinator.count('R608FramePixelEvidence.beforeZip('),1)
    def test_no_claims(self):
        for text in ('"owner_verified":false','"display_orientation_verified":false',
                     '"roi_verified":false','"mega_verified":false',
                     '"certified_for_battle":false'):
            self.assertIn(text,self.swift)
    def test_real_png_decode_and_crc(self):
        for text in ('CGImageSourceCreateImageAtIndex','png_ihdr_crc_verified',
                     'crc32(b[12..<29])','SATURATED_HORIZONTAL_COLOR_RUN_UNVERIFIED'):
            self.assertIn(text,self.swift)
    def test_sha_against_archive(self):
        self.assertIn('R598OneButtonFormAttachment.testDigest(match.bytes)==hash',self.swift)
if __name__=='__main__':unittest.main()
