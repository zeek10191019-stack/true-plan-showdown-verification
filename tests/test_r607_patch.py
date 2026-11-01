from pathlib import Path
from tempfile import TemporaryDirectory
import unittest,sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.r607_patch import patch
class Case(unittest.TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.f=Path(self.tmp.name)/'app/ios/ChampionsOnDevice/CaptureCoordinator.swift'
        self.f.parent.mkdir(parents=True)
        self.original=('  let r605Entries = R605ExactFrameBinding.beforeZip(r604Entries)\n'
          '  _ = try R548ResearchArchive.write(\n'
          '      r605Entries, to: zipURL, work: exportWork\n'
          '  )\n')
        self.f.write_text(self.original)
    def test_exact(self):
        patch(self.tmp.name)
        self.assertIn('let r607Entries = R607FrameProvenanceAudit.beforeZip(r605Entries)',self.f.read_text())
    def test_double_apply(self):
        patch(self.tmp.name)
        with self.assertRaises(ValueError):patch(self.tmp.name)
    def test_wrong_writer(self):
        self.f.write_text(self.original.replace('zipURL','wrongURL'))
        with self.assertRaises(ValueError):patch(self.tmp.name)
    def test_multiple(self):
        self.f.write_text(self.original+self.original)
        with self.assertRaises(ValueError):patch(self.tmp.name)
    def test_no_change_on_error(self):
        self.f.write_text('let other = 1')
        with self.assertRaises(ValueError):patch(self.tmp.name)
        self.assertEqual(self.f.read_text(),'let other = 1')
if __name__=='__main__':unittest.main()
