"""Reconstruct source-bound literal readouts from packet/layout, independently of Swift.

Passing this check proves traceability and literal consistency, not a game owner,
individual, Mega form, present frame, or recognition accuracy. No network is used.
"""
import math
import re
from screen_read_layout import variants, bound_roi
from screen_read_semantics import normalized, canonical

SCHEMA = 'trueplan.screen-read.source-bound-hints.v2'
PASS = 'PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION'
ROLES = {'own_hp','opponent_hp','own_name','opponent_name','move_name','move_pp'}

def _compact(text, normalize=False):
    if normalize: text = normalized(text)
    return text.replace(' ','').replace('\u3000','').replace('\n','').replace('\r','').strip()

def _ratio(text, pp=False):
    if text.startswith('HP' if pp else 'PP'): return None
    if text.startswith(('HP','PP')): text = text[2:]
    match = re.fullmatch(r'([0-9]{1,2})/([0-9]{1,2})' if pp else r'([0-9]{1,4})/([0-9]{1,4})',text)
    if not match: return None
    current, maximum = map(int,match.groups())
    if not 0 <= current <= maximum or maximum <= 0 or (pp and maximum > 64): return None
    return dict(current=current,maximum=maximum)

def _accepts(role, text):
    text = _compact(text)
    if role == 'own_hp': return _ratio(text) is not None
    if role == 'opponent_hp':
        return _ratio(text) is not None or bool(re.fullmatch(r'[0-9]{1,3}(\.[0-9]{1,2})?%',text) and 0 <= float(text[:-1]) <= 100)
    if role in ('own_name','opponent_name','move_name'):
        return bool(2 <= len(text) <= 24 and re.fullmatch(r'[ぁ-ゖァ-ヺー一-龯A-Za-z0-9・♀♂]+',text) and re.search(r'[ぁ-ゖァ-ヺ一-龯]',text))
    return False

def pp_literal(sites, legacy=False):
    if not 1 <= len(sites) <= (32 if legacy else 6): return None
    groups = {}
    for site in sites:
        roi = site['roi']
        if not all(type(roi.get(k)) is int and roi[k] >= (1 if k in ('width','height') else 0) for k in ('x','y','width','height')): return None
        if not 0 <= site['reading'] < 512 or not 0 <= site['rank'] < 32 or len(site['text'].encode()) > 256: return None
        groups.setdefault(site['reading'],[]).append(site)
    if not legacy:
        if len(groups) > 2: return None
        for group in groups.values():
            if len(group) > 3 or {s['rank'] for s in group} != set(range(len(group))) or any(s['roi'] != group[0]['roi'] for s in group): return None
    texts = [_compact(s['text'],normalize=not legacy) for s in sites]
    full = [_ratio(t,pp=True) for t in texts]
    if all(value is not None for value in full):
        return full[0] if len(groups) == 1 and all(v == full[0] for v in full) else None
    if any(value is not None for value in full) or len(groups) != 2 or (legacy and len(sites) != 2): return None
    numerators = [(s,t) for s,t in zip(sites,texts) if re.fullmatch(r'[0-9]{1,2}',t)]
    denominators = [(s,t) for s,t in zip(sites,texts) if re.fullmatch(r'/[0-9]{1,2}',t)]
    if not numerators or not denominators or len(numerators)+len(denominators) != len(sites): return None
    if len({s['reading'] for s,_ in numerators}) != 1 or len({s['reading'] for s,_ in denominators}) != 1: return None
    n, nt = numerators[0]; d, dt = denominators[0]
    if n['reading'] == d['reading'] or len({int(t) for _,t in numerators}) != 1 or len({int(t[1:]) for _,t in denominators}) != 1: return None
    current, maximum = int(nt), int(dt[1:])
    if not 0 <= current <= maximum or not 1 <= maximum <= 64: return None
    nr, dr = n['roi'], d['roi']
    if any(v > 4096 for roi in (nr,dr) for v in roi.values()): return None
    if not nr['y'] < dr['y'] or (not legacy and nr['y']+nr['height'] > dr['y']): return None
    if abs(nr['x']-dr['x']) > 2*max(nr['width'],dr['width']) or dr['y']-nr['y'] > 4*max(nr['height'],dr['height']): return None
    return dict(current=current,maximum=maximum)

