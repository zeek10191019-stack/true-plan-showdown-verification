import Foundation

enum R548ResearchArchive {
 struct Entry {let name:String;let bytes:Data}
 static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
 static func testDigest(_ d:Data)->String {
  String(repeating: d.last == 5 ? "b" : "a", count:64)
 }
}
@main struct Tests {
 static func main() throws {
  var count=0
  func check(_ b:Bool,_ label:String) {precondition(b,label); count+=1;print("PASS_R621",label)}
  func flags(_ schema:String)->[String:Any] {
   ["schema":schema,"certified_for_battle":false,"owner_verified":false,
    "roi_verified":false,"mega_verified":false,"display_orientation_verified":false]
  }
  func entry(_ name:String,_ obj:[String:Any])->R548ResearchArchive.Entry {
   .init(name:name,bytes:try! JSONSerialization.data(withJSONObject:obj))
  }
  func obj(_ item:R548ResearchArchive.Entry)->[String:Any] {
   (try! JSONSerialization.jsonObject(with:item.bytes)) as! [String:Any]
  }
  func embedded(_ entries:[R548ResearchArchive.Entry])->[String:Any] {
   let file=entries.first(where:{$0.name==R617R620RotationReadout.memberName})!
   return obj(file)["r621_r624_embedded_candidate_report"] as! [String:Any]
  }
  let sha=String(repeating:"a",count:64)
  let sha2=String(repeating:"b",count:64)
  func token(_ text:String,_ x:Double)->[String:Any] {
   ["token":text,"confidence":0.83,"identity":"UNKNOWN","battle_field_certified":false,
    "visual_semantics":R617R620RotationReadout.parseVisualToken(text)!,
    "rect_norm_bottom_left_in_orientation_hypothesis":
      ["x":x,"y":0.65,"width":0.14,"height":0.05]]
  }
  func frame(_ frameID:Int64,_ name:String,_ tok:[String:Any])->[String:Any] {
   ["epoch":Int64(2),"frame_id":frameID,"archive_png":name,"original_png_sha256":name == "two.png" ? sha2 : sha,
    "orientation_probes":[
      ["hypothesis":"UP","status":"OCR_OBSERVED_NOT_ORIENTATION_CALIBRATED","visual_tokens":[tok]],
      ["hypothesis":"RIGHT","status":"HOLD_VISION_UNAVAILABLE","visual_tokens":[[String:Any]]()],
      ["hypothesis":"DOWN","status":"HOLD_VISION_UNAVAILABLE","visual_tokens":[[String:Any]]()],
      ["hypothesis":"LEFT","status":"HOLD_VISION_UNAVAILABLE","visual_tokens":[[String:Any]]()]]]
  }
  let f1=frame(10,"one.png",token("148/197",0.35))
  let f2=frame(11,"two.png",token("140/197",0.36))
  check(R617R620RotationReadout.parseVisualToken("メガシンカ")?["kind"] as? String ==
        "MEGA_SCENE_TEXT_CUE_UNASSIGNED","mega_scene_word_only")
  check(R617R620RotationReadout.parseVisualToken("MEGA EVOLUTION")?["kind"] as? String ==
        "MEGA_SCENE_TEXT_CUE_UNASSIGNED","mega_english_phrase")
  check(R621R624VisualCandidates.review(f1)?.count==1,"four_orientation_coordinates_read")
  let reviewed=R621R624VisualCandidates.review(f1)!.first!
  check(reviewed["visual_half_in_hypothesis"] as? String=="UPPER","visual_upper")
  check(reviewed["owner"] as? String=="UNKNOWN","owner_hold")
  check(reviewed["exact_hp"] as? String=="UNKNOWN","hp_hold")
  var bad=f1
  bad["orientation_probes"]=[
     ["hypothesis":"UP","status":"OCR_OBSERVED_NOT_ORIENTATION_CALIBRATED","visual_tokens":[token("148/197",0.35)]],
     ["hypothesis":"UP","status":"HOLD_VISION_UNAVAILABLE","visual_tokens":[[String:Any]]()],
     ["hypothesis":"DOWN","status":"HOLD_VISION_UNAVAILABLE","visual_tokens":[[String:Any]]()],
     ["hypothesis":"LEFT","status":"HOLD_VISION_UNAVAILABLE","visual_tokens":[[String:Any]]()]]
  check(R621R624VisualCandidates.review(bad)==nil,"duplicate_orientation_rejected")
  var fake=f1
  var ss=fake["orientation_probes"] as! [[String:Any]]
  var tt=ss[0]["visual_tokens"] as! [[String:Any]]
  tt[0]["token"]="500/197"
  ss[0]["visual_tokens"]=tt
  fake["orientation_probes"]=ss
  check(R621R624VisualCandidates.review(fake)==nil,"fabricated_visual_semantics_rejected")
  var off=f1
  ss=f1["orientation_probes"] as! [[String:Any]]
  tt=ss[0]["visual_tokens"] as! [[String:Any]]
  tt[0]["rect_norm_bottom_left_in_orientation_hypothesis"]=["x":0.99,"y":0.65,"width":0.14,"height":0.05]
  ss[0]["visual_tokens"]=tt
  off["orientation_probes"]=ss
  check(R621R624VisualCandidates.review(off)==nil,"out_of_bounds_rejected")
  let fixture=Data([1,2,3,4])
  func make(_ f:[[String:Any]])->[R548ResearchArchive.Entry] {
   var r8=flags("trueplan.r608.raw_png_visual_evidence.v1")
   r8["bindings"]=f.map { x in
    ["epoch":x["epoch"]!,"frame_id":x["frame_id"]!,"archive_png":x["archive_png"]!,
     "original_png_sha256":x["original_png_sha256"]!,"decoded_pixels_verified":true,"png_ihdr_crc_verified":true]
   }
   let ready=flags("trueplan.r613-r616.integrated_readiness.v1")
   var r17=flags("trueplan.r617-r620.rotation_readout.v1")
   r17["status"]="HOLD_ROTATION_SWEEP_RESEARCH_NOT_ACTOR_CERTIFICATION"
   r17["frames"]=f
   return [entry("r608_original_pixel_evidence.json",r8),
           entry("r613_r616_integrated_readiness.json",ready),
           entry("r617_r620_rotation_readout.json",r17)] +
       f.map {.init(name:$0["archive_png"] as! String,
                     bytes:($0["archive_png"] as! String) == "two.png" ? Data([1,2,3,5]) : fixture)}
  }
  var entries=make([f1,f2])
  let built=R621R624VisualCandidates.beforeZip(entries)
  check(built.count==entries.count,"no_extra_archive_member")
  check(R621R624VisualCandidates.containsReport(built),"embedded_archive_report_created")
  let report=embedded(built)
  print("DEBUG_R621_STATUS", report["status"] ?? "NONE")
  check(report["status"] as? String == "HOLD_UI_SLOTS_REQUIRE_LABELED_GAME_FRAMES", "safe_hold")
  check(report["certified_for_battle"] as? Bool == false,"no_auto_battle_cert")
  check(report["mega_verified"] as? Bool == false,"no_auto_mega_cert")
  check(report["owner_verified"] as? Bool == false,"no_auto_owner_cert")
  check(report["r623_mega_form"] as? String == "UNKNOWN_NO_LABELLED_SPRITE_REFERENCE", "form_hold")
  check((report["r623_repeated_visual_locations"] as? [[String:Any]])?.count==1,"location_only_timeline")
  check(R621R624VisualCandidates.beforeZip(built).count==built.count,"duplicate_append_reject")
  check(R621R624VisualCandidates.beforeZip(built)[2].bytes==built[2].bytes,"double_embedded_no_change")
  entries=make([f1])
  let badFile=frame(10,"different.png",token("148/197",0.35))
  var r17=flags("trueplan.r617-r620.rotation_readout.v1")
  r17["status"]="HOLD_ROTATION_SWEEP_RESEARCH_NOT_ACTOR_CERTIFICATION"
  r17["frames"]=[badFile]
  entries[2]=entry("r617_r620_rotation_readout.json",r17)
  let deny=embedded(R621R624VisualCandidates.beforeZip(entries))
  check(deny["status"] as? String == "HOLD_FRAME_HASH_OR_OCR_CONTRADICTION","bad_image_link")
  entries=make([f1])
  var forged=flags("trueplan.r613-r616.integrated_readiness.v1")
  forged["owner_verified"]=true
  entries[1]=entry("r613_r616_integrated_readiness.json",forged)
  check(embedded(R621R624VisualCandidates.beforeZip(entries))["status"] as? String ==
        "HOLD_REQUIRED_ORIGINAL_EVIDENCE_MISSING","forged_cert_rejected")
  entries=make([f1])
  for k in 0..<20 {entries.append(.init(name:"fill\(k)",bytes:Data()))}
  check(entries.count==24 && R621R624VisualCandidates.beforeZip(entries).count==24,
        "archive_count_stable_at_capacity")
  check(R621R624VisualCandidates.containsReport(R621R624VisualCandidates.beforeZip(entries)),
        "embedded_even_at_member_capacity")
  print("R621_R624_CHECKS=\(count)")
 }
}
