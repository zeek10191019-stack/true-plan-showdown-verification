import Foundation
@main struct R647Harness {
 static func main(){
  var tests=0
  func check(_ b:Bool,_ tag:String){precondition(b,tag);tests+=1;print("PASS_R647",tag)}
  let h=String(repeating:"a",count:64),sid="s1"
  func item(_ t:String,_ id:String)->[String:Any]{
   ["evidence_ref":id,"raw_text":t,"image_sha256":h,
    "capture_session_id":sid,"frame_id":1,"epoch":1,
    "owner_verified":false,"roi":["x":100,"y":100,"width":80,"height":15]]
  }
  func mk(_ tokens:[[String:Any]]) -> [String:Any] {
   let names=R581ReadabilityCoverage.tracks.map{$0.0}
   return ["image_sha256":h,
    "r581_full_read_coverage":["schema":R581ReadabilityCoverage.schema,
     "source_kind":"USER_IMPORTED_PNG_OFFLINE_ONLY","source_binding_valid":true,
     "snapshot_binding_valid":true,"image_sha256":h,"analysis_image_sha256":h,
     "current_state_eligible":false,"battle_advice_authorized":false],
    "r646_field_readers":["schema":R646FieldSignalReaders.schema,
      "source_kind":"USER_IMPORTED_PNG_OFFLINE_ONLY","raw_image_sha256":h,
      "analysis_image_sha256":h,"capture_session_id":sid,
      "frame_id":1,"epoch":1,"game_fields_certified":0,
      "owner_verified":false,"current_state_eligible":false,
      "battle_advice_authorized":false,
      "field_read_attempts":names.map{["field":$0] as [String:Any]}],
    "screen_read_state":["image_sha256":h,"capture_session_id":sid,
      "frame_id":1,"epoch":1,"source_validation":"PASS_FRAME_BINDING_ONLY",
      "current_state_eligible":false,"battle_advice_authorized":false,
      "ocr_source_inventory":tokens]]
  }
  func run(_ d:[String:Any],kind:String="USER_IMPORTED_PNG_OFFLINE_ONLY") -> [String:Any] {
   var x=d;R647MegaSignalBoundary.enrich(&x,sourceKind:kind);return x
  }
  let cases:[(String,String,String)] = [
   ("メガシンカ","MEGA_MENU_OR_GENERIC_MENTION","NONE"),
   ("メガシンカする","MEGA_MENU_OR_GENERIC_MENTION","NONE"),
   ("メガ進化できない","MEGA_NEGATED_TEXT_MENTION","NONE"),
   ("相手のギャラドスはメガシンカした！","MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF","OPPONENT_TEXT_ONLY"),
   ("こちらのグソクムシャはメガシンカした！","MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF","OWN_TEXT_ONLY"),
   ("ギャラドスはメガシンカした","MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF","UNSPECIFIED_TEXT"),
   ("メガギャラドス","MEGA_FORM_NAME_TEXT_MENTION","UNSPECIFIED_TEXT"),
   ("メガグソクムシャ","MEGA_FORM_NAME_TEXT_MENTION","UNSPECIFIED_TEXT"),
   ("メガリザードンＸ","MEGA_FORM_NAME_TEXT_MENTION","UNSPECIFIED_TEXT")
  ]
  for (i,row) in cases.enumerated() {
   let actual=R647MegaSignalBoundary.classify(row.0)
   check(actual?.0==row.1 && actual?.1==row.2,"lexical_\(i)")
  }
  for t in ["メガホーン","メガドレイン","ギャラドス","トリックルーム","メガトンパンチ"] {
   check(R647MegaSignalBoundary.classify(t)==nil,"not_mega_\(t)")
  }
  check(R647MegaSignalBoundary.classify("メガシンカしたら")?.0 !=
   "MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF","conditional_not_event")
  check(R647MegaSignalBoundary.classify("メガシンカしたい")?.0 !=
   "MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF","desire_not_event")
  check(R647MegaSignalBoundary.classify("メガシンカしたという噂")?.0 !=
   "MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF","rumor_not_event")
  let d=mk([item("メガシンカ", "r0"),item("相手のギャラドスはメガシンカした！","r1"),item("メガグソクムシャ","r2")])
  let good=run(d)
  check(good["r647_status"] as? String=="MEGA_TEXT_CUES_NOT_EVENT_CERTIFICATION","bound_report")
  let rep=good["r647_mega_boundary"] as! [String:Any]
  check(rep["cue_count"] as? Int==3,"three_cues")
  check(rep["completed_word_mentions"] as? Int==1,"one_mention_not_event")
  check(rep["form_name_mentions"] as? Int==1,"mega_form_name_hint")
  check(rep["mega_event_certified"] as? Bool == false,"never_certify_mega")
  check(rep["owner_verified"] as? Bool == false,"never_certify_owner")
  check(rep["same_display_name_does_not_exclude_mega"] as? Bool == true,"name_unchanged_safe")
  check(rep["unseen_animation_is_not_negative_evidence"] as? Bool == true,"animation_absent_safe")
  check(rep["visual_form_reference_calibrated"] as? Bool == false,"no_fake_model")
  check(JSONSerialization.isValidJSONObject(good),"json")
  check((run(mk([]))["r647_mega_boundary"] as? [String:Any])?["status"] as? String=="NO_BOUND_MEGA_TEXT_ON_FRAME","empty_not_negative")
  var bad=d;var s=bad["screen_read_state"] as! [String:Any]
  s["frame_id"]=2;bad["screen_read_state"]=s
  check(run(bad)["r647_status"] as? String=="HOLD_SOURCE_OR_ALL_FIELD_PROOF_MISSING","wrong_frame")
  bad=d;s=bad["screen_read_state"] as! [String:Any];s["ocr_source_inventory"]=[item("メガギャラドス","r0"),item("メガシンカした","r0")];bad["screen_read_state"]=s
  check(run(bad)["r647_status"] as? String=="HOLD_OCR_SOURCE_CONTRADICTION","duplicate_ref")
  bad=d;s=bad["screen_read_state"] as! [String:Any];var tok=item("メガシンカした","r0");tok["image_sha256"]=String(repeating:"b",count:64);s["ocr_source_inventory"]=[tok];bad["screen_read_state"]=s
  check(run(bad)["r647_status"] as? String=="HOLD_OCR_SOURCE_CONTRADICTION","cross_frame_image")
  bad=d;var full=bad["r646_field_readers"] as! [String:Any];full["field_read_attempts"]=[];bad["r646_field_readers"]=full
  check(run(bad)["r647_status"] as? String=="HOLD_SOURCE_OR_ALL_FIELD_PROOF_MISSING","79_manifest_required")
  bad=d;var cover=bad["r581_full_read_coverage"] as! [String:Any];cover["battle_advice_authorized"]=true;bad["r581_full_read_coverage"]=cover
  check(run(bad)["r647_status"] as? String=="HOLD_SOURCE_OR_ALL_FIELD_PROOF_MISSING","no_advice_escalation")
  bad=d;s=bad["screen_read_state"] as! [String:Any];var tok2=item("メガグソクムシャ","r0");tok2["owner_verified"]=true;s["ocr_source_inventory"]=[tok2];bad["screen_read_state"]=s
  check(run(bad)["r647_status"] as? String=="HOLD_OCR_SOURCE_CONTRADICTION","spoofed_owner")
  check(run(d,kind:"OTHER")["r647_status"] as? String=="HOLD_SOURCE_OR_ALL_FIELD_PROOF_MISSING","invalid_source")
  print("R647_ALL_PASS",tests)
 }
}
