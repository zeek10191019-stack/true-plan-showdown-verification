import Foundation
@main struct R578OfflineBundlePolicyHarness {
 static func main() throws {
   guard CommandLine.arguments.count==2 else {fatalError("NEED_PNG")}
   let png=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
   guard case .accepted(let w,let h)=R576OfflinePNGImportGate.validate(png) else {fatalError("BAD_PNG")}
   let sha=String(repeating:"a",count:64)
   func make(_ packetSHA:String?=nil)->[String:Any] {
     ["schema":R577OfflineEvidenceReport.schema,
      "source_kind":"USER_IMPORTED_PNG_OFFLINE_ONLY",
      "image_sha256":sha,"image_width":w,"image_height":h,"png_bytes":png.count,
      "source_png_in_report":false,"user_opt_in_share_required":true,
      "current_state_eligible":false,"owner_certified":false,"turn_certified":false,
      "mega_form_visual_certified":false,"real_game_accuracy_certified":false,
      "battle_advice_authorized":false,
      "payload":["image_sha256":packetSHA ?? sha,"frame_id":1,"epoch":1,
                 "source_ref":"user-imported-exact-png-not-live"],
      "snapshot":["image_sha256":sha,"current_state_eligible":false,"battle_advice_authorized":false],
      "mega_text_probe":["image_sha256":sha,"mega_certified":false,"visual_form_certified":false]]
   }
   func evaluate(_ document:[String:Any],_ expected:Bool,_ tag:String) {
       let data=try! JSONSerialization.data(withJSONObject:document,options:[.sortedKeys])
       let actual=R578OfflineBundlePolicy.accepts(png,data,sourceSHA:sha)
       assert(actual==expected,tag)
       print("PASS_R578_"+tag)
   }
   let base=make();evaluate(base,true,"VALID_METADATA")
   let props:[(String,Any)]=[
       ("schema","wrong"),("source_kind","LIVE"),
       ("image_sha256",String(repeating:"b",count:64)),("image_width",w+1),
       ("image_height",h+1),("png_bytes",png.count+1),
       ("source_png_in_report",true),("user_opt_in_share_required",false),
       ("current_state_eligible",true),("owner_certified",true),("turn_certified",true),
       ("mega_form_visual_certified",true),("real_game_accuracy_certified",true),
       ("battle_advice_authorized",true)]
   for (i,kv) in props.enumerated() {var x=base;x[kv.0]=kv.1;evaluate(x,false,"BAD_TOP_\(i)")}
   evaluate(make(String(repeating:"b",count:64)),false,"BAD_PACKET_HASH")
   var a=base;var p=a["payload"] as! [String:Any];p["frame_id"]=2;a["payload"]=p;evaluate(a,false,"WRONG_FRAME")
   a=base;p=a["payload"] as! [String:Any];p["epoch"]=2;a["payload"]=p;evaluate(a,false,"WRONG_EPOCH")
   a=base;p=a["payload"] as! [String:Any];p["source_ref"]="live";a["payload"]=p;evaluate(a,false,"WRONG_SOURCE")
   a=base;var snap=a["snapshot"] as! [String:Any];snap["image_sha256"]="wrong";a["snapshot"]=snap;evaluate(a,false,"BAD_SNAPSHOT_HASH")
   a=base;snap=a["snapshot"] as! [String:Any];snap["current_state_eligible"]=true;a["snapshot"]=snap;evaluate(a,false,"BAD_SNAPSHOT_CURRENT")
   a=base;var meg=a["mega_text_probe"] as! [String:Any];meg["image_sha256"]="wrong";a["mega_text_probe"]=meg;evaluate(a,false,"BAD_MEGA_HASH")
   a=base;meg=a["mega_text_probe"] as! [String:Any];meg["mega_certified"]=true;a["mega_text_probe"]=meg;evaluate(a,false,"BAD_MEGA_CERT")
   a=base;meg=a["mega_text_probe"] as! [String:Any];meg["visual_form_certified"]=true;a["mega_text_probe"]=meg;evaluate(a,false,"BAD_MEGA_FORM")
   a=base;a.removeValue(forKey:"payload");evaluate(a,false,"MISSING_PACKET")
   a=base;a.removeValue(forKey:"snapshot");evaluate(a,false,"MISSING_SNAPSHOT")
   a=base;a.removeValue(forKey:"mega_text_probe");evaluate(a,false,"MISSING_MEGA")
   assert(!R578OfflineBundlePolicy.accepts(png,Data("{}".utf8),sourceSHA:sha))
   assert(!R578OfflineBundlePolicy.accepts(png,Data(),sourceSHA:sha))
   assert(!R578OfflineBundlePolicy.accepts(png,Data("junk".utf8),sourceSHA:sha))
   assert(!R578OfflineBundlePolicy.accepts(Data(),Data("{}".utf8),sourceSHA:sha))
   let validDocument=try JSONSerialization.data(withJSONObject:base)
   assert(!R578OfflineBundlePolicy.accepts(png,validDocument,sourceSHA:sha.uppercased()))
   print("PASS_R578_ALL_POLICY_TESTS")
 }
}
