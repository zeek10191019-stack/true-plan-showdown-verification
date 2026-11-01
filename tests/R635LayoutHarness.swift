import Foundation
@main struct R635Harness {
 static func main() {
  var n=0
  func ok(_ yes:Bool,_ label:String) {precondition(yes,label);n+=1;print("PASS_R635",label)}
  let sha=String(repeating:"a",count:64)
  let session="sid"
  let evidence="r[0]"
  let base:[String:Any]=[
    "image_sha256":sha,"source_validation":"PASS_FRAME_BINDING_ONLY",
    "current_state_eligible":false,"battle_advice_authorized":false,
    "capture_session_id":session,"frame_id":Int64(8),"epoch":Int64(3),
    "candidates":[["domain":"hp", "evidence_ref":evidence,
                   "image_sha256":sha,"side":"UNKNOWN_OWNER",
                   "verification_status":"UNVERIFIED",
                   "current_state_eligible":false, "raw_text":"170/185"]]
  ]
  var doc:[String:Any]=[
    "png_sha256":sha,"capture_session_id":session,"frame_id":Int64(8),
    "epoch":Int64(3),"image_width":1156,"image_height":534,
    "observed_ms_monotonic":Int64(200),"screen_read_state":base,
    "r581_full_read_coverage":R581ReadabilityCoverage.make(
      sourceSHA:sha,sourceKind:"LIVE_RETAINED_FRAME",snapshot:base,mega:nil)
  ]
  R634FieldEvidenceRouting.enrich(&doc,sourceKind:"LIVE_RETAINED_FRAME")
  var snap=base
  var entries=[[String:Any]]()
  func association(_ role:String,_ slot:Any,_ value:Any)->[String:Any] {
    return ["role_hint":role,"slot":slot,"value":value,"knowledge_state":"INFERRED",
      "capture_session_id":session,"frame_id":Int64(8),"epoch":Int64(3),
      "image_sha256":sha,"current_state_eligible":false,
      "side":"UNKNOWN_OWNER","verification_status":"UNVERIFIED",
      "evidence_refs":[evidence],"raw_texts":["170/185"],
      "orientation":"ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED",
      "roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT"]
  }
  entries.append(association("own_hp",NSNull(),["current":170,"maximum":185]))
  entries.append(association("move_name",0,"じしん"))
  entries.append(association("move_pp",0,["current":8,"maximum":10]))
  let layout:[String:Any]=[
    "schema":"trueplan.screen-read.layout-candidates.v1",
    "image_sha256":sha,"capture_session_id":session,"frame_id":Int64(8),
    "epoch":Int64(3),"current_state_eligible":false,"owner_certified":false,
    "calibration_certified":false,"associations":entries]
  let kind="move_selection_candidate"
  let screen:[String:Any]=[
    "schema":"trueplan.screen-read.screen-evidence.v1",
    "image_sha256":sha,"capture_session_id":session,"frame_id":Int64(8),
    "epoch":Int64(3),"current_state_eligible":false,"owner_certified":false,
    "status":"PRIMARY_AND_ALTERNATIVES_AGREE","screen_kind":kind,
    "evaluated_evidence_refs":[evidence]]
  snap["layout_candidates"]=layout
  snap["screen_classification"]=screen
  snap["screen_kind"]=kind
  doc["screen_read_state"]=snap
  R635LayoutToFields.enrich(&doc,sourceKind:"LIVE_RETAINED_FRAME")
  ok(doc["r635_layout_status"] as? String ==
     "LAYOUT_HYPOTHESES_ATTACHED_WITHOUT_PROMOTION","layout_attached")
  let cov=doc["r581_full_read_coverage"] as! [String:Any]
  let fields=cov["fields"] as! [[String:Any]]
  func f(_ key:String)->[String:Any] {fields.first{$0["field"] as? String == key}!}
  ok(fields.count==79,"79_fields_unchanged")
  ok((f("own.hp")["r635_structured_layout_candidates"] as? [[String:Any]])?.count == 1,"own_hp_candidate")
  ok((f("own.hp_max")["r635_structured_layout_candidates"] as? [[String:Any]])?.count == 1,"own_hp_max_candidate")
  ok((f("own.moves_four")["r635_structured_layout_candidates"] as? [[String:Any]])?.count == 1,"move_slot_candidate")
  ok((f("own.pp_four")["r635_structured_layout_candidates"] as? [[String:Any]])?.count == 1,"pp_slot_candidate")
  ok((f("opponent.hp")["r635_structured_layout_candidates"] as? [[String:Any]])?.count == 0,"not_cross_assigned")
  ok(f("own.hp")["owner_verified"] as? Bool == false &&
     f("own.hp")["current_value_admitted"] as? Bool == false,"never_promote")
  ok(f("screen.ui_state")["r635_screen_kind_hypothesis"] is [String:Any],"screen_kind_candidate")
  ok(cov["r635_verified_game_fields"] as? Int == 0,"no_false_accuracy")
  ok(JSONSerialization.isValidJSONObject(doc),"JSON_valid")
  var conflict=doc
  var alt=entries;alt.append(entries[1]);var layout2=layout;layout2["associations"]=alt
  var snap2=snap;snap2["layout_candidates"]=layout2;conflict["screen_read_state"]=snap2
  R635LayoutToFields.enrich(&conflict,sourceKind:"LIVE_RETAINED_FRAME")
  ok(conflict["r635_layout_status"] as? String == "HOLD_DUPLICATE_ROLE_SLOT","ambiguous_slots_rejected")
  var tampered=doc;var s3=snap;var l3=layout;l3["image_sha256"]=String(repeating:"b",count:64)
  s3["layout_candidates"]=l3;tampered["screen_read_state"]=s3
  R635LayoutToFields.enrich(&tampered,sourceKind:"LIVE_RETAINED_FRAME")
  ok(tampered["r635_layout_status"] as? String == "HOLD_BAD_LAYOUT_SOURCE_OR_CALIBRATION","tampered_sha_rejected")
  var fake=doc;var s4=snap;var l4=layout;l4["calibration_certified"]=true
  s4["layout_candidates"]=l4;fake["screen_read_state"]=s4
  R635LayoutToFields.enrich(&fake,sourceKind:"LIVE_RETAINED_FRAME")
  ok(fake["r635_layout_status"] as? String == "HOLD_BAD_LAYOUT_SOURCE_OR_CALIBRATION","fake_calibration_rejected")
  print("R635_HARNESS_ALL_PASS",n)
 }
}
