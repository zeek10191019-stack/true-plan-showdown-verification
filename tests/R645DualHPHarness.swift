enum R642MappedFrameProof {static let schema="trueplan.r642.raw-frame-roi-evidence.v1"}
enum R641RotatedHUDCandidates {static let schema="trueplan.r641.four-way-independent-layout.v1"}
enum R644MoveSlotCoupler {static let schema="trueplan.r644.four-move-pp-pairs.v1"}
import Foundation
@main struct R645Harness {
 static func main() {
  var n=0
  func ok(_ yes:Bool,_ name:String) {
   precondition(yes,name);n+=1;print("R645_PASS",name)
  }
  let a=String(repeating:"a",count:64)
  let b=String(repeating:"b",count:64)
  let sid="synthetic-frame-only",f=11,e=3
  let raw=["148/197","81%"]
  let roles=["own_hp","opponent_percent"]
  let refs=["hp-observation","percent-observation"]
  let rects:[[String:Any]]=[
   ["x":100,"y":550,"width":60,"height":20],
   ["x":1100,"y":60,"width":45,"height":18]
  ]
  func source(_ i:Int)->[String:Any] {
   ["evidence_ref":refs[i],"raw_text":raw[i],
    "image_sha256":a,"capture_session_id":sid,
    "frame_id":f,"epoch":e,"owner_verified":false]
  }
  func mapped(_ i:Int)->[String:Any] {
   ["reference":refs[i],"raw_text":raw[i],
    "role_hint":roles[i],"slot":NSNull(),
    "raw_frame_rect":rects[i],
    "analysis_image_sha256":a,"source_image_sha256":b,
    "owner_verified":false,"current_value_admitted":false]
  }
  func value(_ i:Int)->[String:Any] {
   ["role_hint":roles[i],"source_ref":refs[i],
    "raw_text":raw[i],"source_sha256":a,
    "side":"UNKNOWN_OWNER","slot":NSNull(),
    "owner_verified":false,"orientation_verified":false,
    "current_value_admitted":false,
    "status":"PROVISIONAL_LAYOUT_VALUE_ONLY",
    "value": i==0 ? ["current":148,"maximum":197] as Any : 81.0 as Any]
  }
  let base:[String:Any]=[
   "schema":R642MappedFrameProof.schema,
   "source_kind":"LIVE_RETAINED_FRAME",
   "owner_verified":false,"source_orientation_verified":false,
   "current_state_eligible":false,"battle_advice_authorized":false,
   "game_fields_certified":0,"raw_image_sha256":b,
   "analysis_image_sha256":a,"capture_session_id":sid,
   "frame_id":f,"epoch":e,"mapped_values":[mapped(0),mapped(1)]]
  let hud:[String:Any]=[
   "schema":R641RotatedHUDCandidates.schema,
   "source_kind":"LIVE_RETAINED_FRAME",
   "source_image_sha256":a,"owner_verified":false,
   "source_orientation_verified":false,
   "game_fields_certified":0,"matching_profile_count":1,
   "rotation_candidate_degrees":90,
   "candidate_values":[value(0),value(1)]]
  let four:[String:Any]=[
   "schema":R644MoveSlotCoupler.schema,
   "source_kind":"LIVE_RETAINED_FRAME",
   "raw_image_sha256":b,"analysis_image_sha256":a,
   "capture_session_id":sid,"frame_id":f,"epoch":e,
   "owner_verified":false,"current_state_eligible":false,
   "battle_advice_authorized":false,"game_fields_certified":0,
   "matched_pair_count":4]
  let snap:[String:Any]=[
   "image_sha256":a,"capture_session_id":sid,
   "frame_id":f,"epoch":e,"current_state_eligible":false,
   "battle_advice_authorized":false,
   "ocr_source_inventory":[source(0),source(1)]]
  let initial:[String:Any]=[
   "r642_status":"PROVISIONAL_RAW_FRAME_ROIS_ONLY",
   "r642_raw_frame_roi_evidence":base,
   "r641_status":"UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
   "r641_rotated_hud_candidates":hud,
   "r644_four_move_slots":four,
   "screen_read_state":snap]
  func run(_ input:[String:Any],kind:String="LIVE_RETAINED_FRAME") ->[String:Any] {
   var copy=input;R645DualHPEvidence.enrich(&copy,sourceKind:kind)
   return copy
  }
  func status(_ d:[String:Any])->String {
   run(d)["r645_status"] as? String ?? "NIL"
  }
  let accepted=run(initial)
  ok(status(initial)=="DUAL_HP_SOURCE_BOUND_HISTORICAL_ONLY","two_hp_source_bound")
  let report=accepted["r645_dual_hp"] as! [String:Any]
  ok(report["four_move_pairs_on_same_frame"] as? Int==4,"same_frame_move_pairs")
  ok(report["rotation_candidate_degrees"] as? Int==90,"angle_preserved_not_certified")
  ok(report["game_fields_certified"] as? Int==0,"no_game_certification")
  ok(report["owner_verified"] as? Bool==false,"no_owner_proof")
  ok(report["battle_advice_authorized"] as? Bool==false,"no_advice")
  ok(report["current_state_eligible"] as? Bool==false,"not_live_state")
  ok(JSONSerialization.isValidJSONObject(accepted),"json_valid")
  var tmp=initial
  tmp["r642_status"]="HOLD"
  ok(status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF","upstream_hold")
  tmp=initial
  var b2=base;b2["frame_id"]=12;tmp["r642_raw_frame_roi_evidence"]=b2
  ok(status(tmp)=="HOLD_INVENTORY_CONTRADICTION" || status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF" || status(tmp)=="HOLD_ROI_OR_SOURCE_CONTRADICTION", "frame_proof_requires_consistency")
  tmp=initial
  var s=snap;var src=source(0);src["raw_text"]="500/197"
  s["ocr_source_inventory"]=[src,source(1)]
  tmp["screen_read_state"]=s
  ok(status(tmp)=="HOLD_ROI_OR_SOURCE_CONTRADICTION","raw_text_tamper")
  tmp=initial
  s=snap;s["ocr_source_inventory"]=[source(0),source(0)]
  tmp["screen_read_state"]=s
  ok(status(tmp)=="HOLD_INVENTORY_CONTRADICTION","duplicate_inventory")
  tmp=initial
  var h=hud;var rows=[value(0),value(1)];var v=rows[0]
  v["value"]=["current":200,"maximum":197];rows[0]=v
  h["candidate_values"]=rows;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_HP_VALUE_CONTRADICTION","hp_over_max")
  tmp=initial
  rows=[value(0),value(1)];v=rows[0]
  v["value"]=["current":147,"maximum":197];rows[0]=v
  h=hud;h["candidate_values"]=rows;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_HP_VALUE_CONTRADICTION","hp_value_tamper")
  tmp=initial
  rows=[value(0),value(1)];v=rows[1];v["value"]=80.0;rows[1]=v
  h=hud;h["candidate_values"]=rows;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_PERCENT_VALUE_CONTRADICTION","percent_value_tamper")
  tmp=initial
  rows=[value(0),value(1)];v=rows[1];v["owner_verified"]=true;rows[1]=v
  h=hud;h["candidate_values"]=rows;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_HP_SOURCE_CONTRADICTION","fake_owner_on_candidate")
  tmp=initial
  rows=[value(0),value(1)];v=rows[1];v["source_ref"]=refs[0];rows[1]=v
  h=hud;h["candidate_values"]=rows;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_HP_SOURCE_CONTRADICTION","reused_hp_reference")
  tmp=initial
  h=hud;h["candidate_values"]=[value(0)]
  tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_INCOMPLETE_DUAL_HP_ANCHORS","missing_percent")
  tmp=initial
  h=hud;h["candidate_values"]=[value(0),value(0),value(1)]
  tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_HP_SOURCE_CONTRADICTION","duplicate_hp_anchor")
  tmp=initial
  var m=base;var mr=[mapped(0),mapped(1)];var item=mr[0]
  item["raw_frame_rect"]=["x":0,"y":0,"width":0,"height":10]
  mr[0]=item;m["mapped_values"]=mr;tmp["r642_raw_frame_roi_evidence"]=m
  ok(status(tmp)=="HOLD_ROI_OR_SOURCE_CONTRADICTION","zero_area_rejected")
  tmp=initial
  m=base;mr=[mapped(0),mapped(1)];item=mr[0];item["source_image_sha256"]=a
  mr[0]=item;m["mapped_values"]=mr;tmp["r642_raw_frame_roi_evidence"]=m
  ok(status(tmp)=="HOLD_ROI_OR_SOURCE_CONTRADICTION","mapped_raw_hash_tamper")
  tmp=initial
  var f4=four;f4["capture_session_id"]="other"
  tmp["r644_four_move_slots"]=f4
  ok(status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF","move_pair_other_session")
  tmp=initial
  f4=four;f4["game_fields_certified"]=1;tmp["r644_four_move_slots"]=f4
  ok(status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF","fake_certification_rejected")
  tmp=initial
  s=snap;src=source(1);src["frame_id"]=12
  s["ocr_source_inventory"]=[source(0),src]
  tmp["screen_read_state"]=s
  ok(status(tmp)=="HOLD_INVENTORY_CONTRADICTION","inventory_cross_frame")
  tmp=initial
  h=hud;h["rotation_candidate_degrees"]=45;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF","invalid_rotation")
  tmp=initial
  h=hud;h["owner_verified"]=true;tmp["r641_rotated_hud_candidates"]=h
  ok(status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF","fake_parent_owner")
  tmp=initial
  s=snap;s["owner_certified"]=true;tmp["screen_read_state"]=s
  ok(status(tmp)=="HOLD_MISSING_SHARED_FRAME_PROOF","fake_snapshot_owner")
  var offline=initial
  m=base;m["source_kind"]="USER_IMPORTED_PNG_OFFLINE_ONLY"
  h=hud;h["source_kind"]="USER_IMPORTED_PNG_OFFLINE_ONLY"
  f4=four;f4["source_kind"]="USER_IMPORTED_PNG_OFFLINE_ONLY"
  offline["r642_raw_frame_roi_evidence"]=m
  offline["r641_rotated_hud_candidates"]=h
  offline["r644_four_move_slots"]=f4
  ok(status(offline)=="HOLD_MISSING_SHARED_FRAME_PROOF","no_offline_source_spoof")
  ok(run(offline,kind:"USER_IMPORTED_PNG_OFFLINE_ONLY")["r645_status"] as? String ==
   "DUAL_HP_SOURCE_BOUND_HISTORICAL_ONLY","offline_source_same_frame")
  tmp=initial
  f4=four;f4["matched_pair_count"]=0;tmp["r644_four_move_slots"]=f4
  let low=run(tmp)
  ok(low["r645_status"] as? String == "DUAL_HP_SOURCE_BOUND_HISTORICAL_ONLY", "hp_independent_of_moves")
  ok((low["r645_dual_hp"] as! [String:Any])["four_move_pairs_on_same_frame"] as? Int==0,
   "zero_move_count_recorded")
  print("R645_LOCAL_ALL_PASS",n)
 }
}
