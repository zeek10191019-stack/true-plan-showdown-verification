import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class Source(unittest.TestCase):
 def test_no_unverified_certification(self):
  s=(ROOT/'app/ios/ChampionsOnDevice/R629R632SlotEvidence.swift').read_text()
  for fragment in ['"owner_verified":false','"mega_verified":false',
                   '"certified_for_battle":false','"roi_verified":false',
                   '"display_orientation_verified":false',
                   '"actor":"UNKNOWN"','"hp_value":NSNull()',
                   '"orientation_hypothesis":"UP_ONLY_UNVERIFIED"']:
   self.assertIn(fragment,s)
 def test_real_pixel_reports_required(self):
  s=(ROOT/'app/ios/ChampionsOnDevice/R629R632SlotEvidence.swift').read_text()
  for fragment in ['HOLD_PIXELS_DECODED_NOT_CALIBRATED','original_png_sha256',
                   'colored_runs','r622_ui_slot_hypotheses','max(0,min',
                   'tracks.append','rows.count==2']:
   self.assertIn(fragment,s)
 def test_real_writer_seam_kept(self):
  s=(ROOT/'app/ios/ChampionsOnDevice/R625R628PixelHUDAndSprite.swift').read_text()
  self.assertIn('R629R632SlotEvidence.enrich(&prior)',s)
  self.assertIn('return entries.map',s)
