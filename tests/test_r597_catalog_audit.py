import importlib.util
import json
import pathlib
import tempfile
import unittest

SOURCE=pathlib.Path(__file__).resolve().parents[1]/'tools/r597_catalog_audit.py'
spec=importlib.util.spec_from_file_location('r597_catalog_audit',SOURCE)
auditmod=importlib.util.module_from_spec(spec);spec.loader.exec_module(auditmod)

def ref(number, session, form='mega', side='opponent', value=.2):
    return {'referenceID':f'ref{number}', 'speciesID':'gyarados', 'formID':form,
            'captureSide':side, 'sessionID':session, 'frameID':number,
            'sourceKind':'champions-screen-capture','labelEvidence':'human-confirmed',
            'extractorID':auditmod.EXTRACTOR,'imageSHA256':f'{number:064x}',
            'features':[value]*192}
def cat(*rows):return {'schema':auditmod.SCHEMA,'references':list(rows)}
class AuditTests(unittest.TestCase):
    def test_empty_holds(self):self.assertEqual(auditmod.audit(cat())['status'],'HOLD')
    def test_ready_sessions_but_not_certified(self):
        r=auditmod.audit(cat(ref(1,'s1'),ref(2,'s2')))
        self.assertEqual(r['distinctFormsWithTwoSessions'],['gyarados/mega/opponent'])
        self.assertFalse(r['canDeclareMega'])
    def test_single_session_not_ready(self):self.assertFalse(auditmod.audit(cat(ref(1,'s1'),ref(2,'s1')))['distinctFormsWithTwoSessions'])
    def test_reject_duplicate_id(self):
        a,b=ref(1,'s1'),ref(2,'s2');b['referenceID']='ref1'
        with self.assertRaisesRegex(ValueError,'DUPLICATE'):auditmod.audit(cat(a,b))
    def test_reject_duplicate_image(self):
        a,b=ref(1,'s1'),ref(2,'s2');b['imageSHA256']=a['imageSHA256']
        with self.assertRaisesRegex(ValueError,'DUPLICATE'):auditmod.audit(cat(a,b))
    def test_reject_bad_features(self):
        a=ref(1,'s1');a['features']=[True]*192
        with self.assertRaisesRegex(ValueError,'FEATURES'):auditmod.audit(cat(a))
    def test_reject_wrong_extractor(self):
        a=ref(1,'s1');a['extractorID']='invented'
        with self.assertRaisesRegex(ValueError,'EXTRACTOR'):auditmod.audit(cat(a))
    def test_reject_unverified_source(self):
        a=ref(1,'s1');a['sourceKind']='fan-art'
        with self.assertRaisesRegex(ValueError,'SOURCE'):auditmod.audit(cat(a))
    def test_reject_unverified_label(self):
        a=ref(1,'s1');a['labelEvidence']='auto-guess'
        with self.assertRaisesRegex(ValueError,'SOURCE'):auditmod.audit(cat(a))
    def test_reject_unknown_side(self):
        a=ref(1,'s1');a['captureSide']='unknown'
        with self.assertRaisesRegex(ValueError,'SIDE'):auditmod.audit(cat(a))
    def test_reject_wrong_schema(self):
        with self.assertRaisesRegex(ValueError,'SCHEMA'):auditmod.audit({'schema':'foo','references':[]})
    def test_separate_sides(self):
        r=auditmod.audit(cat(ref(1,'s1'),ref(2,'s2',side='own')))
        self.assertFalse(r['distinctFormsWithTwoSessions'])
    def test_report_has_no_images(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);(root/'catalog.json').write_text(json.dumps(cat(ref(1,'s1'))))
            out=auditmod.audit_files(root/'catalog.json',root/'report.json')
            self.assertEqual(out['references'],1)
            self.assertNotIn('features', (root/'report.json').read_text())
    def test_conflicting_same_frame(self):
        a,b=ref(1,'s1'),ref(2,'s1',form='normal');b['frameID']=a['frameID']
        self.assertIn('CONFLICTING_LABELS_IN_SAME_FRAME',auditmod.audit(cat(a,b))['holds'])

if __name__=='__main__':unittest.main()
