import tempfile,unittest,hashlib
from pathlib import Path
from tools.r611batch_patch import patch,TARGET,TESTS
ROOT=Path(__file__).resolve().parents[1]
class BatchPatchTest(unittest.TestCase):
  def setUp(self):
    self.temp=tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.root=Path(self.temp.name)
    self.target=self.root/TARGET
    self.target.parent.mkdir(parents=True)
    self.original='''    let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)
    _ = try R548ResearchArchive.write(
        r610Entries, to: zipURL, work: exportWork
    )'''
    self.target.write_text(self.original)
    for name in TESTS:
      p=self.root/name
      p.parent.mkdir(parents=True,exist_ok=True)
      # Undo only the known single-line source test adaptation to recreate
      # the pinned preimage used by the production patch test.
      src=(ROOT/name).read_text()
      digest,old,new=TESTS[name]
      self.assertEqual(src.count(new),1)
      prior=src.replace(new,old).encode()
      self.assertEqual(hashlib.sha256(prior).hexdigest(),digest)
      p.write_bytes(prior)
  def test_exact_seam_and_two_test_repairs(self):
    patch(self.root)
    s=self.target.read_text()
    self.assertIn('r612Entries, to: zipURL, work: exportWork',s)
    self.assertEqual(s.count('R611TemporalHUDReview.beforeZip('),1)
    self.assertEqual(s.count('R612ArchiveEvidenceClosure.beforeZip('),1)
    for name,(sha,old,new) in TESTS.items():
      t=(self.root/name).read_text()
      self.assertIn(new,t)
      self.assertNotIn(old,t)
  def test_double_apply_rejected_unchanged(self):
    patch(self.root)
    files=[self.target]+[self.root/x for x in TESTS]
    before=[x.read_bytes() for x in files]
    with self.assertRaises(ValueError):patch(self.root)
    self.assertEqual(before,[x.read_bytes() for x in files])
  def test_missing_writer_rejected_without_mutation(self):
    self.target.write_text('UNRELATED')
    files=[self.target]+[self.root/x for x in TESTS]
    before=[x.read_bytes() for x in files]
    with self.assertRaises(ValueError):patch(self.root)
    self.assertEqual(before,[x.read_bytes() for x in files])
  def test_changed_test_rejected_transactionally(self):
    p=self.root/'tests/test_r609_source.py'
    p.write_text(p.read_text()+'\nDRIFT')
    files=[self.target]+[self.root/x for x in TESTS]
    before=[x.read_bytes() for x in files]
    with self.assertRaises(ValueError):patch(self.root)
    self.assertEqual(before,[x.read_bytes() for x in files])
  def test_two_writer_seams_rejected(self):
    self.target.write_text(self.original+'\n'+self.original)
    with self.assertRaises(ValueError):patch(self.root)
    self.assertEqual(self.target.read_text(),self.original+'\n'+self.original)
if __name__=='__main__':unittest.main()
