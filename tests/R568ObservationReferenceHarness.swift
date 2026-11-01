import Foundation

@main struct R568ObservationReferenceHarness {
 static func main() {
  let hash=String(repeating:"a",count:64)
  let rect:[String:Int64]=["x":95,"y":220,"width":30,"height":10]
  func site(_ reading:Int,_ rank:Int=0,_ text:String="120/170",_ ref:String?=nil)->R553LayoutReading.Site {
   let canonical="payload_json.readings[\(reading)]"+(rank==0 ? "" : ".ocr_alternatives[\(rank)]")
   return .init(reading:reading,rank:rank,text:text,confidence:0.91,
     reference:ref ?? canonical,roi:rect)
  }
  let valid:[R553LayoutReading.Site]=[site(0),site(0,1),site(0,2),site(511,31)]
  for (i,s) in valid.enumerated(){assert(R568ObservationReferenceFence.canonical(s));print("PASS_R568_CANONICAL_\(i)")}
  let invalid:[R553LayoutReading.Site]=[
   site(0,0,"120/170","payload_json.readings[1]"),
   site(0,1,"120/170","payload_json.readings[0]"),
   site(0,0,"120/170","payload_json.readings[0].ocr_alternatives[0]"),
   site(0,1,"120/170","payload_json.readings[0].ocr_alternatives[2]"),
   site(0,1,"120/170","payload_json.readings[0].ocr_alternatives[01]"),
   site(0,0,"120/170","payload_json.readings[00]"),
   site(0,0,"120/170","payload_json.readings[0]suffix"),
   site(0,0,"120/170","payload_json.readings[0].ocr_alternatives[1]"),
   site(0,0,"120/170","payload_json.readings[-1]"),
   site(0,0,"120/170","payload_json.readings[0][0]"),
   site(512),site(-1),site(0,32),site(0,-1)
  ]
  for (i,s) in invalid.enumerated(){assert(!R568ObservationReferenceFence.canonical(s));print("PASS_R568_REFERENCE_REJECT_\(i)")}
  func hint(_ role:String,_ sources:[R553LayoutReading.Site])->[String:Any]{
   ["role_hint":role,"slot":NSNull(),"verification":"POSITION_ONLY_UNVERIFIED",
    "current_state_eligible":false,"knowledge_state":"INFERRED",
    "evidence_refs":sources.map(\.reference),"rois":sources.map(\.roi)]
  }
  func check(_ hints:[[String:Any]],_ sites:[R553LayoutReading.Site],_ expected:String){
   let b:[String:Any]=["status":"PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION",
    "owner_certified":false,"current_state_eligible":false,
    "capture_session_id":"session","frame_id":Int64(7),"epoch":Int64(2),
    "image_sha256":hash,"hints":hints]
   let out=R565SourceEvidenceFence.report(base:b,sites:sites,session:"session",frame:7,epoch:2,imageSHA:hash)
   assert(out["status"] as? String == expected,"status = \(out["status"] ?? "nil")")
   assert(out["owner_certified"] as? Bool == false)
   assert(out["current_state_eligible"] as? Bool == false)
   assert(out["battle_advice_authorized"] as? Bool == false)
   if expected.hasPrefix("HOLD") {assert((out["hints"] as? [[String:Any]])?.isEmpty == true)}
  }
  let primary=site(0),alternative=site(0,1),other=site(1,0,"70%")
  check([hint("own_hp",[primary])],[primary],"PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  print("PASS_R568_PRIMARY_INTEGRATION")
  check([hint("own_hp",[primary,alternative])],[primary,alternative],"PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  print("PASS_R568_SAME_HINT_ALTERNATIVES_ALLOWED")
  check([hint("own_hp",[primary]),hint("opponent_hp",[alternative])],[primary,alternative],"HOLD_R568_OBSERVATION_REUSED_ACROSS_HINTS")
  print("PASS_R568_CROSS_ROLE_ALTERNATIVE_REJECTED")
  check([hint("own_hp",[primary]),hint("opponent_hp",[other])],[primary,other],"PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  print("PASS_R568_DIFFERENT_READINGS_ALLOWED")
  let bad=site(0,0,"120/170","payload_json.readings[1]")
  check([hint("own_hp",[bad])],[bad],"HOLD_R565_MALFORMED_SOURCE_SITE")
  print("PASS_R568_FORGED_SITE_REJECTED_AND_CLEARED")
  let wrongRank=site(0,1,"120/170","payload_json.readings[0].ocr_alternatives[5]")
  check([hint("own_hp",[wrongRank])],[wrongRank],"HOLD_R565_MALFORMED_SOURCE_SITE")
  print("PASS_R568_MISMATCHED_ALTERNATIVE_RANK_REJECTED")
  let pp0=site(0,0,"14/16"),pp1=site(1,0,"14/16")
  assert(!R567EvidenceGroupFence.inspect(role:"move_pp",sites:[pp0,pp1]))
  print("PASS_R568_DUPLICATE_FULL_PP_OTHER_OBSERVATION_REJECTED")
  let ppAlt=site(0,1,"14/16")
  assert(R567EvidenceGroupFence.inspect(role:"move_pp",sites:[pp0,ppAlt]))
  print("PASS_R568_DUPLICATE_FULL_PP_SAME_OBSERVATION_ALLOWED")
  print("PASS_R568_ALL_26_CASES")
 }
}
