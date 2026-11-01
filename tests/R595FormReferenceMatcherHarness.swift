import Foundation
@main struct R595FormReferenceMatcherHarness {
 static func main() {
  var n=0
  func check(_ p:Bool,_ label:String){guard p else{fatalError("R595_\(label)")};n+=1}
  let w=512,h=256,s1=String(repeating:"a",count:64),s2=String(repeating:"b",count:64)
  func image()->[UInt8]{var a=[UInt8](repeating:0,count:w*h*4)
   for k in stride(from:3,to:a.count,by:4){a[k]=255};return a}
  func fill(_ a:inout [UInt8],_ x0:Int,_ x1:Int,_ y0:Int,_ y1:Int,_ c:UInt8){
   for y in y0..<y1 {for x in x0..<x1 {let i=(y*w+x)*4;a[i]=c;a[i+1]=c;a[i+2]=c}}}
  func draw(_ a:inout [UInt8],mega:Bool){
   for x in stride(from:50,to:300,by:18) {fill(&a,x,min(300,x+9),100,185,mega ? 30:225)}
   for x in stride(from:315,to:385,by:12) {fill(&a,x,min(385,x+7),110,196,225)}
  }
  func capture(_ img:[UInt8],_ id:Int64,ep:Int64=1,ms:Int64=100,sha:String=s1)->[String:Any]{
   R594ActorAppearance.capture(pixels:img,width:w,height:h,rowBytes:w*4,
     epoch:ep,frame:id,ms:ms,sha:sha)
  }
  func grid(_ frame:[String:Any],_ region:String)->[Int] {
   let rows=frame["regions"] as! [[String:Any]]
   return rows.first{$0["name"] as? String==region}!["luma_grid"] as! [Int]
  }
  let left="MEMORY_LEFT_ACTOR_HYPOTHESIS"
  var before=image();draw(&before,mega:false)
  var after=image();draw(&after,mega:true)
  let first=capture(before,1),second=capture(after,2,ms:200,sha:s2)
  func ref(_ id:String,_ form:String,_ mega:Bool,_ g:[Int],_ region:String=left)->[String:Any] {
   ["reference_id":id,"region":region,"species_token":"GYARADOS",
    "form_token":form,"mega_label_claim":mega,"human_label_reviewed":true,
    "reference_image_sha256":s1,"luma_grid":g,
    "coordinate_space":"RGBA_MEMORY_ROW_ORDER_UNVERIFIED",
    "certified_as_game_state":false]
  }
  let base=ref("R1","BASE",false,grid(first,left))
  let mega=ref("R2","MEGA",true,grid(second,left))
  let no=R595FormReferenceMatcher.audit([first,second],references:[])
  check(no["status"] as? String=="HOLD_NO_LABELED_FORM_REFERENCES","no_reference_hold")
  check(no["mega_certified"] as? Bool==false,"no_reference_no_mega")
  check(no["frame_count"] as? Int==2,"no_ref_count")
  let report=R595FormReferenceMatcher.audit([first,second],references:[base,mega])
  check(report["status"] as? String=="HISTORICAL_REFERENCE_FORM_CANDIDATES_ONLY","report_status")
  check(report["owner_certified"] as? Bool==false,"owner_unverified")
  check(report["species_certified"] as? Bool==false,"species_unverified")
  check(report["mega_certified"] as? Bool==false,"mega_unverified")
  check(report["automatic_upload"] as? Bool==false,"no_upload")
  let frames=report["frames"] as? [[String:Any]] ?? []
  check(frames.count==2,"two_frames")
  let initial=frames[0]["regions"] as! [[String:Any]]
  let evolved=frames[1]["regions"] as! [[String:Any]]
  check(initial[0]["status"] as? String=="VISUAL_FORM_REFERENCE_MATCH_CANDIDATE","match_base")
  check(initial[0]["form_token"] as? String=="BASE","form_base")
  check(evolved[0]["status"] as? String=="VISUAL_FORM_REFERENCE_MATCH_CANDIDATE","match_mega")
  check(evolved[0]["form_token"] as? String=="MEGA","form_mega")
  check(evolved[0]["mega_label_claim"] as? Bool==true,"mega_claim_only")
  check(initial[1]["status"] as? String=="HOLD_INSUFFICIENT_REFERENCE_OR_TEXTURE","no_right_reference")
  let transitions=report["possible_form_transitions"] as? [[String:Any]] ?? []
  check(transitions.count==1,"one_possible_transition")
  check(transitions[0]["status"] as? String=="BASE_TO_MEGA_REFERENCE_SEQUENCE_CANDIDATE","sequence_candidate")
  check(transitions[0]["mega_confirmed"] as? Bool==false,"no_transition_mega_cert")
  check(transitions[0]["owner"] as? String=="UNKNOWN","unknown_owner")
  let tie=R595FormReferenceMatcher.audit([first],references:[base,ref("R3","MEGA",true,grid(first,left))])
  let tieRows=((tie["frames"] as? [[String:Any]])?.first?["regions"] as? [[String:Any]]) ?? []
  check(tieRows.first?["status"] as? String=="HOLD_COMPETING_FORM_REFERENCES","tie_hold")
  let notClose=R595FormReferenceMatcher.audit([first],references:[mega])
  let distant=((notClose["frames"] as? [[String:Any]])?.first?["regions"] as? [[String:Any]]) ?? []
  check(distant.first?["status"] as? String=="HOLD_NO_CLOSE_FORM_REFERENCE","far_hold")
  check(R595FormReferenceMatcher.audit([second,first],references:[base])["status"] as? String=="HOLD_INVALID_FRAME_PROVENANCE","reverse")
  check(R595FormReferenceMatcher.audit([first,first],references:[base])["status"] as? String=="HOLD_INVALID_FRAME_PROVENANCE","duplicate")
  check(R595FormReferenceMatcher.audit(Array(repeating:first,count:9),references:[base])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","frame_limit")
  var bad=second;bad["mega_certified"]=true
  check(R595FormReferenceMatcher.audit([first,bad],references:[base])["status"] as? String=="HOLD_INVALID_FRAME_PROVENANCE","claim_injection")
  bad=first;bad["regions"]=[]
  check(R595FormReferenceMatcher.audit([bad],references:[base])["status"] as? String=="HOLD_INVALID_FRAME_PROVENANCE" || R595FormReferenceMatcher.audit([bad],references:[base])["status"] as? String=="HOLD_INVALID_FRAME_GRID","tamper_grid")
  var fake=base;fake["human_label_reviewed"]=false
  check(R595FormReferenceMatcher.audit([first],references:[fake])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","no_review")
  fake=base;fake["certified_as_game_state"]=true
  check(R595FormReferenceMatcher.audit([first],references:[fake])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","reject_certified_value")
  fake=base;fake["reference_image_sha256"]="INVALID"
  check(R595FormReferenceMatcher.audit([first],references:[fake])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","bad_ref_sha")
  fake=base;fake["luma_grid"]=[42,43]
  check(R595FormReferenceMatcher.audit([first],references:[fake])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","bad_template")
  check(R595FormReferenceMatcher.audit([first],references:[base,base])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","duplicate_ref_id")
  check(R595FormReferenceMatcher.audit([first],references:[ref("x!","BASE",false,grid(first,left))])["status"] as? String=="HOLD_INVALID_INPUT_OR_CATALOG","bad_id")
  let x=R595FormReferenceMatcher.loadLocalCatalog(at:nil)
  check(x.isEmpty,"nil_file")
  let tmp=FileManager.default.temporaryDirectory.appendingPathComponent("r595-local-\(UUID().uuidString).json")
  let obj:[String:Any]=["schema":R595FormReferenceMatcher.catalogSchema,"references":[base,mega]]
  try! JSONSerialization.data(withJSONObject:obj).write(to:tmp)
  check(R595FormReferenceMatcher.loadLocalCatalog(at:tmp).count==2,"valid_local_catalog")
  try! "malformed".write(to:tmp,atomically:true,encoding:.utf8)
  check(R595FormReferenceMatcher.loadLocalCatalog(at:tmp).isEmpty,"malformed_local_catalog")
  try? FileManager.default.removeItem(at:tmp)
  let json=try! JSONSerialization.data(withJSONObject:report)
  check(json.count < 120_000,"bounded_output")
  print("R595_FORM_REFERENCE_MATCHER_TESTS_\(n)_PASS")
 }
}
