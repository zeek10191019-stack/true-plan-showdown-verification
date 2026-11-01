import hashlib,io,json,pathlib,sys,tempfile,unittest,zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from r600_bundle_audit import check_bundle
class BundleTests(unittest.TestCase):
    def fixture(self,path,modify=None):
        crop=b'PNG-example-for-fixture'
        evidence={'certification':'NOT_CERTIFIED_FOR_LIVE_BATTLE','result':{'status':'hold'},'cropSHA256':hashlib.sha256(crop).hexdigest(), 'captureSide':'own','frameID':21,'epoch':3}
        ev=json.dumps(evidence).encode()
        man={'original':True,'r598_form_evidence':{'path':'evidence/held.json','sha256':hashlib.sha256(ev).hexdigest(),'bytes':len(ev),'certification':'NOT_CERTIFIED_FOR_LIVE_BATTLE','status':'hold'}}
        if modify:modify(man,evidence)
        # Reflect all modifications to the evidence but deliberately don't fix a corrupted hash unless specifically tested.
        ev=json.dumps(evidence).encode()
        if modify and man['r598_form_evidence'].get('sha256')=='REHASH':
            man['r598_form_evidence']['sha256']=hashlib.sha256(ev).hexdigest()
            man['r598_form_evidence']['bytes']=len(ev)
        with zipfile.ZipFile(path,'w') as z:
            z.writestr('manifest.json',json.dumps(man))
            z.writestr('crop.png',crop)
            z.writestr('evidence/held.json',ev)
    def test_success(self):
        with tempfile.TemporaryDirectory() as d:
            f=pathlib.Path(d)/'a.zip';self.fixture(f)
            self.assertEqual(check_bundle(f),(True,'R600_RESEARCH_ONLY_BUNDLE_VERIFIED'))
    def test_invalid_certification(self):
        with tempfile.TemporaryDirectory() as d:
            f=pathlib.Path(d)/'a.zip'
            def tweak(m,e):
                e['certification']='CERTIFIED';m['r598_form_evidence']['sha256']='REHASH'
            self.fixture(f,tweak);self.assertEqual(check_bundle(f)[1],'LIVE_CERTIFICATION_FORBIDDEN')
    def test_bad_hash(self):
        with tempfile.TemporaryDirectory() as d:
            f=pathlib.Path(d)/'a.zip'
            self.fixture(f,lambda m,e:m['r598_form_evidence'].update(sha256='x'*64))
            self.assertEqual(check_bundle(f)[1],'EVIDENCE_DIGEST_MISMATCH')
    def test_bad_crop(self):
        with tempfile.TemporaryDirectory() as d:
            f=pathlib.Path(d)/'a.zip'
            def tweak(m,e):e['cropSHA256']='0'*64;m['r598_form_evidence']['sha256']='REHASH'
            self.fixture(f,tweak);self.assertEqual(check_bundle(f)[1],'CROP_FRAME_HASH_MISMATCH')
    def test_duplicate_member(self):
        with tempfile.TemporaryDirectory() as d:
            f=pathlib.Path(d)/'a.zip';self.fixture(f)
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter('ignore',UserWarning)
                with zipfile.ZipFile(f,'a') as z:z.writestr('crop.png',b'x')
            self.assertEqual(check_bundle(f)[1],'ZIP_DUPLICATE_ENTRIES')
    def test_path_traversal(self):
        with tempfile.TemporaryDirectory() as d:
            f=pathlib.Path(d)/'a.zip';self.fixture(f)
            with zipfile.ZipFile(f,'a') as z:z.writestr('../escape',b'x')
            self.assertEqual(check_bundle(f)[1],'ZIP_MEMBER_PATH_UNSAFE')
    def test_missing_archive(self):
        self.assertFalse(check_bundle('/no_such_bundle.zip')[0])
if __name__=='__main__':unittest.main()
