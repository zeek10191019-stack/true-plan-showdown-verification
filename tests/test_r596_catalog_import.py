import importlib.util
import json
import pathlib
import struct
import tempfile
import unittest
import zlib

MODULE=pathlib.Path(__file__).resolve().parents[1]/'tools/r596_catalog_import.py'
spec=importlib.util.spec_from_file_location('r596_catalog_import',MODULE)
importer=importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


def chunk(name,data):
    return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data))


def png():
    raw=b'\x00'+b'\x00\x55\x88\xff'*16
    ihdr=struct.pack('>II5B',16,16,8,2,0,0,0)
    return importer.PNG_SIGNATURE+chunk(b'IHDR',ihdr)+chunk(b'IDAT',zlib.compress(raw*16))+chunk(b'IEND',b'')


class R596CatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base=pathlib.Path(self.tmp.name)
        self.crop=self.base/'crop.png'; self.crop.write_bytes(png())
        self.features=self.base/'features.json';self.features.write_text(json.dumps([0.2]*192))
        self.catalog=self.base/'catalog.json'

    def add(self,**kwargs):
        opts=dict(reference_id='ref1',species_id='gyarados',form_id='mega',side='opponent',session_id='s1',frame_id=42,confirm_capture=True,confirm_label=True)
        opts.update(kwargs)
        return importer.register(self.catalog,self.crop,self.features,**opts)

    def test_png_valid(self): self.assertEqual(importer.check_png(self.crop.read_bytes()),(16,16))
    def test_register(self):
        ret=self.add();self.assertFalse(ret['certified'])
        self.assertEqual(len(json.loads(self.catalog.read_text())['references']),1)
    def test_reject_duplicate_reference_id(self):
        self.add()
        with self.assertRaisesRegex(ValueError,'ALREADY_REGISTERED'):self.add()
    def test_reject_duplicate_png_even_different_id(self):
        self.add()
        with self.assertRaisesRegex(ValueError,'ALREADY_REGISTERED'):self.add(reference_id='ref2')
    def test_reject_missing_attestation(self):
        with self.assertRaisesRegex(ValueError,'ATTESTATION_REQUIRED'):self.add(confirm_label=False)
    def test_reject_unknown_form(self):
        with self.assertRaisesRegex(ValueError,'FORM_LABEL_INVALID'):self.add(form_id='alternate')
    def test_reject_png_crc(self):
        self.crop.write_bytes(png()[:-5]+b'xxxxx')
        with self.assertRaises(ValueError):self.add()
    def test_reject_wrong_feature_count(self):
        self.features.write_text(json.dumps([0.1]*191))
        with self.assertRaisesRegex(ValueError,'COUNT_MISMATCH'):self.add()
    def test_reject_invalid_features(self):
        self.features.write_text(json.dumps([True]+[0.2]*191))
        with self.assertRaisesRegex(ValueError,'FEATURE_INVALID'):self.add()
    def test_reject_negative_frame(self):
        with self.assertRaisesRegex(ValueError,'SIDE_OR_FRAME_INVALID'):self.add(frame_id=-3)
    def test_reject_unsafe_reference_id(self):
        with self.assertRaisesRegex(ValueError,'REFERENCE_ID_INVALID'):self.add(reference_id='../escape')
    def test_reject_wrong_schema(self):
        self.catalog.write_text(json.dumps({'schema':'incorrect','references':[]}))
        with self.assertRaisesRegex(ValueError,'SCHEMA_MISMATCH'):self.add()

if __name__ == '__main__': unittest.main()
