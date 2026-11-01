"""Literal synthetic screen contracts. Expected classes are hand specified."""
import json
from r553_fixture import menu_fixture,source_update,layout_base

MOVE='move_selection_candidate'
OVERLAY='move_selection_with_move_details_overlay_candidate'

def literal_report(image,kind,count):
    return dict(schema='trueplan.screen-read.screen-evidence.v1',policy_id='STRICT_LABELS_BOUND_ROIS_ALL_VARIANTS_V1',
        capture_session_id='capture-test',frame_id=17,epoch=3,image_sha256=image,receipt_uptime_ms=1200,
        battle_id=None,turn=None,scope='HISTORICAL_TEXT_SCREEN_CANDIDATES_ONLY',roi_coordinate_space='ANALYSIS_PIXELS_TOP_LEFT',
        status='PRIMARY_AND_ALTERNATIVES_AGREE',primary_kind=kind,all_variants_kind=kind,screen_kind=kind,
        declared_packet_kind=kind,evaluated_evidence_refs=[f'payload_json.readings[{i}]' for i in range(count)],
        omitted_reading_refs=[],owner_certified=False,game_accuracy_certified=False,
        current_state_eligible=False,battle_advice_authorized=False)

def screen_fixture(overlay=True):
    files=menu_fixture();selected=json.loads(files['selected_evidence.json'])
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
    kind=OVERLAY if overlay else MOVE
    if overlay:
        # Panel labels lie outside the HP/name/move/PP regions.
        for text,y in [('技分類',80),('威力',105)]:
            packet['readings'].append(dict(raw_text=text,confidence=0.9,reason='FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND',
                source_frame_id=17,source_epoch=3,source_image_sha256=packet['image_sha256'],
                roi_rect=dict(x=120,y=y,width=90,height=12)))
    packet['screen_kind']=kind
    state=selected['screen_read_state'];state.update(screen_read_engine_version='r557.snapshot.v1',screen_kind=kind)
    state['screen_classification']=literal_report(packet['image_sha256'],kind,len(packet['readings']))
    if overlay:
        state['layout_candidates']['profile_id']='LEGACY_VERTICAL_MOVES_216_LEFT_DETAILS_V2'
        for index,label in [(14,'技分類'),(15,'威力')]:
            state['layout_candidates']['anchors'].append(dict(role_hint='overlay_'+label,reading_index=index,
                evidence_refs=[f'payload_json.readings[{index}]'],value=label))
    return source_update(files,selected,packet)

def screen_conflict_fixture(alternative_only=False):
    files=screen_fixture();selected=json.loads(files['selected_evidence.json'])
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
    row=packet['readings'][3]
    row['raw_text']='不明' if alternative_only else '技の説明'
    row['ocr_alternatives']=[dict(rank=0,raw_text=row['raw_text'],confidence=0.9),
                             dict(rank=1,raw_text='技の説明' if alternative_only else '勝利',confidence=0.8)]
    packet['screen_kind']='unknown'
    state=selected['screen_read_state'];state.update(screen_kind='unknown',knowledge_state='UNKNOWN' if alternative_only else 'CONFLICT')
    report=state['screen_classification'];report.update(screen_kind='unknown',declared_packet_kind='unknown',
        primary_kind='unknown' if alternative_only else OVERLAY,all_variants_kind=OVERLAY if alternative_only else 'unknown',
        status='HOLD_UNKNOWN_PRIMARY' if alternative_only else 'HOLD_OCR_SCREEN_CONFLICT')
    report['evaluated_evidence_refs'].insert(4,'payload_json.readings[3].ocr_alternatives[1]')
    state['layout_candidates']=layout_base(packet['image_sha256'])
    return source_update(files,selected,packet)
