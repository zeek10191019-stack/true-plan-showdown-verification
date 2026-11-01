import Foundation
@main struct R634FieldRoutingHarness {
 static func main() {
  func check(_ b:Bool,_ name:String) {precondition(b,name);print("PASS_R634",name)}
  let sha=String(repeating:"a",count:64)
  let base:[String:Any] = ["image_sha256":sha,"current_state_eligible":false,
   "battle_advice_authorized":false,"source_validation":"PASS_FRAME_BINDING_ONLY",
   "frame_id":Int64(7),"epoch":Int64(3),"capture_session_id":"evidence-session",
   "candidates":[["domain":"hp_percent","evidence_ref":"r[0]","raw_text":"81%",
     "image_sha256":sha,"side":"UNKNOWN_OWNER","current_state_eligible":false,
     "verification_status":"UNVERIFIED"]]]
  let c=R634FieldEvidenceRouting.catalog()
  check(c.count==79 && Set(c.compactMap{$0["field"]}).count==79,"all_79_reader_routes")
  var d:[String:Any] = ["png_sha256":sha,"frame_id":Int64(7),"epoch":Int64(3),
     "capture_session_id":"evidence-session","image_width":1920,"image_height":1080,
     "observed_ms_monotonic":Int64(1900),"screen_read_state":base,
     "r581_full_read_coverage":R581ReadabilityCoverage.make(
      sourceSHA:sha,sourceKind:"LIVE_RETAINED_FRAME",snapshot:base,mega:nil)]
  R634FieldEvidenceRouting.enrich(&d,sourceKind:"LIVE_RETAINED_FRAME")
  let cov=d["r581_full_read_coverage"] as! [String:Any]
  let fields=cov["fields"] as! [[String:Any]]
  func field(_ key:String) -> [String:Any] {fields.first{$0["field"] as? String == key}!}
  check(fields.count==79 && cov["r634_reader_route_count"] as? Int==79,"all_fields_present")
  check(cov["r634_source_receipt_metadata_count"] as? Int == 5,"five_authentic_capture_metadata")
  check(field("capture.frame_id")["observed_metadata_value"] as? Int64 == 7,"capture_frame_actual_receipt")
  check((field("capture.pixel_geometry")["observed_metadata_value"] as? [String:Any])?["width"] as? Int64==1920,"raw_pixel_dimensions")
  let snippets=field("own.hp_percent")["bounded_ocr_evidence"] as! [[String:Any]]
  check(snippets.count==1 && snippets[0]["text_candidate"] as? String=="81%","evidence_kept")
  check(field("own.hp_percent")["owner_verified"] as? Bool==false &&
       field("opponent.hp_percent")["current_value_admitted"] as? Bool==false,"no_own_opponent_guess")
  check(field("battle.move_history")["source_proof"] as? String=="GAME_LOG_PANEL_NOT_CAPTURED_OR_UNVERIFIED","log_not_invented")
  check(cov["r634_game_values_certified"] as? Int==0,"no_false_79_certification")
  check(JSONSerialization.isValidJSONObject(d),"json_valid")
  var tampered=d;tampered["png_sha256"]=String(repeating:"b",count:64)
  R634FieldEvidenceRouting.enrich(&tampered,sourceKind:"LIVE_RETAINED_FRAME")
  let broken=(tampered["r581_full_read_coverage"] as! [String:Any])
  check(broken["r634_source_receipt_metadata_count"] as? Int==0,"tampered_png_sha_rejected")
  var duplicate=d;var rows=(d["r581_full_read_coverage"] as! [String:Any])["fields"] as! [[String:Any]]
  rows[1]=rows[0];var stale=d["r581_full_read_coverage"] as! [String:Any];stale["fields"]=rows
  duplicate["r581_full_read_coverage"]=stale
  R634FieldEvidenceRouting.enrich(&duplicate,sourceKind:"LIVE_RETAINED_FRAME")
  check(duplicate["r634_field_reader_status"] as? String=="REJECTED_R581_CATALOG_OR_SOURCE_MISMATCH","duplicate_field_rejected")
  check(field("own.mega_visual_form")["reader_route"] as? String=="PIXEL_AND_OCR_WITH_OWNER_CALIBRATION","mega_needs_image_calibration")
  print("R634_ROUTING_LOCAL_TEST_ALL_PASS")
 }
}
