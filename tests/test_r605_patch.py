import tempfile,unittest
from pathlib import Path
from tools.r605_patch import patch,TARGET
SRC='''func export() {
    let r604Entries = R604HistoricalFeatureArchive.beforeZip(
        r603Entries, samples: actorAppearanceSamples
    )
    _ = try R548ResearchArchive.write(
        r604Entries, to: zipURL, work: exportWork
    )
}
'''
class PatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        self.path=self.root/TARGET
        self.path.parent.mkdir(parents=True)
        self.path.write_text(SRC)
    def tearDown(self):self.tmp.cleanup()
    def test_exact_seam(self):
        patch(self.root)
        data=self.path.read_text()
        self.assertIn('R605ExactFrameBinding.beforeZip(r604Entries)',data)
        self.assertIn('r605Entries, to: zipURL',data)
    def test_double_patch_rejected(self):
        patch(self.root)
        with self.assertRaises(ValueError):patch(self.root)
    def test_wrong_seam_rejected(self):
        self.path.write_text(SRC.replace('r604Entries','wrong'))
        with self.assertRaises(ValueError):patch(self.root)
    def test_duplicate_seam_rejected(self):
        self.path.write_text(SRC+SRC)
        with self.assertRaises(ValueError):patch(self.root)
    def test_bad_indent_rejected(self):
        self.path.write_text(SRC.replace('    r603Entries','   r603Entries'))
        with self.assertRaises(ValueError):patch(self.root)
if __name__=='__main__':unittest.main()
