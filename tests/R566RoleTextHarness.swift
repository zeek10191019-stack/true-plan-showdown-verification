import Foundation
@main struct R566RoleTextHarness {
 static func main() {
  let hash=String(repeating:"a",count:64)
  func s(_ id:Int,_ str:String)->R553LayoutReading.Site {
   .init(reading:id,rank:0,text:str,confidence:0.9,
    reference:"payload_json.readings[\(id)]",roi:["x":Int64(id*30),"y":10,"width":20,"height":10])
  }
  let samples:[(String,String,Bool)]=[
   ("own_hp","170/185",true), ("own_hp","HP 170/185",true),
   ("own_hp","80%",false), ("own_hp","じしん",false),
   ("own_hp","200/185",false), ("own_hp","200/0",false),
   ("own_hp","PP14/16",false),
   ("opponent_hp","81%",true), ("opponent_hp","100.00%",true),
   ("opponent_hp","101%",false), ("opponent_hp","-1%",false),
   ("own_name","メガギャラドス",true), ("own_name","55/100",false),
   ("opponent_name","ガブリアス♂",true), ("opponent_name","80%",false),
   ("move_name","10まんボルト",true), ("move_name","じしん",true),
   ("move_name","14/16",false), ("move_pp","PP 14/16",true),
   ("move_pp","0/64",true), ("move_pp","65/65",false),
   ("move_pp","ハイパーボイス",false), ("move_pp","HP14/16",false),
   ("mega_form","メガギャラドス",false)
  ]
  for (i,v) in samples.enumerated() {
   let got=R566RoleTextFence.inspect(role:v.0,site:s(i,v.1))
   assert(got==v.2,"test \(i) \(v.0) \(v.1)")
   print("PASS_R566_TEXT_\(i)")
  }
  let sites=[s(0,"じしん"),s(1,"81%")]
  func hint(_ role:String,_ i:Int)->[String:Any]{
   ["role_hint":role,"slot":NSNull(),"verification":"POSITION_ONLY_UNVERIFIED",
    "current_state_eligible":false,"knowledge_state":"INFERRED",
    "evidence_refs":[sites[i].reference],"rois":[sites[i].roi]]
  }
  let base:[String:Any]=["status":"PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION",
   "owner_certified":false,"current_state_eligible":false,
   "capture_session_id":"session","frame_id":Int64(8),"epoch":Int64(2),
   "image_sha256":hash,"hints":[hint("own_hp",0),hint("opponent_hp",1)]]
  func inspect(_ initial:[String:Any],_ lines:[R553LayoutReading.Site]=sites)->[String:Any]{
   R565SourceEvidenceFence.report(base:initial,sites:lines,session:"session",frame:8,epoch:2,imageSHA:hash)
  }
  let failed=inspect(base)
  assert(failed["status"] as? String=="HOLD_R566_ROLE_TEXT_MISMATCH")
  assert(failed["role_text_checked"] as? Bool==false)
  assert((failed["hints"] as? [[String:Any]])?.isEmpty==true)
  print("PASS_R566_WRONG_HP_STRING_REJECT")
  let good=[s(0,"170/185"),sites[1]]
  let ok=inspect(base,good)
  assert(ok["status"] as? String=="PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  assert(ok["role_text_checked"] as? Bool==true && ok["owner_certified"] as? Bool==false)
  print("PASS_R566_GOOD_SOURCE_REMAINS_UNVERIFIED")
  let altered=[s(0,"170/185"),s(1,"0/0")]
  let fail2=inspect(base,altered)
  assert(fail2["status"] as? String=="HOLD_R566_ROLE_TEXT_MISMATCH")
  print("PASS_R566_INVALID_OPP_HP_REJECT")
  print("PASS_R566_27_TESTS")
 }
}
