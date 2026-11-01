"""Independent reconstruction of provisional OCR layout associations.

The one legacy layout is an unverified profile, never an ownership certificate.
All references are checked against the same source packet; no image inference.
"""
import math
import re
from screen_read_semantics import normalized, canonical

def safe_confidence(value):
    return value if type(value) in (int,float) and math.isfinite(value) and 0 <= value <= 1 else None

def variants(row, reading):
    raw = row.get('raw_text')
    if not isinstance(raw,str) or not 0 < len(raw) <= 256:
        raise ValueError('OCR_ALTERNATIVE_RAW')
    prefix = f'payload_json.readings[{reading}]'
    primary = {'text':raw,'confidence':safe_confidence(row.get('confidence')),'rank':0,'reference':prefix}
    if 'ocr_alternatives' not in row:
        return [primary]
    alternatives = row['ocr_alternatives']
    if not isinstance(alternatives,list) or not 1 <= len(alternatives) <= 3:
        raise ValueError('OCR_ALTERNATIVE_COUNT')
    result = []
    for rank, alt in enumerate(alternatives):
        if not isinstance(alt,dict):raise ValueError('OCR_ALTERNATIVE_ROW')
        score, text, recorded_rank = safe_confidence(alt.get('confidence')), alt.get('raw_text'), alt.get('rank')
        if (type(recorded_rank) not in (int,float) or recorded_rank != rank or
                not isinstance(text,str) or not 0 < len(text) <= 256 or score is None or
                (rank == 0 and (text != raw or score != primary['confidence'])) or
                (result and result[-1]['confidence'] < score)):
            raise ValueError('OCR_ALTERNATIVE_ORDER_OR_SOURCE')
        result.append({'text':text,'confidence':score,'rank':rank,
                       'reference':prefix if rank == 0 else prefix+f'.ocr_alternatives[{rank}]'})
    return result

def _uint(value):
    return type(value) in (int,float) and math.isfinite(value) and 0 <= value < 2**63 and value == int(value)

def bound_roi(row, width, height, frame, epoch, image):
    roi = row.get('roi_rect')
    if not (isinstance(roi,dict) and all(_uint(roi.get(k)) for k in ('x','y','width','height')) and
            _uint(row.get('source_frame_id')) and row['source_frame_id'] == frame and
            _uint(row.get('source_epoch')) and row['source_epoch'] == epoch and row.get('source_image_sha256') == image):
        return None
    x,y,w,h = (int(roi[k]) for k in ('x','y','width','height'))
    if not (w > 0 and h > 0 and x+w <= width and y+h <= height):return None
    return dict(x=x,y=y,width=w,height=h)

def _inside(site, region, width, height):
    x,y,w,h = region
    roi = site['roi']
    sx,sy,sw,sh = roi['x']/width,roi['y']/height,roi['width']/width,roi['height']/height
    overlap = max(0,min(x+w,sx+sw)-max(x,sx))*max(0,min(y+h,sy+sh)-max(y,sy))
    return overlap/(sw*sh) >= 0.9

def _compact(raw):return normalized(raw).replace(' ','')
def _fraction(raw, pp=False):
    text = _compact(raw)
    if text.startswith('PP' if pp else 'HP'):text = text[2:]
    match = re.fullmatch(r'([0-9]{1,2})/([0-9]{1,2})' if pp else r'([0-9]{1,4})/([0-9]{1,4})', text)
    if not match:return None
    current, maximum = int(match[1]),int(match[2])
    return dict(current=current,maximum=maximum) if maximum > 0 and current <= maximum else None
def _percent(raw):
    text = _compact(raw)
    if not re.fullmatch(r'[0-9]{1,3}(\.[0-9]{1,2})?%',text):return None
    value = float(text[:-1])
    # Match integer-valued Foundation JSON numbers for equality of candidates.
    return (int(value) if value.is_integer() else value) if 0 <= value <= 100 else None
def _name(raw):
    text = normalized(raw)
    return text if (2 <= len(text) <= 24 and re.fullmatch(r'[ぁ-ゖァ-ヺー一-龯A-Za-z0-9・♀♂]+',text) and
                    re.search(r'[ぁ-ゖァ-ヺ一-龯]',text)) else None

