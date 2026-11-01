import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SourceContract(unittest.TestCase):
    def setUp(self):
        self.swift=(ROOT/'app/ios/ChampionsOnDevice/R609VisionTextSpatialEvidence.swift').read_text()
        self.coordinator=(ROOT/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift').read_text()
    def test_one_production_seam(self):
        self.assertEqual(self.coordinator.count('R608FramePixelEvidence.beforeZip('),1)
        self.assertEqual(self.coordinator.count('R609VisionTextSpatialEvidence.beforeZip('),1)
        self.assertIn('let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)',self.coordinator)
    def test_actual_ocr_and_box(self):
        for token in ('VNRecognizeTextRequest()','VNImageRequestHandler(data:data,orientation:.up',
                      'result.boundingBox','best.confidence','"ja-JP","en-US"',
                      'R598OneButtonFormAttachment.testDigest(image.bytes)==hash'):
            self.assertIn(token,self.swift)
    def test_no_false_promotion(self):
        for token in ('"certified_for_battle":false','"owner_verified":false',
                      '"roi_verified":false','"display_orientation_verified":false',
                      '"mega_verified":false','"UP_NOT_SCREEN_VERIFIED"'):
            self.assertIn(token,self.swift)
    def test_explicit_frame_provenance(self):
        for token in ('"epoch":epoch','"frame_id":frame','"original_png_sha256":hash',
                      'HOLD_DUPLICATE_FRAME_ID','HOLD_ORIGINAL_PNG_OR_R608_BINDING_NOT_VERIFIED',
                      'RAW_ROW_FLIPPED_VERTICALLY','RAW_ROW_EQUALS_VISION_BOTTOM'):
            self.assertIn(token,self.swift)
if __name__=='__main__':unittest.main()
