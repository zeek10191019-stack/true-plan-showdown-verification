import Foundation
@main struct R638Harness {
 static func main() {
  var tests=0
  func check(_ b:Bool,_ name:String){precondition(b,name);tests+=1;print("PASS_R638",name)}
  let hash=String(repeating:"a",count:64)
  let sid="test-frame"
  let rect:[String:Int]=["x":12,"y":10,"width":60,"height":14]
  let norm:[String:Int]=["x":120,"y":100,"width":600,"height":140]
  let ref="r[0]#rank0", txt="10/10"
  let item:[String:Any]=["evidence_ref":ref,"raw_text":txt,
     "roi":rect,"image_sha256":hash,"capture_session_id":sid,
     "frame_id":Int64(1),"epoch":Int64(2),"owner_verified":false]
  let association:[String:Any]=["role_hint":"move_pp","slot":0,
     "evidence_refs":[ref],"raw_texts":[txt],"rois":[rect]]
  let box:[String:Any]=["role_hint":"move_pp","slot":0,
     "source_refs":[ref],"rects_top_left_10000":[norm],
     "image_sha256":hash,"owner_verified":false,
     "orientation_verified":false,"status":"PROVISIONAL_IMAGE_GEOMETRY_ONLY"]
  let report:[String:Any]=["schema":R637GeometryDiagnostics.schema,
    "source_kind":"LIVE_RETAINED_FRAME","owner_verified":false,
    "source_orientation_verified":false,"game_fields_certified":0,
    "cross_role_ref_collisions":0,"image_sha256":hash,
    "geometry_candidates":[box]]
  let snapshot:[String:Any]=["image_sha256":hash,
    "capture_session_id":sid,"frame_id":Int64(1),"epoch":Int64(2),
    "current_state_eligible":false,"battle_advice_authorized":false,
    "ocr_source_inventory":[item],
    "layout_candidates":["image_sha256":hash,"associations":[association]]]
  let original:[String:Any]=["r637_status":"PROVISIONAL_ROI_AUDIT",
    "r637_geometry_audit":report,"screen_read_state":snapshot,
    "image_width":1000,"image_height":1000]
  func run(_ d:[String:Any])->[String:Any]{var copy=d
    R638SourceBindingAudit.enrich(&copy,sourceKind:"LIVE_RETAINED_FRAME")
    return copy}
  let valid=run(original)
  check(valid["r638_status"] as? String == "SOURCE_AND_LAYOUT_BOUND_HISTORICAL_ONLY","same_source_rect_text")
  let audit=valid["r638_binding_audit"] as! [String:Any]
  check(audit["source_matched_observations"] as? Int == 1,"one_evidence_binding")
  check(audit["game_fields_certified"] as? Int == 0 &&
    audit["owner_verified"] as? Bool == false,"no_certification")
  check(JSONSerialization.isValidJSONObject(valid),"json_roundtrip")
  var noInv=original;var s=snapshot;s.removeValue(forKey:"ocr_source_inventory");noInv["screen_read_state"]=s
  check(run(noInv)["r638_status"] as? String == "HOLD_SOURCE_INVENTORY_OR_GEOMETRY_MISSING","inventory_required")
  var changed=original;s=snapshot;var src=item;src["raw_text"]="99/99";s["ocr_source_inventory"]=[src];changed["screen_read_state"]=s
  check(run(changed)["r638_status"] as? String == "HOLD_SOURCE_REFERENCE_OR_TEXT_MISMATCH","text_tamper_rejected")
  var move=original;s=snapshot;src=item;src["roi"]=["x":22,"y":10,"width":60,"height":14];s["ocr_source_inventory"]=[src];move["screen_read_state"]=s
  check(run(move)["r638_status"] as? String == "HOLD_SOURCE_REFERENCE_OR_TEXT_MISMATCH","rect_tamper_rejected")
  var duplicate=original;s=snapshot;s["ocr_source_inventory"]=[item,item];duplicate["screen_read_state"]=s
  check(run(duplicate)["r638_status"] as? String == "HOLD_INVALID_OR_DUPLICATE_OCR_SOURCE","duplicate_ref_rejected")
  var missing=original;s=snapshot;src=item;src["evidence_ref"]="other";s["ocr_source_inventory"]=[src];missing["screen_read_state"]=s
  check(run(missing)["r638_status"] as? String == "HOLD_SOURCE_REFERENCE_OR_TEXT_MISMATCH","missing_ref_rejected")
  var wrong=original;s=snapshot;src=item;src["image_sha256"]=String(repeating:"b",count:64);s["ocr_source_inventory"]=[src];wrong["screen_read_state"]=s
  check(run(wrong)["r638_status"] as? String == "HOLD_INVALID_OR_DUPLICATE_OCR_SOURCE","cross_frame_rejected")
  var fake=original;var rep=report;rep["owner_verified"]=true;fake["r637_geometry_audit"]=rep
  check(run(fake)["r638_status"] as? String == "HOLD_SOURCE_INVENTORY_OR_GEOMETRY_MISSING","fake_owner_rejected")
  var offline=original;rep=report;rep["source_kind"]="USER_IMPORTED_PNG_OFFLINE_ONLY";offline["r637_geometry_audit"]=rep
  var offlineCopy=offline;R638SourceBindingAudit.enrich(&offlineCopy,sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY")
  check(offlineCopy["r638_status"] as? String == "SOURCE_AND_LAYOUT_BOUND_HISTORICAL_ONLY","offline_historical_only")
  var misplaced=original;var layout=snapshot["layout_candidates"] as! [String:Any];var assoc=association;assoc["raw_texts"]=["other"];layout["associations"]=[assoc];s=snapshot;s["layout_candidates"]=layout;misplaced["screen_read_state"]=s
  check(run(misplaced)["r638_status"] as? String == "HOLD_SOURCE_REFERENCE_OR_TEXT_MISMATCH","layout_tamper_rejected")
  var replay=original;rep=report
  var another=box;another["slot"]=1
  rep["geometry_candidates"]=[box,another]
  replay["r637_geometry_audit"]=rep
  s=snapshot
  layout=s["layout_candidates"] as! [String:Any]
  var replayAssoc=association;replayAssoc["slot"]=1
  layout["associations"]=[association,replayAssoc]
  s["layout_candidates"]=layout
  replay["screen_read_state"]=s
  check(run(replay)["r638_status"] as? String ==
    "HOLD_DUPLICATE_REF_ACROSS_SLOTS","same_ocr_cannot_fill_two_slots")
  print("R638_HARNESS_ALL_PASS",tests)
 }
}