def layout_report(packet, width, height, screen_kind, session, frame, epoch, image, observed, allow_details_overlay=False):
    report = dict(schema='trueplan.screen-read.layout-candidates.v1',profile_id='LEGACY_VERTICAL_MOVES_216_V1',
        status='HOLD_UNSUPPORTED_SCREEN',capture_session_id=session,frame_id=frame,epoch=epoch,image_sha256=image,
        receipt_uptime_ms=observed,roi_coordinate_space='ANALYSIS_PIXELS_TOP_LEFT',scope='HISTORICAL_FRAME_LAYOUT_CANDIDATES_ONLY',
        calibration_certified=False,owner_certified=False,current_state_eligible=False,battle_advice_authorized=False,
        anchors=[],associations=[],conflict_count=0)
    if allow_details_overlay and screen_kind == 'move_selection_with_move_details_overlay_candidate':
        report['profile_id']='LEGACY_VERTICAL_MOVES_216_LEFT_DETAILS_V2'
    if screen_kind != 'move_selection_candidate' and not (allow_details_overlay and
            screen_kind == 'move_selection_with_move_details_overlay_candidate'):return report
    report['status'] = 'HOLD_UNSUPPORTED_GEOMETRY'
    if not (width >= 400 and height >= 180 and abs(width/height-578/267) < 0.025):return report
    sites = []
    for index, row in enumerate(packet['readings']):
        if row.get('reason') != 'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND':continue
        members = variants(row,index)
        roi = bound_roi(row,width,height,frame,epoch,image)
        if roi is not None:
            sites.extend({**member,'reading':index,'roi':roi} for member in members)
    primary = [s for s in sites if s['rank'] == 0]
    def association(role, slot, group, choices, method):
        distinct = {canonical(value) for value in choices}
        return dict(role_hint=role,slot=slot,suggested_owner='opponent' if role.startswith('opponent_') else 'own',
            side='UNKNOWN_OWNER',capture_session_id=session,frame_id=frame,epoch=epoch,image_sha256=image,receipt_uptime_ms=observed,
            battle_id=None,turn=None,capture_timestamp_ms=None,stale_deadline_ms=None,
            orientation='ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED',roi_coordinate_space='ANALYSIS_PIXELS_TOP_LEFT',
            confidence=None,source_confidences=[s['confidence'] for s in group],source='VISION_OCR_LAYOUT_CANDIDATE',
            evidence_refs=[s['reference'] for s in group],raw_texts=[s['text'] for s in group],rois=[s['roi'] for s in group],
            verification_status='UNVERIFIED',current_state_eligible=False,validity='HISTORICAL_FRAME_ONLY',
            knowledge_state='UNKNOWN' if not distinct else ('INFERRED' if len(distinct) == 1 else 'CONFLICT'),
            value=choices[0] if len(distinct) == 1 else None,method=method)
    def names(group):
        values = [_name(s['text']) for s in group]
        return values if all(v is not None for v in values) else []
    anchors, associations = [], []
    for role, region, parse in [('own_hp',(0.15,0.90,0.12,0.08),_fraction),
            ('opponent_hp',(0.84,0.10,0.09,0.07),_percent),
            ('command',(0.78,0.20,0.10,0.06),lambda raw:'COMMAND' if _compact(raw).upper() == 'COMMAND' else None)]:
        report['status'] = 'HOLD_MISSING_ANCHORS'
        found = [s for s in primary if _inside(s,region,width,height) and
                 s['confidence'] is not None and s['confidence'] >= 0.65 and parse(s['text']) is not None]
        if len(found) != 1:
            if len(found) > 1:report['status'] = 'HOLD_AMBIGUOUS_ANCHORS'
            return report
        selected = found[0]
        group = [s for s in sites if s['reading'] == selected['reading']]
        values = [parse(s['text']) for s in group]
        if any(value is None for value in values) or len({canonical(v) for v in values}) != 1:
            report['status'] = 'HOLD_AMBIGUOUS_ANCHORS';return report
        anchors.append(dict(role_hint=role,reading_index=selected['reading'],evidence_refs=[s['reference'] for s in group],value=values[0]))
        if role != 'command':associations.append(association(role,None,group,values,'UNVERIFIED_LAYOUT_ANCHOR'))
    if screen_kind == 'move_selection_with_move_details_overlay_candidate':
        report['status']='HOLD_UNSUPPORTED_OVERLAY'
        panel=(0.08,0.14,0.49,0.24)
        found=[s for s in primary if _compact(s['text']) in {'技分類','威力','命中','効果範囲'} and
               s['confidence'] is not None and s['confidence']>=0.65 and _inside(s,panel,width,height)]
        labels={_compact(s['text']) for s in found}
        if len(labels)<2:return report
        report['status']='HOLD_AMBIGUOUS_OVERLAY'
        if len(labels)!=len(found):return report
        for selected in found:
            group=[s for s in sites if s['reading']==selected['reading']]
            label=_compact(selected['text'])
            if any(_compact(s['text'])!=label for s in group):return report
            anchors.append(dict(role_hint='overlay_'+label,reading_index=selected['reading'],
                evidence_refs=[s['reference'] for s in group],value=label))
    for role,region in [('own_name',(0.12,0.84,0.14,0.07)),('opponent_name',(0.78,0.035,0.14,0.065))]:
        group = [s for s in sites if _inside(s,region,width,height)]
        associations.append(association(role,None,group,names(group),'UNVERIFIED_NAME_REGION_TEXT'))
    for slot in range(4):
        move = [s for s in sites if _inside(s,(0.75,0.44+slot*0.12,0.13,0.065),width,height)]
        associations.append(association('move_name',slot,move,names(move),'UNVERIFIED_MOVE_REGION_TEXT'))
        pp = [s for s in sites if _inside(s,(0.88,0.43+slot*0.12,0.05,0.10),width,height)]
        whole = [_fraction(s['text'],True) for s in pp]
        complete = [v for v in whole if v is not None]
        numerators = [s for s in pp if re.fullmatch(r'[0-9]{1,2}',_compact(s['text']))]
        denominators = [s for s in pp if re.fullmatch(r'/[0-9]{1,2}',_compact(s['text']))]
        choices = complete if len(complete) == len(pp) and len({s['reading'] for s in pp}) == 1 else []
        if (len(pp) <= 12 and not complete and len(numerators)+len(denominators) == len(pp) and
                len({s['reading'] for s in numerators}) == len({s['reading'] for s in denominators}) == 1):
            for a in numerators:
                for b in denominators:
                    value = _fraction(_compact(a['text'])+_compact(b['text']),True)
                    if (a['reading'] != b['reading'] and a['roi']['y'] < b['roi']['y'] and
                            abs(a['roi']['x']-b['roi']['x']) <= width*0.04 and value is not None):
                        choices.append(value)
        associations.append(association('move_pp',slot,pp,choices,'LITERAL_OR_EXPLICIT_SLASH_PARTS_ONLY'))
    report.update(status='PROVISIONAL_PROFILE_MATCH_ONLY',anchors=anchors,associations=associations,
                  conflict_count=sum(s['knowledge_state'] == 'CONFLICT' for s in associations))
    return report
