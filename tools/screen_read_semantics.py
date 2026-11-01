"""Independent literal checks for historical OCR candidates, never game truth.

This implementation does not call the Swift parser. It verifies that a structured
value can be read literally from the referenced text and compares bound ROIs only.
"""
import json
import re
import unicodedata

LABELS = {
    'weather': ('あめ','雨','すなあらし','ひざしがつよい','はれ','晴れ','ゆき','雪'),
    'terrain': ('グラスフィールド','エレキフィールド','サイコフィールド','ミストフィールド'),
    'room': ('トリックルーム','マジックルーム','ワンダールーム'),
    'screen_or_side_effect': ('リフレクター','ひかりのかべ','オーロラベール','おいかぜ','しんぴのまもり','しろいきり'),
    'entry_hazard': ('ステルスロック','まきびし','どくびし','ねばねばネット'),
    'major_status': ('やけど','まひ','ねむり','こおり','どく','もうどく'),
    'visible_volatile': ('こんらん','みがわり','ちょうはつ','アンコール','かなしばり','あくび','ほろびのうた'),
    'mega_text': ('メガシンカ','メガ進化','メガギャラドス','メガグソクムシャ','メガバンギラス'),
}
TIMED = {'weather','terrain','room','screen_or_side_effect','visible_volatile'}
STATS = {'こうげき':'atk','ぼうぎょ':'def','とくこう':'spa','とくぼう':'spd',
         'すばやさ':'spe','命中':'accuracy','回避':'evasion'}
STATUSES = {'やけど':'burn','まひ':'paralysis','ねむり':'sleep','こおり':'freeze','どく':'poison','もうどく':'poison'}
DOMAINS = ('hp','pp','hp_or_pp','hp_percent',*LABELS,'absolute_boost','visible_ability_label','visible_item_label')

def normalized(raw):
    return unicodedata.normalize('NFKC', raw).replace('−','-').strip()

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',',':'), allow_nan=False)

def expected_domains(raw):
    domains = []
    for domain in DOMAINS:
        try:expected_value(raw,domain)
        except ValueError:continue
        domains.append(domain)
    return domains

def expected_value(raw, domain, structured=True):
    text = normalized(raw)
    compact = text.replace(' ','')
    if domain in ('hp','pp','hp_or_pp'):
        pair = re.fullmatch(r'(HP|PP)?\s*([0-9]{1,4})\s*/\s*([0-9]{1,4})', text)
        if pair:
            current, maximum = int(pair[2]), int(pair[3])
            actual = {'HP':'hp','PP':'pp',None:'hp_or_pp'}[pair[1]]
            if actual == domain and maximum > 0 and current <= maximum:
                return {'current':current,'maximum':maximum}
    elif domain == 'hp_percent':
        if re.fullmatch(r'[0-9]{1,3}(\.[0-9]{1,2})?%', compact):
            value = float(compact[:-1])
            if 0 <= value <= 100:
                return value
    elif domain == 'absolute_boost':
        match = re.fullmatch(r'('+'|'.join(STATS)+r')(?:\s+|:\s*)([+-]?[0-6])', text)
        if match:
            return {'stat':STATS[match[1]],'stage':int(match[2]),'semantics':'ABSOLUTE_DISPLAY_CANDIDATE'} if structured else text
    elif domain in ('visible_ability_label','visible_item_label'):
        prefixes = ('特性:','とくせい:') if domain == 'visible_ability_label' else ('持ち物:','もちもの:')
        for prefix in prefixes:
            if text.startswith(prefix):
                value = text[len(prefix):].strip()
                if 0 < len(value) <= 128:
                    return {'label':value,'visibility':'TEXT_LABEL_ONLY'} if structured else text
    elif domain in LABELS:
        label, count, explicit = compact, None, False
        if compact not in LABELS[domain]:
            match = re.fullmatch('('+'|'.join(map(re.escape, LABELS[domain]))+r'):?(あと|残り)?([0-9]{1,2})ターン', compact)
            if not match or (structured and domain not in TIMED):
                raise ValueError('SNAPSHOT_LITERAL_DOMAIN')
            label, explicit = match[1], match[2] is not None
            count = int(match[3]) if explicit else None
        if not structured:
            return text
        if domain in TIMED:
            return {'label':label,'remaining_turns':count,
                    'duration_semantics':'EXPLICIT_REMAINING_CANDIDATE' if explicit else 'UNKNOWN'}
        if domain == 'major_status':
            return {'kind':STATUSES[label], 'poison_severity':
                    ('BAD_POISON_TEXT_CANDIDATE' if label == 'もうどく' else 'UNKNOWN') if STATUSES[label] == 'poison' else None,
                    'scope':'TEXT_LABEL_ONLY'}
        return text
    raise ValueError('SNAPSHOT_LITERAL_DOMAIN')

def _components(candidate):
    domain, value = candidate['domain'], candidate['value']
    if domain == 'hp_percent':
        return [('value',float(value))]
    if domain in ('hp','pp','hp_or_pp'):
        return [('value',value)]
    if not isinstance(value,dict):
        return []
    if domain == 'absolute_boost':
        return [('stage:'+value['stat'],value['stage'])]
    if domain == 'major_status':
        return [('kind',value['kind'])]
    if domain in ('visible_ability_label','visible_item_label'):
        return [('label',value['label'])]
    if domain in TIMED:
        parts = [('label',value['label'])] if domain in ('weather','terrain') else []
        if type(value['remaining_turns']) is int:
            parts.append(('remaining_turns:'+value['label'], value['remaining_turns']))
        return parts
    return []

def expected_conflicts(candidates):
    groups = {}
    for index, candidate in enumerate(candidates):
        roi = candidate.get('roi')
        if not isinstance(roi,dict):
            continue
        for semantic, value in _components(candidate):
            key = (candidate['capture_session_id'],candidate['frame_id'],candidate['epoch'],candidate['image_sha256'],
                   *(roi[k] for k in ('x','y','width','height')),candidate['domain'],semantic)
            if key not in groups:
                groups[key] = {'indices':[],'values':set(),'record':{
                    **{k:candidate[k] for k in ('domain','capture_session_id','frame_id','epoch','image_sha256','roi')},
                    'semantic_key':semantic, 'knowledge_state':'CONFLICT', 'scope':'OCR_INTERPRETATION_ONLY',
                    'reason':'DIFFERENT_VALUES_SAME_BOUND_FRAME_AND_ROI','side':'UNKNOWN_OWNER','current_state_eligible':False}}
            group = groups[key]
            group['indices'].append(index)
            group['values'].add(canonical(value))
    conflicts = []
    for group in groups.values():
        if len(group['values']) > 1:
            conflicts.append({**group['record'],'candidate_indices':group['indices'],
                'evidence_refs':[candidates[i]['evidence_ref'] for i in group['indices']]})
    return sorted(conflicts, key=lambda x:(x['candidate_indices'][0],x['semantic_key']))
