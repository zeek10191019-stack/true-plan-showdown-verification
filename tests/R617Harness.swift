import Foundation

enum R548ResearchArchive {
 struct Entry {let name:String;let bytes:Data}
 static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
 static func testDigest(_ d:Data)->String {String(repeating:"a",count:64)}
}
@main struct Tests {
 static func main() throws {
  var count=0
  func check(_ b:Bool,_ s:String) {precondition(b,s);count+=1;print("PASS_R617",s)}
  func obj(_ x:R548ResearchArchive.Entry)->[String:Any] {
   (try! JSONSerialization.jsonObject(with:x.bytes)) as! [String:Any]
  }
  func entry(_ name:String,_ body:[String:Any])->R548ResearchArchive.Entry {
   .init(name:name,bytes:try! JSONSerialization.data(withJSONObject:body))
  }
  func flags(_ schema:String)->[String:Any] {
   ["schema":schema,"certified_for_battle":false,"owner_verified":false,
    "roi_verified":false,"mega_verified":false,"display_orientation_verified":false]
  }
  let items:[(String,String)]=[
    ("148/197","FRACTION_HP_OR_PP_UNASSIGNED"),
    (" 7 / 10 ","FRACTION_HP_OR_PP_UNASSIGNED"),
    ("81%","PERCENT_HP_OR_OTHER_UNASSIGNED"),
    (" １００％ ","PERCENT_HP_OR_OTHER_UNASSIGNED"),
    ("まひ","STATUS_WORD_UNASSIGNED"),
    ("BRN","STATUS_WORD_UNASSIGNED")]
  for (s,k) in items { check(R617R620RotationReadout.parseVisualToken(s)?["kind"] as? String==k,"parsed_\(s)") }
  for s in ["200/197","1/0","101%","HP=?","","0/0","18446744073709551616/10"] {
   check(R617R620RotationReadout.parseVisualToken(s)==nil,"reject_\(s)")
  }
  func tk(_ text:String,_ x:Double)->[String:Any] {
   ["visual_semantics":R617R620RotationReadout.parseVisualToken(text)!,
    "rect_norm_bottom_left_in_orientation_hypothesis":
       ["x":x,"y":0.3,"width":0.2,"height":0.05]]
  }
  func frame(_ v:String,_ x:Double)->[String:Any] {
   ["orientation_probes":[["hypothesis":"UP","visual_tokens":[tk(v,x)]],
       ["hypothesis":"RIGHT","visual_tokens":[[String:Any]]()],
       ["hypothesis":"DOWN","visual_tokens":[[String:Any]]()],
       ["hypothesis":"LEFT","visual_tokens":[[String:Any]]()]]]
  }
  check(R617R620RotationReadout.continuity([frame("148/197",0.2),frame("140/197",0.22)]).count==1,
       "same_location_different_hp_shape_only")
  check(R617R620RotationReadout.continuity([frame("148/197",0.2),frame("140/197",0.65)]).isEmpty,
       "far_coordinate_no_link")
  check(R617R620RotationReadout.continuity([frame("148/197",0.2)]).isEmpty,"one_frame_no_link")
  var raw=flags("trueplan.r608.raw_png_visual_evidence.v1")
  raw["bindings"]=[["epoch":1,"frame_id":19,"archive_png":"s1.png",
    "original_png_sha256":String(repeating:"a",count:64),
    "png_ihdr_crc_verified":true,"decoded_pixels_verified":true]]
  var ocr=flags("trueplan.r609.vision_text_spatial_evidence.v1")
  ocr["bindings"]=[["epoch":1,"frame_id":19,"archive_png":"s1.png",
    "original_png_sha256":String(repeating:"a",count:64)]]
  let ready=flags("trueplan.r613-r616.integrated_readiness.v1")
  let fixture=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAIElEQVR4nGP89esXAy0BE01NH7Vg1IJRC0YtGLWASgAAJSIDDp4iFzIAAAAASUVORK5CYII=")!
  func samples()->[R548ResearchArchive.Entry] {
    [entry("r608_original_pixel_evidence.json",raw),
     entry("r609_vision_text_spatial_evidence.json",ocr),
     entry("r613_r616_integrated_readiness.json",ready),
     .init(name:"s1.png",bytes:fixture)]
  }
  var good=R617R620RotationReadout.beforeZip(samples())
  check(good.count==5,"one_member_added")
  let report=obj(good.last!)
  check(report["status"] as? String=="HOLD_ROTATION_SWEEP_RESEARCH_NOT_ACTOR_CERTIFICATION",
        "valid_lineage_status")
  check(report["owner_verified"] as? Bool==false,"no_own_assignment")
  check(report["mega_verified"] as? Bool==false,"no_mega_assignment")
  check(report["display_orientation_verified"] as? Bool==false,"no_orientation_claim")
  check((report["frames"] as? [[String:Any]])?.count==1,"one_frame")
  check(R617R620RotationReadout.beforeZip(good).count==good.count,"duplicate_guard")
  var fake=ocr;fake["bindings"]=[["epoch":1,"frame_id":20,
    "archive_png":"s1.png","original_png_sha256":String(repeating:"a",count:64)]]
  let broken=[samples()[0],entry("r609_vision_text_spatial_evidence.json",fake),samples()[2],samples()[3]]
  let rejected=obj(R617R620RotationReadout.beforeZip(broken).last!)
  check(rejected["status"] as? String=="HOLD_FRAME_IMAGE_OR_HASH_CONTRADICTION",
       "wrong_frame_rejected")
  var certified=ready;certified["owner_verified"]=true
  let falseCert=[samples()[0],samples()[1],entry("r613_r616_integrated_readiness.json",certified),samples()[3]]
  check(obj(R617R620RotationReadout.beforeZip(falseCert).last!)["status"] as? String ==
        "HOLD_SOURCE_MISSING_OR_CONTRADICTORY","false_own_cert_rejected")
  good=samples()
  for i in 0..<20 {good.append(.init(name:"x\(i)",bytes:Data()))}
  check(good.count==24 && R617R620RotationReadout.beforeZip(good).count==24,"zip_capacity_guard")
  print("R617_R620_CHECKS=\(count)")
 }
}