def role_literal(role, sites):
    if not sites or len(sites) > 32 or role not in ROLES or role == 'move_pp': return None
    values = []
    for site in sites:
        raw = site['text']
        if len(raw.encode()) > 256 or not _accepts(role,raw): return None
        text = _compact(raw,normalize=True)
        if role in ('own_name','opponent_name','move_name'): value = text
        elif text.endswith('%'):
            parts=text[:-1].split('.')
            basis=int(parts[0])*100+(int(parts[1].ljust(2,'0')) if len(parts)==2 else 0)
            value=basis/100
            if value.is_integer(): value=int(value)
        else: value = _ratio(text)
        if value is None: return None
        values.append(value)
    return values[0] if all(canonical(v) == canonical(values[0]) for v in values) else None

def source_bound_report(packet, layout, width, height, session, frame, epoch, image, legacy=False):
    result = dict(schema=SCHEMA if not legacy else 'trueplan.screen-read.source-bound-hints.v1',
        status='HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED',scope='SINGLE_HISTORICAL_FRAME_HINTS_ONLY',
        capture_session_id=session,frame_id=frame,epoch=epoch,image_sha256=image,hints=[],
        owner_certified=False,current_state_eligible=False,battle_advice_authorized=False,game_accuracy_certified=False,
        battle_id=None,turn=None,source_evidence_checked=False,role_text_checked=False,
        evidence_group_checked=False,semantic_consensus_checked=False,iPhone_accuracy_certified=False)
    if not legacy: result.update(literal_values_checked=False,identity_certified=False)
    def hold(reason):
        result['status']=reason
        return result
    if not (0 < len(session.encode()) <= 128 and 400 <= width <= 4096 and 180 <= height <= 4096 and layout['status']=='PROVISIONAL_PROFILE_MATCH_ONLY'): return result
    anchor_roles=[r['role_hint'] for r in layout['anchors']]
    if not {'own_hp','opponent_hp','command'} <= set(anchor_roles) or len(set(anchor_roles)) != len(anchor_roles): return hold('HOLD_MISSING_OR_DUPLICATE_ANCHORS')
    rows=layout['associations']
    if len(rows)>32: return result
    hints=[]
    for row in rows:
        if row['knowledge_state']=='CONFLICT': return hold('HOLD_AMBIGUOUS_OCR_VALUES')
        if row['knowledge_state']=='INFERRED' and row['evidence_refs']:
            hints.append(dict(role_hint=row['role_hint'],suggested_side='opponent' if row['role_hint'].startswith('opponent_') else 'own',
                slot=row['slot'],evidence_refs=row['evidence_refs'],rois=row['rois'],knowledge_state='INFERRED',
                verification='POSITION_ONLY_UNVERIFIED',current_state_eligible=False))
    if not hints: return hold('HOLD_R565_NO_POSITION_HINTS')
    sites=[]
    for index,row in enumerate(packet['readings']):
        if row.get('reason') != 'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND': continue
        rect=bound_roi(row,width,height,frame,epoch,image)
        if rect is not None: sites.extend(dict(**v,reading=index,roi=rect) for v in variants(row,index))
    if len(sites)>2048: return hold('HOLD_R565_TOO_MANY_SITES')
    references={s['reference']:s for s in sites}
    consumed=set();observations={};valued=[]
    for index,hint in enumerate(hints):
        role=hint['role_hint'];group=[]
        for ref,roi in zip(hint['evidence_refs'],hint['rois']):
            site=references.get(ref)
            if site is None or site['roi'] != roi: return hold('HOLD_R565_SOURCE_EVIDENCE_ROI_MISMATCH')
            if ref in consumed: return hold('HOLD_R565_ROLE_REFERENCE_COLLISION')
            if site['reading'] in observations and observations[site['reading']] != index: return hold('HOLD_R568_OBSERVATION_REUSED_ACROSS_HINTS')
            observations[site['reading']]=index;consumed.add(ref);group.append(site)
        if role=='move_pp':
            value=pp_literal(group,legacy=legacy)
            if value is None: return hold('HOLD_R567_ROLE_EVIDENCE_GROUP_INVALID')
        else:
            if any(not _accepts(role,s['text']) for s in group): return hold('HOLD_R566_ROLE_TEXT_MISMATCH')
            value=role_literal(role,group)
            if value is None: return hold('HOLD_R569_AMBIGUOUS_ROLE_VALUE')
        if not legacy:
            hint.update(literal_value=value,raw_texts=[s['text'] for s in group],
                source_confidences=[s['confidence'] for s in group],value_basis='OCR_LITERAL_CONSENSUS_ONLY',
                side='UNKNOWN_OWNER',owner_certified=False,identity_certified=False,validity='HISTORICAL_FRAME_ONLY')
        valued.append(hint)
    result.update(status=PASS,hints=valued,source_evidence_checked=True,role_text_checked=True,
        evidence_group_checked=True,semantic_consensus_checked=True,source_evidence_count=len(consumed))
    if not legacy: result['literal_values_checked']=True
    return result

