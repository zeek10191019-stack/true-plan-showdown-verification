import pathlib,tempfile,unittest,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from r600_source_trace import trace
class TraceTests(unittest.TestCase):
    def test_empty_is_hold(self):
        with tempfile.TemporaryDirectory() as d:
            r=trace(d)
            self.assertFalse(r['r595_source_present']);self.assertEqual(r['one_button_production_invocation'],'NOT_PROVEN')
    def test_find_definitions_and_calls_without_false_certification(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d)/'app/ios/ChampionsOnDevice';root.mkdir(parents=True)
            (root/'Collector.swift').write_text('func exportDiagnostics() {}\nfunc buttonTapped() {\n exportDiagnostics()\n}\n')
            (root/'R595FormReferenceMatcher.swift').write_text('struct R595Form { let count = 16*12 }')
            r=trace(d)
            self.assertTrue(r['r595_source_present'])
            self.assertEqual(len(r['candidate_declarations']),1)
            self.assertEqual(r['candidate_declarations'][0]['symbol'],'exportDiagnostics')
            self.assertEqual(r['callsites'][0]['line'],3)
            self.assertEqual(r['one_button_production_invocation'],'NOT_PROVEN')
    def test_ignores_research_only_module_as_production(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d)/'app/ios/ChampionsOnDevice';root.mkdir(parents=True)
            (root/'R599BoundOneButton.swift').write_text('func exportDiagnostics() {}')
            r=trace(d)
            self.assertEqual(r['candidate_declarations'],[])
    def test_tampering_changes_tree_fingerprint(self):
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d)/'app/ios/ChampionsOnDevice';root.mkdir(parents=True)
            p=root/'A.swift';p.write_text('func export() {}')
            a=trace(d)['source_tree_sha256'];p.write_text('func export() { print(1) }')
            self.assertNotEqual(a,trace(d)['source_tree_sha256'])
if __name__=='__main__':unittest.main()
