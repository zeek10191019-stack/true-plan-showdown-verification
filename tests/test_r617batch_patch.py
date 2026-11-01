import unittest,tempfile
from pathlib import Path
from tools.r617batch_patch import patch,TARGET,OLD_TEST,OLD_HARNESS,TEST_OLD,OLD_ASSERT,TEST_NEW,NEW_ASSERT
ROOT=Path(__file__).resolve().parents[1]
class PatchTest(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup)
  self.root=Path(self.t.name)
  for p in [OLD_TEST,OLD_HARNESS]:
   f=self.root/p;f.parent.mkdir(parents=True,exist_ok=True)
   text=(ROOT/p).read_text()
   if p==OLD_TEST:text=text.replace(TEST_NEW,TEST_OLD)
   if p==OLD_HARNESS:text=text.replace(NEW_ASSERT,OLD_ASSERT)
   f.write_text(text)
  f=self.root/TARGET;f.parent.mkdir(parents=True,exist_ok=True)
  f.write_text('''                    let r613Entries = R613R616IntegratedReadiness.beforeZip(r612Entries)
                    guard r613Entries.count == r612Entries.count + 1 else {
                        throw NSError(domain:"R616_ARCHIVE_READINESS_CAPACITY_EXHAUSTED",code:616)
                    }
                    _ = try R548ResearchArchive.write(
                        r613Entries, to: zipURL, work: exportWork
                    )''')
 def test_patch(self):
  patch(self.root);s=(self.root/TARGET).read_text()
  self.assertEqual(s.count('R617R620RotationReadout.beforeZip('),1)
  self.assertEqual(s.count('R548ResearchArchive.write('),1)
  self.assertIn('r617Entries, to: zipURL, work: exportWork',s)
  self.assertIn(TEST_NEW,(self.root/OLD_TEST).read_text())
  self.assertIn(NEW_ASSERT,(self.root/OLD_HARNESS).read_text())
 def test_double_patch_blocks(self):
  patch(self.root)
  before=(self.root/TARGET).read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(before,(self.root/TARGET).read_bytes())
 def test_writer_missing_atomic(self):
  (self.root/TARGET).write_text('bad')
  original=(self.root/OLD_TEST).read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(original,(self.root/OLD_TEST).read_bytes())
 def test_test_sha_drift_atomic(self):
  (self.root/OLD_TEST).write_text('bad')
  before=(self.root/TARGET).read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(before,(self.root/TARGET).read_bytes())
 def test_harness_sha_drift_atomic(self):
  (self.root/OLD_HARNESS).write_text('bad')
  before=(self.root/TARGET).read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(before,(self.root/TARGET).read_bytes())
if __name__=='__main__':unittest.main()
