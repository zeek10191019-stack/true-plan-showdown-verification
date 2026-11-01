import Foundation
import CoreFoundation

/// Four move-name/PP pairs from OCR on one historical image.
/// A slot candidate is never a current battle value or an owner proof.
enum R644MoveSlotCoupler {
 static let schema="trueplan.r644.four-move-pp-pairs.v1"
 private static func num(_ v:Any?)->Int? {
  guard let n=v as? NSNumber,
   CFGetTypeID(n) != CFBooleanGetTypeID(),
   n.doubleValue.isFinite,n.doubleValue>=0,
   n.doubleValue<1_000_000,
   n.doubleValue==Double(n.intValue) else{return nil}
  return n.intValue
 }
 private static func sha(_ x:Any?)->String? {
  guard let s=x as? String,s.utf8.count==64,
   s.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})
   else{return nil}
  return s
 }
 private static func pp(_ value:Any?)->[String:Int]? {
  guard let d=value as? [String:Any],
   let a=num(d["current"]),let b=num(d["maximum"]),
   b>0,b<=64,a<=b else{return nil}
  return ["current":a,"maximum":b]
 }
 private static func digits(_ text:String)->Int? {
  guard !text.isEmpty,text.count<=4,
   text.utf8.allSatisfy({(48...57).contains($0)}),
   let v=Int(text) else{return nil}
  return v
 }
 private static func literalPP(_ s:String)->[String:Int]? {
  var t=s.replacingOccurrences(of:" ",with:"")
   .replacingOccurrences(of:"　",with:"")
  if t.hasPrefix("HP") {t=String(t.dropFirst(2))}
  let parts=t.split(separator:"/",omittingEmptySubsequences:false)
  guard parts.count==2,let a=digits(String(parts[0])),
   let b=digits(String(parts[1])),b>0,b<=64,a<=b else{return nil}
  return ["current":a,"maximum":b]
 }
 private static func splitNumerator(_ raw:String)->Int? {
  var t=raw.replacingOccurrences(of:" ",with:"")
   .replacingOccurrences(of:"　",with:"")
  if t.uppercased().hasPrefix("PP") {
   t=String(t.dropFirst(2))
   if t.hasPrefix(":") || t.hasPrefix("：") {t.removeFirst()}
  }
  guard (1...2).contains(t.count),let v=digits(t),v<=64 else{return nil}
  return v
 }
 private static func splitDenominator(_ raw:String)->Int? {
  let t=raw.replacingOccurrences(of:" ",with:"")
   .replacingOccurrences(of:"　",with:"")
  guard t.hasPrefix("/"),let v=digits(String(t.dropFirst())),
   (1...2).contains(t.count-1),v>0,v<=64 else{return nil}
  return v
 }
 static func enrich(_ doc:inout [String:Any],sourceKind:String) {
  doc.removeValue(forKey:"r644_four_move_slots")
  doc["r644_status"]="HOLD_UNBOUND_PARENT_EVIDENCE"
  guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
   doc["r642_status"] as? String=="PROVISIONAL_RAW_FRAME_ROIS_ONLY",
   let base=doc["r642_raw_frame_roi_evidence"] as? [String:Any],
   base["schema"] as? String=="trueplan.r642.raw-frame-roi-evidence.v1",
   base["source_kind"] as? String==sourceKind,
   base["owner_verified"] as? Bool==false,
   base["source_orientation_verified"] as? Bool==false,
   base["battle_advice_authorized"] as? Bool==false,
   num(base["game_fields_certified"])==0,
   let frame=num(base["frame_id"]),frame>0,
   let epoch=num(base["epoch"]),epoch>0,
   let sid=base["capture_session_id"] as? String,!sid.isEmpty,
   let rawSHA=sha(base["raw_image_sha256"]),
   let analysisSHA=sha(base["analysis_image_sha256"]),
   let mapped=base["mapped_values"] as? [[String:Any]],mapped.count<=11,
   doc["r641_status"] as? String=="UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
   let hud=doc["r641_rotated_hud_candidates"] as? [String:Any],
   hud["schema"] as? String=="trueplan.r641.four-way-independent-layout.v1",
   hud["source_kind"] as? String==sourceKind,
   hud["source_image_sha256"] as? String==analysisSHA,
   num(hud["matching_profile_count"])==1,
   hud["source_orientation_verified"] as? Bool==false,
   hud["owner_verified"] as? Bool==false,
   let typed=hud["candidate_values"] as? [[String:Any]],typed.count<=11,
   let snap=doc["screen_read_state"] as? [String:Any],
   snap["image_sha256"] as? String==analysisSHA,
   snap["capture_session_id"] as? String==sid,
   num(snap["frame_id"])==frame,
   num(snap["epoch"])==epoch,
   snap["current_state_eligible"] as? Bool==false,
   snap["battle_advice_authorized"] as? Bool==false,
   let inv=snap["ocr_source_inventory"] as? [[String:Any]],inv.count<=288 else{return}
  var sources=[String:String]()
  for row in inv {
   guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
    sources[ref]==nil,
    let text=row["raw_text"] as? String,!text.isEmpty,
    row["image_sha256"] as? String==analysisSHA,
    row["capture_session_id"] as? String==sid,
    num(row["frame_id"])==frame,
    num(row["epoch"])==epoch,
    row["owner_verified"] as? Bool==false else {
    doc["r644_status"]="HOLD_OCR_INVENTORY_CONFLICT";return
   }
   sources[ref]=text
  }
  var parent=[String:[String:Any]]()
  for row in mapped {
   guard let ref=row["reference"] as? String,!ref.isEmpty,
    parent[ref]==nil,
    row["source_image_sha256"] as? String==rawSHA,
    row["analysis_image_sha256"] as? String==analysisSHA,
    row["owner_verified"] as? Bool==false,
    row["current_value_admitted"] as? Bool==false,
    let text=row["raw_text"] as? String,
    sources[ref]==text else {
    doc["r644_status"]="HOLD_MAPPED_REFERENCE_CONFLICT";return
   }
   parent[ref]=row
  }
  struct Candidate {let value:Any;let refs:[String];let kind:String}
  var names=[Int:Candidate](),whole=[Int:Candidate]()
  var used=Set<String>()
  for row in typed {
   guard let role=row["role_hint"] as? String,
    let ref=row["source_ref"] as? String,!ref.isEmpty,
    let src=parent[ref],let slot=num(row["slot"]),slot<4,
    row["source_sha256"] as? String==analysisSHA,
    row["side"] as? String=="UNKNOWN_OWNER",
    row["owner_verified"] as? Bool==false,
    row["current_value_admitted"] as? Bool==false,
    row["raw_text"] as? String==sources[ref] else {
    if ["move_name","move_pp"].contains(row["role_hint"] as? String ?? "") {
     doc["r644_status"]="HOLD_TYPED_REFERENCE_CONFLICT";return
    }
    continue
   }
   guard role=="move_name" || role=="move_pp" else{continue}
   guard src["role_hint"] as? String==role,
    num(src["slot"])==slot,used.insert(ref).inserted else {
    doc["r644_status"]="HOLD_SLOT_OR_REFERENCE_REUSED";return
   }
   if role=="move_name" {
    guard names[slot]==nil,let s=row["value"] as? String,
     (2...24).contains(s.count),
     s == (sources[ref] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
     else {
     doc["r644_status"]="HOLD_DUPLICATE_MOVE_NAME";return
    }
    names[slot]=Candidate(value:s,refs:[ref],kind:"SINGLE_OCR_NAME")
   }else {
    guard whole[slot]==nil,let parsed=pp(row["value"]),
     parsed == literalPP(sources[ref] ?? "") else {
     doc["r644_status"]="HOLD_DUPLICATE_OR_INVALID_PP";return
    }
    whole[slot]=Candidate(value:parsed,refs:[ref],kind:"WHOLE_OCR_PP")
   }
  }
  var split=[Int:Candidate](),ambiguous=Set<Int>()
  if let state=doc["r643_status"] as? String,
   state=="PROVISIONAL_PP_FRAGMENTS_ONLY" ||
   state=="HOLD_AMBIGUOUS_PP_FRAGMENTS" ||
   state=="HOLD_NO_SPLIT_PP_MATCH" {
   guard let report=doc["r643_split_pp_evidence"] as? [String:Any],
    report["schema"] as? String=="trueplan.r643.split-pp-evidence.v1",
    report["source_kind"] as? String==sourceKind,
    report["raw_image_sha256"] as? String==rawSHA,
    report["analysis_image_sha256"] as? String==analysisSHA,
    report["capture_session_id"] as? String==sid,
    num(report["frame_id"])==frame,
    num(report["epoch"])==epoch,
    report["owner_verified"] as? Bool==false,
    num(report["game_fields_certified"])==0,
    let rows=report["split_pp_candidates"] as? [[String:Any]],rows.count<=4,
    let ambiguities=report["ambiguous_slots"] as? [Int] else {
    doc["r644_status"]="HOLD_SPLIT_PP_REPORT_CONFLICT";return
   }
   for slot in ambiguities {
    guard (0..<4).contains(slot),ambiguous.insert(slot).inserted else {
     doc["r644_status"]="HOLD_INVALID_AMBIGUITY_SLOT";return
    }
   }
   for r in rows {
    guard let slot=num(r["slot"]),slot<4,split[slot]==nil,
     whole[slot]==nil,!ambiguous.contains(slot),
     let refs=r["source_refs"] as? [String],refs.count==2,
     refs[0] != refs[1],
     let texts=r["raw_texts"] as? [String],texts.count==2,
     sources[refs[0]]==texts[0],sources[refs[1]]==texts[1],
     !used.contains(refs[0]),!used.contains(refs[1]),
     let pair=pp(["current":r["current"] ?? NSNull(),
                   "maximum":r["maximum"] ?? NSNull()]),
     splitNumerator(texts[0])==pair["current"],
     splitDenominator(texts[1])==pair["maximum"] else {
     doc["r644_status"]="HOLD_SPLIT_PP_COLLISION";return
    }
    used.formUnion(refs)
    split[slot]=Candidate(value:pair,refs:refs,kind:"SPLIT_OCR_PP")
   }
  }else if doc["r643_status"] as? String=="HOLD_REUSED_OCR_REFERENCE" {
   doc["r644_status"]="HOLD_UPSTREAM_REUSED_REFERENCE";return
  }
  let pairs:[[String:Any]]=(0..<4).map{slot in
   let name=names[slot],p=whole[slot] ?? split[slot]
   return ["slot":slot,"name":name?.value ?? NSNull(),
    "pp":p?.value ?? NSNull(),
    "name_refs":name?.refs ?? [],"pp_refs":p?.refs ?? [],
    "pp_method":p?.kind ?? "NONE",
    "status":ambiguous.contains(slot) ? "HOLD_AMBIGUOUS_PP" :
     name != nil && p != nil ? "COUPLED_OCR_CANDIDATE_ONLY" :
     name != nil ? "MOVE_NAME_ONLY" :
     p != nil ? "PP_ONLY" : "UNKNOWN",
    "owner_verified":false,"current_value_admitted":false]
  }
  let complete=pairs.filter{$0["status"] as? String=="COUPLED_OCR_CANDIDATE_ONLY"}.count
  let state=ambiguous.isEmpty ?
   (complete==4 ? "FOUR_HISTORICAL_PAIRS_UNCERTIFIED" :
    "PARTIAL_HISTORICAL_PAIRS_UNCERTIFIED") :
    "HOLD_AMBIGUOUS_PP_SLOTS"
  let output:[String:Any]=["schema":schema,"source_kind":sourceKind,
   "raw_image_sha256":rawSHA,"analysis_image_sha256":analysisSHA,
   "capture_session_id":sid,"frame_id":frame,"epoch":epoch,
   "four_slots":pairs,"matched_pair_count":complete,
   "ambiguous_pp_slots":ambiguous.sorted(),"status":state,
   "owner_verified":false,"source_orientation_verified":false,
   "game_fields_certified":0,"battle_advice_authorized":false,
   "current_state_eligible":false,"requires_real_game_ground_truth":true]
  guard JSONSerialization.isValidJSONObject(output) else {
   doc["r644_status"]="HOLD_INVALID_JSON";return
  }
  doc["r644_four_move_slots"]=output
  doc["r644_status"]=state
 }
}
