"""Independent source/value checks and adversarial edits of complete evidence ZIPs."""
import copy
import json
import unittest
from pathlib import Path
import test_evidence_verifier as base
from r553_fixture import source_update
from r557_fixture import screen_fixture
from screen_read_layout import layout_report
from verify_source_bound_hints import source_bound_report,pp_literal,role_literal,PASS
from schema_contract import validate_document

def source_fixture():
    files=screen_fixture()
    selected=json.loads(files['selected_evidence.json'])
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
    state=selected['screen_read_state'];state['screen_read_engine_version']='r571.snapshot.v1'
    state['owner_position_hints']=source_bound_report(packet,state['layout_candidates'],1000,462,'capture-test',17,3,packet['image_sha256'])
    return source_update(files,selected,packet)

def edited(files, change):
    files=copy.deepcopy(files);selected=json.loads(files['selected_evidence.json'])
    change(selected['screen_read_state']['owner_position_hints'])
    files['selected_evidence.json']=base.encoded(selected)
    return files

def site(reading,text,rank=0,x=300,y=10,w=20,h=10):
    return dict(reading=reading,rank=rank,text=text,roi=dict(x=x,y=y,width=w,height=h),confidence=.9,
        reference=f'payload_json.readings[{reading}]'+(f'.ocr_alternatives[{rank}]' if rank else ''))

class SourceBoundArchiveTests(unittest.TestCase):
    setUp=base.EvidenceVerifierTests.setUp
    tearDown=base.EvidenceVerifierTests.tearDown
    verify=base.EvidenceVerifierTests.verify
    reject=base.EvidenceVerifierTests.reject

    def test_complete_menu_has_twelve_literal_values_without_owner_claim(self):
        files=source_fixture();self.verify(files)
        state=json.loads(files['selected_evidence.json'])['screen_read_state'];report=state['owner_position_hints']
        validate_document(report);validate_document(state)
        self.assertEqual(report['status'],PASS);self.assertEqual(len(report['hints']),12)
        self.assertEqual(report['hints'][0]['literal_value'],dict(current=100,maximum=200))
        self.assertEqual(report['hints'][1]['literal_value'],81)
        self.assertEqual(report['hints'][2]['literal_value'],'ピカチュウ')
        self.assertEqual(report['hints'][5]['literal_value'],dict(current=4,maximum=10))
        for hint in report['hints']:
            self.assertIs(hint['owner_certified'],False);self.assertIs(hint['identity_certified'],False)
            self.assertEqual(hint['side'],'UNKNOWN_OWNER');self.assertEqual(hint['validity'],'HISTORICAL_FRAME_ONLY')
        self.assertIsNone(state['own']['hp']['value']);self.assertIsNone(state['opponent']['hp']['value'])
    def test_forged_hp_value_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0]['literal_value'].update(current=101)))
    def test_forged_name_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][2].update(literal_value='ライチュウ')))
    def test_boolean_fraction_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0]['literal_value'].update(current=True)))
    def test_forged_pp_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][5]['literal_value'].update(maximum=64)))
    def test_owner_promotion_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(owner_certified=True)))
    def test_identity_promotion_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][2].update(identity_certified=True)))
    def test_current_promotion_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0].update(current_state_eligible=True)))
    def test_bool_zero_equivalence_does_not_bypass_independent_check(self):
        self.reject(edited(source_fixture(),lambda r:r.update(owner_certified=0)))
    def test_forged_roi_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0]['rois'][0].update(x=1)))
    def test_foreign_frame_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(frame_id=18)))
    def test_foreign_epoch_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(epoch=4)))
    def test_foreign_image_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(image_sha256='0'*64)))
    def test_raw_text_tampering_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0]['raw_texts'].__setitem__(0,'200/200')))
    def test_confidence_tampering_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0]['source_confidences'].__setitem__(0,.99)))
    def test_role_swap_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][0].update(role_hint='opponent_hp')))
    def test_slot_swap_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'][5].update(slot=1)))
    def test_omitted_hint_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'].pop()))
    def test_duplicate_hint_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r['hints'].append(copy.deepcopy(r['hints'][0]))))
    def test_false_hold_cannot_hide_verified_literal_readouts(self):
        self.reject(edited(source_fixture(),lambda r:r.update(status='HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED',hints=[])))
    def test_false_check_claim_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(literal_values_checked=False)))
    def test_invented_event_field_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(mega_activation_certified=True)))
    def test_missing_r571_report_is_rejected(self):
        files=source_fixture();selected=json.loads(files['selected_evidence.json'])
        selected['screen_read_state'].pop('owner_position_hints');files['selected_evidence.json']=base.encoded(selected)
        self.reject(files)
    def test_policy_downgrade_is_rejected(self):
        self.reject(edited(source_fixture(),lambda r:r.update(schema='trueplan.screen-read.source-bound-hints.v1')))
    def test_standalone_schema_rejects_unknown_fields(self):
        r=json.loads(source_fixture()['selected_evidence.json'])['screen_read_state']['owner_position_hints']
        r['unproven']=True
        with self.assertRaises(Exception):validate_document(r)
    def test_legacy_snapshot_report_still_checks_source(self):
        files=screen_fixture();selected=json.loads(files['selected_evidence.json'])
        packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
        selected['screen_read_state']['owner_position_hints']=source_bound_report(packet,selected['screen_read_state']['layout_candidates'],1000,462,'capture-test',17,3,packet['image_sha256'],legacy=True)
        files=source_update(files,selected,packet);self.verify(files)
        self.reject(edited(files,lambda r:r.update(owner_certified=True)))

