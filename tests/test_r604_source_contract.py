import sys,tempfile,pathlib,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from tools.r604_feature_source_contract import audit,TARGETS
class Tests(unittest.TestCase):
 def test_verified_structure(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)
   for name in TARGETS:
    (p/name).write_text('private func featureRaster() {}\n')
   (p/'CaptureCoordinator.swift').write_text('R603FormReadiness.beforeZip(entries)\n')
   x=audit(p)
   self.assertEqual(x['existing_one_tap_hook_count'],1)
   self.assertFalse(x['numeric_parity_certified'])
   self.assertEqual(len(x['files']),5)
 def test_duplicate_one_tap_hook_fails(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)
   for name in TARGETS:(p/name).write_text('func featureLuminance(){}\n')
   (p/'CaptureCoordinator.swift').write_text('R603FormReadiness.beforeZip\n'*2)
   with self.assertRaisesRegex(AssertionError,'R603_HOOK_MISSING'):
    audit(p)
 def test_missing_file_fails(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaisesRegex(ValueError,'SOURCE_FILE_MISSING'):audit(d)
if __name__=='__main__':unittest.main()
