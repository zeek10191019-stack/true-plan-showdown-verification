import unittest,tempfile,hashlib
from pathlib import Path
from tools.r629batch_patch import patch,TARGET,ORIGINAL_SHA
ROOT=Path(__file__).resolve().parents[1]
class PatchTest(unittest.TestCase):
 def setUp(self):
  self.dir=tempfile.TemporaryDirectory();self.addCleanup(self.dir.cleanup)
  self.root=Path(self.dir.name)
  p=self.root/TARGET;p.parent.mkdir(parents=True)
  data=(ROOT/'fixtures/R625R628PixelHUDAndSprite.swift').read_bytes()
  assert hashlib.sha256(data).hexdigest()==ORIGINAL_SHA
  p.write_bytes(data)
 def test_atomic_patch(self):
  patch(self.root)
  txt=(self.root/TARGET).read_text()
  self.assertEqual(txt.count('R629R632SlotEvidence.enrich(&prior)'),1)
  self.assertEqual(txt.count('return entries.map'),1)
 def test_double_patch_rejected(self):
  patch(self.root);p=self.root/TARGET;old=p.read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(p.read_bytes(),old)
 def test_drift_rejected_without_mutation(self):
  p=self.root/TARGET;p.write_bytes(p.read_bytes()+b' ');old=p.read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(p.read_bytes(),old)
