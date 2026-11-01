from pathlib import Path
import copy,json,sys,tempfile,unittest
sys.path[:0]=[str(Path(__file__).resolve().parents[1]/'tools')]
from test_evidence_verifier import archive,indexed,encoded
from r556_fixture import projection_fixture
from verify_screen_evidence import verify_archive,EvidenceError
from screen_read_projection import source_rect

class ProjectionTests(unittest.TestCase):
    def modified(self,callback):
        files=projection_fixture();s=json.loads(files['selected_evidence.json']);callback(s['analysis_projection'])
        files['selected_evidence.json']=encoded(s);return files
    def verify(self,files):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'evidence.zip';p.write_bytes(archive(indexed(files)));return verify_archive(p)
    def reject(self,callback):
        with self.assertRaises(EvidenceError):self.verify(self.modified(callback))
    def test_literal_crop_ccw_fixture(self):self.assertEqual(self.verify(projection_fixture())['source_binding'],'PASS')
    def test_wrong_raw_image(self):self.reject(lambda p:p.update(raw_image_sha256='a'*64))
    def test_wrong_analysis_image(self):self.reject(lambda p:p.update(analysis_image_sha256='a'*64))
    def test_other_frame(self):self.reject(lambda p:p.update(frame_id=18))
    def test_boolean_frame(self):self.reject(lambda p:p.update(frame_id=True))
    def test_other_epoch(self):self.reject(lambda p:p.update(epoch=4))
    def test_other_session(self):self.reject(lambda p:p.update(capture_session_id='another'))
    def test_wrong_receipt(self):self.reject(lambda p:p.update(receipt_uptime_ms=1201))
    def test_boolean_crop(self):self.reject(lambda p:p['pixel_crop'].update(y=True))
    def test_crop_outside_source(self):self.reject(lambda p:p['pixel_crop'].update(x=6))
    def test_zero_crop(self):self.reject(lambda p:p['pixel_crop'].update(width=0))
    def test_wrong_analysis_dimensions(self):self.reject(lambda p:p.update(analysis_width=3))
    def test_boolean_rotation(self):self.reject(lambda p:p.update(quarter_turns_ccw=True))
    def test_unknown_rotation(self):self.reject(lambda p:p.update(quarter_turns_ccw=4))
    def test_reverse_rotation_cannot_keep_old_coordinates(self):self.reject(lambda p:p.update(quarter_turns_ccw=3))
    def test_missing_mapped_roi(self):self.reject(lambda p:p.update(mapped_rois=[]))
    def test_missing_omitted_roi(self):self.reject(lambda p:p.update(omitted_rois=[]))
    def test_duplicate_reference(self):self.reject(lambda p:p['mapped_rois'].append(copy.deepcopy(p['mapped_rois'][0])))
    def test_wrong_raw_roi(self):self.reject(lambda p:p['mapped_rois'][0]['raw_rect'].update(x=2))
    def test_boolean_nested_roi(self):self.reject(lambda p:p['mapped_rois'][0]['analysis_rect'].update(width=True))
    def test_false_pixel_certificate(self):self.reject(lambda p:p.update(pixel_equality_verified=True))
    def test_false_owner_certificate(self):self.reject(lambda p:p.update(owner_certified=True))
    def test_false_current_state(self):self.reject(lambda p:p.update(current_state_eligible=True))
    def test_false_game_orientation(self):self.reject(lambda p:p.update(game_orientation_certified=True))
    def test_game_battle_identity(self):self.reject(lambda p:p.update(battle_id='invented'))
    def test_malformed_ocr_row_is_a_verification_error(self):
        import hashlib
        files=projection_fixture();s=json.loads(files['selected_evidence.json'])
        wrapper=json.loads(s['research_candidate_envelope']);packet=json.loads(wrapper['payload_json'])
        packet['readings']=[17];payload=encoded(packet)
        wrapper.update(payload_json=payload.decode(),payload_sha256=hashlib.sha256(payload).hexdigest())
        s['research_candidate_envelope']=encoded(wrapper).decode();files['selected_evidence.json']=encoded(s)
        with self.assertRaises(EvidenceError):self.verify(files)
    def test_four_inverse_corner_cases(self):
        c=dict(x=2,y=1,width=3,height=2)
        for turn,roi,expected in [(0,dict(x=0,y=0,width=1,height=1),dict(x=2,y=1,width=1,height=1)),
                                  (1,dict(x=0,y=0,width=1,height=1),dict(x=4,y=1,width=1,height=1)),
                                  (2,dict(x=0,y=0,width=1,height=1),dict(x=4,y=2,width=1,height=1)),
                                  (3,dict(x=0,y=0,width=1,height=1),dict(x=2,y=2,width=1,height=1))]:
            self.assertEqual(source_rect(roi,c,turn),expected)

if __name__=='__main__':unittest.main()
