import Foundation
@main struct R581CoverageHarness {
 static func main() {
  let hash=String(repeating:"a",count:64)
  func field(_ report:[String:Any],_ path:String)->[String:Any] {
    let fields=report["fields"] as! [[String:Any]]
    return fields.first(where:{$0["field"] as? String == path})!
  }
  let source:[String:Any] = ["image_sha256":hash,"current_state_eligible":false,
    "battle_advice_authorized":false,"source_validation":"PASS_FRAME_BINDING_ONLY",
    "candidates":[["domain":"hp_percent","evidence_ref":"payload.readings[0]",
      "image_sha256":hash,"side":"UNKNOWN_OWNER","current_state_eligible":false,
      "verification_status":"UNVERIFIED","raw_text":"81%"],
      ["domain":"weather","evidence_ref":"payload.readings[1]",
      "image_sha256":hash,"side":"UNKNOWN_OWNER","current_state_eligible":false,
      "verification_status":"UNVERIFIED","raw_text":"あめ"],
      ["domain":"mega_text","evidence_ref":"payload.readings[2]",
      "image_sha256":hash,"side":"UNKNOWN_OWNER","current_state_eligible":false,
      "verification_status":"UNVERIFIED","raw_text":"メガシンカ"]]]
  let mega:[String:Any] = ["image_sha256":hash,"mega_certified":false,"visual_form_certified":false,"text_hints":["メガシンカ"]]
  let r=R581ReadabilityCoverage.make(sourceSHA:hash,sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY",snapshot:source,mega:mega)
  let count=R581ReadabilityCoverage.tracks.count
  assert(count >= 70 && r["field_count"] as? Int == count)
  print("PASS_R581_COMPLETE_FIELD_REGISTRY_\(count)")
  assert(r["current_state_eligible"] as? Bool == false && r["battle_advice_authorized"] as? Bool == false)
  assert(r["owner_certified"] as? Bool == false && r["turn_certified"] as? Bool == false)
  print("PASS_R581_NEVER_CERTIFY_LIVE_OR_OWNER")
  assert(field(r,"own.hp_percent")["status"] as? String == "OCR_TEXT_CANDIDATE_ONLY")
  assert(field(r,"opponent.hp_percent")["status"] as? String == "OCR_TEXT_CANDIDATE_ONLY")
  assert(field(r,"own.hp_percent")["owner_verified"] as? Bool == false)
  print("PASS_R581_HP_AMBIGUOUS_SIDE_RETAINS_PROVISIONAL")
  assert(field(r,"own.held_item")["status"] as? String == "UNKNOWN")
  assert(field(r,"own.mega_visual_form")["status"] as? String == "UNKNOWN")
  assert(field(r,"field.weather")["status"] as? String == "OCR_TEXT_CANDIDATE_ONLY")
  assert(r["mega_ocr_available"] as? Bool == true)
  print("PASS_R581_UNOBSERVED_UNKNOWNS_AND_MEGA_TEXT_ONLY")
  let fake=String(repeating:"b",count:64)
  let mismatched=R581ReadabilityCoverage.make(sourceSHA:fake,sourceKind:"LIVE_RETAINED_FRAME",snapshot:source,mega:mega)
  assert(mismatched["snapshot_binding_valid"] as? Bool == false)
  assert(mismatched["mega_ocr_available"] as? Bool == false)
  assert(mismatched["candidate_field_count"] as? Int == 0)
  print("PASS_R581_CROSS_IMAGE_REFUSE")
  let broken=R581ReadabilityCoverage.make(sourceSHA:"sha",sourceKind:"LIVE_RETAINED_FRAME",snapshot:source,mega:mega)
  assert(broken["source_binding_valid"] as? Bool == false)
  assert(broken["candidate_field_count"] as? Int == 0)
  print("PASS_R581_BAD_SHA_REFUSE")
  var forged=source;forged["current_state_eligible"]=true
  let forgery=R581ReadabilityCoverage.make(sourceSHA:hash,sourceKind:"LIVE_RETAINED_FRAME",snapshot:forged,mega:mega)
  assert(forgery["snapshot_binding_valid"] as? Bool == false)
  print("PASS_R581_FORGED_LIVE_REFUSE")
  var polluted=source;var rows=source["candidates"] as! [[String:Any]]
  var injected=rows[0];injected["side"]="OWN";rows.append(injected)
  injected=rows[0];injected["current_state_eligible"]=true;rows.append(injected)
  injected=rows[0];injected["image_sha256"]=fake;rows.append(injected)
  injected=rows[0];injected["evidence_ref"]=String(repeating:"X",count:161);rows.append(injected)
  polluted["candidates"]=rows
  let stripped=R581ReadabilityCoverage.make(sourceSHA:hash,sourceKind:"LIVE_RETAINED_FRAME",snapshot:polluted,mega:mega)
  assert(field(stripped,"own.hp_percent")["candidate_count"] as? Int == 1)
  print("PASS_R581_UNTRUSTED_ROW_FILTER")
  let analysisHash=String(repeating:"c",count:64)
  var rotated=source;rotated["image_sha256"]=analysisHash
  rotated["frame_id"]=Int64(7);rotated["epoch"]=Int64(3);rotated["capture_session_id"]="session"
  var mapped=rotated["candidates"] as! [[String:Any]]
  for i in mapped.indices { mapped[i]["image_sha256"]=analysisHash }
  rotated["candidates"]=mapped
  let projection:[String:Any]=["schema":"trueplan.screen-read.analysis-projection.v1",
    "status":"DECLARED_GEOMETRY_ONLY","raw_image_sha256":hash,
    "analysis_image_sha256":analysisHash,"frame_id":Int64(7),"epoch":Int64(3),
    "capture_session_id":"session","pixel_equality_verified":false]
  let transformed=R581ReadabilityCoverage.make(sourceSHA:hash,sourceKind:"LIVE_RETAINED_FRAME",snapshot:rotated,mega:nil,projection:projection)
  assert(transformed["declared_analysis_projection_valid"] as? Bool == true)
  assert(transformed["snapshot_binding_valid"] as? Bool == true)
  assert(field(transformed,"field.weather")["status"] as? String == "OCR_TEXT_CANDIDATE_ONLY")
  assert(transformed["owner_certified"] as? Bool == false)
  print("PASS_R581_DECLARED_ROTATED_ANALYSIS_IS_PROVISIONAL")
  var wrongProjection=projection;wrongProjection["frame_id"]=Int64(6)
  let rejected=R581ReadabilityCoverage.make(sourceSHA:hash,sourceKind:"LIVE_RETAINED_FRAME",snapshot:rotated,mega:nil,projection:wrongProjection)
  assert(rejected["candidate_field_count"] as? Int == 0)
  print("PASS_R581_MISMATCHED_TRANSFORM_FRAME_REFUSED")
  let nils=R581ReadabilityCoverage.make(sourceSHA:hash,sourceKind:"LIVE_RETAINED_FRAME",snapshot:nil,mega:nil)
  assert(nils["unknown_field_count"] as? Int == count)
  assert(JSONSerialization.isValidJSONObject(nils))
  print("PASS_R581_ALL_UNKNOWN_SERIALIZABLE")
 }
}
