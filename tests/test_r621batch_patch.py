import unittest,tempfile
from pathlib import Path
from tools.r621batch_patch import patch,TARGET,MODULE,TEST,OLD,NEW,ANCHOR,MEGA_INSERT
ROOT=Path(__file__).resolve().parents[1]
NEW_WRITER='''    let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)
    guard r621Entries.count == r617Entries.count &&
          R621R624VisualCandidates.containsReport(r621Entries) else {
        throw NSError(domain:"R624_VISUAL_EMBEDDED_REPORT_MISSING",code:624)
    }
    _ = try R548ResearchArchive.write(
        r621Entries, to: zipURL, work: exportWork
    )'''
OLD_WRITER='''    _ = try R548ResearchArchive.write(
        r617Entries, to: zipURL, work: exportWork
    )'''
class PatchTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
  self.root=Path(self.tmp.name)
  for path in [TARGET,MODULE,TEST]:
   f=self.root/path;f.parent.mkdir(parents=True,exist_ok=True)
   data=(ROOT/path).read_text()
   if path==TARGET:
    # R625 is the terminal writer now; restore the R621 writer in a test-only
    # temp copy before R621's original inverse-patch fixture runs.
    import re
    step=r'(?m)^(?P<i>[ \t]*)let r625Entries = R625R628PixelHUDAndSprite\.beforeZip\(r621Entries\)$'
    steps=list(re.finditer(step,data))
    assert len(steps)==1,'R625_WRITER_MARKER_NOT_UNIQUE'
    j=steps[0].group('i')
    start=steps[0].start()
    tail=(j+'let r625Entries = R625R628PixelHUDAndSprite.beforeZip(r621Entries)\n'
          +j+'guard r625Entries.count == r621Entries.count &&\n'
          +j+'      R625R628PixelHUDAndSprite.containsReport(r625Entries) else {\n'
          +j+'    throw NSError(domain:"R628_PIXEL_ARCHIVE_HOLD",code:628)\n'
          +j+'}\n'
          +j+'_ = try R548ResearchArchive.write(\n'
          +j+'    r625Entries, to: zipURL, work: exportWork\n'
          +j+')')
    assert data[start:start+len(tail)]==tail,'R625_TERMINAL_WRITER_DRIFT'
    old=(j+'_ = try R548ResearchArchive.write(\n'
         +j+'    r621Entries, to: zipURL, work: exportWork\n'
         +j+')')
    data=data[:start]+old+data[start+len(tail):]
    # R621 is nested in CaptureCoordinator, not at four-space indentation.
    # Recover exact writer indent from the production source and invert once.
    import re
    marker=r'(?m)^(?P<i>[ \t]*)let r621Entries = R621R624VisualCandidates\.beforeZip\(r617Entries\)$'
    matches=list(re.finditer(marker,data))
    assert len(matches)==1,'R621_WRITER_MARKER_NOT_UNIQUE'
    i=matches[0].group('i')
    normal=NEW_WRITER.splitlines()
    target='\n'.join(i+line[4:] for line in normal)
    fallback='\n'.join(i+line[4:] for line in OLD_WRITER.splitlines())
    assert data.count(target)==1,'R621_WRITER_BLOCK_NOT_UNIQUE'
    data=data.replace(target,fallback)
   elif path==MODULE:
    assert data.count(MEGA_INSERT)==1
    data=data.replace(MEGA_INSERT,ANCHOR)
   elif path==TEST:
    assert data.count(NEW)==1
    data=data.replace(NEW,OLD)
   f.write_text(data)
 def test_patch_contract(self):
  patch(self.root)
  c=(self.root/TARGET).read_text();m=(self.root/MODULE).read_text()
  self.assertEqual(c.count('R548ResearchArchive.write('),1)
  self.assertIn('r621Entries, to: zipURL, work: exportWork',c)
  self.assertEqual(c.count('R621R624VisualCandidates.beforeZip('),1)
  self.assertIn('MEGA_SCENE_TEXT_CUE_UNASSIGNED',m)
  self.assertIn(NEW,(self.root/TEST).read_text())
 def test_double_patch_rejected(self):
  patch(self.root);old=(self.root/TARGET).read_bytes()
  with self.assertRaises(ValueError):patch(self.root)
  self.assertEqual(old,(self.root/TARGET).read_bytes())
 def test_drift_is_atomic(self):
  for path in [TARGET,MODULE,TEST]:
   with self.subTest(path=path):
    original=(self.root/path).read_bytes()
    (self.root/path).write_bytes(b'UNEXPECTED')
    before={p:(self.root/p).read_bytes() for p in [TARGET,MODULE,TEST]}
    with self.assertRaises(ValueError):patch(self.root)
    self.assertEqual(before,{p:(self.root/p).read_bytes() for p in [TARGET,MODULE,TEST]})
    (self.root/path).write_bytes(original)
