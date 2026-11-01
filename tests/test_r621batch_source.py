import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SourceContract(unittest.TestCase):
 def test_writer_one_append(self):
  s=(ROOT/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift').read_text()
  self.assertEqual(s.count('R548ResearchArchive.write('),1)
  self.assertEqual(s.count('R621R624VisualCandidates.beforeZip('),1)
  self.assertIn('let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)',s)
  self.assertIn('R621R624VisualCandidates.containsReport(r621Entries)',s)
 def test_source_holds_authentication(self):
  m=(ROOT/'app/ios/ChampionsOnDevice/R621R624VisualCandidates.swift').read_text()
  for t in ['"certified_for_battle":false','"owner_verified":false',
            '"roi_verified":false','"mega_verified":false',
            '"display_orientation_verified":false',
            'R598OneButtonFormAttachment.testDigest(image.bytes)',
            'semanticallyIdentical','r621_r624_embedded_candidate_report']:
   self.assertIn(t,m)
  for forbidden in ['"owner_verified":true','"mega_verified":true']:
   self.assertNotIn(forbidden,m)
 def test_mega_word_is_unverified(self):
  m=(ROOT/'app/ios/ChampionsOnDevice/R617R620RotationReadout.swift').read_text()
  self.assertIn('MEGA_SCENE_TEXT_CUE_UNASSIGNED',m)
  self.assertIn('OCR_SCENE_WORD_NOT_ACTOR_OR_FORM',m)
 def test_old_source_test_is_extendable(self):
  s=(ROOT/'tests/test_r617batch_source.py').read_text()
  self.assertNotIn("self.assertIn('r617Entries, to: zipURL, work: exportWork',s)",s)
  self.assertIn('let r617Entries = R617R620RotationReadout.beforeZip(r613Entries)',s)
