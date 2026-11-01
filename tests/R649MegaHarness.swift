import Foundation
@main struct R649Harness {
 static func main() {
  var n=0
  func check(_ yes:Bool,_ label:String) {
   precondition(yes,label)
   n += 1
  }
  let m=R649MegaRegistryAudit.self
  check(m.validCatalog(),"81_unique_catalog")
  check(m.entries.count==81,"81_count")
  check(Set(m.entries.map{$0.id}).count==81,"ids_unique")
  for (phase,count) in [("M-A",59),("M-B",16),("M-C",6)] {
   check(m.entries.filter{$0.phase==phase}.count==count,phase)
  }
  for label in ["メガリザードンX","メガリザードンY",
   "メガライチュウX","メガライチュウY",
   "メガアブソル","メガアブソルZ",
   "メガガブリアス","メガガブリアスZ",
   "メガルカリオ","メガルカリオZ",
   "メガギャラドス","メガグソクムシャ"] {
   check(m.candidates(label).count==1,"isolated_"+label)
  }
  check(m.candidates("メガルカリオZ")[0].variant=="Z",
   "z_must_not_match_normal")
  check(m.candidates("メガルカリオ")[0].variant=="N",
   "normal_must_not_be_z")
  for name in ["ギャラドス","メガホーン","メガシンカ",
   "メガシンカした","メガドレイン", "メガメガニウムZ"] {
   check(m.candidates(name).isEmpty,"negative_"+name)
  }
  let sha=String(repeating:"a",count:64)
  func cue(_ name:String,_ ref:String)->[String:Any] {
   ["evidence_ref":ref,"raw_text":name,
    "source_image_sha256":sha,
    "capture_session_id":"s1","frame_id":1,"epoch":1,
    "owner_verified":false,"actual_mega_event_confirmed":false]
  }
  func source(_ text:String)->[String:Any] {
   ["r647_mega_boundary":[
    "schema":"trueplan.r647.mega-signal-boundary.v1",
    "source_kind":"LIVE_RETAINED_FRAME",
    "raw_image_sha256":sha,
    "analysis_image_sha256":sha,
    "capture_session_id":"s1","frame_id":1,"epoch":1,
    "owner_verified":false,"current_state_eligible":false,
    "battle_advice_authorized":false,
    "cues":[cue(text,"r0")]] as [String:Any]]
  }
  var doc=source("メガルカリオZ")
  m.enrich(&doc,sourceKind:"LIVE_RETAINED_FRAME")
  let report=doc["r649_mega_catalog"] as! [String:Any]
  let forms=report["candidates"] as! [[String:Any]]
  check(forms.count==1,"bound_candidate")
  check(forms[0]["form_id"] as? String=="lucario-mega-z",
   "variant_preserved")
  check(report["mega_form_certified"] as? Bool==false,
   "no_false_certification")
  check(report["owner_verified"] as? Bool==false,
   "no_false_owner")
  check(report["battle_advice_authorized"] as? Bool==false,
   "no_false_advice")
  check(report["eligible_form_count"] as? Int==81,
   "complete_catalog")
  doc=source("メガルカリオZ")
  var bad=doc["r647_mega_boundary"] as! [String:Any]
  var wrong=cue("メガルカリオZ","r0")
  wrong["frame_id"]=2
  bad["cues"]=[wrong]
  doc["r647_mega_boundary"]=bad
  m.enrich(&doc,sourceKind:"LIVE_RETAINED_FRAME")
  check(doc["r649_status"] as? String == "HOLD_CUE_BINDING_CONTRADICTION", "reject_wrong_frame")
  check(doc["r649_mega_catalog"]==nil,"discard_bad_result")
  doc=source("メガルカリオZ")
  m.enrich(&doc,sourceKind:"OTHER")
  check(doc["r649_mega_catalog"]==nil,"reject_source")
  check(n>=35,"minimum_test_count")
  print("R649_CATALOG_PASS",n)
 }
}