class SplitPPTests(unittest.TestCase):
    def test_complete_pp_value(self):self.assertEqual(pp_literal([site(0,'PP14/16')]),dict(current=14,maximum=16))
    def test_zero_is_known_not_missing(self):self.assertEqual(pp_literal([site(0,'0/16')]),dict(current=0,maximum=16))
    def test_split_alternatives_are_not_independent_votes(self):
        group=[site(0,'14'),site(0,'１４',1),site(1,'/16',y=25),site(1,'／１６',1,y=25)]
        self.assertEqual(pp_literal(group),dict(current=14,maximum=16));self.assertIsNone(pp_literal(group,legacy=True))
    def test_split_alternative_disagreement_holds(self):
        self.assertIsNone(pp_literal([site(0,'14'),site(0,'13',1),site(1,'/16',y=25)]))
    def test_denominator_disagreement_holds(self):
        self.assertIsNone(pp_literal([site(0,'14'),site(1,'/16',y=25),site(1,'/18',1,y=25)]))
    def test_missing_primary_is_rejected(self):self.assertIsNone(pp_literal([site(0,'14',1),site(1,'/16',y=25)]))
    def test_duplicate_rank_is_rejected(self):self.assertIsNone(pp_literal([site(0,'14'),site(0,'14'),site(1,'/16',y=25)]))
    def test_changed_alternative_roi_is_rejected(self):self.assertIsNone(pp_literal([site(0,'14'),site(0,'14',1,x=301),site(1,'/16',y=25)]))
    def test_overlapping_fragments_are_rejected(self):self.assertIsNone(pp_literal([site(0,'14'),site(1,'/16',y=15)]))
    def test_distant_fragments_are_rejected(self):self.assertIsNone(pp_literal([site(0,'14'),site(1,'/16',y=200)]))
    def test_reversed_fragments_are_rejected(self):self.assertIsNone(pp_literal([site(0,'14',y=25),site(1,'/16')]))
    def test_full_pp_from_different_observations_is_rejected(self):self.assertIsNone(pp_literal([site(0,'14/16'),site(1,'14/16')]))
    def test_same_observation_cannot_supply_both_parts(self):self.assertIsNone(pp_literal([site(0,'14'),site(0,'/16',1,y=25)]))
    def test_invalid_ratio_is_rejected(self):self.assertIsNone(pp_literal([site(0,'17/16')]))
    def test_hp_prefix_cannot_claim_pp(self):self.assertIsNone(pp_literal([site(0,'HP14/16')]))
    def test_boolean_coordinates_are_rejected(self):self.assertIsNone(pp_literal([site(0,'14/16',x=True)]))
    def test_non_pp_literal_consensus(self):self.assertEqual(role_literal('own_hp',[site(0,'HP170/185'),site(0,'170/185',1)]),dict(current=170,maximum=185))
    def test_percent_consensus_is_decimal_exact(self):self.assertEqual(role_literal('opponent_hp',[site(0,'0.05%'),site(0,'0.05%',1)]),.05)
    def test_distinct_name_alternatives_hold(self):self.assertIsNone(role_literal('own_name',[site(0,'ガブリアス'),site(0,'ギャラドス',1)]))
    def test_pp_schema_does_not_imply_species_or_move_validity(self):
        self.assertEqual(pp_literal([site(0,'0/64')]),dict(current=0,maximum=64))
        self.assertIsNone(pp_literal([site(0,'0/0')]))

if __name__=='__main__':unittest.main()
