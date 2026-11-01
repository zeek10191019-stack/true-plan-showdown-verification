import Foundation

@main struct Run {
 static func main() {
  let sha=String(repeating:"a",count:64)
  let one:[String:Any]=["x":100,"y":195,"width":50,"height":12]
  let two:[String:Any]=["x":460,"y":15,"width":50,"height":12]
  func association(_ role:String,_ references:[String],_ rect:[String:Any], _ frame:Int64=5)->[String:Any] {
   ["role_hint":role,"slot":NSNull(),"frame_id":frame,"epoch":2,
    "capture_session_id":"session","image_sha256":sha,"side":"UNKNOWN_OWNER",
    "current_state_eligible":false,"verification_status":"UNVERIFIED",
    "roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT","battle_id":NSNull(),"turn":NSNull(),
    "evidence_refs":references,"rois":references.map {_ in rect},"knowledge_state":"INFERRED"]
  }
  func layout(_ rows:[[String:Any]]) -> [String:Any] {
   ["schema":"trueplan.screen-read.layout-candidates.v1",
    "status":"PROVISIONAL_PROFILE_MATCH_ONLY","capture_session_id":"session", "frame_id":5,"epoch":2,
    "image_sha256":sha,"roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
    "owner_certified":false,"calibration_certified":false,"current_state_eligible":false,
    "anchors":[["role_hint":"own_hp"],["role_hint":"opponent_hp"],["role_hint":"command"]],
    "associations":rows]
  }
  func run(_ record:[String:Any]) -> [String:Any] {
   R564OwnerHintFence.report(layout:record,session:"session",frame:5,epoch:2,imageSHA:sha,width:578,height:267)
  }
  let rows=[association("own_hp",["payload_json.readings[1]"],one),
            association("opponent_hp",["payload_json.readings[2]"],two)]
  let success=run(layout(rows));let allowed="PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION"
  assert(success["status"] as? String == allowed)
  assert(success["owner_certified"] as? Bool == false)
  assert(success["current_state_eligible"] as? Bool == false)
  assert((success["hints"] as? [[String:Any]])?.count==2)
  assert((success["hints"] as? [[String:Any]])?.allSatisfy{$0["current_state_eligible"] as? Bool == false} == true)
  func check(_ name:String,_ change:(inout [String:Any])->Void,_ expected:String) {
   var inp=layout(rows);change(&inp);let actual=run(inp)["status"] as? String
   guard actual==expected else {fatalError("FAIL_\(name): \(actual ?? "nil") != \(expected)")}
   print("PASS_R564_"+name)
  }
  check("VALID_FRAME",{_ in},allowed)
  check("FOREIGN_FRAME",{inp in inp["frame_id"]=99},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("FOREIGN_SESSION",{inp in inp["capture_session_id"]="foreign"},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("FOREIGN_EPOCH",{inp in inp["epoch"]=3},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("HASH_MISMATCH",{inp in inp["image_sha256"]=String(repeating:"b",count:64)},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("CERTIFIED_FORGERY",{inp in inp["owner_certified"]=true},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("CALIBRATION_FORGERY",{inp in inp["calibration_certified"]=true},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("BAD_LAYOUT",{inp in inp["status"]="UNKNOWN"},"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  check("MISSING_ANCHOR",{inp in inp["anchors"]=[["role_hint":"own_hp"]]},"HOLD_MISSING_OR_DUPLICATE_ANCHORS")
  check("DUPLICATE_ANCHOR",{inp in inp["anchors"]=[["role_hint":"own_hp"],["role_hint":"own_hp"],["role_hint":"command"]]},"HOLD_MISSING_OR_DUPLICATE_ANCHORS")
  check("MISMATCHED_ROW_FRAME",{inp in var x=rows;x[1]["frame_id"]=6;inp["associations"]=x},"HOLD_ASSOCIATION_PROVENANCE_INVALID")
  check("SIDE_FORGERY",{inp in var x=rows;x[0]["side"]="own";inp["associations"]=x},"HOLD_ASSOCIATION_PROVENANCE_INVALID")
  check("INVALID_BOUNDS",{inp in var x=rows;x[0]["rois"]=[["x":574,"y":10,"width":20,"height":20]];inp["associations"]=x},"HOLD_ROI_BOUNDS_INVALID")
  check("DUPLICATE_ROLE",{inp in var x=rows;x.append(rows[0]);inp["associations"]=x},"HOLD_DUPLICATE_OR_MALFORMED_ROLE")
  check("CONFLICTING_OCR",{inp in var x=rows;x[0]["knowledge_state"]="CONFLICT";inp["associations"]=x},"HOLD_AMBIGUOUS_OCR_VALUES")
  check("CROSS_SIDE_COLLISION",{inp in var x=rows;x[1]["evidence_refs"]=["payload_json.readings[1]"];inp["associations"]=x},"HOLD_CROSS_SIDE_EVIDENCE_COLLISION")
  check("BAD_EVIDENCE_SOURCE",{inp in var x=rows;x[0]["evidence_refs"]=["arbitrary"];inp["associations"]=x},"HOLD_DUPLICATE_OR_MALFORMED_ROLE")
  check("NOT_CURRENT",{inp in var x=rows;x[0]["current_state_eligible"]=true;inp["associations"]=x},"HOLD_ASSOCIATION_PROVENANCE_INVALID")
  print("PASS_R564_OWNER_HINT_FENCE_ALL_18_CASES")
 }
}
