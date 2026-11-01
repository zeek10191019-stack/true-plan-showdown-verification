import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SWIFT=ROOT/'app/ios/ChampionsOnDevice/R625R628PixelHUDAndSprite.swift'
WRITER=ROOT/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift'
LEGACY=ROOT/'tests/test_r621batch_source.py'

class Contract(unittest.TestCase):
 def test_real_pixel_decoding(self):
  s=SWIFT.read_text()
  for term in ('CGImageSourceCreateWithData','CGImageSourceCreateImageAtIndex',
               'CGContext(data:nil','probeRGBA','GREEN_LIKE','RED_LIKE',
               'YELLOW_LIKE','original_png_sha256','testDigest(image.bytes)'):
   self.assertIn(term,s)
 def test_pixel_and_sprite_separation(self):
  s=SWIFT.read_text()
  for term in ('dhash64','UNVERIFIED_VISUAL_CHANGE_NOT_MEGA_EVOLUTION',
               'HOLD_PIXEL_LOCATIONS_NOT_GROUND_TRUTH','r625_r628_embedded_pixel_probe_report',
               'containsReport','HOLD_ORIGINAL_PIXEL_FRAME_OR_OCR_CONTRADICTION'):
   self.assertIn(term,s)
 def test_no_battle_promotion(self):
  s=SWIFT.read_text()
  for forbidden in ['"owner_verified":true','"mega_verified":true',
                    '"certified_for_battle":true','"display_orientation_verified":true']:
   self.assertNotIn(forbidden,s)
  for required in ['"certified_for_battle":false','"mega_verified":false',
                   '"owner_verified":false','"roi_verified":false']:
   self.assertIn(required,s)
 def test_existing_archive_member_not_increased(self):
  s=SWIFT.read_text()
  self.assertNotIn('entries+[.init(name:memberName',s)
  self.assertIn('return entries.map',s)
 def test_production_zip_writer(self):
  s=WRITER.read_text()
  self.assertEqual(s.count('R548ResearchArchive.write('),1)
  self.assertIn('let r625Entries = R625R628PixelHUDAndSprite.beforeZip(r621Entries)',s)
  self.assertIn('R625R628PixelHUDAndSprite.containsReport(r625Entries)',s)
  self.assertIn('r625Entries, to: zipURL, work: exportWork',s)
 def test_legacy_source_expectation_is_not_terminal(self):
  s=LEGACY.read_text()
  self.assertIn('let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)',s)
  self.assertNotIn("self.assertIn('r621Entries, to: zipURL, work: exportWork',s)",s)
