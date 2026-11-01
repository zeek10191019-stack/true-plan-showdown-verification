"""Adversarial evidence edits, not an OCR accuracy or device test."""
import copy
import json
import unittest
import test_evidence_verifier as evidence_base
fixture, encoded, sha = evidence_base.fixture, evidence_base.encoded, evidence_base.sha

def state_fixture(rows):
    files = fixture()
    selected = json.loads(files['selected_evidence.json'])
    wrapper = json.loads(selected['research_candidate_envelope'])
    packet = json.loads(wrapper['payload_json'])
    packet['readings'] = []
    state = selected['screen_read_state']
    state.update(screen_read_engine_version='r552.snapshot.v1',knowledge_state='UNKNOWN',conflicts=[],source_validation='PASS_FRAME_BINDING_ONLY',
                 receipt_uptime_ms=1200,capture_timestamp_ms=None,stale_deadline_ms=None,
                 orientation='ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED',timestamp_basis='UNCALIBRATED_HOST_RECEIPT_UPTIME')
    state['candidates'] = []
    for index, (raw, domain, value) in enumerate(rows):
        roi = {'x':0,'y':0,'width':2,'height':2}
        packet['readings'].append({'raw_text':raw,'confidence':0.8,'reason':'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND',
            'source_frame_id':17,'source_epoch':3,'source_image_sha256':packet['image_sha256'],'roi_rect':roi})
        from screen_read_semantics import normalized
        state['candidates'].append({'domain':domain,'raw_text':raw,'normalized_text':normalized(raw),'value':value,
            'evidence_ref':f'payload_json.readings[{index}]','capture_session_id':'capture-test',
            'image_sha256':packet['image_sha256'],'frame_id':17,'epoch':3,'roi':roi,
            'roi_coordinate_space':'ANALYSIS_PIXELS_TOP_LEFT','confidence':0.8,'source':'VISION_OCR_TEXT_CANDIDATE',
            'knowledge_state':'INFERRED','side':'UNKNOWN_OWNER','verification_status':'UNVERIFIED',
            'current_state_eligible':False,'validity':'HISTORICAL_FRAME_ONLY',
            'receipt_uptime_ms':1200,'battle_id':None,'turn':None,'capture_timestamp_ms':None,
            'stale_deadline_ms':None,'orientation':'ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED'})
    wrapper['payload_json'] = encoded(packet).decode()
    wrapper['payload_sha256'] = sha(wrapper['payload_json'].encode())
    selected['research_candidate_envelope'] = encoded(wrapper).decode()
    files['selected_evidence.json'] = encoded(selected)
    return files

def timed(label='トリックルーム', count=3):
    return {'label':label,'remaining_turns':count,
            'duration_semantics':'EXPLICIT_REMAINING_CANDIDATE' if count is not None else 'UNKNOWN'}

def mutate_state(files, edit):
    files = copy.deepcopy(files)
    selected = json.loads(files['selected_evidence.json'])
    edit(selected['screen_read_state'])
    files['selected_evidence.json'] = encoded(selected)
    return files

def conflicting_fixture():
    files = state_fixture([('81%','hp_percent',81),('82%','hp_percent',82)])
    def set_conflict(state):
        state['knowledge_state'] = 'CONFLICT'
        candidate = state['candidates'][0]
        state['conflicts'] = [{**{k:candidate[k] for k in ('domain','capture_session_id','frame_id','epoch','image_sha256','roi')},
            'semantic_key':'value','knowledge_state':'CONFLICT','scope':'OCR_INTERPRETATION_ONLY',
            'reason':'DIFFERENT_VALUES_SAME_BOUND_FRAME_AND_ROI','side':'UNKNOWN_OWNER','current_state_eligible':False,
            'candidate_indices':[0,1],'evidence_refs':['payload_json.readings[0]','payload_json.readings[1]']}]
    return mutate_state(files,set_conflict)

