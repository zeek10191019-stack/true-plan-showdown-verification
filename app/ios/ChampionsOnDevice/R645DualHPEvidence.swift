import Foundation
import CoreFoundation

/// OCR-only, same-frame HP fraction and opponent percentage association.
/// Screen-space hints are NOT a player-owner proof or current battle state.
enum R645DualHPEvidence {
 static let schema="trueplan.r645.dual-hp-source-proof.v1"
 private static func int(_ v:Any?) -> Int? {
  guard let n=v as? NSNumber,
   CFGetTypeID(n) != CFBooleanGetTypeID(),
   n.doubleValue.isFinite,n.doubleValue>=0,
   n.doubleValue<1_000_000,
   n.doubleValue==Double(n.intValue) else {return nil}
  return n.intValue
 }
 private static func sha(_ v:Any?) -> String? {
  guard let s=v as? String,s.utf8.count==64,
   s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})
   else {return nil}
  return s
 }
 private static func frac(_ v:Any?) -> [String:Int]? {
  guard let p=v as? [String:Any],let c=int(p["current"]),
   let m=int(p["maximum"]),m>0,m<=9999,c<=m else {return nil}
  return ["current":c,"maximum":m]
 }
 private static func textFrac(_ s:String) -> [String:Int]? {
  var t=s.replacingOccurrences(of:" ",with:"")
   .replacingOccurrences(of:"　",with:"")
  if t.hasPrefix("HP") {t=String(t.dropFirst(2))}
  guard t.range(of:#"^[0-9]{1,4}/[0-9]{1,4}$"#,
   options:.regularExpression) != nil else{return nil}
  let parts=t.split(separator:"/",omittingEmptySubsequences:false)
  guard parts.count==2,let c=Int(parts[0]),let m=Int(parts[1]),
   m>0,c<=m else{return nil}
  return ["current":c,"maximum":m]
 }
 private static func textPercent(_ s:String)->Double? {
  let t=s.replacingOccurrences(of:" ",with:"")
   .replacingOccurrences(of:"　",with:"")
  guard t.range(of:#"^[0-9]{1,3}(\.[0-9]{1,2})?%$"#,
   options:.regularExpression) != nil,
   let d=Double(t.dropLast()),(0...100).contains(d) else{return nil}
  return d
 }
 private static func percent(_ v:Any?) -> Double? {
  guard let n=v as? NSNumber,
   CFGetTypeID(n) != CFBooleanGetTypeID(),
   n.doubleValue.isFinite,(0...100).contains(n.doubleValue)
   else {return nil}
  return n.doubleValue
 }
 private static func rect(_ v:Any?)->[String:Int]? {
  guard let d=v as? [String:Any],
   let x=int(d["x"]),let y=int(d["y"]),
   let w=int(d["width"]),let h=int(d["height"]),
   w>0,h>0 else{return nil}
  return ["x":x,"y":y,"width":w,"height":h]
 }
 static func enrich(_ doc:inout [String:Any],sourceKind:String) {
  doc.removeValue(forKey:"r645_dual_hp")
  doc["r645_status"]="HOLD_MISSING_SHARED_FRAME_PROOF"
  guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
   doc["r642_status"] as? String=="PROVISIONAL_RAW_FRAME_ROIS_ONLY",
   let map=doc["r642_raw_frame_roi_evidence"] as? [String:Any],
   map["schema"] as? String==R642MappedFrameProof.schema,
   map["source_kind"] as? String==sourceKind,
   map["owner_verified"] as? Bool==false,
   map["source_orientation_verified"] as? Bool==false,
   map["current_state_eligible"] as? Bool==false,
   map["battle_advice_authorized"] as? Bool==false,
   int(map["game_fields_certified"])==0,
   let original=sha(map["raw_image_sha256"]),
   let analysis=sha(map["analysis_image_sha256"]),
   let sid=map["capture_session_id"] as? String,!sid.isEmpty,
   let frame=int(map["frame_id"]),frame>0,
   let epoch=int(map["epoch"]),epoch>0,
   let rows=map["mapped_values"] as? [[String:Any]],rows.count<=11,
   doc["r641_status"] as? String=="UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
   let hud=doc["r641_rotated_hud_candidates"] as? [String:Any],
   hud["schema"] as? String==R641RotatedHUDCandidates.schema,
   hud["source_kind"] as? String==sourceKind,
   hud["source_image_sha256"] as? String==analysis,
   hud["owner_verified"] as? Bool==false,
   hud["source_orientation_verified"] as? Bool==false,
   int(hud["game_fields_certified"])==0,
   int(hud["matching_profile_count"])==1,
   let angle=int(hud["rotation_candidate_degrees"]),
   [0,90,180,270].contains(angle),
   let values=hud["candidate_values"] as? [[String:Any]],values.count<=11,
   let snap=doc["screen_read_state"] as? [String:Any],
   snap["image_sha256"] as? String==analysis,
   snap["capture_session_id"] as? String==sid,
   int(snap["frame_id"])==frame,int(snap["epoch"])==epoch,
   snap["owner_certified"] as? Bool != true,
   snap["current_state_eligible"] as? Bool==false,
   snap["battle_advice_authorized"] as? Bool==false,
   let inventory=snap["ocr_source_inventory"] as? [[String:Any]],
   inventory.count<=288,
   let four=doc["r644_four_move_slots"] as? [String:Any],
   four["schema"] as? String==R644MoveSlotCoupler.schema,
   four["source_kind"] as? String==sourceKind,
   four["raw_image_sha256"] as? String==original,
   four["analysis_image_sha256"] as? String==analysis,
   four["capture_session_id"] as? String==sid,
   int(four["frame_id"])==frame,int(four["epoch"])==epoch,
   four["owner_verified"] as? Bool==false,
   four["current_state_eligible"] as? Bool==false,
   four["battle_advice_authorized"] as? Bool==false,
   int(four["game_fields_certified"])==0,
   let fourCount=int(four["matched_pair_count"]),fourCount<=4
  else {return}
  var source=[String:String]()
  for row in inventory {
   guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
    source[ref]==nil,
    let t=row["raw_text"] as? String,!t.isEmpty,
    row["image_sha256"] as? String==analysis,
    row["capture_session_id"] as? String==sid,
    int(row["frame_id"])==frame,int(row["epoch"])==epoch,
    row["owner_verified"] as? Bool==false else {
     doc["r645_status"]="HOLD_INVENTORY_CONTRADICTION";return
    }
   source[ref]=t
  }
  var mapByRef=[String:[String:Any]]()
  for row in rows {
   guard let ref=row["reference"] as? String,!ref.isEmpty,
    mapByRef[ref]==nil,
    row["source_image_sha256"] as? String==original,
    row["analysis_image_sha256"] as? String==analysis,
    row["owner_verified"] as? Bool==false,
    row["current_value_admitted"] as? Bool==false,
    let t=row["raw_text"] as? String,source[ref]==t,
    rect(row["raw_frame_rect"]) != nil else {
     doc["r645_status"]="HOLD_ROI_OR_SOURCE_CONTRADICTION";return
    }
   mapByRef[ref]=row
  }
  let hpRoles=Set(["own_hp","opponent_percent"])
  var found=[String:[String:Any]](),used=Set<String>()
  for val in values {
   guard let role=val["role_hint"] as? String,hpRoles.contains(role)
    else {continue}
   guard found[role]==nil,
    let ref=val["source_ref"] as? String,!ref.isEmpty,
    used.insert(ref).inserted,
    let mapped=mapByRef[ref],
    mapped["role_hint"] as? String==role,
    mapped["slot"] is NSNull,
    let literal=source[ref],
    val["raw_text"] as? String==literal,
    val["source_sha256"] as? String==analysis,
    val["side"] as? String=="UNKNOWN_OWNER",
    val["owner_verified"] as? Bool==false,
    val["orientation_verified"] as? Bool==false,
    val["current_value_admitted"] as? Bool==false,
    val["status"] as? String=="PROVISIONAL_LAYOUT_VALUE_ONLY"
   else {doc["r645_status"]="HOLD_HP_SOURCE_CONTRADICTION";return}
   let verified:Any
   if role=="own_hp" {
    guard let p=frac(val["value"]),p==textFrac(literal) else {
     doc["r645_status"]="HOLD_HP_VALUE_CONTRADICTION";return
    }
    verified=p
   }else {
    guard let p=percent(val["value"]),let raw=textPercent(literal),
     abs(p-raw)<0.000001 else {
     doc["r645_status"]="HOLD_PERCENT_VALUE_CONTRADICTION";return
    }
    verified=p
   }
   found[role]=["value":verified,"source_ref":ref,
    "source_text":literal,"raw_frame_rect":mapped["raw_frame_rect"]!,
    "owner_verified":false,"current_value_admitted":false,
    "status":"HISTORICAL_HUD_POSITION_CANDIDATE_ONLY"]
  }
  let ready=found.count==2
  let status=ready ? "DUAL_HP_SOURCE_BOUND_HISTORICAL_ONLY" :
    "HOLD_INCOMPLETE_DUAL_HP_ANCHORS"
  let receipt:[String:Any]=["schema":schema,"status":status,
   "source_kind":sourceKind,"raw_image_sha256":original,
   "analysis_image_sha256":analysis,"capture_session_id":sid,
   "frame_id":frame,"epoch":epoch,
   "rotation_candidate_degrees":angle,
   "own_position_hp_candidate":found["own_hp"] ?? NSNull() as Any,
   "opponent_position_percent_candidate":found["opponent_percent"] ?? NSNull() as Any,
   "four_move_pairs_on_same_frame":fourCount,
   "owner_verified":false,"source_orientation_verified":false,
   "game_fields_certified":0,"battle_advice_authorized":false,
   "current_state_eligible":false,
   "requires_real_game_ground_truth":true]
  guard JSONSerialization.isValidJSONObject(receipt) else {
   doc["r645_status"]="HOLD_JSON_SERIALIZATION";return
  }
  doc["r645_dual_hp"]=receipt
  doc["r645_status"]=status
 }
}
