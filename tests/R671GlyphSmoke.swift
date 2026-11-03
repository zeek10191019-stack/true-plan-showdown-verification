import Foundation
@main struct R671GlyphSmoke {
 static func main() {
  let h=String(repeating:"a",count:64),z=String(repeating:"0",count:64)
  func ref(_ id:String,_ label:String,_ shape:String,_ source:String)->[String:Any] {
   ["reference_id":id,"label":label,"silhouette_8x8_hex":shape,
    "color_family":"WARM","source_image_sha256":source,
    "review_kind":"USER_REVIEWED_REAL_GAME_CROP"]
  }
  let refs=[ref("b1","BURN","ffff000000000000",h),
            ref("b2","BURN","ffff000000000000",z),
            ref("n1","NONE","000000000000ffff",h),
            ref("n2","NONE","000000000000ffff",z)]
  let glyph:[String:Any]=[
   "silhouette_8x8_hex_unlabeled":"ffff000000000000",
   "color_family_unclassified":"WARM",
   "position_hint":"OWN_HUD_POSITION_ONLY",
   "owner_verified":false,"current_state_eligible":false]
  let f:[String:Any]=[
   "schema":R670HUDPixelGlyphs.schema,
   "status":"HISTORICAL_HUD_RGBA_GLYPH_CANDIDATES_ONLY",
   "raw_image_sha256":String(repeating:"b",count:64),
   "frame_id":1 as Int64,"epoch":1 as Int64,"candidates":[glyph]]
  let good=R671StatusGlyphMatcher.audit(frames:[f],references:refs)
  precondition(good["candidate_count"] as? Int==1)
  precondition((good["candidates"] as? [[String:Any]])?[0]["status_label_candidate"] as? String=="BURN")
  precondition(good["status_icon_class_certified"] as? Bool==false)
  precondition(R671StatusGlyphMatcher.audit(frames:[f],references:[])["status"] as? String=="HOLD_NO_REVIEWED_REFERENCES")
  precondition(R671StatusGlyphMatcher.audit(frames:[f],references:[refs[0],refs[2]])["status"] as? String=="HOLD_NO_INDEPENDENT_POSITIVE_AND_NEGATIVE_CONTROLS")
  var bad=refs;bad[0]["review_kind"]="SCRAPED_UNREVIEWED"
  precondition((R671StatusGlyphMatcher.audit(frames:[f],references:bad)["status"] as? String)?.hasPrefix("HOLD_")==true)
  var selfLeak=f;selfLeak["raw_image_sha256"]=h
  let leak=R671StatusGlyphMatcher.audit(frames:[selfLeak],references:refs)
  precondition(leak["candidate_count"] as? Int==0)
  var fake=f;fake["candidates"]=[["silhouette_8x8_hex_unlabeled":"INVALID"]]
  precondition(R671StatusGlyphMatcher.audit(frames:[fake],references:refs)["status"] as? String=="HOLD_UNTRUSTED_GLYPH_INPUT")
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent("r671-fixture-\(UUID().uuidString)")
  defer{try? FileManager.default.removeItem(at:dir)}
  let payload:[String:Any]=["schema":"trueplan.r671.user-reviewed-reference-library.v1","references":refs]
  try! JSONSerialization.data(withJSONObject:payload).write(to:dir)
  precondition(R671StatusGlyphMatcher.loadReferences(at:dir).count==4)
  print("R671_REVIEWED_GLYPH_MATCH_SMOKE_PASS 8")
 }
}
