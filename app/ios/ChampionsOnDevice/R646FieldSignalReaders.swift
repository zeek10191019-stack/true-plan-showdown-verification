import Foundation
import CoreFoundation
enum R646FieldSignalReaders {
static let schema = "trueplan.r646.field-signal-readers.v1"
private static func integer(_ a:Any?) -> Int? {
guard let n=a as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<Double(Int.max),
Double(n.intValue)==n.doubleValue else{return nil}
return n.intValue
}
private static func sha(_ a:Any?) -> String? {
guard let s=a as? String,s.utf8.count==64,
s.utf8.allSatisfy({(48...57).contains($0) ||
(97...102).contains($0)}) else{return nil}
return s
}
private static func words(_ s:String) -> String {
s.precomposedStringWithCompatibilityMapping
.replacingOccurrences(of:"　",with:" ")
.trimmingCharacters(in:.whitespacesAndNewlines)
}
private static func matches(_ s:String,_ r:String)->Bool {
s.range(of:r,options:.regularExpression) != nil
}
private static func keys(_ field:String)->[String] {
let f=field.hasPrefix("own.") || field.hasPrefix("opponent.")
? String(field.split(separator:".").dropFirst().joined(separator:".")) : field
switch f {
case "battle.turn":return [#"(?:第\s*)?[0-9]{1,3}\s*ターン"#]
case "battle.timer":return [#"(?:残り|制限)\s*[0-9]{1,3}\s*(?:秒|sec)"#]
case "battle.phase":return ["対戦開始|対戦終了|勝負|選出|コマンド"]
case "battle.switch_history":return ["引っ込めた|ひっこめた|戻した|もどした|くりだした|繰り出した"]
case "battle.faint_history":return ["倒れた|たおれた|ひんし|戦闘不能"]
case "battle.move_history":return ["使った|つかった|使用した"]
case "battle.mega_history","mega_history","mega_trigger":return ["メガシンカ|メガ進化|メガシンカした"]
case "major_status":return ["^(やけど|まひ|ねむり|こおり|どく|もうどく|BRN|PAR|SLP|FRZ|PSN)$"]
case "volatile_status":return ["こんらん|混乱|ひるみ|やどりぎ|みがわり|ちょうはつ|アンコール|かなしばり"]
case "boost_seven":return ["(?:こうげき|ぼうぎょ|とくこう|とくぼう|すばやさ|命中|回避).{0,12}[+-]?[0-6]", "(?:上がった|下がった)"]
case "ability":return ["^(?:特性|とくせい)[：:].+"]
case "held_item":return ["^(?:持ち物|もちもの|どうぐ)[：:].+"]
case "gender":return ["[♀♂]"]
case "active_species","identity","party_six","active_slot":return ["^(?:ポケモン|手持ち|相手|名前)[：:].+"]
case "moves_four","moves_revealed":return ["^(?:技|わざ)[：:].+"]
case "pp_four","pp_revealed":return [#"(?:PP[：:]?\s*)?[0-9]{1,2}\s*/\s*[0-9]{1,2}"#]
case "move_types":return ["(?:タイプ)[：:](?:ノーマル|ほのお|みず|でんき|くさ|こおり|かくとう|どく|じめん|ひこう|エスパー|むし|いわ|ゴースト|ドラゴン|あく|はがね|フェアリー)"]
case "hp","hp_max":return [#"(?:HP)?\s*[0-9]{1,4}/[0-9]{1,4}"#]
case "hp_percent":return ["[0-9]{1,3}(?:\\.[0-9]{1,2})?%"]
case "field.weather","field.weather_turns":return ["あめ|雨|ひざし|日差し|晴れ|すなあらし|砂嵐|ゆき|雪"]
case "field.terrain","field.terrain_turns":return ["エレキフィールド|グラスフィールド|サイコフィールド|ミストフィールド"]
case "field.trick_room","field.trick_room_turns":return ["トリックルーム"]
case "field.other_rooms":return ["マジックルーム|ワンダールーム"]
case "reflect":return ["リフレクター"]
case "light_screen":return ["ひかりのかべ|光の壁"]
case "aurora_veil":return ["オーロラベール"]
case "tailwind":return ["おいかぜ|追い風"]
case "safeguard_mist":return ["しろいきり|白い霧|しんぴのまもり|神秘の守り"]
case "side_effect_turns":return ["(?:リフレクター|ひかりのかべ|オーロラベール|おいかぜ).{0,12}(?:残り|あと)[0-9]{1,2}ターン"]
case "entry_hazards","hazard_layers":return ["ステルスロック|まきびし|どくびし|ねばねばネット"]
case "field.temporary_effects":return ["じゅうりょく|重力|ふういん|フェアリーロック"]
case "one_time_resource":return ["メガシンカ|メガ進化|テラスタル|Zワザ"]
default:return []
}
}
private static func visual(_ name:String)->Bool {
name.contains("mega_visual_form") ||
name == "own.party_six" || name == "opponent.party_six"
}
private static func temporal(_ name:String)->Bool {
name.contains("_turns") || name.contains("_history") ||
name.contains("one_time_resource") || name.contains("hazard_layers") ||
name.hasPrefix("battle.") && name != "battle.turn" &&
name != "battle.phase" && name != "battle.timer"
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc.removeValue(forKey:"r646_field_readers")
doc["r646_status"]="HOLD_UNBOUND_SOURCE_OR_CATALOG"
guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
let coverage=doc["r581_full_read_coverage"] as? [String:Any],
coverage["schema"] as? String == R581ReadabilityCoverage.schema,
coverage["source_kind"] as? String == sourceKind,
coverage["source_binding_valid"] as? Bool == true,
coverage["snapshot_binding_valid"] as? Bool == true,
coverage["current_state_eligible"] as? Bool == false,
coverage["battle_advice_authorized"] as? Bool == false,
let raw=sha(coverage["image_sha256"]),
raw==sha(sourceKind == "LIVE_RETAINED_FRAME" ? doc["png_sha256"] : doc["image_sha256"]),
let snap=doc["screen_read_state"] as? [String:Any],
let analysis=sha(snap["image_sha256"]),
analysis==sha(coverage["analysis_image_sha256"]),
snap["source_validation"] as? String == "PASS_FRAME_BINDING_ONLY",
snap["current_state_eligible"] as? Bool == false,
snap["battle_advice_authorized"] as? Bool == false,
let frame=integer(snap["frame_id"]),frame>0,
let epoch=integer(snap["epoch"]),epoch>0,
let session=snap["capture_session_id"] as? String,
!session.isEmpty,session.utf8.count<=160,
let inventory=snap["ocr_source_inventory"] as? [[String:Any]],
inventory.count<=288,
let fields=coverage["fields"] as? [[String:Any]],
fields.count==79 else{return}
let list=R581ReadabilityCoverage.tracks.map{$0.0}
guard list.count==79,Set(list).count==79,
fields.compactMap({$0["field"] as? String})==list else{return}
var width=integer(doc["image_width"]),height=integer(doc["image_height"])
if analysis != raw {
guard coverage["declared_analysis_projection_valid"] as? Bool == true,
let p=doc["analysis_projection"] as? [String:Any],
p["analysis_image_sha256"] as? String == analysis,
p["raw_image_sha256"] as? String == raw,
p["status"] as? String == "DECLARED_GEOMETRY_ONLY",
integer(p["frame_id"]) == frame,
integer(p["epoch"]) == epoch,
p["capture_session_id"] as? String == session else{return}
width=integer(p["analysis_width"])
height=integer(p["analysis_height"])
}
guard let w=width,let h=height,(180...8192).contains(w),
(180...8192).contains(h) else{return}
struct Token {let ref:String;let raw:String;let roi:[String:Int]}
var items=[Token](),seen=Set<String>()
for row in inventory {
guard let ref=row["evidence_ref"] as? String,!ref.isEmpty,
ref.utf8.count<=160,seen.insert(ref).inserted,
let value=row["raw_text"] as? String,!value.isEmpty,
value.utf8.count<=160,
row["image_sha256"] as? String == analysis,
row["capture_session_id"] as? String == session,
integer(row["frame_id"]) == frame,
integer(row["epoch"]) == epoch,
row["owner_verified"] as? Bool == false,
let box=row["roi"] as? [String:Any],
let x=integer(box["x"]),let y=integer(box["y"]),
let dx=integer(box["width"]),let dy=integer(box["height"]),
dx>0,dy>0,x<w,y<h,dx<=w-x,dy<=h-y else {
doc["r646_status"]="HOLD_OCR_SOURCE_CONTRADICTION";return
}
if !ref.contains(".ocr_alternatives[") {
items.append(Token(ref:ref,raw:value,
roi:["x":x,"y":y,"width":dx,"height":dy]))
}
}
let moves=doc["r644_four_move_slots"] as? [String:Any]
let movesBound=moves?["schema"] as? String == "trueplan.r644.four-move-pp-pairs.v1" &&
moves?["raw_image_sha256"] as? String == raw &&
moves?["analysis_image_sha256"] as? String == analysis &&
moves?["capture_session_id"] as? String == session &&
integer(moves?["frame_id"]) == frame &&
integer(moves?["epoch"]) == epoch &&
moves?["owner_verified"] as? Bool == false &&
moves?["current_state_eligible"] as? Bool == false
let hp=doc["r645_dual_hp"] as? [String:Any]
let hpBound=hp?["schema"] as? String == "trueplan.r645.dual-hp-source-proof.v1" &&
hp?["raw_image_sha256"] as? String == raw &&
hp?["analysis_image_sha256"] as? String == analysis &&
hp?["capture_session_id"] as? String == session &&
integer(hp?["frame_id"]) == frame &&
integer(hp?["epoch"]) == epoch &&
hp?["owner_verified"] as? Bool == false &&
hp?["current_state_eligible"] as? Bool == false
var records=[[String:Any]](),observed=0
for field in list {
let patterns=keys(field)
var hits=[[String:Any]](),refs=Set<String>()
if !patterns.isEmpty {
for row in items where hits.count<8 {
let s=words(row.raw)
if patterns.contains(where:{matches(s,$0)}) && refs.insert(row.ref).inserted {
hits.append(["evidence_ref":row.ref,"text":row.raw,
"analysis_roi":row.roi,"side":"UNKNOWN_OWNER",
"current_value_admitted":false])
}
}
}
let stage:String
let source:String
let content:Any
if field.hasPrefix("capture.") {
source="CAPTURE_RECEIPT"
let original=fields.first(where:{$0["field"] as? String==field})
content=original?["observed_metadata_value"] ?? NSNull()
stage=content is NSNull ? "RECEIPT_MISSING" : "CAPTURE_METADATA_ONLY"
} else if field=="screen.ui_state" || field=="screen.menu_state" {
source="FRAME_CLASSIFIER"
content=snap["screen_kind"] ?? NSNull()
stage=content is NSNull ? "CLASSIFIER_MISSING" : "UI_CLASSIFICATION_CANDIDATE"
} else if field=="screen.orientation" {
source="FOUR_WAY_LAYOUT"
let proposal=doc["r641_rotated_hud_candidates"] as? [String:Any]
content=proposal?["rotation_candidate_degrees"] ?? NSNull()
stage=proposal?["status"] as? String == "UNIQUE_LAYOUT_HYPOTHESIS_NOT_CERTIFIED" ?
"ORIENTATION_LAYOUT_CANDIDATE" : "ORIENTATION_UNRESOLVED"
} else if ["own.moves_four","own.pp_four"].contains(field),
movesBound,let slots=moves?["four_slots"] as? [[String:Any]],
slots.count==4 {
source="R644_SOURCE_BOUND_MOVE_SLOTS"
content=slots.map {row -> Any in
let key=field=="own.moves_four" ? "name" : "pp"
return row[key] ?? NSNull()
}
stage="HISTORICAL_FOUR_SLOTS_OWNER_UNVERIFIED"
} else if ["own.hp","own.hp_max","opponent.hp_percent"].contains(field),
hpBound,let status=hp?["status"] as? String,
status=="DUAL_HP_SOURCE_BOUND_HISTORICAL_ONLY" {
let key=field=="opponent.hp_percent" ?
"opponent_position_percent_candidate" : "own_position_hp_candidate"
let entry=hp?[key] as? [String:Any]
let pair=entry?["value"] as? [String:Any]
source="R645_SOURCE_BOUND_DUAL_HP"
content=field=="own.hp" ? (pair?["current"] ?? NSNull()) :
field=="own.hp_max" ? (pair?["maximum"] ?? NSNull()) :
(entry?["value"] ?? NSNull())
stage="HISTORICAL_HP_POSITION_OWNER_UNVERIFIED"
} else if field=="own.hp_percent",hpBound,
let status=hp?["status"] as? String,
status=="DUAL_HP_SOURCE_BOUND_HISTORICAL_ONLY",
let entry=hp?["own_position_hp_candidate"] as? [String:Any],
let pair=entry["value"] as? [String:Any],
let a=integer(pair["current"]),let b=integer(pair["maximum"]),b>0,a<=b {
source="R645_DERIVED_DISPLAY_HP_RATIO"
content=100.0*Double(a)/Double(b)
stage="HISTORICAL_HP_POSITION_OWNER_UNVERIFIED"
} else if field=="battle.conflict_and_staleness" {
source="R551_SOURCE_CONFLICT_REPORT"
let conflicts=snap["conflicts"] as? [[String:Any]]
content=conflicts != nil && conflicts!.count<=512 ?
["ocr_conflict_count":conflicts!.count] as [String:Any] : NSNull()
stage=content is NSNull ? "CONFLICT_REPORT_NOT_AVAILABLE" :
"OCR_CONFLICTS_NOT_BATTLE_STATE"
} else if visual(field) {
source="PIXEL_SPRITE_CLASSIFIER_REQUIRED"
content=NSNull()
stage="MODEL_OR_CALIBRATION_MISSING"
} else {
source=temporal(field) ? "OCR_EVENT_TIMELINE_ATTEMPT" :
"FRAME_BOUND_OCR_PATTERN_ATTEMPT"
content=NSNull()
stage=hits.isEmpty ? (patterns.isEmpty ?
"FIELD_SPECIFIC_READER_NOT_IMPLEMENTED" :
temporal(field) ? "TEMPORAL_EVIDENCE_NOT_ESTABLISHED" :
"NO_MATCH_IN_AVAILABLE_OCR") :
(temporal(field) ? "TEXT_MENTION_NO_TURN_PROOF" :
"TEXT_CANDIDATE_OWNER_UNVERIFIED")
}
if !hits.isEmpty || stage=="CAPTURE_METADATA_ONLY" ||
stage=="UI_CLASSIFICATION_CANDIDATE" ||
stage=="HISTORICAL_FOUR_SLOTS_OWNER_UNVERIFIED" ||
stage=="HISTORICAL_HP_POSITION_OWNER_UNVERIFIED" ||
stage=="OCR_CONFLICTS_NOT_BATTLE_STATE" {observed+=1}
records.append(["field":field,"reader":source,
"attempt_status":stage,"ocr_evidence":hits,
"metadata_or_classifier_value":content,
"owner_verified":false,"turn_verified":false,
"game_value_certified":false,
"current_state_eligible":false])
}
let report:[String:Any]=["schema":schema,"source_kind":sourceKind,
"raw_image_sha256":raw,"analysis_image_sha256":analysis,
"capture_session_id":session,"frame_id":frame,"epoch":epoch,
"field_count":79,"field_read_attempts":records,
"fields_with_source_signal":observed,
"source_bound_ocr_tokens":items.count,
"game_fields_certified":0,"owner_verified":false,
"battle_advice_authorized":false,
"current_state_eligible":false,
"status":"79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED"]
guard JSONSerialization.isValidJSONObject(report) else {
doc["r646_status"]="HOLD_INVALID_JSON";return
}
doc["r646_field_readers"]=report
doc["r646_status"]="79_SOURCE_READER_ATTEMPTS_NOT_GAME_CERTIFIED"
}
}
