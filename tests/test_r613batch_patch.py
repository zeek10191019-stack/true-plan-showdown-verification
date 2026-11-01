import unittest,hashlib,tempfile
from pathlib import Path
from tools.r613batch_patch import patch,TARGET,TEST,OLD_TEST,NEW_TEST,TEST_SHA
REF=Path(__file__).resolve().parents[1]
class R613Patch(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        for name,contents in {
            TARGET:("    let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)\n"
            "    guard r612Entries.count == r610Entries.count + 2 else {\n"
            "        throw NSError(domain:\"R612_EVIDENCE_CAPACITY_EXHAUSTED\",code:612)\n"
            "    }\n"
            "    _ = try R548ResearchArchive.write(\n"
            "        r612Entries, to: zipURL, work: exportWork\n"
            "    )"),
            TEST:("class Sample:\n    chain=[\n"
              "      'r612Entries, to: zipURL, work: exportWork']\n")} .items():
            p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True)
            p.write_text(contents)
        # Installed parent test must match exact pinned hash, provided in
        # the replay directory for CI; in isolation reconstruct the version.
        patched=(REF/TEST).read_text()
        self.assertEqual(patched.count(NEW_TEST),1)
        source=patched.replace(NEW_TEST,OLD_TEST).encode('utf-8')
        self.assertEqual(hashlib.sha256(source).hexdigest(),TEST_SHA)
        (self.root/TEST).write_bytes(source)
    def test_exact(self):
        patch(self.root)
        v=(self.root/TARGET).read_text()
        self.assertIn('r613Entries, to: zipURL, work: exportWork',v)
        self.assertEqual(v.count('R613R616IntegratedReadiness.beforeZip('),1)
        self.assertEqual(v.count('R548ResearchArchive.write('),1)
        t=(self.root/TEST).read_text()
        self.assertNotIn(OLD_TEST,t)
        self.assertIn(NEW_TEST,t)
    def test_duplicate_rejected_without_rewrite(self):
        patch(self.root)
        before=[(self.root/x).read_bytes() for x in [TARGET,TEST]]
        with self.assertRaises(ValueError):patch(self.root)
        self.assertEqual(before,[(self.root/x).read_bytes() for x in [TARGET,TEST]])
    def test_writer_absent_rejected(self):
        (self.root/TARGET).write_text('unrelated')
        before=(self.root/TEST).read_bytes()
        with self.assertRaises(ValueError):patch(self.root)
        self.assertEqual(before,(self.root/TEST).read_bytes())
    def test_test_changed_rejected_without_writer_edit(self):
        (self.root/TEST).write_text('drift')
        before=(self.root/TARGET).read_bytes()
        with self.assertRaises(ValueError):patch(self.root)
        self.assertEqual(before,(self.root/TARGET).read_bytes())
    def test_duplicate_writer_rejected(self):
        (self.root/TARGET).write_text((self.root/TARGET).read_text()*2)
        with self.assertRaises(ValueError):patch(self.root)
if __name__=='__main__':unittest.main()
