import Foundation
@main struct R636CompactHarness {
 static func main() {
  let sha=String(repeating:"a",count:64)
  var n=0
  func ok(_ b:Bool){precondition(b);n+=1}
  func p(_ role:String,_ v:Any,_ slot:Any=NSNull())->[String:Any] {
   ["role_hint":role,"unverified_value":v,"slot_candidate":slot,
    "source_image_sha256":sha,"status":"HISTORICAL_LAYOUT_HYPOTHESIS_NOT_CERTIFIED",
    "side":"UNKNOWN_OWNER","owner_verified":false,
    "screen_orientation_verified":false,"current_value_admitted":false,
    "knowledge_state":"INFERRED","evidence_refs":["r0"],"raw_texts":["17/20"]]
  }
  let values:[(String,[String:Any])]=[
   ("own.hp",p("own_hp",["current":17,"maximum":20])),
   ("own.hp_max",p("own_hp",["current":17,"maximum":20])),
   ("opponent.hp_percent",p("opponent_hp",81)),
   ("own.moves_four",p("move_name","じしん",0)),
   ("own.pp_four",p("move_pp",["current":8,"maximum":10],0))]
  var rows=values.map{["field":$0.0,"r635_structured_layout_candidates":[$0.1]] as [String:Any]}
  for i in 0..<74 {rows.append(["field":"other.\(i)"])}
  let cover:[String:Any]=["source_kind":"LIVE_RETAINED_FRAME",
   "r635_schema":R635LayoutToFields.schema,"r635_verified_game_fields":0,
   "fields":rows]
  func run(_ r:[[String:Any]],_ sha:String=sha,_ status:String="LAYOUT_HYPOTHESES_ATTACHED_WITHOUT_PROMOTION")->[String:Any] {
   var d:[String:Any]=["r635_layout_status":status,
    "screen_read_state":["image_sha256":sha,
     "current_state_eligible":false,"battle_advice_authorized":false],
    "r581_full_read_coverage":cover.merging(["fields":r]){$1}]
   R636TypedHUDEvidence.enrich(&d,sourceKind:"LIVE_RETAINED_FRAME")
   return d
  }
  let d=run(rows)
  let c=d["r581_full_read_coverage"] as! [String:Any]
  let f=c["fields"] as! [[String:Any]]
  ok(c["r636_typed_fields"] as? Int==5)
  ok(c["r636_verified_game_fields"] as? Int==0)
  ok(f.count==79)
  ok(f.allSatisfy{$0["current_value_admitted"] as? Bool==false})
  ok(JSONSerialization.isValidJSONObject(d))
  var r=rows;r[0]["r635_structured_layout_candidates"]=[p("opponent_hp",81)]
  var x=run(r)["r581_full_read_coverage"] as! [String:Any]
  ok(((x["fields"] as! [[String:Any]])[0]["r636_typed_candidates"] as! [[String:Any]]).isEmpty)
  r=rows;r[4]["r635_structured_layout_candidates"]=[p("move_pp",["current":11,"maximum":10],0)]
  x=run(r)["r581_full_read_coverage"] as! [String:Any]
  ok(((x["fields"] as! [[String:Any]])[4]["r636_typed_candidates"] as! [[String:Any]]).isEmpty)
  x=run(rows,String(repeating:"b",count:64))["r581_full_read_coverage"] as! [String:Any]
  ok(((x["fields"] as! [[String:Any]])[0]["r636_typed_candidates"] as! [[String:Any]]).isEmpty)
  ok(run(rows,sha,"HOLD_DUPLICATE_ROLE_SLOT")["r636_status"] as? String=="HOLD_UNBOUND_SOURCE")
  ok((f[3]["r636_typed_candidates"] as! [[String:Any]])[0]["slot"] as? Int==0)
  print("R636_TYPED_HUD_PASS",n)
 }
}
