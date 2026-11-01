import tempfile
import unittest
from pathlib import Path
from tools.r608_patch import patch, TARGET

OLD = '''    let r607Entries = R607FrameProvenanceAudit.beforeZip(r605Entries)
    _ = try R548ResearchArchive.write(
        r607Entries, to: zipURL, work: exportWork
    )'''

class R608Seam(unittest.TestCase):
    def test_exact_and_idempotency(self):
        with tempfile.TemporaryDirectory() as t:
            f=Path(t)/TARGET;f.parent.mkdir(parents=True)
            f.write_text('before\n'+OLD+'\nafter\n')
            patch(t)
            c=f.read_text()
            self.assertIn('R608FramePixelEvidence.beforeZip(r607Entries)',c)
            self.assertIn('r608Entries, to: zipURL',c)
            before=f.read_bytes()
            with self.assertRaises(ValueError):patch(t)
            self.assertEqual(f.read_bytes(),before)
    def test_bad_seam_is_rejected_without_changes(self):
        for fragment in ('nothing',OLD.replace('r607Entries, to:','r605Entries, to:'),OLD+'\n'+OLD):
            with self.subTest(fragment=fragment[:20]),tempfile.TemporaryDirectory() as t:
                f=Path(t)/TARGET;f.parent.mkdir(parents=True)
                f.write_text(fragment)
                original=f.read_bytes()
                with self.assertRaises(ValueError):patch(t)
                self.assertEqual(original,f.read_bytes())
if __name__=='__main__':unittest.main()
