import unittest
from pathlib import Path
class Audit(unittest.TestCase):
 def test_no_claims(self):
  src=Path('app/ios/ChampionsOnDevice/R605ExactFrameBinding.swift').read_text()
  self.assertIn('NOT_CERTIFIED_FOR_LIVE_BATTLE',src)
  self.assertIn('crop_verified":false',src)
  self.assertIn('R598OneButtonFormAttachment.testDigest',src)
  self.assertIn('HOLD_ORIGINAL_PNG_NOT_IN_ARCHIVE',src)
  self.assertNotIn('mega_verified":true',src)
 def test_fail_closed(self):
  src=Path('app/ios/ChampionsOnDevice/R605ExactFrameBinding.swift').read_text()
  self.assertIn('entries.count < R548ResearchArchive.maximumMembers',src)
  self.assertIn('names.count == Set(names).count',src)
  self.assertIn('source.bytes.count <= 96 * 1024',src)
if __name__=='__main__':unittest.main()
