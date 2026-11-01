"""Hand-authored synthetic menu and expected profile associations; no game image."""
import base64,copy,json,struct,zlib,binascii
from test_state_semantics import state_fixture
from test_evidence_verifier import encoded,sha

def menu_png():
    def chunk(kind,body):return struct.pack('>I',len(body))+kind+body+struct.pack('>I',binascii.crc32(kind+body)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1000,462,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\x00'+b'\x10\x20\x30'*1000)*462))+chunk(b'IEND',b'')

def source_update(files, selected, packet):
    wrapper=json.loads(selected['research_candidate_envelope'])
    payload=encoded(packet)
    wrapper.update(payload_json=payload.decode(),payload_sha256=sha(payload))
    selected['research_candidate_envelope']=encoded(wrapper).decode()
    files['selected_evidence.json']=encoded(selected)
    return files

def layout_base(image):
    return dict(schema='trueplan.screen-read.layout-candidates.v1',profile_id='LEGACY_VERTICAL_MOVES_216_V1',
        status='HOLD_UNSUPPORTED_SCREEN',capture_session_id='capture-test',frame_id=17,epoch=3,image_sha256=image,
        receipt_uptime_ms=1200,roi_coordinate_space='ANALYSIS_PIXELS_TOP_LEFT',scope='HISTORICAL_FRAME_LAYOUT_CANDIDATES_ONLY',
        calibration_certified=False,owner_certified=False,current_state_eligible=False,battle_advice_authorized=False,
        anchors=[],associations=[],conflict_count=0)

def menu_fixture():
    files=state_fixture([])
    selected=json.loads(files['selected_evidence.json']);state=selected['screen_read_state']
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
    image=menu_png();digest=sha(image)
    metadata={'image_png_base64':base64.b64encode(image).decode(),'png_bytes':len(image),'png_sha256':digest}
    selected.update(**metadata,image_width=1000,image_height=462)
    selected['analysis_image'].update(**metadata,width=1000,height=462)
    packet.update(image_sha256=digest,screen_kind='move_selection_candidate',readings=[])
    manifest=json.loads(files['capture_manifest.json']);frame=manifest['frames'][0]
    frame.update(png_bytes=len(image),png_sha256=digest,width=1000,height=462)
    frame['mega_scene_ocr_hints']['image_sha256']=digest
    files['capture_manifest.json']=encoded(manifest);files['frames/frame_17.png']=image
    text_rows=[('100/200',(170,420,80,14)),('81%',(860,51,45,14)),('COMMAND',(790,100,70,10)),
        ('技の説明',(680,160,90,10)),('ピカチュウ',(130,394,100,12)),('イーブイ',(795,22,90,12))]
    for slot,move in enumerate(('たいあたり','まもる','でんこうせっか','なきごえ')):
        text_rows.extend([(move,(760,208+slot*55,100,12)),(f'{slot+4}/10',(891,204+slot*55,30,10))])
    for text,(x,y,w,h) in text_rows:
        packet['readings'].append(dict(raw_text=text,confidence=0.9,reason='FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND',
            source_frame_id=17,source_epoch=3,source_image_sha256=digest,roi_rect=dict(x=x,y=y,width=w,height=h)))
    state.update(screen_read_engine_version='r553.snapshot.v1',screen_kind='move_selection_candidate',image_sha256=digest,
                 candidates=[],conflicts=[],knowledge_state='UNKNOWN')
    # Literal numeric candidates are explicitly specified; text names only enter
    # the unverified layout report, never either side's current state.
    template=json.loads(state_fixture([('81%','hp_percent',81)])['selected_evidence.json'])['screen_read_state']['candidates'][0]
    for index,domain,value in [(0,'hp_or_pp',dict(current=100,maximum=200)),(1,'hp_percent',81),
                              *((7+slot*2,'hp_or_pp',dict(current=slot+4,maximum=10)) for slot in range(4))]:
        row=packet['readings'][index]
        state['candidates'].append({**copy.deepcopy(template),'domain':domain,'value':value,'raw_text':row['raw_text'],
            'normalized_text':row['raw_text'],'confidence':0.9,'roi':row['roi_rect'],'image_sha256':digest,
            'evidence_ref':f'payload_json.readings[{index}]','ocr_rank':0})
    layout=layout_base(digest);layout['status']='PROVISIONAL_PROFILE_MATCH_ONLY'
    def record(role,index,value,slot=None,method='UNVERIFIED_LAYOUT_ANCHOR'):
        row=packet['readings'][index]
        return dict(role_hint=role,slot=slot,suggested_owner='opponent' if role.startswith('opponent_') else 'own',
            side='UNKNOWN_OWNER',capture_session_id='capture-test',frame_id=17,epoch=3,image_sha256=digest,receipt_uptime_ms=1200,
            battle_id=None,turn=None,capture_timestamp_ms=None,stale_deadline_ms=None,
            orientation='ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED',roi_coordinate_space='ANALYSIS_PIXELS_TOP_LEFT',
            confidence=None,source_confidences=[0.9],source='VISION_OCR_LAYOUT_CANDIDATE',
            evidence_refs=[f'payload_json.readings[{index}]'],raw_texts=[row['raw_text']],rois=[row['roi_rect']],
            verification_status='UNVERIFIED',current_state_eligible=False,validity='HISTORICAL_FRAME_ONLY',
            knowledge_state='INFERRED',value=value,method=method)
    for role,index,value in [('own_hp',0,dict(current=100,maximum=200)),('opponent_hp',1,81),('command',2,'COMMAND')]:
        layout['anchors'].append(dict(role_hint=role,reading_index=index,evidence_refs=[f'payload_json.readings[{index}]'],value=value))
        if role!='command':layout['associations'].append(record(role,index,value))
    layout['associations'].extend([record('own_name',4,'ピカチュウ',method='UNVERIFIED_NAME_REGION_TEXT'),
                                   record('opponent_name',5,'イーブイ',method='UNVERIFIED_NAME_REGION_TEXT')])
    for slot in range(4):
        layout['associations'].extend([record('move_name',6+slot*2,text_rows[6+slot*2][0],slot,'UNVERIFIED_MOVE_REGION_TEXT'),
                                      record('move_pp',7+slot*2,dict(current=slot+4,maximum=10),slot,'LITERAL_OR_EXPLICIT_SLASH_PARTS_ONLY')])
    state['layout_candidates']=layout
    return source_update(files,selected,packet)

def alternative_fixture():
    files=state_fixture([('81%','hp_percent',81)])
    selected=json.loads(files['selected_evidence.json']);state=selected['screen_read_state']
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json']);row=packet['readings'][0]
    row['ocr_alternatives']=[dict(rank=0,raw_text='81%',confidence=0.8),dict(rank=1,raw_text='82%',confidence=0.7)]
    state.update(screen_read_engine_version='r553.snapshot.v1',screen_kind='unknown',knowledge_state='CONFLICT')
    first=state['candidates'][0];first['ocr_rank']=0
    state['candidates'].append({**copy.deepcopy(first),'raw_text':'82%','normalized_text':'82%','value':82,
                               'confidence':0.7,'ocr_rank':1,'evidence_ref':'payload_json.readings[0].ocr_alternatives[1]'})
    state['layout_candidates']=layout_base(packet['image_sha256'])
    state['conflicts']=[{**{k:first[k] for k in ('domain','capture_session_id','frame_id','epoch','image_sha256','roi')},
        'semantic_key':'value','knowledge_state':'CONFLICT','scope':'OCR_INTERPRETATION_ONLY',
        'reason':'DIFFERENT_VALUES_SAME_BOUND_FRAME_AND_ROI','side':'UNKNOWN_OWNER','current_state_eligible':False,
        'candidate_indices':[0,1],'evidence_refs':['payload_json.readings[0]','payload_json.readings[0].ocr_alternatives[1]']}]
    return source_update(files,selected,packet)
