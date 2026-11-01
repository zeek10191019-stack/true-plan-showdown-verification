import Foundation

// The M-C whitelist is a *catalog*, never a form classifier.
// Any signal remains non-certifying until independent game
// frame ownership, image references and variant proof exist.
struct R649MegaEntry: Equatable {
 let species: String
 let jp: String
 let variant: String
 let phase: String
 var id: String {
  species.lowercased() + "-mega" +
  (variant == "N" ? "" : "-" + variant.lowercased())
 }
 var label: String {
  "メガ" + jp + (variant == "N" ? "" : variant)
 }
}

enum R649MegaRegistryAudit {
 static let schema = "trueplan.r649.mega-81.v1"
 static let sourceKinds: Set<String> = [
  "LIVE_RETAINED_FRAME", "USER_IMPORTED_PNG_OFFLINE_ONLY"
 ]
 private static let source = """
Venusaur|フシギバナ|N|M-A
Charizard|リザードン|X|M-A
Charizard|リザードン|Y|M-A
Blastoise|カメックス|N|M-A
Beedrill|スピアー|N|M-A
Pidgeot|ピジョット|N|M-A
Clefable|ピクシー|N|M-A
Alakazam|フーディン|N|M-A
Victreebel|ウツボット|N|M-A
Slowbro|ヤドラン|N|M-A
Gengar|ゲンガー|N|M-A
Kangaskhan|ガルーラ|N|M-A
Starmie|スターミー|N|M-A
Pinsir|カイロス|N|M-A
Gyarados|ギャラドス|N|M-A
Aerodactyl|プテラ|N|M-A
Dragonite|カイリュー|N|M-A
Meganium|メガニウム|N|M-A
Feraligatr|オーダイル|N|M-A
Ampharos|デンリュウ|N|M-A
Steelix|ハガネール|N|M-A
Scizor|ハッサム|N|M-A
Heracross|ヘラクロス|N|M-A
Skarmory|エアームド|N|M-A
Houndoom|ヘルガー|N|M-A
Tyranitar|バンギラス|N|M-A
Gardevoir|サーナイト|N|M-A
Sableye|ヤミラミ|N|M-A
Aggron|ボスゴドラ|N|M-A
Medicham|チャーレム|N|M-A
Manectric|ライボルト|N|M-A
Sharpedo|サメハダー|N|M-A
Camerupt|バクーダ|N|M-A
Altaria|チルタリス|N|M-A
Banette|ジュペッタ|N|M-A
Chimecho|チリーン|N|M-A
Absol|アブソル|N|M-A
Glalie|オニゴーリ|N|M-A
Lopunny|ミミロップ|N|M-A
Garchomp|ガブリアス|N|M-A
Lucario|ルカリオ|N|M-A
Abomasnow|ユキノオー|N|M-A
Gallade|エルレイド|N|M-A
Froslass|ユキメノコ|N|M-A
Emboar|エンブオー|N|M-A
Excadrill|ドリュウズ|N|M-A
Audino|タブンネ|N|M-A
Chandelure|シャンデラ|N|M-A
Golurk|ゴルーグ|N|M-A
Chesnaught|ブリガロン|N|M-A
Delphox|マフォクシー|N|M-A
Greninja|ゲッコウガ|N|M-A
Floette|フラエッテ|N|M-A
Meowstic|ニャオニクス|N|M-A
Hawlucha|ルチャブル|N|M-A
Crabominable|ケケンカニ|N|M-A
Drampa|ジジーロン|N|M-A
Scovillain|スコヴィラン|N|M-A
Glimmora|キラフロル|N|M-A
Raichu|ライチュウ|X|M-B
Raichu|ライチュウ|Y|M-B
Sceptile|ジュカイン|N|M-B
Blaziken|バシャーモ|N|M-B
Swampert|ラグラージ|N|M-B
Mawile|クチート|N|M-B
Metagross|メタグロス|N|M-B
Staraptor|ムクホーク|N|M-B
Scolipede|ペンドラー|N|M-B
Scrafty|ズルズキン|N|M-B
Eelektross|シビルドン|N|M-B
Pyroar|カエンジシ|N|M-B
Malamar|カラマネロ|N|M-B
Barbaracle|ガメノデス|N|M-B
Dragalge|ドラミドロ|N|M-B
Falinks|タイレーツ|N|M-B
Absol|アブソル|Z|M-C
Salamence|ボーマンダ|N|M-C
Garchomp|ガブリアス|Z|M-C
Lucario|ルカリオ|Z|M-C
Golisopod|グソクムシャ|N|M-C
Baxcalibur|セグレイブ|N|M-C
"""
 static let entries: [R649MegaEntry] = source
  .split(separator:"\n").compactMap { row in
   let a=row.split(separator:"|",omittingEmptySubsequences:false)
   guard a.count == 4 else {return nil}
   return R649MegaEntry(species:String(a[0]),jp:String(a[1]),
    variant:String(a[2]),phase:String(a[3]))
  }
 static func validCatalog() -> Bool {
  guard entries.count == 81,
   Set(entries.map{$0.id}).count == 81,
   Set(entries.map{$0.label}).count == 81 else {return false}
  for (phase,count) in [("M-A",59),("M-B",16),("M-C",6)] {
   guard entries.filter({$0.phase == phase}).count == count
   else {return false}
  }
  let multiples = Dictionary(grouping:entries,by:{$0.species})
   .filter{$0.value.count>1}.mapValues{$0.count}
  guard multiples == ["Charizard":2,"Raichu":2,
   "Absol":2,"Garchomp":2,"Lucario":2] else {return false}
  return true
 }
 private static func safeHex(_ x:Any?) -> String? {
  guard let s=x as? String,s.utf8.count==64,
   s.utf8.allSatisfy({(48...57).contains($0) ||
    (97...102).contains($0)}) else {return nil}
  return s
 }
 private static func number(_ x:Any?) -> Int? {
  guard let a=x as? NSNumber,a.intValue>0,
   a.doubleValue==Double(a.intValue) else {return nil}
  return a.intValue
 }
 private static func normalize(_ s:String) -> String {
  s.precomposedStringWithCompatibilityMapping
   .replacingOccurrences(of:" ",with:"")
   .replacingOccurrences(of:"　",with:"")
 }
 // OCR hints are allowed; matching names does not prove a form.
 static func candidates(_ text:String) -> [R649MegaEntry] {
  let s=normalize(text)
  guard s.utf8.count<=160 else {return []}
  let matched=entries.filter {s == normalize($0.label)}
  // Longest variant wins for *each* base species.
  return matched.filter {f in
   !matched.contains {other in
    other.species==f.species &&
    other.label.count>f.label.count}
  }.sorted{$0.id<$1.id}
 }
 static func enrich(_ doc:inout [String:Any],sourceKind:String) {
  doc.removeValue(forKey:"r649_mega_catalog")
  doc["r649_status"]="HOLD_SOURCE_OR_BOUNDARY_MISSING"
  guard validCatalog(),sourceKinds.contains(sourceKind),
   let prior=doc["r647_mega_boundary"] as? [String:Any],
   prior["schema"] as? String=="trueplan.r647.mega-signal-boundary.v1",
   prior["source_kind"] as? String==sourceKind,
   prior["current_state_eligible"] as? Bool==false,
   prior["battle_advice_authorized"] as? Bool==false,
   prior["owner_verified"] as? Bool==false,
   let png=safeHex(prior["raw_image_sha256"]),
   let sha=safeHex(prior["analysis_image_sha256"]),
   let sid=prior["capture_session_id"] as? String,
   !sid.isEmpty,
   let frame=number(prior["frame_id"]),
   let epoch=number(prior["epoch"]),
   let cues=prior["cues"] as? [[String:Any]],
   cues.count<=288 else {return}
  var observed=[[String:Any]]()
  var seen=Set<String>()
  for cue in cues {
   guard let ref=cue["evidence_ref"] as? String,
    !ref.isEmpty,seen.insert(ref).inserted,
    cue["source_image_sha256"] as? String==sha,
    cue["capture_session_id"] as? String==sid,
    number(cue["frame_id"])==frame,
    number(cue["epoch"])==epoch,
    cue["owner_verified"] as? Bool==false,
    cue["actual_mega_event_confirmed"] as? Bool==false,
    let raw=cue["raw_text"] as? String else {
    doc["r649_status"]="HOLD_CUE_BINDING_CONTRADICTION"
    return
   }
   for f in candidates(raw) {
    observed.append(["form_id":f.id,
     "base_species":f.species,"branch":f.variant,
     "regulation_first_allowed":f.phase,
     "source_ref":ref,"candidate_only":true,
     "owner":"UNKNOWN","mega_activated":"UNKNOWN",
     "visual_reference_certified":false])
   }
  }
  doc["r649_mega_catalog"] = [
   "schema":schema,"source_kind":sourceKind,
   "raw_image_sha256":png,"analysis_image_sha256":sha,
   "capture_session_id":sid,"frame_id":frame,
   "epoch":epoch,"eligible_form_count":81,
   "regulated_as_of":"2026-11-01_M-C",
   "catalog_integrity":true,"candidates":observed,
   "candidate_count":observed.count,
   "unverified_visual_form_count":81,
   "same_name_not_form_proof":true,
   "no_animation_not_negative_proof":true,
   "owner_verified":false,"mega_event_certified":false,
   "mega_form_certified":false,"current_state_eligible":false,
   "battle_advice_authorized":false,
   "actual_game_image_accuracy":"NOT_MEASURED"
  ] as [String:Any]
  doc["r649_status"]="CATALOG_COVERED_VISUAL_UNCERTIFIED"
 }
}
