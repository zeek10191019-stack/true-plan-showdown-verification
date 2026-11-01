import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SWIFT=ROOT/'app/ios/ChampionsOnDevice/R617R620RotationReadout.swift'
WRITER=ROOT/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift'
class SourceContract(unittest.TestCase):
 def test_four_orientations_with_vision(self):
  s=SWIFT.read_text()
  for t in ['VNRecognizeTextRequest()','CGImagePropertyOrientation',
            '("UP",.up)', '("RIGHT",.right)', '("DOWN",.down)', '("LEFT",.left)',
            '"ja-JP","en-US"', 'maxFrames = 2','maxTokensPerRotation = 12']:
   self.assertIn(t,s)
 def test_no_actor_field_promotion(self):
  s=SWIFT.read_text()
  for t in ['"certified_for_battle":false','"owner_verified":false',
            '"roi_verified":false','"mega_verified":false',
            '"display_orientation_verified":false']:
   self.assertIn(t,s)
  for t in ['"owner_verified":true','"certified_for_battle":true']:
   self.assertNotIn(t,s)
 def test_single_zip_writing_seam(self):
  s=WRITER.read_text()
  self.assertEqual(s.count('R548ResearchArchive.write('),1)
  self.assertEqual(s.count('R617R620RotationReadout.beforeZip('),1)
  self.assertIn('let r617Entries = R617R620RotationReadout.beforeZip(r613Entries)',s)
 def test_old_source_is_dependent_not_terminal(self):
  s=(ROOT/'tests/test_r613batch_source.py').read_text()
  self.assertNotIn("self.assertIn('r613Entries, to: zipURL, work: exportWork',s)",s)
  self.assertIn('let r613Entries = R613R616IntegratedReadiness.beforeZip(r612Entries)',s)
if __name__=='__main__':unittest.main()
