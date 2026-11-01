"""Ownership/slot failure modes and tampered wire evidence, with synthetic pixels."""
import copy,json,unittest
import test_evidence_verifier as base
from r553_fixture import menu_fixture,alternative_fixture,source_update,layout_base
from screen_read_layout import layout_report

def unpack(files):
    selected=json.loads(files['selected_evidence.json'])
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
    return selected,packet

def edited(files, edit):
    files=copy.deepcopy(files);selected,packet=unpack(files)
    edit(selected['screen_read_state'],packet)
    return source_update(files,selected,packet)

def report_after(edit):
    selected,packet=unpack(menu_fixture());edit(packet)
    return layout_report(packet,1000,462,'move_selection_candidate','capture-test',17,3,packet['image_sha256'],1200)

class LayoutReadingTests(unittest.TestCase):
    setUp=base.EvidenceVerifierTests.setUp
    tearDown=base.EvidenceVerifierTests.tearDown
    verify=base.EvidenceVerifierTests.verify
    reject=base.EvidenceVerifierTests.reject

    def test_hand_authored_menu_matches_independent_verifier(self):self.verify(menu_fixture())
    def test_alternatives_are_not_independent_consensus(self):self.verify(alternative_fixture())
    def test_layout_cannot_certify_owner(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates'].update(owner_certified=True)))
    def test_layout_cannot_certify_calibration(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates'].update(calibration_certified=True)))
    def test_layout_cannot_promote_current_state(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates']['associations'][0].update(current_state_eligible=True)))
    def test_layout_cannot_swap_move_slots(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates']['associations'][4].update(slot=1)))
    def test_layout_pp_cannot_invent_value(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates']['associations'][5].update(value=dict(current=99,maximum=99))))
    def test_layout_reference_must_match_frame(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates']['associations'][0].update(epoch=4)))
    def test_layout_reference_cannot_be_changed(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates']['associations'][4]['evidence_refs'].__setitem__(0,'payload_json.readings[999]')))
    def test_name_misspelling_is_not_automatically_replaced(self):
        self.reject(edited(menu_fixture(),lambda s,p:s['layout_candidates']['associations'][2].update(value='ライチュウ')))
    def test_missing_anchor_withholds_layout(self):
        r=report_after(lambda p:p['readings'].__delitem__(2))
        self.assertEqual(r['status'],'HOLD_MISSING_ANCHORS');self.assertEqual(r['associations'],[])
    def test_foreign_anchor_source_withholds_layout(self):
        r=report_after(lambda p:p['readings'][0].update(source_epoch=4))
        self.assertEqual(r['status'],'HOLD_MISSING_ANCHORS')
    def test_ambiguous_anchor_withholds_layout(self):
        def change(p):p['readings'][0]['ocr_alternatives']=[dict(rank=0,raw_text='100/200',confidence=0.9),dict(rank=1,raw_text='101/200',confidence=0.8)]
        self.assertEqual(report_after(change)['status'],'HOLD_AMBIGUOUS_ANCHORS')
    def test_duplicate_anchor_withholds_layout(self):
        self.assertEqual(report_after(lambda p:p['readings'].append(copy.deepcopy(p['readings'][0])))['status'],'HOLD_AMBIGUOUS_ANCHORS')
    def test_split_pp_needs_visible_slash_and_vertical_order(self):
        def change(p):
            row=p['readings'][7];row['raw_text']='4'
            lower=copy.deepcopy(row);lower['raw_text']='/10';lower['roi_rect']['y']+=15;p['readings'].append(lower)
        r=report_after(change);pp=r['associations'][5]
        self.assertEqual(pp['value'],dict(current=4,maximum=10));self.assertEqual(len(pp['evidence_refs']),2)
    def test_pp_without_slash_stays_unknown(self):
        def change(p):
            row=p['readings'][7];row['raw_text']='4'
            lower=copy.deepcopy(row);lower['raw_text']='10';lower['roi_rect']['y']+=15;p['readings'].append(lower)
        self.assertEqual(report_after(change)['associations'][5]['knowledge_state'],'UNKNOWN')
    def test_reversed_pp_parts_stay_unknown(self):
        def change(p):
            row=p['readings'][7];row['raw_text']='4'
            lower=copy.deepcopy(row);lower['raw_text']='/10';lower['roi_rect']['y']-=10;p['readings'].append(lower)
        self.assertEqual(report_after(change)['associations'][5]['knowledge_state'],'UNKNOWN')
    def test_cross_slot_pp_is_not_joined(self):
        def change(p):
            row=p['readings'][7];row['raw_text']='4'
            lower=copy.deepcopy(row);lower['raw_text']='/10';lower['roi_rect']['y']+=55;p['readings'].append(lower)
        self.assertEqual(report_after(change)['associations'][5]['knowledge_state'],'UNKNOWN')
    def test_name_alternative_conflict_is_retained(self):
        def change(p):p['readings'][4]['ocr_alternatives']=[dict(rank=0,raw_text='ピカチュウ',confidence=0.9),dict(rank=1,raw_text='ライチュウ',confidence=0.8)]
        r=report_after(change);self.assertEqual(r['associations'][2]['knowledge_state'],'CONFLICT');self.assertEqual(r['conflict_count'],1)
    def test_unknown_name_alternative_does_not_get_discarded(self):
        def change(p):p['readings'][4]['ocr_alternatives']=[dict(rank=0,raw_text='ピカチュウ',confidence=0.9),dict(rank=1,raw_text='?',confidence=0.8)]
        self.assertEqual(report_after(change)['associations'][2]['knowledge_state'],'UNKNOWN')
    def test_hidden_alternative_candidate_is_rejected(self):
        def edit(s,p):s['candidates'].pop();s.update(conflicts=[],knowledge_state='UNKNOWN')
        self.reject(edited(alternative_fixture(),edit))
    def test_alternative_confidence_must_match_its_rank(self):
        self.reject(edited(alternative_fixture(),lambda s,p:s['candidates'][1].update(confidence=0.8)))
    def test_alternative_ref_rank_cannot_be_swapped(self):
        self.reject(edited(alternative_fixture(),lambda s,p:s['candidates'][1].update(ocr_rank=0)))
    def test_more_than_three_alternatives_are_rejected(self):
        def change(s,p):p['readings'][0]['ocr_alternatives'] += [dict(rank=2,raw_text='83%',confidence=0.6),dict(rank=3,raw_text='84%',confidence=0.5)]
        self.reject(edited(alternative_fixture(),change))
    def test_primary_alternative_cannot_disagree_with_row(self):
        self.reject(edited(alternative_fixture(),lambda s,p:p['readings'][0]['ocr_alternatives'][0].update(raw_text='100%')))
    def test_boolean_rank_is_rejected(self):
        self.reject(edited(alternative_fixture(),lambda s,p:p['readings'][0]['ocr_alternatives'][1].update(rank=True)))
    def test_unsorted_confidence_is_rejected(self):
        self.reject(edited(alternative_fixture(),lambda s,p:p['readings'][0]['ocr_alternatives'][1].update(confidence=0.9)))
    def test_missing_layout_report_is_rejected(self):
        self.reject(edited(menu_fixture(),lambda s,p:s.pop('layout_candidates')))
    def test_unsupported_detail_overlay_has_no_owner_associations(self):
        files=menu_fixture();s,p=unpack(files)
        s['screen_read_state']['screen_kind']=p['screen_kind']='move_selection_with_move_details_overlay_candidate'
        s['screen_read_state']['layout_candidates']=layout_base(p['image_sha256'])
        self.verify(source_update(files,s,p))
    def test_portrait_and_letterbox_geometry_withheld(self):
        s,p=unpack(menu_fixture())
        for width,height in [(462,1000),(1200,462),(2,2)]:
            self.assertEqual(layout_report(p,width,height,'move_selection_candidate','capture-test',17,3,p['image_sha256'],1200)['status'],'HOLD_UNSUPPORTED_GEOMETRY')

if __name__=='__main__':unittest.main()
