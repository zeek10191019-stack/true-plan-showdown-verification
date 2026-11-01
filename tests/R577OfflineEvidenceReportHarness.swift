import Foundation

@main struct R577OfflineEvidenceReportHarness {
 static func main() throws {
  let digest=String(repeating:"a",count:64)
  var packet:[String:Any]=["image_sha256":digest,"frame_id":1,"epoch":1,
        "readings":[["raw_text":"170/185","ocr_observation_index":0,
        "ocr_alternatives":[["raw_text":"170/185","rank":0]],
        "roi_rect":["x":0,"y":0,"width":60,"height":24]]]]
  let snap:[String:Any]=["image_sha256":digest,"current_state_eligible":false,
       "battle_advice_authorized":false,"own":["hp":"UNKNOWN"]]
  let mega:[String:Any]=["image_sha256":digest,"mega_certified":false,
       "visual_form_certified":false,"state":"TEXT_HINTS_ONLY",
       "text_hints":["メガシンカ"],"orientation_evidence":[]]
  func packetString()->String {
   let d=try! JSONSerialization.data(withJSONObject:packet,options:[.sortedKeys])
   return String(data:d,encoding:.utf8)!
  }
  func run(_ hash:String=_defaultDigest(),_ w:Int=1280,_ h:Int=720,_ size:Int=2000,
           _ data:String?=nil,_ snapshot:[String:Any]?=nil,_ mega:[String:Any]?=nil)->Data? {
   R577OfflineEvidenceReport.encode(sourceSHA:hash,width:w,height:h,sourceBytes:size,
        packetJSON:data ?? packetString(),snapshot:snapshot ?? snap,mega:mega ?? R577OfflineEvidenceReportHarness.megaDefault())
  }
  // Avoid any test privilege or live-source assumptions.
  let output=R577OfflineEvidenceReport.encode(sourceSHA:digest,width:1280,height:720,
         sourceBytes:2000,packetJSON:packetString(),snapshot:snap,mega:mega)
  assert(output != nil)
  let doc=try JSONSerialization.jsonObject(with:output!) as! [String:Any]
  assert(doc["schema"] as? String == R577OfflineEvidenceReport.schema)
  assert(doc["source_png_in_report"] as? Bool==false)
  assert(doc["user_opt_in_share_required"] as? Bool==true)
  for k in ["current_state_eligible","owner_certified","turn_certified",
     "battle_advice_authorized","real_game_accuracy_certified","mega_form_visual_certified"] {
   assert(doc[k] as? Bool==false,"unexpected certification: \(k)")
  }
  assert((doc["payload"] as? [String:Any])?["image_sha256"] as? String == digest)
  assert(((doc["mega_text_probe"] as? [String:Any])?["text_hints"] as? [String]) == ["メガシンカ"])
  print("R577_POSITIVE_AND_FAIL_CLOSED_FLAGS_PASS")
  func rejected(_ hash:String,_ w:Int,_ h:Int,_ size:Int,_ data:String,
                _ shot:[String:Any],_ meg:[String:Any]) -> Bool {
   R577OfflineEvidenceReport.encode(sourceSHA:hash,width:w,height:h,sourceBytes:size,
          packetJSON:data,snapshot:shot,mega:meg)==nil
  }
  assert(rejected("a",1280,720,2000,packetString(),snap,mega))
  assert(rejected(digest.uppercased(),1280,720,2000,packetString(),snap,mega))
  assert(rejected(digest,0,720,2000,packetString(),snap,mega))
  assert(rejected(digest,8193,720,2000,packetString(),snap,mega))
  assert(rejected(digest,8192,8192,2000,packetString(),snap,mega))
  assert(rejected(digest,1280,720,12000001,packetString(),snap,mega))
  assert(rejected(digest,1280,720,5,packetString(),snap,mega))
  assert(rejected(digest,1280,720,2000,"{}",snap,mega))
  assert(rejected(digest,1280,720,2000,"not-json",snap,mega))
  packet["image_sha256"]=String(repeating:"b",count:64)
  assert(rejected(digest,1280,720,2000,packetString(),snap,mega))
  packet["image_sha256"]=digest;packet["frame_id"]=2
  assert(rejected(digest,1280,720,2000,packetString(),snap,mega))
  packet["frame_id"]=1;packet["epoch"]=2
  assert(rejected(digest,1280,720,2000,packetString(),snap,mega))
  packet["epoch"]=1
  var wrong=snap;wrong["current_state_eligible"]=true
  assert(rejected(digest,1280,720,2000,packetString(),wrong,mega))
  wrong=snap;wrong["battle_advice_authorized"]=true
  assert(rejected(digest,1280,720,2000,packetString(),wrong,mega))
  wrong=snap;wrong["image_sha256"]=String(repeating:"b",count:64)
  assert(rejected(digest,1280,720,2000,packetString(),wrong,mega))
  var other=mega;other["image_sha256"]=String(repeating:"b",count:64)
  assert(rejected(digest,1280,720,2000,packetString(),snap,other))
  other=mega;other["mega_certified"]=true
  assert(rejected(digest,1280,720,2000,packetString(),snap,other))
  other=mega;other["visual_form_certified"]=true
  assert(rejected(digest,1280,720,2000,packetString(),snap,other))
  assert(rejected(digest,1280,720,2000,String(repeating:"X",count:2_000_001),snap,mega))
  print("PASS_R577_24_REPORT_INTEGRITY_AND_NONLIVE_CASES")
 }
 static func _defaultDigest()->String {String(repeating:"a",count:64)}
 static func megaDefault()->[String:Any] {
    ["image_sha256":_defaultDigest(),"mega_certified":false,"visual_form_certified":false]
 }
}
