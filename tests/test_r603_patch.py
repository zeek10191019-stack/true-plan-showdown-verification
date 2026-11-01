import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tools.r603_patch import patch, TARGET


class PatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.target = self.root / TARGET
        self.target.parent.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_single_exact_seam(self):
        self.target.write_text('''func export() {
  let r602Entries = R602OneTapFormArchive.beforeZip(entries)
  _ = try R548ResearchArchive.write(
      r602Entries, to: zipURL, work: exportWork
  )
}\n''')
        patch(self.root)
        s = self.target.read_text()
        self.assertIn('let r603Entries = R603FormReadiness.beforeZip(r602Entries)', s)
        self.assertEqual(s.count('R548ResearchArchive.write('), 1)
        self.assertRaises(ValueError, patch, self.root)

    def test_no_parent_seam(self):
        self.target.write_text('bad')
        self.assertRaises(ValueError, patch, self.root)
        self.assertEqual(self.target.read_text(), 'bad')

    def test_multiple_seams(self):
        text = ('let r602Entries = R602OneTapFormArchive.beforeZip(entries)\n'
                '_ = try R548ResearchArchive.write(\n'
                '    r602Entries, to: zipURL, work: exportWork\n)')
        self.target.write_text(text + '\n' + text)
        self.assertRaises(ValueError, patch, self.root)

    def test_not_blind_extra_mutation(self):
        self.target.write_text('let r602Entries = beforeZip(entries)')
        self.assertRaises(ValueError, patch, self.root)

if __name__ == '__main__': unittest.main()
