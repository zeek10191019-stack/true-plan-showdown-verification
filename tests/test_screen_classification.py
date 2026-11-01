"""Screen-source tampering and literal label boundaries, not game OCR accuracy."""
import copy,unittest
import test_evidence_verifier as base
from test_layout_reading import unpack,edited
from r557_fixture import screen_fixture,screen_conflict_fixture,MOVE,OVERLAY
from screen_read_classification import classify,classification_report
from screen_read_layout import layout_report

def report_after(edit):
    selected,packet=unpack(screen_fixture());edit(packet)
    return classification_report(packet,1000,462,'capture-test',17,3,packet['image_sha256'],1200)

def change_row(packet,index,**changes):packet['readings'][index].update(changes)

class ScreenClassificationTests(unittest.TestCase):
    setUp=base.EvidenceVerifierTests.setUp
    tearDown=base.EvidenceVerifierTests.tearDown
    verify=base.EvidenceVerifierTests.verify
    reject=base.EvidenceVerifierTests.reject

    def test_literal_plain_screen_archive(self):self.verify(screen_fixture(False))
    def test_literal_overlay_archive_retains_twelve_associations(self):
        f=screen_fixture();s,p=unpack(f)
        self.assertEqual(len(s['screen_read_state']['layout_candidates']['associations']),12)
        self.verify(f)
    def test_literal_overlay_report_reconstructed(self):
        s,p=unpack(screen_fixture())
        self.assertEqual(report_after(lambda p:None),s['screen_read_state']['screen_classification'])
    def test_conflicting_screen_archive_is_valid_with_unknown(self):self.verify(screen_conflict_fixture())
    def test_alternative_only_screen_archive_stays_unknown(self):self.verify(screen_conflict_fixture(True))
    def test_screen_conflict_cannot_be_hidden_at_root(self):
        self.reject(edited(screen_conflict_fixture(),lambda s,p:s.update(knowledge_state='UNKNOWN')))
    def test_alternative_ref_cannot_be_omitted_from_screen_evidence(self):
        self.reject(edited(screen_conflict_fixture(),lambda s,p:s['screen_classification']['evaluated_evidence_refs'].pop(4)))
    def test_new_screen_policy_cannot_claim_a_legacy_engine(self):
        self.reject(edited(screen_fixture(),lambda s,p:s.update(screen_read_engine_version='r553.snapshot.v1')))
    def test_command_substrings_are_not_labels(self):
        for text in ['COMMANDER','XCOMMAND','記録COMMAND','COMMANDING','COMMAND-1','COMMAND1.0','COMMAND1000']:
            self.assertEqual(classify([text,'技の説明']),'unknown',text)
    def test_exact_and_fullwidth_command_timer_labels(self):
        for text in ['COMMAND','COMMAND 32','COMMAND:32','ＣＯＭＭＡＮＤ　３２']:
            self.assertEqual(classify([text,'技の説明']),MOVE)
    def test_button_prose_is_not_a_button(self):
        for text in ['技の説明はありません','技の説明について','先ほどの技の説明']:
            self.assertEqual(classify(['COMMAND',text]),'unknown')
    def test_detail_prose_does_not_open_overlay(self):
        self.assertEqual(classify(['COMMAND','技の説明','威力は80','技分類について']),MOVE)
    def test_conflicting_screen_families_stay_unknown(self):
        self.assertEqual(classify(['COMMAND','技の説明','YOU WIN']),'unknown')
    def test_all_screen_families_have_literal_cases(self):
        for tokens,kind in [(['COMMAND','たたかう'],'normal_command_candidate'),(['選出','決定'],'party_selection_candidate'),
            (['相手のパーティ','選出時間'],'party_preview_candidate'),(['交代先を選んでください','もどる'],'switch_selection_candidate'),
            (['YOU WIN'],'battle_end_candidate'),(['メガシンカ'],'animation_or_battle_message_candidate'),(['あめ'],'unknown')]:
            self.assertEqual(classify(tokens),kind)
    def test_foreign_frame_screen_label_is_omitted(self):
        r=report_after(lambda p:change_row(p,2,source_frame_id=18))
        self.assertEqual(r['screen_kind'],'unknown');self.assertEqual(r['omitted_reading_refs'],['payload_json.readings[2]'])
    def test_foreign_epoch_screen_label_is_omitted(self):
        self.assertEqual(report_after(lambda p:change_row(p,2,source_epoch=4))['screen_kind'],'unknown')
    def test_boolean_source_frame_cannot_be_a_bound_label(self):
        self.assertEqual(report_after(lambda p:change_row(p,2,source_frame_id=True))['omitted_reading_refs'],['payload_json.readings[2]'])
    def test_foreign_image_screen_label_is_omitted(self):
        self.assertEqual(report_after(lambda p:change_row(p,2,source_image_sha256='0'*64))['screen_kind'],'unknown')
    def test_unlocated_detail_text_cannot_enable_overlay(self):
        def change(p):
            for row in p['readings'][-2:]:row.pop('roi_rect')
            p['screen_kind']=MOVE
        r=report_after(change)
        self.assertEqual(r['screen_kind'],MOVE);self.assertEqual(len(r['omitted_reading_refs']),2)
    def test_zero_or_outside_roi_is_not_a_screen_anchor(self):
        for rect in [dict(x=1001,y=100,width=4,height=4),dict(x=790,y=100,width=0,height=10)]:
            self.assertEqual(report_after(lambda p:change_row(p,2,roi_rect=rect))['screen_kind'],'unknown')
    def test_alternative_end_label_vetoes_primary_overlay(self):
        def change(p):
            change_row(p,3,ocr_alternatives=[dict(rank=0,raw_text='技の説明',confidence=0.9),dict(rank=1,raw_text='勝利',confidence=0.8)])
            p['screen_kind']='unknown'
        r=report_after(change)
        self.assertEqual(r['status'],'HOLD_OCR_SCREEN_CONFLICT');self.assertEqual(r['screen_kind'],'unknown')
        self.assertIn('payload_json.readings[3].ocr_alternatives[1]',r['evaluated_evidence_refs'])
    def test_alternative_cannot_promote_unknown_primary(self):
        def change(p):
            change_row(p,3,raw_text='不明',ocr_alternatives=[dict(rank=0,raw_text='不明',confidence=0.9),dict(rank=1,raw_text='技の説明',confidence=0.8)])
            p['screen_kind']='unknown'
        r=report_after(change)
        self.assertEqual(r['primary_kind'],'unknown');self.assertEqual(r['all_variants_kind'],OVERLAY)
        self.assertEqual(r['screen_kind'],'unknown');self.assertEqual(r['status'],'HOLD_UNKNOWN_PRIMARY')
    def test_packet_claim_cannot_override_raw_screen_text(self):
        r=report_after(lambda p:p.update(screen_kind='battle_end_candidate'))
        self.assertEqual(r['screen_kind'],'unknown');self.assertEqual(r['status'],'HOLD_PACKET_KIND_DISAGREEMENT')
    def test_boolean_packet_kind_is_malformed(self):
        r=report_after(lambda p:p.update(screen_kind=True))
        self.assertEqual(r['screen_kind'],'unknown');self.assertEqual(r['status'],'HOLD_MALFORMED_PACKET_KIND')
    def test_missing_screen_evidence_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s.pop('screen_classification')))
    def test_deleted_screen_ref_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification']['evaluated_evidence_refs'].pop()))
    def test_duplicate_screen_ref_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification']['evaluated_evidence_refs'].append('payload_json.readings[0]')))
    def test_forged_screen_classification_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(screen_kind='battle_end_candidate')))
    def test_forged_primary_kind_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(primary_kind='unknown')))
    def test_forged_source_frame_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(frame_id=18)))
    def test_forged_source_image_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(image_sha256='0'*64)))
    def test_owner_promotion_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(owner_certified=True)))
    def test_game_accuracy_promotion_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(game_accuracy_certified=True)))
    def test_current_promotion_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(current_state_eligible=True)))
    def test_actions_promotion_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(battle_advice_authorized=True)))
    def test_missing_omission_is_rejected(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['screen_classification'].update(omitted_reading_refs=['payload_json.readings[2]'])))
    def test_fake_overlay_packet_without_labels_is_rejected(self):
        self.reject(edited(screen_fixture(False),lambda s,p:p.update(screen_kind=OVERLAY)))
    def test_overlay_requires_two_left_panel_labels(self):
        s,p=unpack(screen_fixture());p['readings'].pop()
        r=layout_report(p,1000,462,OVERLAY,'capture-test',17,3,p['image_sha256'],1200,allow_details_overlay=True)
        self.assertEqual(r['status'],'HOLD_UNSUPPORTED_OVERLAY');self.assertEqual(r['associations'],[])
    def test_right_panel_labels_withhold_layout(self):
        s,p=unpack(screen_fixture())
        for row in p['readings'][-2:]:row['roi_rect']['x']=750
        r=layout_report(p,1000,462,OVERLAY,'capture-test',17,3,p['image_sha256'],1200,allow_details_overlay=True)
        self.assertEqual(r['status'],'HOLD_UNSUPPORTED_OVERLAY');self.assertEqual(r['associations'],[])
    def test_duplicate_panel_label_is_ambiguous(self):
        s,p=unpack(screen_fixture());p['readings'].append(copy.deepcopy(p['readings'][-1]))
        r=layout_report(p,1000,462,OVERLAY,'capture-test',17,3,p['image_sha256'],1200,allow_details_overlay=True)
        self.assertEqual(r['status'],'HOLD_AMBIGUOUS_OVERLAY');self.assertEqual(r['associations'],[])
    def test_panel_alternative_conflict_withholds_layout(self):
        s,p=unpack(screen_fixture());p['readings'][14]['ocr_alternatives']=[dict(rank=0,raw_text='技分類',confidence=0.9),dict(rank=1,raw_text='別の文字',confidence=0.8)]
        r=layout_report(p,1000,462,OVERLAY,'capture-test',17,3,p['image_sha256'],1200,allow_details_overlay=True)
        self.assertEqual(r['status'],'HOLD_AMBIGUOUS_OVERLAY')
    def test_overlay_cannot_delete_panel_anchor_references(self):
        self.reject(edited(screen_fixture(),lambda s,p:s['layout_candidates']['anchors'].pop()))

if __name__=='__main__':unittest.main()
