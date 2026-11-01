"""Independent reconstruction of source-bound screen candidates, not image OCR."""
import re
from screen_read_semantics import normalized
from screen_read_layout import bound_roi,variants

def classify(tokens):
    exact={''.join(normalized(t).split()).upper() for t in tokens}
    command=any(re.fullmatch(r'COMMAND(?::?[0-9]{1,3})?',t) for t in exact)
    kinds=[]
    if command and '技の説明' in exact:
        detail=bool(exact & {'技分類','威力','命中','効果範囲'})
        kinds.append('move_selection_with_move_details_overlay_candidate' if detail else 'move_selection_candidate')
    elif command and exact & {'たたかう','こうたい','ポケモン','にげる'}:
        kinds.append('normal_command_candidate')
    if exact & {'選出','選出順','出すポケモンを選んでください'} and exact & {'決定','完了','あと3匹','あと2匹'}:
        kinds.append('party_selection_candidate')
    if exact & {'相手のパーティ','対戦相手のポケモン'} and exact & {'パーティ確認','見せ合い','選出時間'}:
        kinds.append('party_preview_candidate')
    if exact & {'交代先を選んでください','交代するポケモンを選んでください'} and exact & {'もどる','キャンセル','決定'}:
        kinds.append('switch_selection_candidate')
    if exact & {'YOUWIN','YOULOSE','対戦終了','勝利','敗北'}:kinds.append('battle_end_candidate')
    if not kinds and exact & {'メガシンカ','メガ進化'}:kinds.append('animation_or_battle_message_candidate')
    return kinds[0] if len(kinds)==1 else 'unknown'

def classification_report(packet,width,height,session,frame,epoch,image,observed):
    primary,all_variants,evaluated,omitted=[],[],[],[]
    for index,row in enumerate(packet['readings']):
        if not isinstance(row,dict):raise ValueError('SCREEN_SOURCE_ROW')
        if row.get('reason') != 'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND':continue
        choices=variants(row,index)
        if bound_roi(row,width,height,frame,epoch,image) is None:
            omitted.append(f'payload_json.readings[{index}]');continue
        primary.append(choices[0]['text'])
        all_variants.extend(c['text'] for c in choices)
        evaluated.extend(c['reference'] for c in choices)
    first,union=classify(primary),classify(all_variants)
    chosen=first if first != 'unknown' and union==first else 'unknown'
    status=('HOLD_UNKNOWN_PRIMARY' if first=='unknown' else
            'HOLD_OCR_SCREEN_CONFLICT' if union!=first else 'PRIMARY_AND_ALTERNATIVES_AGREE')
    declared=packet.get('screen_kind')
    if declared is not None:
        if not isinstance(declared,str):status='HOLD_MALFORMED_PACKET_KIND';chosen='unknown'
        elif declared != chosen:status='HOLD_PACKET_KIND_DISAGREEMENT';chosen='unknown'
    return dict(schema='trueplan.screen-read.screen-evidence.v1',policy_id='STRICT_LABELS_BOUND_ROIS_ALL_VARIANTS_V1',
        capture_session_id=session,frame_id=frame,epoch=epoch,image_sha256=image,receipt_uptime_ms=observed,
        battle_id=None,turn=None,scope='HISTORICAL_TEXT_SCREEN_CANDIDATES_ONLY',
        roi_coordinate_space='ANALYSIS_PIXELS_TOP_LEFT',status=status,primary_kind=first,all_variants_kind=union,
        screen_kind=chosen,declared_packet_kind=declared,evaluated_evidence_refs=evaluated,omitted_reading_refs=omitted,
        owner_certified=False,game_accuracy_certified=False,current_state_eligible=False,battle_advice_authorized=False)
