import Foundation
@main struct R666Smoke {
 static func main() {
  let cases:[(String,String,String)]=[
   ("own.hp","148/197","HP_FRACTION_CANDIDATE"),
   ("own.hp_percent","81%","HP_PERCENT_CANDIDATE"),
   ("own.pp_four","10/16","MOVE_PP_FRACTION_CANDIDATE"),
   ("own.major_status","やけど","STATUS_TEXT_CANDIDATE"),
   ("own.gender","♀","GENDER_GLYPH_CANDIDATE"),
   ("battle.turn","3ターン","TURN_TEXT_CANDIDATE"),
   ("own.mega_trigger","メガシンカ","TEXT_MENTION_NOT_EFFECT_PROOF")]
  for (f,t,k) in cases {
   precondition(R666TypedOCRCandidates.decode(
    field:f,text:t)["kind"] as? String == k)
  }
  let empty=R666TypedOCRCandidates.audit(
   [:],sourceKind:"LIVE_RETAINED_FRAME")
  precondition((empty["status"] as? String)?.hasPrefix("HOLD_")==true)
  precondition(empty["game_fields_certified"] as? Int==0)
  print("R666_TYPED_OCR_SMOKE_PASS 9")
 }
}
