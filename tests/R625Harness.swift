import Foundation

enum R548ResearchArchive {
 struct Entry {let name:String;let bytes:Data}
 static let maximumMembers=24
}
enum R598OneButtonFormAttachment {
 static func testDigest(_ d:Data)->String {
  String(repeating:d.last==5 ? "b" : "a",count:64)
 }
}
@main struct Main {
 static func main() throws {
  var checks=0
  func check(_ condition:Bool,_ reason:String) {
   precondition(condition,reason);checks += 1;print("PASS_R625",reason)
  }
  let w=128,h=64
  var rgba=[UInt8](repeating:0,count:w*h*4)
  func paint(_ x:Int,_ y:Int,_ width:Int,_ height:Int,_ r:UInt8,_ g:UInt8,_ b:UInt8) {
   for row in y..<(y+height) {
    for col in x..<(x+width) {
     let i=(row*w+col)*4;rgba[i]=r;rgba[i+1]=g;rgba[i+2]=b;rgba[i+3]=255
    }
   }
  }
  paint(24,45,58,4,30,190,38)
  paint(23,7,60,3,240,190,40)
  paint(40,25,52,4,230,30,35)
  let bands=R625R628PixelHUDAndSprite.probeRGBA(rgba,width:w,height:h)
  check(bands.count==3,"actual_bitmap_bands_3")
  check(Set(bands.compactMap{$0["color_class"] as? String}) == Set(["GREEN_LIKE","YELLOW_LIKE","RED_LIKE"]),"green_yellow_red_classes")
  check(bands.allSatisfy{$0["owner"] as? String=="UNKNOWN"},"pixel_no_owner_claim")
  check(bands.allSatisfy{$0["confirmed_hud"] as? Bool==false},"pixel_no_hp_claim")
  check(R625R628PixelHUDAndSprite.probeRGBA([0],width:w,height:h).isEmpty,"bad_byte_length_rejected")
  check(R625R628PixelHUDAndSprite.probeRGBA(rgba,width:16,height:h).isEmpty,"small_dimensions_rejected")
  check(R625R628PixelHUDAndSprite.validRect(["x":0.1,"y":0.3,"width":0.2,"height":0.1]) != nil,"valid_box")
  check(R625R628PixelHUDAndSprite.validRect(["x":0.95,"y":0.2,"width":0.2,"height":0.1]) == nil,"offscreen_box_rejected")
  check(R625R628PixelHUDAndSprite.validRect(["x":Double.nan,"y":0.2,"width":0.2,"height":0.1]) == nil,"nan_box_rejected")
  let result=R625R628PixelHUDAndSprite.scanPixels(rgba,width:w,height:h)
  check(result["status"] as? String=="HOLD_PIXELS_DECODED_NOT_CALIBRATED","pixel_hold")
  check((result["sprite_window_fingerprints"] as? [[String:Any]])?.count==2,"sprite_two_windows")
  let proposals=result["sprite_window_fingerprints"] as! [[String:Any]]
  check(proposals.allSatisfy{$0["mega_form"] as? String=="UNKNOWN"},"sprite_mega_hold")
  check(proposals.allSatisfy{$0["reference_catalog_matched"] as? Bool==false},"no_false_catalogue_match")
  check(proposals.allSatisfy{($0["dhash64"] as? String)?.count==16},"sprite_dhash_width")
  // A REAL encoded PNG exercises ImageIO on Apple CI (Linux holds safely).
  let fixtureB64="iVBORw0KGgoAAAANSUhEUgAAAIAAAABACAIAAABdtOgoAAAAe0lEQVR42u3ZsQ2AIBAFUHECawsaE+McDs4cxsTGwtoRXEIRyHsDcHf8667rAAAgu/DKK3daqpt8WLcS2ujtoAAAAAAAAIBvhb8KX3Eq9lPG88hWy0HmZwIQAAAAAAAAQNteuwnHNFc09rnuhXTiIiYAAQAAAAAAAG17AMwpCRTdgNaNAAAAAElFTkSuQmCC"
  let decoded=R625R628PixelHUDAndSprite.decodePNG(Data(base64Encoded:fixtureB64)!)
  #if canImport(ImageIO) && canImport(CoreGraphics)
  check(decoded["status"] as? String=="HOLD_PIXELS_DECODED_NOT_CALIBRATED",
        "apple_real_png_decoding")
  let actual=decoded["colored_runs"] as? [[String:Any]] ?? []
  check(actual.count>=2,"apple_real_png_pixel_runs")
  #else
  check(decoded["status"] as? String=="HOLD_IMAGEIO_UNAVAILABLE","linux_imageio_hold")
  #endif
  let no=R625R628PixelHUDAndSprite.scanPixels([0],width:w,height:h)
  check(no["status"] as? String=="HOLD_PIXEL_BUFFER_INVALID","bad_pixel_hold")
  let bar=bands.first(where:{$0["color_class"] as? String=="GREEN_LIKE"})!
  let b=bar["rect_top_left_norm"] as! [String:Any]
  let sameY=1-(b["y"] as! Double)-(b["height"] as! Double)
  let text=["orientation_hypothesis":"UP","kind":"FRACTION_HP_OR_PP_UNASSIGNED",
            "normalized_rect_in_hypothesis":["x":0.24,"y":sameY,"width":0.15,"height":b["height"]!]] as [String:Any]
  let near=R625R628PixelHUDAndSprite.visualMatches([text],bands)
  check(!near.isEmpty,"ocr_pixel_proximity_hypothesis")
  check(near.allSatisfy{$0["exact_hp_certified"] as? Bool==false},"proximity_not_hp")
  check(near.allSatisfy{$0["owner"] as? String=="UNKNOWN"},"proximity_not_actor")
  var ambiguous=text;ambiguous["orientation_hypothesis"]="RIGHT"
  check(R625R628PixelHUDAndSprite.visualMatches([ambiguous],bands).isEmpty,"rotated_coords_not_overclaimed")
  var forged=text;forged["normalized_rect_in_hypothesis"]=["x":0.99,"y":0.2,"width":0.12,"height":0.1]
  check(R625R628PixelHUDAndSprite.visualMatches([forged],bands).isEmpty,"forged_box_rejected")
  func flags(_ schema:String)->[String:Any] {
   ["schema":schema,"certified_for_battle":false,"owner_verified":false,"roi_verified":false,
    "mega_verified":false,"display_orientation_verified":false]
  }
  func entry(_ name:String,_ obj:[String:Any])->R548ResearchArchive.Entry {
   .init(name:name,bytes:try! JSONSerialization.data(withJSONObject:obj))
  }
  let png=Data([1,2,3,4]);let hash=String(repeating:"a",count:64)
  let source:[String:Any]=["epoch":Int64(2),"frame_id":Int64(12),"original_png_sha256":hash,
      "archive_png":"game.png","decoded_pixels_verified":true,"png_ihdr_crc_verified":true]
  var r8=flags("trueplan.r608.raw_png_visual_evidence.v1");r8["bindings"]=[source]
  var r21=flags("trueplan.r621-r624.visual_candidate_slots.v1")
  r21["status"]="HOLD_UI_SLOTS_REQUIRE_LABELED_GAME_FRAMES"
  var row=source;row["observations"]=[text]
  r21["r622_ui_slot_hypotheses"]=[row]
  var r17=flags("trueplan.r617-r620.rotation_readout.v1")
  r17["r621_r624_embedded_candidate_report"]=r21
  let input=[entry("r608_original_pixel_evidence.json",r8),
             entry(R617R620RotationReadout.memberName,r17),
             R548ResearchArchive.Entry(name:"game.png",bytes:png)]
  func out(_ arr:[R548ResearchArchive.Entry])->[String:Any] {
   let e=arr.first(where:{$0.name==R617R620RotationReadout.memberName})!
   let parent=(try! JSONSerialization.jsonObject(with:e.bytes)) as! [String:Any]
   return parent[R625R628PixelHUDAndSprite.embeddedKey] as! [String:Any]
  }
  let appended=R625R628PixelHUDAndSprite.beforeZip(input)
  check(appended.count==input.count,"member_count_stable")
  check(R625R628PixelHUDAndSprite.containsReport(appended),"embedded_report_receipt")
  let report=out(appended)
  check(report["status"] as? String=="HOLD_PIXEL_LOCATIONS_NOT_GROUND_TRUTH","overall_hold")
  check(report["certified_for_battle"] as? Bool == false,"archive_no_battle_cert")
  check(report["mega_verified"] as? Bool == false,"archive_mega_hold")
  check(report["owner_verified"] as? Bool == false,"archive_owner_hold")
  check((report["frames"] as? [[String:Any]])?.count==1,"verified_frame_correlated")
  check(R625R628PixelHUDAndSprite.beforeZip(appended)[1].bytes==appended[1].bytes,"idempotent_no_duplicate")
  var broken=input
  var forgedRow=row;forgedRow["original_png_sha256"]=String(repeating:"b",count:64)
  var corrupt=r21;corrupt["r622_ui_slot_hypotheses"]=[forgedRow]
  var corruptParent=r17
  corruptParent["r621_r624_embedded_candidate_report"]=corrupt
  broken[1]=entry(R617R620RotationReadout.memberName,corruptParent)
  let hold=out(R625R628PixelHUDAndSprite.beforeZip(broken))
  check(hold["status"] as? String=="HOLD_ORIGINAL_PIXEL_FRAME_OR_OCR_CONTRADICTION","sha_mismatch_rejected")
  broken=input
  var claimed=r21;claimed["owner_verified"]=true
  var claimedParent=r17
  claimedParent["r621_r624_embedded_candidate_report"]=claimed
  broken[1]=entry(R617R620RotationReadout.memberName,claimedParent)
  check(out(R625R628PixelHUDAndSprite.beforeZip(broken))["status"] as? String == "HOLD_SOURCE_MISSING_OR_CONTRADICTORY","claimed_ownership_rejected")
  broken=input
  broken.append(.init(name:"game.png",bytes:png))
  check(R625R628PixelHUDAndSprite.beforeZip(broken).count==broken.count,"duplicate_entry_hold")
  broken=input
  for i in 0..<21 {broken.append(.init(name:"padding\(i)",bytes:Data()))}
  check(broken.count==24 && R625R628PixelHUDAndSprite.beforeZip(broken).count==24,
        "archive_capacity_no_member_increase")
  check(R625R628PixelHUDAndSprite.containsReport(R625R628PixelHUDAndSprite.beforeZip(broken)),
        "embedded_at_archive_member_limit")
  print("R625_R628_CHECKS=\(checks)_NO_GAME_CERTIFICATION")
 }
}
