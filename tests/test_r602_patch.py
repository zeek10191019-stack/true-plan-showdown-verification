import tempfile
import unittest
from pathlib import Path
from tools.r602_patch import patch, TARGET

class PatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.file = self.root / TARGET
        self.file.parent.mkdir(parents=True)
    def test_exact_callsite(self):
        self.file.write_text('func f() {\n    _=try R548ResearchArchive.write(entries,to:zipURL,work:exportWork)\n}\n')
        patch(self.root)
        result = self.file.read_text()
        self.assertEqual(result.count('R602OneTapFormArchive.beforeZip(entries)'), 1)
        self.assertIn('to: zipURL, work: exportWork', result)
        self.assertRaises(ValueError, patch, self.root)
    def test_other_writer_is_not_patched(self):
        self.file.write_text('func f() {\n    try R548ResearchArchive.write([],to:a,work:b)\n}\n')
        self.assertRaises(ValueError, patch, self.root)
    def test_ambiguous_writes_are_rejected(self):
        line = '    _=try R548ResearchArchive.write(entries,to:zipURL,work:exportWork)\n'
        self.file.write_text(line + line)
        self.assertRaises(ValueError, patch, self.root)
    def test_no_source_does_not_get_created(self):
        self.assertRaises(FileNotFoundError, patch, self.root)

if __name__ == '__main__':
    unittest.main()
