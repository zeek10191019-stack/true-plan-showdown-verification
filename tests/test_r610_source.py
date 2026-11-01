import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SourceContract(unittest.TestCase):
    def setUp(self):
        self.swift=(ROOT/'app/ios/ChampionsOnDevice/R610CrossEvidenceCandidate.swift').read_text()
        self.target=(ROOT/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift').read_text()
    def test_exact_zip_writer(self):
        self.assertEqual(self.target.count('R609VisionTextSpatialEvidence.beforeZip('),1)
        self.assertEqual(self.target.count('R610CrossEvidenceCandidate.beforeZip('),1)
        self.assertIn('let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)',self.target)
    def test_frame_and_png_identity(self):
        for required in ['"epoch"','"frame_id"','"original_png_sha256"','"archive_png"',
                         'sameIdentity(row8,row9)','testDigest(original.bytes)==sha',
                         'spatialRecheck(rel,ocr:ocr[oi],rawColor:colors[bi]',
                         '"r608_original_pixel_evidence.json"','"r609_vision_text_spatial_evidence.json"']:
            self.assertIn(required,self.swift)
    def test_no_battle_certification(self):
        for required in ['"certified_for_battle":false','"owner_verified":false',
                         '"roi_verified":false','"display_orientation_verified":false',
                         '"mega_verified":false','"frame_identity_verified":false',
                         'HOLD_HUD_ROLE_AND_COORDINATES_NOT_CALIBRATED']:
            self.assertIn(required,self.swift)
        self.assertNotIn('"owner_verified":true',self.swift)
        self.assertNotIn('"roi_verified":true',self.swift)
    def test_shape_only(self):
        self.assertIn('NUMERIC_FRACTION_SHAPE_UNVERIFIED',self.swift)
        self.assertIn('PERCENTAGE_SHAPE_UNVERIFIED',self.swift)
        self.assertIn('review_priority_score_not_probability',self.swift)
if __name__=='__main__':unittest.main()
