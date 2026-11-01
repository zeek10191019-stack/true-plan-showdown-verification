import Foundation
@main struct R637GeometryHarness {
 static func main() {
  let hash=String(repeating:"a",count:64)
  var count=0
  func ok(_ test:Bool){precondition(test);count+=1}
  func a(_ role:String,_ ref:String,_ box:[String:Int],_ slot:Any=NSNull())->[String:Any] {
   ["role_hint":role,"slot":slot,"image_sha256":hash,
    "capture_session_id":"s","frame_id":2,"epoch":1,
    "verification_status":"UNVERIFIED","side":"UNKNOWN_OWNER",
    "current_state_eligible":false,
    "orientation":"ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED",
    "roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
    "evidence_refs":[ref],"rois":[box]]
  }
  let hp=a("own_hp","x",["x":80,"y":450,"width":100,"height":30])
  let pp=a("move_pp","y",["x":830,"y":260,"width":40,"height":20],0)
  func run(_ items:[[String:Any]],_ image:String=hash)->[String:Any] {
   let lay:[String:Any]=[
    "schema":"trueplan.screen-read.layout-candidates.v1",
    "status":"PROVISIONAL_PROFILE_MATCH_ONLY",
    "profile_id":"LEGACY_VERTICAL_MOVES_216_V1",
    "image_sha256":hash,"capture_session_id":"s","frame_id":2,"epoch":1,
    "owner_certified":false,"calibration_certified":false,
    "current_state_eligible":false,"roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
    "associations":items]
   var d:[String:Any]=[
    "r636_status":"TYPED_HYPOTHESES_ONLY_NO_OWNER_PROOF",
    "image_width":1156,"image_height":534,
    "screen_read_state":["image_sha256":image,"capture_session_id":"s",
     "frame_id":2,"epoch":1,"current_state_eligible":false,
     "battle_advice_authorized":false,"layout_candidates":lay],
    "r581_full_read_coverage":[
     "source_kind":"LIVE_RETAINED_FRAME",
     "r636_schema":R636TypedHUDEvidence.schema,"r636_verified_game_fields":0,
     "fields":(0..<79).map{["field":"f\($0)"]}]]
   R637GeometryDiagnostics.enrich(&d,sourceKind:"LIVE_RETAINED_FRAME")
   return d
  }
  func audit(_ x:[[String:Any]])->[String:Any] {
   run(x)["r637_geometry_audit"] as! [String:Any]
  }
  let d=run([hp,pp]),g=audit([hp,pp])
  ok(d["r637_status"] as? String=="PROVISIONAL_ROI_AUDIT")
  ok(g["accepted_region_groups"] as? Int==2)
  ok(g["game_fields_certified"] as? Int==0)
  ok(g["owner_verified"] as? Bool==false)
  ok(g["source_orientation_verified"] as? Bool==false)
  let boxes=g["geometry_candidates"] as! [[String:Any]]
  let rect=(boxes[0]["rects_top_left_10000"] as! [[String:Int]])[0]
  ok(rect["x"]==80*10000/1156 && rect["y"]==450*10000/534)
  ok(JSONSerialization.isValidJSONObject(d))
  var bad=pp
  bad["rois"]=[["x":1150,"y":260,"width":40,"height":20]]
  ok(audit([hp,bad])["rejected_associations"] as? Int==1)
  bad=pp;bad["evidence_refs"]=["x"]
  ok(audit([hp,bad])["cross_role_ref_collisions"] as? Int==1)
  ok((run([hp,bad])["r637_status"] as? String) ==
    "HOLD_SHARED_EVIDENCE_ACROSS_DIFFERENT_ROLES")
  bad=pp;bad["slot"]=9
  ok(audit([hp,bad])["rejected_associations"] as? Int==1)
  ok((run([hp,pp],String(repeating:"b",count:64))["r637_status"] as? String) ==
    "HOLD_SOURCE_OR_PROFILE_UNVERIFIED")
  print("R637_GEOMETRY_TEST_ALL_PASS",count)
 }
}
