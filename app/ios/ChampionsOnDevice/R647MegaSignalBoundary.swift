import Foundation
import CoreFoundation

/// R647: source-bound Mega mentions and transition-risk accounting.
/// A transformation animation is optional evidence, not a prerequisite.
/// Text, sprites without independently calibrated references, and name OCR
/// must never become an owner, Mega identity, or live battle assertion.
enum R647MegaSignalBoundary {
 static let schema = "trueplan.r647.mega-signal-boundary.v1"
 static let current: Set<String> = ["LIVE_RETAINED_FRAME", "USER_IMPORTED_PNG_OFFLINE_ONLY"]
 private static func int(_ x: Any?) -> Int? {
  guard let n=x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
   n.doubleValue.isFinite,n.doubleValue>=0,
   n.doubleValue < Double(Int.max),n.doubleValue==Double(n.intValue)
   else {return nil}
  return n.intValue
 }
 private static func sha(_ x:Any?) -> String? {
  guard let s=x as? String,s.utf8.count==64,
   s.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)})
   else{return nil}
  return s
 }
 private static func compact(_ t:String)->String {
  t.precomposedStringWithCompatibilityMapping
   .replacingOccurrences(of:"　",with:"")
   .replacingOccurrences(of:" ",with:"")
   .trimmingCharacters(in:.whitespacesAndNewlines)
 }
 private static func rx(_ s:String,_ pattern:String)->Bool {
  s.range(of:pattern, options:.regularExpression) != nil
 }
 /// Explicitly distinguish action menu text from a text report of a completed event.
 /// No return code here establishes that a Mega event happened on the battlefield.
 static func classify(_ raw:String)->(String,String)? {
  let s=compact(raw)
  guard !s.isEmpty,s.utf8.count<=160 else{return nil}
  if rx(s,#"^(?:メガシンカ|メガ進化)(?:する|させる|をする|する？|できる|可能)?[?？]?$"#) {
   return ("MEGA_MENU_OR_GENERIC_MENTION","NONE")
  }
  if s.contains("メガシンカできない") || s.contains("メガ進化できない") {
   return ("MEGA_NEGATED_TEXT_MENTION","NONE")
  }
  if rx(s,#"(?:メガシンカ|メガ進化)した[！!。]?$"#) {
   let side:String
   if s.hasPrefix("相手の") || s.hasPrefix("あいての") {side="OPPONENT_TEXT_ONLY"}
   else if s.hasPrefix("自分の") || s.hasPrefix("こちらの") {side="OWN_TEXT_ONLY"}
   else {side="UNSPECIFIED_TEXT"}
   return ("MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF",side)
  }
  if rx(s,#"(?:^|[^一-龯ァ-ヴ])メガ[ァ-ヶー]{2,24}(?:[XYZＸＹＺ])?$"#) &&
    !["メガホーン","メガドレイン","メガトンパンチ","メガトンキック"].contains(s) {
   return ("MEGA_FORM_NAME_TEXT_MENTION","UNSPECIFIED_TEXT")
  }
  if s.contains("メガシンカ") || s.contains("メガ進化") {
   return ("MEGA_CONTEXT_MENTION_NOT_EVENT","UNSPECIFIED_TEXT")
  }
  return nil
 }
 static func enrich(_ doc:inout [String:Any],sourceKind:String) {
  doc.removeValue(forKey:"r647_mega_boundary")
  doc["r647_status"]="HOLD_SOURCE_OR_ALL_FIELD_PROOF_MISSING"
  guard current.contains(sourceKind),
   let cover=doc["r581_full_read_coverage"] as? [String:Any],
   cover["schema"] as? String==R581ReadabilityCoverage.schema,
   cover["source_kind"] as? String==sourceKind,
   cover["source_binding_valid"] as? Bool==true,
   cover["snapshot_binding_valid"] as? Bool==true,
   cover["current_state_eligible"] as? Bool==false,
   cover["battle_advice_authorized"] as? Bool==false,
   let raw=sha(cover["image_sha256"]),
   raw==sha(sourceKind=="LIVE_RETAINED_FRAME" ? doc["png_sha256"] : doc["image_sha256"]),
   let report=doc["r646_field_readers"] as? [String:Any],
   report["schema"] as? String==R646FieldSignalReaders.schema,
   report["source_kind"] as? String==sourceKind,
   report["raw_image_sha256"] as? String==raw,
   report["game_fields_certified"] as? Int==0,
   report["owner_verified"] as? Bool==false,
   report["current_state_eligible"] as? Bool==false,
   report["battle_advice_authorized"] as? Bool==false,
   let fields=report["field_read_attempts"] as? [[String:Any]],
   fields.count==79,
   fields.compactMap({$0["field"] as? String})==R581ReadabilityCoverage.tracks.map({$0.0}),
   let snap=doc["screen_read_state"] as? [String:Any],
   let analysis=sha(snap["image_sha256"]),
   analysis==sha(cover["analysis_image_sha256"]),
   report["analysis_image_sha256"] as? String==analysis,
   let session=snap["capture_session_id"] as? String,!session.isEmpty,
   report["capture_session_id"] as? String==session,
   let frame=int(snap["frame_id"]),frame>0,
   let epoch=int(snap["epoch"]),epoch>0,
   int(report["frame_id"])==frame,int(report["epoch"])==epoch,
   snap["source_validation"] as? String=="PASS_FRAME_BINDING_ONLY",
   snap["current_state_eligible"] as? Bool==false,
   snap["battle_advice_authorized"] as? Bool==false,
   let inventory=snap["ocr_source_inventory"] as? [[String:Any]],
   inventory.count<=288 else{return}
  var index=Set<String>(),observed=[[String:Any]]()
  for row in inventory {
   guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
    ref.utf8.count<=160,index.insert(ref).inserted,
    let t=row["raw_text"] as? String,!t.isEmpty,t.utf8.count<=160,
    row["image_sha256"] as? String==analysis,
    row["capture_session_id"] as? String==session,
    int(row["frame_id"])==frame,int(row["epoch"])==epoch,
    row["owner_verified"] as? Bool==false,
    let box=row["roi"] as? [String:Any],
    let x=int(box["x"]),let y=int(box["y"]),
    let w=int(box["width"]),let h=int(box["height"]),w>0,h>0 else {
    doc["r647_status"]="HOLD_OCR_SOURCE_CONTRADICTION";return
   }
   // Coordinate validity against analysis raster is proved upstream by R646.
   guard !ref.contains(".ocr_alternatives[") else{continue}
   guard let cue=classify(t) else{continue}
   observed.append(["cue":cue.0,"text_side_hint":cue.1,
    "evidence_ref":ref,"raw_text":t,
    "analysis_roi":["x":x,"y":y,"width":w,"height":h],
    "source_image_sha256":analysis,"capture_session_id":session,
    "frame_id":frame,"epoch":epoch,
    "owner_verified":false,"actual_mega_event_confirmed":false])
  }
  // A name-only cue, menu text, or animation absent cannot establish state.
  let events=observed.filter{$0["cue"] as? String=="MEGA_COMPLETED_WORDS_NOT_ACTIVATION_PROOF"}
  let labels=observed.filter{$0["cue"] as? String=="MEGA_FORM_NAME_TEXT_MENTION"}
  let menus=observed.filter{$0["cue"] as? String=="MEGA_MENU_OR_GENERIC_MENTION"}
  let historicalOnly: [String:Any] = [
   "schema":schema,"status":observed.isEmpty ? "NO_BOUND_MEGA_TEXT_ON_FRAME" : "MEGA_TEXT_CUES_NOT_EVENT_CERTIFICATION",
   "source_kind":sourceKind,"raw_image_sha256":raw,
   "analysis_image_sha256":analysis,"capture_session_id":session,
   "frame_id":frame,"epoch":epoch,
   "cue_count":observed.count,"completed_word_mentions":events.count,
   "form_name_mentions":labels.count,"menu_or_generic_mentions":menus.count,
   "cues":observed,"unseen_animation_is_not_negative_evidence":true,
   "same_display_name_does_not_exclude_mega":true,
   "mega_x_y_z_variant_requires_independent_form_evidence":true,
   "owner_role_from_text_is_not_actor_proof":true,
   "visual_form_reference_calibrated":false,
   "visual_form_status":"HOLD_NO_INDEPENDENT_LABELED_FORM_REFERENCE",
   "own_mega_state":"UNKNOWN","opponent_mega_state":"UNKNOWN",
   "one_mega_per_side_rule":"MECHANICS_REFERENCE_ONLY_NOT_OBSERVATION",
   "battle_roster_identity_verified":false,
   "mega_event_certified":false,"mega_form_certified":false,
   "owner_verified":false,"current_state_eligible":false,
   "game_fields_certified":0,"battle_advice_authorized":false]
  guard JSONSerialization.isValidJSONObject(historicalOnly) else {
   doc["r647_status"]="HOLD_REPORT_SERIALIZATION";return
  }
  doc["r647_mega_boundary"]=historicalOnly
  doc["r647_status"]=historicalOnly["status"]
 }
}
