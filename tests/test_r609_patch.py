import tempfile, unittest
from pathlib import Path
from tools.r609_patch import patch, TARGET
class StrictPatch(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/TARGET
        self.path.parent.mkdir(parents=True)
        self.source='''    let r608Entries = R608FramePixelEvidence.beforeZip(r607Entries)
    _ = try R548ResearchArchive.write(
        r608Entries, to: zipURL, work: exportWork
    )'''
    def test_exact_once(self):
        self.path.write_text(self.source)
        patch(self.tmp.name)
        a=self.path.read_text()
        self.assertEqual(a.count('R609VisionTextSpatialEvidence.beforeZip('),1)
        self.assertIn('r609Entries, to: zipURL, work: exportWork',a)
    def test_second_application_rejected_without_mutation(self):
        self.path.write_text(self.source)
        patch(self.tmp.name)
        a=self.path.read_bytes()
        with self.assertRaises(ValueError): patch(self.tmp.name)
        self.assertEqual(a,self.path.read_bytes())
    def test_missing_seam_rejected_without_mutation(self):
        self.path.write_text('no source')
        old=self.path.read_bytes()
        with self.assertRaises(ValueError): patch(self.tmp.name)
        self.assertEqual(old,self.path.read_bytes())
    def test_mismatched_symbol_rejected(self):
        self.path.write_text(self.source.replace('exportWork','otherWork'))
        with self.assertRaises(ValueError): patch(self.tmp.name)
    def test_two_seams_rejected(self):
        self.path.write_text(self.source+'\n'+self.source)
        with self.assertRaises(ValueError): patch(self.tmp.name)
if __name__=='__main__':unittest.main()
