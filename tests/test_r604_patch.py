import unittest,tempfile,pathlib,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from tools.r604_patch import patch,TARGET
class Tests(unittest.TestCase):
 BASE='''func save() {\n    var actorAppearanceSamples=[[String:Any]]()\n    let r602Entries = R602OneTapFormArchive.beforeZip(entries)\n    let r603Entries = R603FormReadiness.beforeZip(r602Entries)\n    _ = try R548ResearchArchive.write(\n        r603Entries, to: zipURL, work: exportWork\n    )\n}'''
 def test_patch_exact(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/TARGET;p.parent.mkdir(parents=True);p.write_text(self.BASE)
   patch(d);s=p.read_text();self.assertIn('R604HistoricalFeatureArchive.beforeZip',s)
   self.assertIn('samples: actorAppearanceSamples',s)
   with self.assertRaises(ValueError):patch(d)
 def test_no_original_one_tap_seam(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/TARGET;p.parent.mkdir(parents=True);p.write_text(self.BASE.replace('r603Entries','XXX'))
   with self.assertRaises(ValueError):patch(d)
if __name__=='__main__':unittest.main()
