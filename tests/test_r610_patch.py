import tempfile
import unittest
from pathlib import Path
from tools.r610_patch import patch, TARGET

class PatchContract(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.file=Path(self.tmp.name)/TARGET
        self.file.parent.mkdir(parents=True)
        self.seam='''    let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)
    _ = try R548ResearchArchive.write(
        r609Entries, to: zipURL, work: exportWork
    )'''
    def test_only_once(self):
        self.file.write_text(self.seam)
        patch(self.tmp.name)
        updated=self.file.read_text()
        self.assertEqual(updated.count('R610CrossEvidenceCandidate.beforeZip('),1)
        self.assertIn('r610Entries, to: zipURL, work: exportWork',updated)
    def test_second_patch_rejected_unchanged(self):
        self.file.write_text(self.seam)
        patch(self.tmp.name)
        frozen=self.file.read_bytes()
        with self.assertRaises(ValueError):patch(self.tmp.name)
        self.assertEqual(self.file.read_bytes(),frozen)
    def test_missing_seam_rejected_unchanged(self):
        self.file.write_text('irrelevant')
        frozen=self.file.read_bytes()
        with self.assertRaises(ValueError):patch(self.tmp.name)
        self.assertEqual(self.file.read_bytes(),frozen)
    def test_two_seams_rejected_unchanged(self):
        self.file.write_text(self.seam+'\n'+self.seam)
        frozen=self.file.read_bytes()
        with self.assertRaises(ValueError):patch(self.tmp.name)
        self.assertEqual(self.file.read_bytes(),frozen)
    def test_writer_mismatch_rejected_unchanged(self):
        self.file.write_text(self.seam.replace('exportWork','renamed'))
        frozen=self.file.read_bytes()
        with self.assertRaises(ValueError):patch(self.tmp.name)
        self.assertEqual(self.file.read_bytes(),frozen)

if __name__=='__main__':unittest.main()
