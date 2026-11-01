"""Hand-authored tiny pixel grid and declared transform, never game accuracy."""
import binascii,copy,hashlib,json,struct,zlib
from test_evidence_verifier import fixture,encoded

def png_grid(rows):
    h,w=len(rows),len(rows[0])
    def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',binascii.crc32(t+d)&0xffffffff)
    pixels=b''.join(b'\0'+b''.join(bytes((v,100,200)) for v in row) for row in rows)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels))+chunk(b'IEND',b'')

def projection_fixture():
    files=fixture();s=json.loads(files['selected_evidence.json']);m=json.loads(files['capture_manifest.json'])
    raw=png_grid([[y*10+x for x in range(7)] for y in range(5)])
    analysis=png_grid([[14,24],[13,23],[12,22]])
    rawsha=hashlib.sha256(raw).hexdigest();sha=hashlib.sha256(analysis).hexdigest()
    import base64
    s.update(image_width=7,image_height=5,png_bytes=len(raw),png_sha256=rawsha,image_png_base64=base64.b64encode(raw).decode())
    s['analysis_image']={'width':2,'height':3,'png_bytes':len(analysis),'png_sha256':sha,'image_png_base64':base64.b64encode(analysis).decode()}
    s.pop('screen_read_state',None)
    packet={'schema':'trueplan.mobile-observation.v1','battle_id':'capture-test','frame_id':17,'epoch':3,'observed_at_ms':1200,'received_at_ms':1250,'image_sha256':sha,'production_enabled':False,'turn':None,
            'readings':[{'raw_text':'81%','confidence':0.8,'reason':'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND','roi_rect':{'x':0,'y':0,'width':1,'height':2},'source_frame_id':17,'source_epoch':3,'source_image_sha256':sha,'roi_source':'VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED','roi_owner_certified':False},
                        {'raw_text':'PP','reason':'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND'}]}
    payload=encoded(packet);s['research_candidate_envelope']=encoded({'schema':'trueplan.mobile-envelope.v1','payload_json':payload.decode(),'payload_sha256':hashlib.sha256(payload).hexdigest()}).decode()
    s['analysis_projection']={'schema':'trueplan.screen-read.analysis-projection.v1','status':'DECLARED_GEOMETRY_ONLY','reason':'OCR_MEANING_AND_PER_FRAME_PIXEL_EQUALITY_UNCERTIFIED',
        'capture_session_id':'capture-test','frame_id':17,'epoch':3,'receipt_uptime_ms':1200,'raw_image_sha256':rawsha,'analysis_image_sha256':sha,
        'raw_width':7,'raw_height':5,'pixel_crop':{'x':2,'y':1,'width':3,'height':2},'quarter_turns_ccw':1,'analysis_width':2,'analysis_height':3,
        'coordinate_convention':'HALF_OPEN_PIXELS_TOP_LEFT','transform':'INTEGER_CROP_THEN_CCW_QUARTER_TURN','pixel_equality_verified':False,'game_orientation_certified':False,'owner_certified':False,'current_state_eligible':False,'battle_advice_authorized':False,'battle_id':None,'turn':None,
        'mapped_rois':[{'evidence_ref':'payload_json.readings[0]','analysis_rect':{'x':0,'y':0,'width':1,'height':2},'raw_rect':{'x':3,'y':1,'width':2,'height':1}}],
        'omitted_rois':[{'evidence_ref':'payload_json.readings[1]','reason':'ROI_MISSING_OR_UNBOUND'}]}
    f=m['frames'][0];f.update(width=7,height=5,png_bytes=len(raw),png_sha256=rawsha);f['mega_scene_ocr_hints']['image_sha256']=rawsha
    return {'selected_evidence.json':encoded(s),'capture_manifest.json':encoded(m),'frames/frame_17.png':raw}
