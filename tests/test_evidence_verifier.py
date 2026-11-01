"""Protocol/adversarial tests; synthetic evidence is not game OCR ground truth."""
from pathlib import Path
import base64,binascii,copy,hashlib,io,json,struct,sys,tempfile,unittest,zipfile,zlib

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from verify_screen_evidence import verify_archive,EvidenceError,INDEX,SCHEMA

def encoded(value):return json.dumps(value,ensure_ascii=False,separators=(',',':')).encode()
def sha(data):return hashlib.sha256(data).hexdigest()
def png():
    def chunk(kind,body):return struct.pack('>I',len(body))+kind+body+struct.pack('>I',binascii.crc32(kind+body)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,2,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00'+b'\xff\x00\x00'*2+b'\x00'+b'\x00\xff\x00'*2))+chunk(b'IEND',b'')

def fixture():
    image=png();digest=sha(image)
    image_record={'image_png_base64':base64.b64encode(image).decode(),'png_bytes':len(image),'png_sha256':digest}
    readings=[{'raw_text':'81%','reason':'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND'}]
    packet={'schema':'trueplan.mobile-observation.v1','battle_id':'capture-test','frame_id':17,'epoch':3,
            'observed_at_ms':1200,'received_at_ms':1250,'image_sha256':digest,'production_enabled':False,'turn':None,'readings':readings}
    payload=encoded(packet)
    wrapper={'payload_json':payload.decode(),'payload_sha256':sha(payload),'schema':'trueplan.mobile-envelope.v1'}
    unknown={'knowledge_state':'UNKNOWN','value':None}
    state={'schema':'trueplan.screen-read.snapshot.v1','capture_session_id':'capture-test','battle_id':None,
           'frame_id':17,'epoch':3,'image_sha256':digest,'turn':None,'capture_timestamp_ms':None,
           'validity':'HISTORICAL_FRAME_ONLY','current_state_eligible':False,'battle_advice_authorized':False,
           'own':{'hp':copy.deepcopy(unknown)},'opponent':{'hp':copy.deepcopy(unknown)},'field':{'weather':copy.deepcopy(unknown)},
           'candidates':[{'domain':'hp_percent','raw_text':'81%','value':81,'evidence_ref':'payload_json.readings[0]',
                          'capture_session_id':'capture-test','image_sha256':digest,'frame_id':17,'epoch':3,
                          'knowledge_state':'INFERRED','side':'UNKNOWN_OWNER','verification_status':'UNVERIFIED',
                          'current_state_eligible':False,'validity':'HISTORICAL_FRAME_ONLY'}]}
    selected={**image_record,'schema':'trueplan.r27441.manual-frame-evidence.v2','image_width':2,'image_height':2,
              'frame_id':17,'epoch':3,'capture_session_id':'capture-test','battle_id':None,'observed_ms_monotonic':1200,
              'production_enabled':False,'battle_advice_authorized':False,
              'analysis_image':{**image_record,'width':2,'height':2},'research_candidate_envelope':encoded(wrapper).decode(),
              'screen_read_state':state}
    ocr={'schema':'trueplan.r551.rotation-ocr-evidence.v1','image_sha256':digest,'mega_certified':False,
         'own_opponent':'UNKNOWN','megascene_observed':None,'mega_event_status':'UNKNOWN','visual_form_certified':False,'orientation_certified':False,
         'rotations_completed':[0,90,180,270],'rotations_failed':[],'rotations_skipped':[],
         'orientation_evidence':[{'orientation_degrees':x,'status':'OCR_CANDIDATES_ONLY','observations':
             [{'candidates':[{'text':'81%','confidence':0.8}],'roi':{'x':0.1,'y':0.1,'width':0.4,'height':0.2}}]} for x in [0,90,180,270]]}
    manifest={'selected_frame_id':17,'selected_epoch':3,'capture_session_id':'capture-test','battle_id':None,'battle_advice_authorized':False,
              'captured_frame_count':1,'omissions':[],'frames':[{'file':'frames/frame_17.png','frame_id':17,'epoch':3,
                'observed_ms_monotonic':1200,'png_bytes':len(image),'png_sha256':digest,'width':2,'height':2,
                'own_opponent_certified':False,'mega_form_visual_certified':False,'mega_scene_ocr_hints':ocr}]}
    return {'selected_evidence.json':encoded(selected),'capture_manifest.json':encoded(manifest),'frames/frame_17.png':image}

def indexed(files):
    result=dict(files)
    index={'schema':SCHEMA,'capture_session_id':'capture-test','battle_id':None,'selected_frame_id':17,'selected_epoch':3,
           'battle_advice_authorized':False,'self_hash_included':False,'entry_count_excluding_index':len(files),
           'entries':[{'path':name,'bytes':len(data),'sha256':sha(data),'crc32':binascii.crc32(data)&0xffffffff} for name,data in sorted(files.items())]}
    result[INDEX]=encoded(index);return result

def archive(files,compression=zipfile.ZIP_STORED):
    result=io.BytesIO()
    with zipfile.ZipFile(result,'w',compression=compression) as z:
        for name,data in files.items():z.writestr(name,data)
    return result.getvalue()

class EvidenceVerifierTests(unittest.TestCase):
    def setUp(self):self.directory=tempfile.TemporaryDirectory();self.path=Path(self.directory.name)/'evidence.zip'
    def tearDown(self):self.directory.cleanup()
    def verify(self,files=None,raw=None,compression=zipfile.ZIP_STORED,expected=None):
        self.path.write_bytes(raw if raw is not None else archive(indexed(files or fixture()),compression))
        return verify_archive(self.path,expected)
    def reject(self,files=None,raw=None):
        with self.assertRaises(EvidenceError):self.verify(files,raw)
    def edit(self,name,mutate):
        files=fixture();root=json.loads(files[name]);mutate(root);files[name]=encoded(root);return files
    def test_stored_archive_and_source_binding(self):self.assertEqual(self.verify()['captured_frames'],1)
    def test_deflated_archive(self):self.assertEqual(self.verify(compression=zipfile.ZIP_DEFLATED)['crc32'],'PASS')
    def test_trusted_archive_sha(self):
        raw=archive(indexed(fixture()));self.assertTrue(self.verify(raw=raw,expected=sha(raw))['trusted_archive_sha_checked'])
    def test_wrong_trusted_sha(self):
        with self.assertRaises(EvidenceError):self.verify(expected='0'*64)
    def test_missing_member(self):
        files=indexed(fixture());del files['frames/frame_17.png'];self.reject(raw=archive(files))
    def test_legacy_has_no_sha_certification(self):self.reject(raw=archive(fixture()))
    def test_modified_selected_bytes(self):
        files=indexed(fixture());files['selected_evidence.json']+=b' ';self.reject(raw=archive(files))
    def test_modified_index_sha(self):
        files=indexed(fixture());i=json.loads(files[INDEX]);i['entries'][0]['sha256']='0'*64;files[INDEX]=encoded(i);self.reject(raw=archive(files))
    def test_duplicate_zip_name(self):
        raw=io.BytesIO(archive(indexed(fixture())))
        with zipfile.ZipFile(raw,'a') as z:z.writestr('selected_evidence.json',b'{}')
        self.reject(raw=raw.getvalue())
    def test_traversal_path(self):
        files=fixture();files['../escape']=b'x';self.reject(files)
    def test_symlink(self):
        raw=io.BytesIO();files=indexed(fixture())
        with zipfile.ZipFile(raw,'w') as z:
            for name,data in files.items():
                i=zipfile.ZipInfo(name);i.create_system=3;i.external_attr=(0o120777<<16);z.writestr(i,data)
        self.reject(raw=raw.getvalue())
    def test_trailing_bytes(self):self.reject(raw=archive(indexed(fixture()))+b'garbage')
    def test_prefixed_bytes(self):self.reject(raw=b'hidden'+archive(indexed(fixture())))
    def test_truncated_zip(self):self.reject(raw=archive(indexed(fixture()))[:-5])
    def test_corrupt_crc(self):
        raw=bytearray(archive(indexed(fixture())));raw[80]^=1;self.reject(raw=bytes(raw))
    def test_local_header_mismatch(self):
        raw=bytearray(archive(indexed(fixture())));raw[8]=8;self.reject(raw=bytes(raw))
    def test_false_battle_advice(self):self.reject(self.edit('selected_evidence.json',lambda r:r.update(battle_advice_authorized=True)))
    def test_false_device_side_certification(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0].update(own_opponent_certified=True)))
    def test_changed_frame_despite_recomputed_sha_index(self):self.reject(self.edit('selected_evidence.json',lambda r:r.update(frame_id=18)))
    def test_boolean_epoch(self):self.reject(self.edit('selected_evidence.json',lambda r:r.update(epoch=True)))
    def test_bad_embedded_base64(self):self.reject(self.edit('selected_evidence.json',lambda r:r.update(image_png_base64='@@@')))
    def test_wrong_image_dimensions(self):self.reject(self.edit('selected_evidence.json',lambda r:r.update(image_width=3)))
    def test_ocr_payload_hash(self):
        def mutate(r):
            w=json.loads(r['research_candidate_envelope']);w['payload_sha256']='0'*64;r['research_candidate_envelope']=encoded(w).decode()
        self.reject(self.edit('selected_evidence.json',mutate))
    def test_ocr_wrong_session_even_with_updated_payload_hash(self):
        def mutate(r):
            w=json.loads(r['research_candidate_envelope']);p=json.loads(w['payload_json']);p['battle_id']='other';w['payload_json']=encoded(p).decode();w['payload_sha256']=sha(w['payload_json'].encode());r['research_candidate_envelope']=encoded(w).decode()
        self.reject(self.edit('selected_evidence.json',mutate))
    def test_partial_ocr_is_explicit_and_allowed(self):
        def mutate(r):
            o=r['frames'][0]['mega_scene_ocr_hints'];o.update(rotations_completed=[0],rotations_failed=[],rotations_skipped=[90,180,270],orientation_evidence=o['orientation_evidence'][:1])
        self.assertEqual(self.verify(self.edit('capture_manifest.json',mutate))['captured_frames'],1)
    def test_duplicate_rotation(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0]['mega_scene_ocr_hints']['rotations_completed'].append(0)))
    def test_rotated_ocr_from_other_image(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0]['mega_scene_ocr_hints'].update(image_sha256='0'*64)))
    def test_nan_confidence(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0]['mega_scene_ocr_hints']['orientation_evidence'][0]['observations'][0]['candidates'][0].update(confidence=float('nan'))))
    def test_boolean_confidence(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0]['mega_scene_ocr_hints']['orientation_evidence'][0]['observations'][0]['candidates'][0].update(confidence=True)))
    def test_out_of_bounds_roi(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0]['mega_scene_ocr_hints']['orientation_evidence'][0]['observations'][0]['roi'].update(x=0.9)))
    def test_unverified_mega_promoted(self):self.reject(self.edit('capture_manifest.json',lambda r:r['frames'][0]['mega_scene_ocr_hints'].update(mega_event_status='ACTIVATED')))
    def test_snapshot_current_state_claim(self):self.reject(self.edit('selected_evidence.json',lambda r:r['screen_read_state'].update(current_state_eligible=True)))
    def test_snapshot_side_value_promoted(self):self.reject(self.edit('selected_evidence.json',lambda r:r['screen_read_state']['own']['hp'].update(knowledge_state='OBSERVED',value=81)))
    def test_snapshot_other_frame(self):self.reject(self.edit('selected_evidence.json',lambda r:r['screen_read_state'].update(frame_id=18)))
    def test_snapshot_raw_text_tampered(self):self.reject(self.edit('selected_evidence.json',lambda r:r['screen_read_state']['candidates'][0].update(raw_text='100%')))
    def test_snapshot_ref_out_of_range(self):self.reject(self.edit('selected_evidence.json',lambda r:r['screen_read_state']['candidates'][0].update(evidence_ref='payload_json.readings[99]')))
    def test_duplicate_json_key(self):
        files=fixture();files['capture_manifest.json']=files['capture_manifest.json'][:-1]+b',"selected_frame_id":99}';self.reject(files)
    def test_wrong_index_self_hash_flag(self):
        files=indexed(fixture());i=json.loads(files[INDEX]);i['self_hash_included']=True;files[INDEX]=encoded(i);self.reject(raw=archive(files))

if __name__=='__main__':unittest.main()
