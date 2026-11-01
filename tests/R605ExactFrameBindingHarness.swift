import Foundation
@main struct Test {
 static func main() throws {
   func check(_ ok:Bool,_ label:String) {precondition(ok,label);print("PASS_R605",label)}
   let png=Data(base64Encoded:
       "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGM44SCAFTEMLQkAiF1GAYJRm+sAAAAASUVORK5CYII=")!
   let hash=R598OneButtonFormAttachment.testDigest(png)
   let regionNames=["MEMORY_LEFT_ACTOR_HYPOTHESIS","MEMORY_RIGHT_ACTOR_HYPOTHESIS"]
   let regions=regionNames.map{["region":$0,"luma_grid":Array(repeating:128,count:192),"valid_samples":192] as [String:Any]}
   func snapshot(_ digest:String,_ frame:Int64=7)->Data {
     let obj:[String:Any]=["schema":"trueplan.r604.r594_exact_snapshot.v1",
       "status":"HOLD_OWNER_OR_ROI_AND_R595_MATCHER_PARITY",
       "owner_verified":false,"mega_verified":false,
       "samples":[["epoch":Int64(2),"frame_id":frame,
                  "monotonic_ms":Int64(900),"full_frame_sha256":digest,
                  "regions":regions] as [String:Any]]]
     return try! JSONSerialization.data(withJSONObject:obj,options:[.sortedKeys])
   }
   func item(_ name:String,_ content:Data)->R548ResearchArchive.Entry { .init(name:name,bytes:content) }
   let orig=[item("manifest.json",Data("{}".utf8)),item("frame.png",png),
             item("r604_r594_feature_snapshot.json",snapshot(hash))]
   let result=R605ExactFrameBinding.beforeZip(orig)
   check(result.count==orig.count+1,"valid full frame indexed")
   let dict=(try JSONSerialization.jsonObject(with:result.last!.bytes)) as! [String:Any]
   let rows=dict["frame_bindings"] as! [[String:Any]]
   check(rows.count==1,"one matching frame")
   check(rows[0]["matched_archive_png"] as? String=="frame.png","exact original png path")
   check(rows[0]["status"] as? String=="EXACT_SOURCE_PNG_BYTES_MATCHED_RESEARCH_ONLY","only research")
   check(rows[0]["actor_verified"] as? Bool==false,"actor remains unverified")
   check(rows[0]["crop_verified"] as? Bool==false,"crop remains unverified")
   check(dict["certification"] as? String=="NOT_CERTIFIED_FOR_LIVE_BATTLE","live prohibition")
   check(R605ExactFrameBinding.beforeZip(result).count==result.count,"idempotent")
   let absent=[orig[0],orig[2]]
   let held=R605ExactFrameBinding.beforeZip(absent)
   let holdDoc=(try JSONSerialization.jsonObject(with:held.last!.bytes)) as! [String:Any]
   let holdRows=holdDoc["frame_bindings"] as! [[String:Any]]
   check(holdRows[0]["status"] as? String=="HOLD_ORIGINAL_PNG_NOT_IN_ARCHIVE","missing PNG hold")
   let duplicate=R605ExactFrameBinding.beforeZip(orig+[item("other.png",png)])
   let duplicateDoc=(try JSONSerialization.jsonObject(with:duplicate.last!.bytes)) as! [String:Any]
   check((duplicateDoc["frame_bindings"] as! [[String:Any]])[0]["status"] as? String=="HOLD_DUPLICATE_IDENTICAL_PNG","duplicate PNG hold")
   check(R605ExactFrameBinding.beforeZip(orig+[orig[0]]).count==orig.count+1,"archive duplicate refused")
   check(R605ExactFrameBinding.beforeZip(orig.dropLast().map{$0}).count==2,"no snapshot refused")
   let bad=orig.dropLast().map{$0}+[item("r604_r594_feature_snapshot.json",snapshot(String(repeating:"z",count:64)))]
   check(R605ExactFrameBinding.beforeZip(bad).count==bad.count,"invalid sha refused")
   let wrong=orig.dropLast().map{$0}+[item("r604_r594_feature_snapshot.json",snapshot(hash,0))]
   check(R605ExactFrameBinding.beforeZip(wrong).count==wrong.count,"invalid frame refused")
   var full=orig
   while full.count<24 { full.append(item("padding-\(full.count)",Data())) }
   check(R605ExactFrameBinding.beforeZip(full).count==24,"capacity refused")
   let untrusted=orig.dropLast().map{$0}+[item("../unsafe.png",png),orig[2]]
   check(R605ExactFrameBinding.beforeZip(untrusted).count==untrusted.count,"unsafe name refused")
 }
}
