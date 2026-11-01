import Foundation

@main struct TestR565 {
 static func main() {
  let sha=String(repeating:"a",count:64)
  let rect:[String:Int64]=["x":95,"y":220,"width":30,"height":10]
  let opp:[String:Int64]=["x":475,"y":20,"width":20,"height":10]
  func site(_ index:Int,_ r:[String:Int64]) -> R553LayoutReading.Site {
   R553LayoutReading.Site(reading:index,rank:0,text:index==0 ? "120/170" : "80%",confidence:0.98,
    reference:"payload_json.readings[\(index)]",roi:r)
  }
  let sites=[site(0,rect),site(1,opp)]
  func hint(_ role:String, _ evidence:[String], _ roi:[[String:Int64]]) -> [String:Any] {
   ["role_hint":role,"slot":NSNull(),"verification":"POSITION_ONLY_UNVERIFIED",
    "current_state_eligible":false,"knowledge_state":"INFERRED", "evidence_refs":evidence,"rois":roi]
  }
  let hints=[hint("own_hp",[sites[0].reference],[rect]),hint("opponent_hp",[sites[1].reference],[opp])]
  func base(_ all:[[String:Any]]=hints) -> [String:Any] {
   ["status":"PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION","owner_certified":false,
    "current_state_eligible":false,"capture_session_id":"session","frame_id":Int64(6),"epoch":Int64(2),
    "image_sha256":sha,"hints":all]
  }
  func run(_ inp:[String:Any],_ sources:[R553LayoutReading.Site]=sites,_ frame:Int64=6)->[String:Any] {
   R565SourceEvidenceFence.report(base:inp,sites:sources,session:"session",frame:frame,epoch:2,imageSHA:sha)
  }
  func test(_ name:String,_ b:[String:Any],_ sources:[R553LayoutReading.Site]=sites,
            _ expected:String="PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION") {
   let out=run(b,sources)
   guard out["status"] as? String == expected else {fatalError("\(name) actual \(out["status"] ?? "nil") expected \(expected)")}
   guard out["owner_certified"] as? Bool == false && out["current_state_eligible"] as? Bool == false &&
         out["battle_advice_authorized"] as? Bool == false && out["iPhone_accuracy_certified"] as? Bool == false else {fatalError("unsafe promotion")}
   if expected.hasPrefix("HOLD") {guard (out["hints"] as? [[String:Any]])?.isEmpty == true else {fatalError("stale hints")}}
   print("PASS_R565_\(name)")
  }
  test("SAME_FRAME_SOURCE_BOUND",base())
  var bad=base();bad["frame_id"]=9;test("FOREIGN_FRAME",bad,sites,"HOLD_R565_WRONG_FRAME_OR_BASE")
  bad=base();bad["epoch"]=3;test("FOREIGN_EPOCH",bad,sites,"HOLD_R565_WRONG_FRAME_OR_BASE")
  bad=base();bad["image_sha256"]=String(repeating:"b",count:64);test("IMAGE_MISMATCH",bad,sites,"HOLD_R565_WRONG_FRAME_OR_BASE")
  bad=base();bad["capture_session_id"]="foreign";test("SESSION_MISMATCH",bad,sites,"HOLD_R565_WRONG_FRAME_OR_BASE")
  bad=base();bad["owner_certified"]=true;test("OWNER_FORGERY",bad,sites,"HOLD_R565_WRONG_FRAME_OR_BASE")
  bad=base();bad["current_state_eligible"]=true;test("CURRENT_FORGERY",bad,sites,"HOLD_R565_WRONG_FRAME_OR_BASE")
  bad=base([]);test("NO_HINT",bad,sites,"HOLD_R565_NO_POSITION_HINTS")
  bad=base([hint("own_hp",["payload_json.readings[333]"],[rect])]);test("PHANTOM_READING",bad,sites,"HOLD_R565_SOURCE_EVIDENCE_ROI_MISMATCH")
  bad=base([hint("own_hp",[sites[0].reference],[opp])]);test("ROI_FORGERY",bad,sites,"HOLD_R565_SOURCE_EVIDENCE_ROI_MISMATCH")
  bad=base([hint("own_hp",[sites[0].reference],[rect]),hint("opponent_hp",[sites[0].reference],[rect])]);test("OWN_OPP_COLLISION",bad,sites,"HOLD_R565_ROLE_REFERENCE_COLLISION")
  bad=base([hint("own_hp",[sites[0].reference],[rect]),hint("own_name",[sites[0].reference],[rect])]);test("HP_NAME_COLLISION",bad,sites,"HOLD_R565_ROLE_REFERENCE_COLLISION")
  bad=base([hint("own_hp",[sites[0].reference],[rect,rect])]);test("COUNT_MISMATCH",bad,sites,"HOLD_R565_HINT_STRUCTURE_INVALID")
  bad=base();var change=hints;change[0]["knowledge_state"]="CERTIFIED";bad["hints"]=change;test("FALSE_KNOWLEDGE",bad,sites,"HOLD_R565_HINT_STRUCTURE_INVALID")
  bad=base();change=hints;change[1]["verification"]="CERTIFIED";bad["hints"]=change;test("FALSE_VERIFICATION",bad,sites,"HOLD_R565_HINT_STRUCTURE_INVALID")
  test("DUPLICATE_SOURCE_ID",base(),[sites[0],sites[0],sites[1]],"HOLD_R565_SOURCE_REFERENCE_DUPLICATED")
  test("NEGATIVE_SOURCE_ROI",base(),[site(0,["x":10,"y":10,"width":0,"height":10]),sites[1]],"HOLD_R565_MALFORMED_SOURCE_SITE")
  bad=base();bad["status"]="HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED";test("BASE_HOLD",bad,sites,"HOLD_LAYOUT_OR_SOURCE_NOT_VERIFIED")
  // Future-frame values do not become current merely through verified geometry.
  let output=run(base());assert(output["source_evidence_checked"] as? Bool == true)
  assert((output["hints"] as? [[String:Any]])?.count==2)
  print("PASS_R565_ALL_18_TESTS")
 }
}