def verify_source_bound_report(actual, packet, layout, width, height, session, frame, epoch, image, require_current=False):
    if not isinstance(actual,dict): raise ValueError('SOURCE_BOUND_HINTS_REQUIRED')
    legacy=actual.get('schema')=='trueplan.screen-read.source-bound-hints.v1'
    if require_current and legacy: raise ValueError('SOURCE_BOUND_HINTS_R571_POLICY_REQUIRED')
    expected=source_bound_report(packet,layout,width,height,session,frame,epoch,image,legacy=legacy)
    # JSON canonicalization keeps bool distinct from numeric zero and detects extra fields.
    if canonical(actual) != canonical(expected): raise ValueError('SOURCE_BOUND_HINTS_SOURCE_VALUE_OR_CLAIM_MISMATCH')
    return dict(status='PASS_LITERAL_AND_SOURCE_ONLY',hint_count=len(expected['hints']),
        owner_certified=False,identity_certified=False,current_state_eligible=False)

def verify_native_report(record, destination, app_version='0.5.71', app_build='571'):
    """Validate the fixed native scenarios and three actual, retrieved Swift ZIPs."""
    import base64
    import hashlib
    import zipfile
    from pathlib import Path
    from verify_screen_evidence import verify_archive,parse_json
    from schema_contract import validate_document
    def need(condition,reason):
        if not condition: raise ValueError('R571_NATIVE_'+reason)
    need(isinstance(record,dict) and record.get('revision')=='R'+app_build and
        record.get('scope')=='SYNTHETIC_SOURCE_VALUE_UI_AND_SWIFT_ZIP_ONLY','SCOPE')
    need(type(record.get('checks')) is int and record['checks']==62,'CHECKS')
    for key in ('game_accuracy_certified','owner_certified','identity_certified','device_certified'):need(record.get(key) is False,'PROMOTION')
    identities=['whole','zero','split','split_alts','numerator_conflict','denominator_conflict','missing_primary',
        'duplicate_rank','changed_roi','overlap','distant','reversed','full_two_sources','same_observation','over_max','hp_prefix']
    expected=[dict(current=14,maximum=16),dict(current=0,maximum=16),dict(current=14,maximum=16),dict(current=14,maximum=16)]+[None]*12
    need(canonical(record.get('pp_cases'))==canonical([dict(id=i,value=v) for i,v in zip(identities,expected)]),'PP_CASES')
    snapshots=record.get('snapshots')
    need(isinstance(snapshots,list) and [s.get('id') for s in snapshots]==['baseline','split_alternatives','ambiguous_pp'],'SCENARIOS')
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False)
    receipts=[]
    for item in snapshots:
        encoded=item.get('archive_base64');need(isinstance(encoded,str) and len(encoded)<2_000_000,'ARCHIVE_SIZE')
        raw=base64.b64decode(encoded,validate=True)
        need(hashlib.sha256(raw).hexdigest()==item.get('archive_sha256'),'ARCHIVE_SHA')
        path=destination/('r571_'+item['id']+'.zip');path.write_bytes(raw)
        receipt=verify_archive(path,expected_sha256=item['archive_sha256'])
        with zipfile.ZipFile(path) as archive:
            selected=parse_json(archive.read('selected_evidence.json'));index=parse_json(archive.read('evidence_integrity.json'))
        need(index.get('app_version')==app_version and index.get('app_build')==app_build,'ARCHIVE_VERSION')
        state=selected['screen_read_state']
        packet=parse_json(parse_json(selected['research_candidate_envelope'])['payload_json'])
        need(canonical(state)==canonical(item.get('state')) and canonical(packet)==canonical(item.get('packet')),'REPORT_ARCHIVE_BINDING')
        validate_document(state);validate_document(state['owner_position_hints'])
        receipts.append(dict(id=item['id'],archive=receipt,hint_count=len(state['owner_position_hints']['hints'])))
    need([r['hint_count'] for r in receipts]==[12,12,0],'FIELD_COUNTS')
    return dict(status='PASS_FIXED_CONTRACTS_AND_THREE_SWIFT_ARCHIVES_ONLY',native_checks=62,archives=receipts,
        owner_certified=False,identity_certified=False,current_state_eligible=False,game_accuracy_certified=False,device_certified=False)
