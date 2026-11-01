import Foundation
import CoreFoundation

/// Typed evidence hypotheses only. No owner assignment or current-state promotion.
enum R636TypedHUDEvidence {
 static let schema="trueplan.r636.typed-hud-hypotheses.v1"
 private static let roles=["own.hp":"own_hp","own.hp_max":"own_hp",
  "opponent.hp_percent":"opponent_hp","own.moves_four":"move_name",
  "own.pp_four":"move_pp"]
 private static func num(_ x:Any?) -> Double? {
  guard let n=x as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
   n.doubleValue.isFinite else{return nil}
  return n.doubleValue
 }
 private static func integer(_ x:Any?,_ limit:Int)->Int? {
  guard let n=num(x),n>=0,n<=Double(limit),n.rounded(.towardZero)==n
   else{return nil}
  return Int(n)
 }
 private static func parse(_ role:String,_ v:Any)->Any? {
  if role=="own_hp" || role=="move_pp" {
   guard let p=v as? [String:Any],let c=integer(p["current"],9999),
    let m=integer(p["maximum"],9999),m>0,c<=m,
    (role != "move_pp" || m<=64) else{return nil}
   return ["current":c,"maximum":m]
  }
  if role=="opponent_hp" {
   guard let v=num(v),(0...100).contains(v) else{return nil}
   return v
  }
  if role=="move_name" {
   guard let s=v as? String,(2...24).contains(s.count),
    s==s.trimmingCharacters(in:.whitespacesAndNewlines),
    !s.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)})
    else{return nil}
   return s
  }
  return nil
 }
 static func enrich(_ doc:inout [String:Any],sourceKind:String) {
  guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
   doc["r635_layout_status"] as? String=="LAYOUT_HYPOTHESES_ATTACHED_WITHOUT_PROMOTION",
   let snap=doc["screen_read_state"] as? [String:Any],
   snap["current_state_eligible"] as? Bool==false,
   snap["battle_advice_authorized"] as? Bool==false,
   let sha=snap["image_sha256"] as? String,sha.utf8.count==64,
   sha.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}),
   let cover=doc["r581_full_read_coverage"] as? [String:Any],
   cover["source_kind"] as? String==sourceKind,
   cover["r635_schema"] as? String==R635LayoutToFields.schema,
   cover["r635_verified_game_fields"] as? Int==0,
   let rows=cover["fields"] as? [[String:Any]],rows.count==79,
   Set(rows.compactMap{$0["field"] as? String}).count==79 else {
   doc["r636_status"]="HOLD_UNBOUND_SOURCE";return
  }
  var output=[[String:Any]]();var count=0;var rejected=0
  for row in rows {
   var rec=row;var typed=[[String:Any]]()
   if let key=row["field"] as? String,let role=roles[key],
    let items=row["r635_structured_layout_candidates"] as? [[String:Any]] {
    for p in items.prefix(4) {
     guard p["role_hint"] as? String==role,
      p["source_image_sha256"] as? String==sha,
      p["status"] as? String=="HISTORICAL_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
      p["side"] as? String=="UNKNOWN_OWNER",
      p["owner_verified"] as? Bool==false,
      p["screen_orientation_verified"] as? Bool==false,
      p["current_value_admitted"] as? Bool==false,
      p["knowledge_state"] as? String=="INFERRED",
      let refs=p["evidence_refs"] as? [String],
      let texts=p["raw_texts"] as? [String],(1...4).contains(refs.count),
      refs.count==texts.count,Set(refs).count==refs.count,
      refs.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}),
      texts.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}),
      let v=p["unverified_value"],let parsed=parse(role,v) else {
      rejected+=1;continue
     }
     let slot=p["slot_candidate"] as? Int
     if role=="move_name" || role=="move_pp" {
      guard let slot,(0...3).contains(slot) else{rejected+=1;continue}
     } else if slot != nil {rejected+=1;continue}
     typed.append(["value":parsed,"source_sha":sha,
      "slot":slot.map{$0 as Any} ?? NSNull(),"refs":refs,
      "owner_verified":false,"current_value_admitted":false,
      "status":"HISTORICAL_TYPED_HYPOTHESIS_ONLY"])
    }
   }
   rec["r636_typed_candidates"]=typed
   rec["current_value_admitted"]=false
   rec["reader_producing_verified_game_value"]=false
   if !typed.isEmpty {count+=1}
   output.append(rec)
  }
  var changed=cover;changed["fields"]=output
  changed["r636_schema"]=schema
  changed["r636_typed_fields"]=count
  changed["r636_rejected_candidates"]=rejected
  changed["r636_verified_game_fields"]=0
  doc["r581_full_read_coverage"]=changed
  doc["r636_status"]="TYPED_HYPOTHESES_ONLY_NO_OWNER_PROOF"
 }
}
