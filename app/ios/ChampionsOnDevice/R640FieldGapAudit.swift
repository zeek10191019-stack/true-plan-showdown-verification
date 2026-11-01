import Foundation
import CoreFoundation
enum R640FieldGapAudit {
static let schema = "trueplan.r640.field-gap-matrix.v1"
private static let kinds = Set([
"LIVE_RETAINED_FRAME", "USER_IMPORTED_PNG_OFFLINE_ONLY"
])
private static func sha(_ value:Any?) -> String? {
guard let x=value as? String,x.utf8.count==64,
x.utf8.allSatisfy({(48...57).contains($0) ||
(97...102).contains($0)}) else{return nil}
return x
}
private static func count(_ value:Any?,maximum:Int)->Int? {
guard let n=value as? NSNumber,
CFGetTypeID(n) != CFBooleanGetTypeID(),
n.doubleValue.isFinite,n.doubleValue>=0,
n.doubleValue<=Double(maximum),
n.doubleValue==Double(n.intValue) else{return nil}
return n.intValue
}
private static func candidates(_ value:Any?,limit:Int)->Int? {
guard let rows=value as? [[String:Any]],rows.count<=limit else {
return value == nil ? 0 : nil
}
for r in rows {
guard r["owner_verified"] as? Bool != true,
r["current_value_admitted"] as? Bool != true else{return nil}
}
return rows.count
}
static func enrich(_ doc:inout [String:Any],sourceKind:String) {
doc.removeValue(forKey:"r640_field_gap_report")
doc["r640_status"]="HOLD_UNBOUND_OR_ALTERED_FIELD_CATALOG"
let names=R581ReadabilityCoverage.tracks.map{$0.0}
guard kinds.contains(sourceKind),names.count==79,
Set(names).count==79,
let cover=doc["r581_full_read_coverage"] as? [String:Any],
cover["schema"] as? String == R581ReadabilityCoverage.schema,
cover["source_kind"] as? String == sourceKind,
cover["field_count"] as? Int == 79,
cover["live_capture_certified"] as? Bool == false,
cover["actual_game_accuracy_certified"] as? Bool == false,
cover["current_state_eligible"] as? Bool == false,
cover["battle_advice_authorized"] as? Bool == false,
cover["source_binding_valid"] as? Bool == true,
cover["owner_certified"] as? Bool == false,
cover["turn_certified"] as? Bool == false,
let rawSHA=sha(cover["image_sha256"]),
let storedSHA=sha(sourceKind=="LIVE_RETAINED_FRAME" ?
doc["png_sha256"] : doc["image_sha256"]),
rawSHA==storedSHA,
let rows=cover["fields"] as? [[String:Any]],
rows.compactMap({$0["field"] as? String})==names else {return}
var records=[[String:Any]]()
var hist=["NO_FIELD_EVIDENCE":0,"OCR_TEXT_CANDIDATE":0,
"LAYOUT_HYPOTHESIS":0,"TYPED_HYPOTHESIS":0,
"CAPTURE_RECEIPT_ONLY":0]
for (i,row) in rows.enumerated() {
guard row["current_value_admitted"] as? Bool == false,
row["owner_verified"] as? Bool == false,
row["time_verified"] as? Bool == false,
row["reader_producing_verified_game_value"] as? Bool != true,
let refs=row["candidate_refs"] as? [String],refs.count<=16,
Set(refs).count==refs.count,
refs.allSatisfy({!$0.isEmpty && $0.utf8.count<=160}),
let observed=count(row["candidate_count"],maximum:288),
let layout=candidates(row["r635_structured_layout_candidates"],limit:4),
let typed=candidates(row["r636_typed_candidates"],limit:4),
(row["bounded_ocr_evidence"] == nil ||
row["bounded_ocr_evidence"] is [[String:Any]]) else {
doc["r640_status"]="HOLD_TAMPERED_FIELD_EVIDENCE"
return
}
let snippets=row["bounded_ocr_evidence"] as? [[String:Any]] ?? []
guard snippets.count<=4 else {
doc["r640_status"]="HOLD_TAMPERED_FIELD_EVIDENCE"
return
}
for entry in snippets {
guard entry["verification"] as? String == "UNVERIFIED",
entry["actor"] as? String == "UNKNOWN" else {
doc["r640_status"]="HOLD_TAMPERED_FIELD_EVIDENCE";return
}
}
let hasReceipt=row["observed_metadata_value"] != nil &&
!(row["observed_metadata_value"] is NSNull)
let declaredLayout=cover["r635_schema"] as? String ==
"trueplan.r635.structured-layout-field-evidence.v1"
let declaredTyped=cover["r636_schema"] as? String ==
"trueplan.r636.typed-hud-hypotheses.v1"
let routeAvailable=cover["r634_schema"] as? String ==
"trueplan.r634.field-reader-routing.v1"
let boundReceipt=hasReceipt && routeAvailable
let stage:String = boundReceipt ? "CAPTURE_RECEIPT_ONLY" :
(typed>0 && declaredTyped) ? "TYPED_HYPOTHESIS" :
(layout>0 && declaredLayout) ? "LAYOUT_HYPOTHESIS" :
(observed>0 || !snippets.isEmpty) ? "OCR_TEXT_CANDIDATE" :
"NO_FIELD_EVIDENCE"
hist[stage,default:0]+=1
let blocker:String
if boundReceipt {blocker="METADATA_NOT_BATTLE_VALUE"}
else if stage != "NO_FIELD_EVIDENCE" {
blocker="OWNER_ORIENTATION_TURN_AND_GROUND_TRUTH_UNVERIFIED"
} else if names[i].hasPrefix("battle.") {
blocker="GAME_EVENT_LOG_NOT_AVAILABLE"
} else {
blocker="NO_BOUND_VISIBLE_VALUE_FOR_THIS_FIELD"
}
records.append(["field":names[i],"evidence_stage":stage,
"primary_blocker":blocker,"owner_verified":false,
"current_value_admitted":false,
"verified_game_value":false])
}
let snap=doc["screen_read_state"] as? [String:Any]
let analysisSHA=sha(snap?["image_sha256"])
let coveredAnalysisSHA=sha(cover["analysis_image_sha256"])
let frameBound=cover["snapshot_binding_valid"] as? Bool == true &&
analysisSHA != nil && analysisSHA == coveredAnalysisSHA &&
snap?["current_state_eligible"] as? Bool == false &&
snap?["battle_advice_authorized"] as? Bool == false
let orientation=doc["r639_orientation_probe"] as? [String:Any]
let orientationBound=frameBound &&
orientation?["schema"] as? String ==
"trueplan.r639.orientation-anchor-probe.v1" &&
orientation?["image_sha256"] as? String == analysisSHA &&
orientation?["orientation_verified"] as? Bool == false &&
orientation?["owner_verified"] as? Bool == false &&
orientation?["battle_advice_authorized"] as? Bool == false
let orientationStatus:String = orientationBound ?
(orientation?["status"] as? String ?? "UNAVAILABLE") : "UNAVAILABLE"
let report:[String:Any]=[
"schema":schema,"source_kind":sourceKind,
"raw_image_sha256":rawSHA,
"field_count":79,"field_diagnostics":records,
"evidence_stage_counts":hist,
"bound_analysis_snapshot_present":frameBound,
"orientation_hypothesis_status":orientationStatus,
"orientation_verified":false,"owner_verified":false,
"turn_verified":false,"game_fields_certified":0,
"battle_advice_authorized":false,
"requires_real_game_ground_truth":true,
"capture_mode":"ONE_TAP_LOCAL_EVIDENCE_ONLY",
"status":"HISTORICAL_79_FIELD_GAP_REPORT_NOT_CERTIFIED"
]
guard JSONSerialization.isValidJSONObject(report) else {
doc["r640_status"]="HOLD_JSON_SERIALIZATION"
return
}
doc["r640_field_gap_report"]=report
doc["r640_status"]="HISTORICAL_79_FIELD_GAP_REPORT_NOT_CERTIFIED"
}
}