# Reuse archive IO assertions without inheriting and rerunning the original 38 tests.
class StateSemanticTests(unittest.TestCase):
    setUp = evidence_base.EvidenceVerifierTests.setUp
    tearDown = evidence_base.EvidenceVerifierTests.tearDown
    verify = evidence_base.EvidenceVerifierTests.verify
    reject = evidence_base.EvidenceVerifierTests.reject

    def test_explicit_remaining_and_unicode_stage(self):
        self.verify(state_fixture([('トリックルーム：残り３ターン','room',timed()),
            ('こうげき −６','absolute_boost',{'stat':'atk','stage':-6,'semantics':'ABSOLUTE_DISPLAY_CANDIDATE'})]))
    def test_duration_without_remaining_marker_stays_unknown(self):
        self.verify(state_fixture([('トリックルーム3ターン','room',timed(count=None))]))
    def test_invented_remaining_from_duration_is_rejected(self):
        self.reject(state_fixture([('トリックルーム3ターン','room',timed())]))
    def test_changed_explicit_remaining_is_rejected(self):
        self.reject(state_fixture([('トリックルームあと3ターン','room',timed(count=4))]))
    def test_boolean_remaining_is_rejected(self):
        self.reject(state_fixture([('トリックルームあと1ターン','room',timed(count=True))]))
    def test_remaining_bounds_are_literal_not_default_mechanics(self):
        self.verify(state_fixture([('おいかぜあと0ターン','screen_or_side_effect',timed('おいかぜ',0))]))
        self.verify(state_fixture([('トリックルーム残り99ターン','room',timed(count=99))]))
        self.reject(state_fixture([('トリックルームあと100ターン','room',timed(count=100))]))
    def test_poison_does_not_imply_toxic(self):
        value = {'kind':'poison','poison_severity':'UNKNOWN','scope':'TEXT_LABEL_ONLY'}
        self.verify(state_fixture([('どく','major_status',value)]))
        value['poison_severity'] = 'BAD_POISON_TEXT_CANDIDATE'
        self.reject(state_fixture([('どく','major_status',value)]))
    def test_explicit_toxic_is_still_a_text_candidate(self):
        self.verify(state_fixture([('もうどく','major_status',
            {'kind':'poison','poison_severity':'BAD_POISON_TEXT_CANDIDATE','scope':'TEXT_LABEL_ONLY'})]))
    def test_stage_seven_is_rejected(self):
        self.reject(state_fixture([('こうげき +7','absolute_boost',{'stat':'atk','stage':7,'semantics':'ABSOLUTE_DISPLAY_CANDIDATE'})]))
    def test_boolean_stage_is_rejected(self):
        self.reject(state_fixture([('こうげき +1','absolute_boost',{'stat':'atk','stage':True,'semantics':'ABSOLUTE_DISPLAY_CANDIDATE'})]))
    def test_stage_event_is_not_absolute(self):
        self.reject(state_fixture([('こうげきが 1段階 あがった','absolute_boost',{'stat':'atk','stage':1,'semantics':'ABSOLUTE_DISPLAY_CANDIDATE'})]))
    def test_visible_item_must_match_literal_label(self):
        self.reject(state_fixture([('持ち物:オボンのみ','visible_item_label',{'label':'きあいのタスキ','visibility':'TEXT_LABEL_ONLY'})]))
    def test_empty_visible_ability_is_rejected(self):
        self.reject(state_fixture([('特性:','visible_ability_label',{'label':'ふゆう','visibility':'TEXT_LABEL_ONLY'})]))
    def test_percent_over_100_is_rejected(self):
        self.reject(state_fixture([('101%','hp_percent',101)]))
    def test_boolean_percent_is_rejected(self):
        self.reject(state_fixture([('1%','hp_percent',True)]))
    def test_fraction_over_maximum_is_rejected(self):
        self.reject(state_fixture([('HP 3/2','hp',{'current':3,'maximum':2})]))
    def test_fraction_zero_maximum_is_rejected(self):
        self.reject(state_fixture([('PP 0/0','pp',{'current':0,'maximum':0})]))
    def test_candidate_frame_boolean_is_rejected(self):
        files = state_fixture([('81%','hp_percent',81)])
        self.reject(mutate_state(files,lambda s:s['candidates'][0].update(epoch=True)))
    def test_unbound_roi_is_rejected(self):
        files = state_fixture([('81%','hp_percent',81)])
        self.reject(mutate_state(files,lambda s:s['candidates'][0]['roi'].update(width=1)))
    def test_fractional_roi_is_rejected(self):
        files = state_fixture([('81%','hp_percent',81)])
        self.reject(mutate_state(files,lambda s:s['candidates'][0]['roi'].update(width=1.5)))
    def test_missing_conflict_is_rejected(self):
        files = conflicting_fixture()
        self.reject(mutate_state(files,lambda s:s.update(conflicts=[],knowledge_state='UNKNOWN')))
    def test_same_bound_roi_conflict_is_accepted(self):
        self.verify(conflicting_fixture())
    def test_conflict_wrong_reference_is_rejected(self):
        self.reject(mutate_state(conflicting_fixture(),lambda s:s['conflicts'][0]['evidence_refs'].__setitem__(1,'payload_json.readings[99]')))
    def test_false_conflict_of_equal_percent_is_rejected(self):
        files = conflicting_fixture()
        selected = json.loads(files['selected_evidence.json'])
        wrapper = json.loads(selected['research_candidate_envelope'])
        packet = json.loads(wrapper['payload_json'])
        packet['readings'][1]['raw_text'] = '81%'
        wrapper.update(payload_json=encoded(packet).decode(),payload_sha256=sha(encoded(packet)))
        selected['research_candidate_envelope'] = encoded(wrapper).decode()
        selected['screen_read_state']['candidates'][1].update(raw_text='81%',normalized_text='81%',value=81)
        files['selected_evidence.json'] = encoded(selected)
        self.reject(files)
    def test_conflict_cannot_be_promoted_to_current_state(self):
        self.reject(mutate_state(conflicting_fixture(),lambda s:s['conflicts'][0].update(current_state_eligible=True)))
    def test_forged_normalization_is_rejected(self):
        self.reject(mutate_state(state_fixture([('81%','hp_percent',81)]),lambda s:s['candidates'][0].update(normalized_text='100%')))
    def test_stale_receipt_is_rejected(self):
        self.reject(mutate_state(state_fixture([('81%','hp_percent',81)]),lambda s:s['candidates'][0].update(receipt_uptime_ms=900)))
    def test_missing_required_candidate_property_is_rejected(self):
        self.reject(mutate_state(state_fixture([('81%','hp_percent',81)]),lambda s:s['candidates'][0].pop('battle_id')))
    def test_missing_required_snapshot_property_is_rejected(self):
        self.reject(mutate_state(state_fixture([('81%','hp_percent',81)]),lambda s:s.pop('turn')))

if __name__ == '__main__':
    unittest.main()
