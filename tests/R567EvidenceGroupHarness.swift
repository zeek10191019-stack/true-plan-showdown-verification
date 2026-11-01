import Foundation
@main struct R567EvidenceGroupHarness {
 static func main(){
  let hash=String(repeating:"a",count:64)
  func site(_ index:Int,_ text:String,_ y:Int64=10,_ x:Int64=300,_ rank:Int=0,_ reading:Int?=nil)->R553LayoutReading.Site {
   R553LayoutReading.Site(reading:reading ?? index,rank:rank,text:text,confidence:0.9,
    reference:"payload_json.readings[\(index)]",roi:["x":x,"y":y,"width":20,"height":10])
  }
  let cases:[(String,[R553LayoutReading.Site],Bool)]=[
   ("single_full",[site(0,"14/16")],true),
   ("full_with_prefix",[site(0,"PP 14/16")],true),
   ("zero_pp",[site(0,"0/16")],true),
   ("full_alternatives_agree",[site(0,"14/16"),site(1,"PP14/16",10,300,1,0)],true),
   ("split_slash",[site(0,"14",10),site(1,"/16",25)],true),
   ("split_zero",[site(0,"0",10),site(1,"/64",25)],true),
   ("split_reverse",[site(0,"14",25),site(1,"/16",10)],false),
   ("split_far_x",[site(0,"14",10,300),site(1,"/16",25,490)],false),
   ("split_far_y",[site(0,"14",10),site(1,"/16",200)],false),
   ("split_same_reading",[site(0,"14",10),site(1,"/16",25,300,0,0)],false),
   ("split_over_max",[site(0,"18",10),site(1,"/16",25)],false),
   ("split_over_64",[site(0,"14",10),site(1,"/65",25)],false),
   ("split_zero_max",[site(0,"0",10),site(1,"/0",25)],false),
   ("split_missing_slash",[site(0,"14",10),site(1,"16",25)],false),
   ("split_with_noise",[site(0,"14",10),site(1,"/16",25),site(2,"じしん",40)],false),
   ("mixed_full_split",[site(0,"14/16",10),site(1,"/16",25)],false),
   ("conflicting_full",[site(0,"14/16"),site(1,"13/16",10,300,1,0)],false),
   ("negative_x",[site(0,"14",10,-1),site(1,"/16",25)],false),
   ("empty",[],false),
   ("nonsense",[site(0,"地震")],false),
   ("own_hp",[site(0,"170/185")],true),
   ("own_hp_wrong",[site(0,"じしん")],false),
   ("name",[site(0,"ガブリアス♂")],true),
   ("name_wrong",[site(0,"14/16")],false)
  ]
  for (i,t) in cases.enumerated(){
   let role=t.0.hasPrefix("own_hp") ? "own_hp" : t.0.hasPrefix("name") ? "own_name" : "move_pp"
   let pass=R567EvidenceGroupFence.inspect(role:role,sites:t.1)
   assert(pass==t.2,"R567 \(t.0) expected \(t.2), got \(pass)")
   print("PASS_R567_\(i)_\(t.0)")
  }
  let good=[site(0,"14",10),site(1,"/16",25)]
  func hint(_ sites:[R553LayoutReading.Site])->[String:Any] {
   ["role_hint":"move_pp","slot":0,"verification":"POSITION_ONLY_UNVERIFIED",
    "current_state_eligible":false,"knowledge_state":"INFERRED",
    "evidence_refs":sites.map(\.reference),"rois":sites.map(\.roi)]
  }
  func report(_ sites:[R553LayoutReading.Site])->[String:Any] {
   let base:[String:Any]=["status":"PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION",
    "owner_certified":false,"current_state_eligible":false,
    "capture_session_id":"session","frame_id":Int64(9),"epoch":Int64(2),
    "image_sha256":hash,"hints":[hint(sites)]]
   return R565SourceEvidenceFence.report(base:base,sites:sites,session:"session",frame:9,epoch:2,imageSHA:hash)
  }
  let accepted=report(good)
  assert(accepted["status"] as? String=="PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION")
  assert(accepted["evidence_group_checked"] as? Bool==true)
  assert(accepted["owner_certified"] as? Bool==false)
  assert(accepted["current_state_eligible"] as? Bool==false)
  assert(accepted["battle_advice_authorized"] as? Bool==false)
  print("PASS_R567_ACCEPTED_SPLIT_PROVISIONAL_NOT_OWNER")
  let broken=report([site(0,"17",10),site(1,"/16",25)])
  assert(broken["status"] as? String=="HOLD_R567_ROLE_EVIDENCE_GROUP_INVALID")
  assert((broken["hints"] as? [[String:Any]])?.isEmpty == true)
  assert(broken["evidence_group_checked"] as? Bool==false)
  print("PASS_R567_REJECTED_SPLIT_RETIRES_ALL_HINTS")
  print("PASS_R567_ALL_26_TESTS")
 }
}
