import unittest, tempfile, hashlib
from pathlib import Path
from tools.r625batch_patch import patch,TARGET,SOURCE_TEST,PATCH_TEST

ROOT=Path(__file__).resolve().parents[1]
# A small actual-writer fixture, identical in the local seam (not a production repo).
WRITER='''                        let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)
                        guard r621Entries.count == r617Entries.count &&
                              R621R624VisualCandidates.containsReport(r621Entries) else {
                            throw NSError(domain:"R624_VISUAL_EMBEDDED_REPORT_MISSING",code:624)
                        }
                        _ = try R548ResearchArchive.write(
                            r621Entries, to: zipURL, work: exportWork
                        )'''

class WriterTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.root=Path(self.tmp.name)
  original=(ROOT/PATCH_TEST).read_text()
  legacy=(ROOT/SOURCE_TEST).read_text()
  start='    # R625 is the terminal writer now; restore the R621 writer in a test-only\n'
  end='    # R621 is nested in CaptureCoordinator, not at four-space indentation.\n'
  if start in original:
   self.assertEqual(original.count(start),1)
   self.assertEqual(original.count(end),1)
   original=original.split(start,1)[0]+end+original.split(end,1)[1]
  newer="self.assertIn('let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)',s)"
  older="self.assertIn('r621Entries, to: zipURL, work: exportWork',s)"
  legacy=legacy.replace(newer,older)
  for name,data in [(TARGET,'stub start\n'+WRITER+'\n'),
                    (PATCH_TEST,original),
                    (SOURCE_TEST,legacy)]:
   f=self.root/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(data)
 def test_atomic_writer_patch(self):
  patch(self.root)
  s=(self.root/TARGET).read_text()
  self.assertEqual(s.count('R548ResearchArchive.write('),1)
  self.assertEqual(s.count('R625R628PixelHUDAndSprite.beforeZip('),1)
  self.assertIn('r625Entries, to: zipURL, work: exportWork',s)
  self.assertIn('R625R628PixelHUDAndSprite.containsReport(r625Entries)',s)
 def test_old_source_contract_extendable(self):
  patch(self.root)
  s=(self.root/SOURCE_TEST).read_text()
  self.assertIn('let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)',s)
  self.assertNotIn("self.assertIn('r621Entries, to: zipURL, work: exportWork',s)",s)
 def test_legacy_fixture_restores_correct_stage(self):
  patch(self.root)
  s=(self.root/PATCH_TEST).read_text()
  self.assertIn('R625_TERMINAL_WRITER_DRIFT',s)
  compile(s,str(PATCH_TEST),'exec')
 def test_double_patch_rejected_without_corruption(self):
  patch(self.root)
  files=[TARGET,SOURCE_TEST,PATCH_TEST]
  old={f:(self.root/f).read_bytes() for f in files}
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(old,{f:(self.root/f).read_bytes() for f in files})
 def test_drift_atomic_for_each_input(self):
  paths=[TARGET,SOURCE_TEST,PATCH_TEST]
  for path in paths:
   with self.subTest(path=str(path)):
    current=(self.root/path).read_bytes()
    (self.root/path).write_text('DRIFT')
    before={x:(self.root/x).read_bytes() for x in paths}
    with self.assertRaises(ValueError):patch(self.root)
    self.assertEqual(before,{x:(self.root/x).read_bytes() for x in paths})
    (self.root/path).write_bytes(current)
