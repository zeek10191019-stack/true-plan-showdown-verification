import Foundation
@main struct R569RoleConsensusHarness {
 static func main() {
  let sha=String(repeating:"a",count:64)
  let rect:[String:Int64]=["x":95,"y":220,"width":30,"height":10]
  func s(_ i:Int,_ value:String,_ rank:Int=0)->R553LayoutReading.Site {
   let ref="payload_json.readings[\(i)]"+(rank==0 ? "" : ".ocr_alternatives[\(rank)]")
   return .init(reading:i,rank:rank,text:value,confidence:0.8,reference:ref,roi:rect)
  }
  let direct:[(String,[String],Bool)]=[
   ("own_hp",["170/185"],true),
   ("own_hp",["HP 170/185","170/185"],true),
   ("own_hp",["170/185","171/185"],false),
   ("own_hp",["170/185","170/186"],false),
   ("own_hp",["170/185","80%"],false),
   ("own_hp",["80%"],false),
   ("own_hp",["170/185","じしん"],false),
   ("opponent_hp",["81%","81.00%"],true),
   ("opponent_hp",["81.0%","81%"],true),
   ("opponent_hp",["0.05%","0.05%"],true),
   ("opponent_hp",["81%","80%"],false),
   ("opponent_hp",["81%","81/100"],false),
   ("opponent_hp",["100.00%","100%"],true),
   ("opponent_hp",["100%","100.01%"],false),
   ("opponent_hp",["170/185","HP 170/185"],true),
   ("opponent_hp",["170/185","171/185"],false),
   ("own_name",["ガブリアス","ガブリアス"],true),
   ("own_name",["ガブリアス","ギャラドス"],false),
   ("opponent_name",["メガギャラドス","ギャラドス"],false),
   ("move_name",["ハイパーボイス","ハイパーボイス"],true),
   ("move_name",["ハイパーボイス","ハイパーポイス"],false),
   ("move_name",["じしん","じしん"],true),
   ("move_name",["じしん","ステルスロック"],false),
   ("move_name",["14/16"],false),
   ("mega_form",["メガギャラドス"],false),
   ("own_hp",[],false),
   ("move_pp",["14/16"],false)
  ]
  for (i,t) in direct.enumerated() {
   let sites=t.1.enumerated().map { j,v in s(0,v,j) }
   let got=R569RoleConsensusFence.inspect(role:t.0,sites:sites)
   assert(got==t.2,"R569 direct \(i): \(got) expected \(t.2)")
   print("PASS_R569_CONSENSUS_\(i)")
  }
  func integration(_ values:[String],role:String,expected:String) {
   let sites=values.enumerated().map {i,t in s(0,t,i)}
   let base:[String:Any]=[
    "status":"PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION",
    "owner_certified":false,"current_state_eligible":false,
    "capture_session_id":"session","frame_id":Int64(12),"epoch":Int64(2),
    "image_sha256":sha,"hints":[["role_hint":role,"slot":NSNull(),
      "verification":"POSITION_ONLY_UNVERIFIED","knowledge_state":"INFERRED",
      "current_state_eligible":false,"evidence_refs":sites.map(\.reference),
      "rois":sites.map(\.roi)]]]
   let out=R565SourceEvidenceFence.report(base:base,sites:sites,
       session:"session",frame:12,epoch:2,imageSHA:sha)
   assert(out["status"] as? String == expected, "\(out["status"] ?? "nil")")
   assert(out["owner_certified"] as? Bool == false)
   assert(out["current_state_eligible"] as? Bool == false)
   assert(out["battle_advice_authorized"] as? Bool == false)
   if expected.hasPrefix("HOLD"){
    assert((out["hints"] as? [[String:Any]])?.isEmpty == true)
    assert(out["semantic_consensus_checked"] as? Bool == false)
   } else {
    assert(out["semantic_consensus_checked"] as? Bool == true)
   }
  }
  integration(["170/185","171/185"],role:"own_hp",expected:"HOLD_R569_AMBIGUOUS_ROLE_VALUE")
  print("PASS_R569_INTEGRATION_CONFLICT")
  integration(["170/185","HP 170/185"],role:"own_hp",expected:"PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  print("PASS_R569_INTEGRATION_CONSENSUS")
  integration(["81%","80%"],role:"opponent_hp",expected:"HOLD_R569_AMBIGUOUS_ROLE_VALUE")
  print("PASS_R569_INTEGRATION_OPP_CONFLICT")
  integration(["ガブリアス","ガブリアス"],role:"own_name",expected:"PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  print("PASS_R569_INTEGRATION_NAME_SAME")
  integration(["メガギャラドス","ギャラドス"],role:"opponent_name",expected:"HOLD_R569_AMBIGUOUS_ROLE_VALUE")
  print("PASS_R569_INTEGRATION_MEGA_NAME_CONFLICT")
  print("PASS_R569_ALL_32_CASES")
 }
}
