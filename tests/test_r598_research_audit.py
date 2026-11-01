import hashlib
import importlib.util
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / 'tools'


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


AUDIT = load('r598_zip_audit')
PROBE = load('r598_extractor_probe')


def bundle(manifest, members=None):
    f = io.BytesIO()
    with zipfile.ZipFile(f, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr('manifest.json', json.dumps(manifest).encode())
        for k, v in (members or {'frames/f001.png': b'original-image-bytes', 'state.json': b'{}'}).items():
            z.writestr(k, v)
    return f.getvalue()


class ResearchAudit(unittest.TestCase):
    def setUp(self):
        self.before_manifest = {'legacy': {'x': 'keep'}, 'frames': ['frames/f001.png']}
        self.original = {'frames/f001.png': b'original-image-bytes', 'state.json': b'{}'}
        self.sidecar_path = 'evidence/r598_form_1_8_aaaaaaaaaaaa.json'
        self.detail = {'schema': 'trueplan.r597.form_evidence.v1',
                       'certification': 'NOT_CERTIFIED_FOR_LIVE_BATTLE',
                       'result': {'status': 'hold', 'reason': 'NO_INDEPENDENT_FORM_REFERENCES'}}
        self.content = json.dumps(self.detail).encode()
        self.ref = {'schema': 'trueplan.r598.sidecar.v1', 'path': self.sidecar_path,
                    'bytes': len(self.content), 'sha256': hashlib.sha256(self.content).hexdigest(),
                    'status': 'hold', 'certification': 'NOT_CERTIFIED_FOR_LIVE_BATTLE'}
        self.prior = bundle(self.before_manifest, self.original)

    def after(self, manifest=None, contents=None, added=None):
        m = dict(self.before_manifest)
        m['r598_form_evidence'] = dict(self.ref)
        if manifest:
            m.update(manifest)
        members = dict(self.original)
        members[self.sidecar_path] = self.content if contents is None else contents
        if added:
            members.update(added)
        return bundle(m, members)

    def rejection(self, updated, reason):
        with self.assertRaisesRegex(ValueError, reason):
            AUDIT.audit(self.prior, updated)

    def test_preserves_all_prior_members(self):
        self.assertEqual(AUDIT.audit(self.prior, self.after())['preserved_original_entries'], 3)

    def test_evidence_not_certified(self):
        self.assertFalse(AUDIT.audit(self.prior, self.after())['live_recognition_certified'])

    def test_sha_correct(self):
        self.assertEqual(AUDIT.audit(self.prior, self.after())['sidecar_sha256'], self.ref['sha256'])

    def test_original_changed(self):
        data = {'frames/f001.png': b'MUTATED', 'state.json': b'{}', self.sidecar_path: self.content}
        self.rejection(bundle({**self.before_manifest, 'r598_form_evidence': self.ref}, data), 'ORIGINAL_MEMBER_MUTATED')

    def test_original_dropped(self):
        data = {'frames/f001.png': b'original-image-bytes', self.sidecar_path: self.content}
        self.rejection(bundle({**self.before_manifest, 'r598_form_evidence': self.ref}, data), 'ORIGINAL_MEMBER_DROPPED')

    def test_manifest_mutated(self):
        self.rejection(self.after({'legacy': {'x': 'MUTATED'}}), 'ORIGINAL_MANIFEST_FIELDS_CHANGED')

    def test_digest_mismatch(self):
        self.rejection(self.after(contents=b'bad'), 'R598_SIDECAR_HASH_MISMATCH')

    def test_unexpected_files(self):
        self.rejection(self.after(added={'arbitrary.dat': b'new'}), 'UNEXPECTED_ADDED_MEMBERS')

    def test_prod_claim_rejected(self):
        d = {**self.detail, 'certification': 'CERTIFIED'}
        b = json.dumps(d).encode()
        obj = dict(self.ref, sha256=hashlib.sha256(b).hexdigest(), bytes=len(b))
        self.rejection(self.after({'r598_form_evidence': obj}, contents=b), 'PRODUCTION_CERTIFICATION_BYPASS')

    def test_candidate_status_rejected(self):
        d = {**self.detail, 'result': {'status': 'confirmed'}}
        b = json.dumps(d).encode()
        obj = dict(self.ref, sha256=hashlib.sha256(b).hexdigest(), bytes=len(b), status='confirmed')
        self.rejection(self.after({'r598_form_evidence': obj}, contents=b), 'CLASSIFICATION_STATUS_UNSAFE')

    def test_traversal_member_rejected(self):
        self.rejection(self.after(added={'../escape': b'oops'}), 'UNSAFE_ZIP_ENTRY')

    def test_backslash_member_rejected(self):
        self.rejection(self.after(added={'dir\\file': b'oops'}), 'UNSAFE_ZIP_ENTRY')

    def test_duplicate_entry_rejected(self):
        f = io.BytesIO()
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(f, 'w') as z:
                z.writestr('manifest.json', b'{}')
                z.writestr('manifest.json', b'{}')
        self.rejection(f.getvalue(), 'DUPLICATED_ZIP_ENTRY')

    def test_source_absent_holds(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(PROBE.probe(d)['extractor_compatibility'], 'HOLD_SOURCE_NOT_FOUND')

    def test_source_present_still_holds(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'app/ios/ChampionsOnDevice/R595FormReferenceMatcher.swift'
            p.parent.mkdir(parents=True)
            p.write_text('struct R595FormReferenceMatcher { func extract() {} }')
            result = PROBE.probe(d)
            self.assertTrue(result['r595_source_present'])
            self.assertFalse(result['production_ready'])
            self.assertIn('extract', result['r595_symbols'])

    def test_empty_r598_extension_rejected(self):
        self.rejection(self.after({'r598_form_evidence': None}), 'R598_EXTENSION_MISSING')

    def test_mismatched_extension_schema(self):
        self.rejection(self.after({'r598_form_evidence': dict(self.ref, schema='something-else')}), 'R598_SCHEMA_INVALID')


if __name__ == '__main__':
    unittest.main()
