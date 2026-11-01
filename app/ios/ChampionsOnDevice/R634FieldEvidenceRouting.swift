import Foundation
import CoreFoundation

/// R634. Routes the 79 existing R581 fields into real available evidence sources.
/// This is an evidence bridge, NOT proof of correct battle-state recognition.
/// In particular the same unowned OCR observation must not become an own or
/// opponent fact merely because both entries reference it.
enum R634FieldEvidenceRouting {
    static let schema = "trueplan.r634.field-reader-routing.v1"
    private static let metadata = Set([
        "capture.frame_id", "capture.epoch", "capture.session", "capture.pixel_geometry", "capture.clock"
    ])
    private static let logFields = Set([
        "battle.turn", "battle.phase", "battle.timer", "battle.switch_history",
        "battle.faint_history", "battle.move_history", "battle.mega_history"
    ])
    private static let pixelFields = Set([
        "own.hp", "own.hp_max", "own.hp_percent", "opponent.hp",
        "opponent.hp_max", "opponent.hp_percent", "own.mega_visual_form",
        "opponent.mega_visual_form"
    ])
    private static let transformFields = Set([
        "screen.orientation", "screen.ui_state", "screen.menu_state"
    ])
    private static let derivedFields = Set([
        "own.hazard_layers", "opponent.hazard_layers", "own.mega_history",
        "opponent.mega_history", "own.one_time_resource", "opponent.one_time_resource",
        "battle.conflict_and_staleness"
    ])
    private static func isSHA(_ s:String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func integer(_ raw:Any?) -> Int64? {
        guard let n=raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue > 0,
              n.doubleValue < Double(Int64.max), n.doubleValue == Double(n.int64Value) else {return nil}
        return n.int64Value
    }
    private static func route(_ field:String) -> String? {
        if metadata.contains(field) {return "CAPTURE_RECEIPT"}
        if transformFields.contains(field) {return "SCREEN_LAYOUT_CLASSIFIER"}
        if logFields.contains(field) {return "GAME_LOG_SCREEN_OCR_OR_TIMELINE"}
        if pixelFields.contains(field) {return "PIXEL_AND_OCR_WITH_OWNER_CALIBRATION"}
        if derivedFields.contains(field) {return "TEMPORAL_EVENT_RECONCILIATION"}
        if field.hasPrefix("own.") || field.hasPrefix("opponent.") {
            return "SIDE_SCOPED_OCR_AND_LOG_REQUIRES_OWNER_PROOF"
        }
        if field.hasPrefix("field.") {return "FIELD_OCR_AND_TIMED_EVENT_RECONCILIATION"}
        return nil
    }
    /// Set of all known evidence-reader routes, checked against the R581 canonical catalog.
    static func catalog() -> [[String:String]] {
        R581ReadabilityCoverage.tracks.compactMap { field, _ in
            guard let r=route(field) else{return nil}
            return ["field":field,"reader_route":r]
        }
    }
    static func enrich(_ document:inout [String:Any], sourceKind:String) {
        let expected=R581ReadabilityCoverage.tracks.map{$0.0}
        guard expected.count==79, Set(expected).count==79,
              let existing=document["r581_full_read_coverage"] as? [String:Any],
              existing["schema"] as? String == R581ReadabilityCoverage.schema,
              existing["source_kind"] as? String == sourceKind,
              let fields=existing["fields"] as? [[String:Any]], fields.count==79,
              fields.compactMap({$0["field"] as? String})==expected,
              catalog().count==79 else {
            document["r634_field_reader_status"]="REJECTED_R581_CATALOG_OR_SOURCE_MISMATCH"
            return
        }
        let hash=document["png_sha256"] as? String ?? ""
        let frame=integer(document["frame_id"])
        let epoch=integer(document["epoch"])
        let session=document["capture_session_id"] as? String
        let width=integer(document["image_width"])
        let height=integer(document["image_height"])
        let receipt=sourceKind=="LIVE_RETAINED_FRAME" && isSHA(hash) &&
            existing["source_binding_valid"] as? Bool == true &&
            existing["image_sha256"] as? String == hash &&
            frame != nil && epoch != nil && session != nil &&
            !session!.isEmpty && session!.utf8.count<=160 &&
            width != nil && height != nil && width! <= 16384 && height! <= 16384
        let snapshot=document["screen_read_state"] as? [String:Any]
        let boundSnapshot=existing["snapshot_binding_valid"] as? Bool == true &&
            (sourceKind != "LIVE_RETAINED_FRAME" || (receipt &&
                integer(snapshot?["frame_id"]) == frame &&
                integer(snapshot?["epoch"]) == epoch &&
                snapshot?["capture_session_id"] as? String == session))
        let analysisSHA=snapshot?["image_sha256"] as? String ?? ""
        let candidates:[[String:Any]] = boundSnapshot && isSHA(analysisSHA) ?
            (snapshot?["candidates"] as? [[String:Any]] ?? []) : []
        var routed=[[String:Any]]()
        var receiptCount=0
        var candidateCount=0
        for row in fields {
            let field=row["field"] as! String
            var record=row
            record["reader_route"]=route(field)!
            record["reader_path_declared"] = true // route exists, not recognition quality
            record["reader_input_observed"] = false
            record["reader_producing_verified_game_value"] = false
            record["source_proof"] = "NO_GAME_GROUND_TRUTH"
            record["current_value_admitted"] = false
            record["owner_verified"] = false
            record["time_verified"] = false
            record["observed_metadata_value"] = NSNull()
            if receipt && metadata.contains(field) {
                var value:Any = NSNull()
                switch field {
                case "capture.frame_id":value=frame!
                case "capture.epoch":value=epoch!
                case "capture.session":value=session!
                case "capture.pixel_geometry":value=["width":width!,"height":height!,
                    "raw_png_sha256":hash] as [String:Any]
                case "capture.clock":
                    if let clock=integer(document["observed_ms_monotonic"]) {value=clock}
                default:break
                }
                if !(value is NSNull) {
                    record["observed_metadata_value"]=value
                    record["status"]="SOURCE_RECEIPT_METADATA_ONLY"
                    record["source_proof"]="RAW_FRAME_RECEIPT_NOT_BATTLE_VALUE"
                    record["reader_input_observed"]=true
                    receiptCount+=1
                }
            }
            // Add bounded, image-linked OCR observations, NEVER assigning actors.
            let refs=Set((row["candidate_refs"] as? [String] ?? []).prefix(16))
            var snippets=[[String:Any]]()
            if boundSnapshot && !refs.isEmpty {
                for item in candidates where snippets.count<4 {
                    guard let ref=item["evidence_ref"] as? String, refs.contains(ref),
                          item["image_sha256"] as? String == analysisSHA,
                          item["side"] as? String == "UNKNOWN_OWNER",
                          item["verification_status"] as? String == "UNVERIFIED",
                          item["current_state_eligible"] as? Bool == false,
                          let raw=item["raw_text"] as? String,raw.utf8.count<=160 else {continue}
                    snippets.append(["evidence_ref":ref,"text_candidate":raw,
                                     "actor":"UNKNOWN","verification":"UNVERIFIED"])
                }
            }
            record["bounded_ocr_evidence"]=snippets
            if !snippets.isEmpty {
                candidateCount+=1
                record["reader_input_observed"]=true
            }
            if logFields.contains(field) && snippets.isEmpty {
                record["source_proof"]="GAME_LOG_PANEL_NOT_CAPTURED_OR_UNVERIFIED"
            }
            routed.append(record)
        }
        var replacement=existing
        replacement["fields"]=routed
        replacement["r634_schema"]=schema
        replacement["r634_reader_route_count"]=catalog().count
        replacement["r634_source_receipt_metadata_count"]=receiptCount
        replacement["r634_fields_with_bounded_ocr_evidence"]=candidateCount
        replacement["r634_game_values_certified"]=0
        replacement["r634_status"]="ROUTED_SOURCE_EVIDENCE_NOT_79_GAME_READ_CERTIFIED"
        document["r581_full_read_coverage"]=replacement
        document["r634_field_reader_status"]="ROUTES_WIRED_NO_GAME_CERTIFICATION"
    }
}
