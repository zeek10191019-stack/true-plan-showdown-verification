"""R580 synthetic contract fixtures only. Never real-game accuracy evidence."""
import copy
import hashlib
import json
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from verify_offline_png_bundle import verify_archive,SCHEMA,REPORT_SCHEMA
from screen_read_metrics import prediction_from_archive,evaluate,DATA_SCHEMA


def sha(b):return hashlib.sha256(b).hexdigest()


def canonical(o):return json.dumps(o,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()


def chunk(tag,data):return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)


def png():
    w,h=10,10
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+b'\xff'*30 for _ in range(h))))+chunk(b'IEND',b'')


def make_fixture(extra=None):
    p=png();im=sha(p)
    packet={'image_sha256':im,'frame_id':1,'epoch':1,'source_ref':'user-imported-exact-png-not-live','ocr_engine_version':'r558.ocr.v1'}
    snapshot={'image_sha256':im,'current_state_eligible':False,'battle_advice_authorized':False,
        'screen_read_engine_version':'r571.snapshot.v1','screen_classification':{
        'status':'PRIMARY_AND_ALTERNATIVES_AGREE','screen_kind':'move_selection_candidate'}}
    mega={'image_sha256':im,'mega_certified':False,'visual_form_certified':False,'text_hints':[]}
    diagnostic={'schema':REPORT_SCHEMA,'source_kind':'USER_IMPORTED_PNG_OFFLINE_ONLY',
        'image_sha256':im,'image_width':10,'image_height':10,'png_bytes':len(p),
        'capture_session_id':None,'real_game_accuracy_certified':False,'owner_certified':False,
        'turn_certified':False,'mega_form_visual_certified':False,
        'current_state_eligible':False,'battle_advice_authorized':False,
        'ground_truth_labels_present':False,'source_png_in_report':False,
        'user_opt_in_share_required':True,'payload':packet,'snapshot':snapshot,'mega_text_probe':mega}
    manifest={'schema':SCHEMA,'source_kind':'USER_IMPORTED_PNG_OFFLINE_ONLY','image_sha256':im,
        'capture_session_id':None,'turn':None,'current_state_eligible':False,'owner_certified':False,
        'mega_visual_certified':False,'game_accuracy_certified':False,'battle_advice_authorized':False,
        'user_explicit_share_required':True,'bundle_contains_original_png':True}
    if extra:extra(p,diagnostic,manifest)
    d=canonical(diagnostic)
    manifest['entries']=[dict(path=name,bytes=len(blob),sha256=sha(blob),crc32=zlib.crc32(blob)&0xffffffff)
                        for name,blob in [('original.png',p),('diagnostic.json',d)]]
    return {'original.png':p,'diagnostic.json':d,'manifest.json':canonical(manifest)}


def make_zip(path,parts):
    with zipfile.ZipFile(path,'w',compression=zipfile.ZIP_STORED) as z:
        for name,blob in parts.items():z.writestr(name,blob)


class OfflineZIPAdapterTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'evidence.zip'

    def check(self,extra=None):
        parts=make_fixture(extra);make_zip(self.path,parts);return verify_archive(self.path)

    def test_verified_original_bytes_and_sha(self):
        receipt=self.check();self.assertEqual(receipt['image_sha256'],sha(png()))
        self.assertEqual(receipt['image_width'],10);self.assertEqual(receipt['image_height'],10)

    def test_scoring_reads_actual_offline_zip_but_never_certifies_game(self):
        receipt=self.check();pred=prediction_from_archive(self.path,'shot1')
        self.assertEqual(pred['source']['kind'],'OFFLINE_PNG_DIAGNOSTIC_ZIP')
        self.assertEqual(pred['fields'][0]['field'],'screen_class')
        sample={'sample_id':'shot1','image_sha256':receipt['image_sha256'],
            'capture_group_id':'group1','split':'development','label_origin':'SYNTHETIC_CONTRACT',
            'labels':[dict(field='screen_class',slot=None,value='move_selection_candidate',side='field',visibility='PRESENT'),
                dict(field='mega_visual',slot=None,value=None,side='UNKNOWN_OWNER',visibility='UNKNOWN')]}
        score=evaluate({'schema':DATA_SCHEMA,'dataset_id':'offline-contract','samples':[sample]},[pred])
        self.assertEqual(score['overall']['value_tp'],1)
        self.assertIsNone(score['overall']['owner_coverage'])
        self.assertEqual(score['overall']['unknown_labels'],1)
        self.assertFalse(score['full_game_accuracy_certified'])
        self.assertFalse(score['device_certified'])

    def test_unrecognized_screen_is_not_a_guessed_prediction(self):
        def modify(p,d,m):d['snapshot']['screen_classification']['screen_kind']='unknown'
        self.check(modify);pred=prediction_from_archive(self.path,'shot1')
        self.assertEqual(pred['fields'],[])
        self.assertEqual(pred['reader_status'],'NO_SOURCE_BOUND_VALUES')

    def test_provisional_role_stays_unknown_owner(self):
        def modify(p,d,m):d['snapshot']['owner_position_hints']={
            'schema':'trueplan.screen-read.source-bound-hints.v2',
            'status':'PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION',
            'hints':[{'role_hint':'own_hp','slot':None,'literal_value':{'current':170,'maximum':185},
                      'side':'UNKNOWN_OWNER','current_state_eligible':False,'identity_certified':False}]}
        self.check(modify);pred=prediction_from_archive(self.path,'shot1')
        hp=[x for x in pred['fields'] if x['field']=='own_hp'][0]
        self.assertEqual(hp['side'],'UNKNOWN_OWNER');self.assertFalse(hp['identity_certified'])

    def test_owner_claim_in_offline_role_rejected(self):
        def modify(p,d,m):d['snapshot']['owner_position_hints']={
            'schema':'trueplan.screen-read.source-bound-hints.v2',
            'status':'PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION',
            'hints':[{'role_hint':'own_hp','slot':None,'literal_value':170,
                     'side':'own','current_state_eligible':False,'identity_certified':False}]}
        self.check(modify)
        with self.assertRaisesRegex(ValueError,'OFFLINE_OWNER_ASSERTION'):prediction_from_archive(self.path,'shot1')

    def test_mega_claim_in_diagnostic_rejected(self):
        def modify(p,d,m):d['mega_text_probe']['visual_form_certified']=True
        with self.assertRaisesRegex(ValueError,'UNAUTHORIZED_CLAIM'):self.check(modify)

    def test_live_claim_in_manifest_rejected(self):
        def modify(p,d,m):m['current_state_eligible']=True
        with self.assertRaisesRegex(ValueError,'UNAUTHORIZED_CLAIM'):self.check(modify)

    def test_diagnostic_wrong_png_sha_rejected(self):
        def modify(p,d,m):d['image_sha256']='f'*64
        with self.assertRaisesRegex(ValueError,'DIAGNOSTIC_SOURCE'):self.check(modify)

    def test_snapshot_and_mega_cross_binding_rejected(self):
        for role in ('snapshot','mega_text_probe'):
            def modify(p,d,m):d[role]['image_sha256']='0'*64
            with self.subTest(role=role),self.assertRaisesRegex(ValueError,'CROSS_PROVENANCE'):self.check(modify)

    def test_corrupted_member_rejected(self):
        parts=make_fixture();parts['original.png']=parts['original.png'][:-1]+b'Z'
        make_zip(self.path,parts)
        with self.assertRaisesRegex(ValueError,'PNG_FORMAT|MANIFEST_SHA'):verify_archive(self.path)

    def test_manifest_rejects_claimed_wrong_crc_or_length(self):
        for key in ('crc32','bytes','sha256'):
            parts=make_fixture();m=json.loads(parts['manifest.json']);m['entries'][0][key]=0
            parts['manifest.json']=canonical(m);make_zip(self.path,parts)
            with self.subTest(key=key),self.assertRaises(ValueError):verify_archive(self.path)

    def test_duplicate_zip_path_rejected(self):
        parts=make_fixture()
        with zipfile.ZipFile(self.path,'w') as z:
            for name,blob in parts.items():z.writestr(name,blob)
            z.writestr('original.png',parts['original.png'])
        with self.assertRaisesRegex(ValueError,'ZIP_MEMBERS'):verify_archive(self.path)

    def test_unknown_extra_member_rejected(self):
        parts=make_fixture();parts['extra.txt']=b'NOT_EXPECTED';make_zip(self.path,parts)
        with self.assertRaisesRegex(ValueError,'ZIP_MEMBERS'):verify_archive(self.path)

    def test_duplicate_json_key_rejected(self):
        parts=make_fixture();raw=parts['diagnostic.json']
        # The extra duplicate key is allowed by generic json.loads but not R580.
        parts['diagnostic.json']=raw[:-1]+b',"schema":"spoof"}'
        make_zip(self.path,parts)
        with self.assertRaisesRegex(ValueError,'DUPLICATE_JSON_KEY'):verify_archive(self.path)

    def test_png_crc_corruption_rejected_even_when_rehashed(self):
        parts=make_fixture();p=bytearray(parts['original.png']);p[42]^=1
        img=bytes(p)
        d=json.loads(parts['diagnostic.json']);m=json.loads(parts['manifest.json'])
        d['image_sha256']=sha(img);d['payload']['image_sha256']=sha(img)
        d['snapshot']['image_sha256']=sha(img);d['mega_text_probe']['image_sha256']=sha(img)
        d['png_bytes']=len(img)
        db=canonical(d);m['image_sha256']=sha(img)
        for e in m['entries']:
            b=img if e['path']=='original.png' else db
            e.update(bytes=len(b),crc32=zlib.crc32(b)&0xffffffff,sha256=sha(b))
        make_zip(self.path,{'original.png':img,'diagnostic.json':db,'manifest.json':canonical(m)})
        with self.assertRaisesRegex(ValueError,'PNG_CHUNK_CRC'):verify_archive(self.path)

    def test_readonly_bad_zip_rejected(self):
        self.path.write_bytes(b'INVALID')
        with self.assertRaises((ValueError,zipfile.BadZipFile)):verify_archive(self.path)

if __name__=='__main__':unittest.main()
