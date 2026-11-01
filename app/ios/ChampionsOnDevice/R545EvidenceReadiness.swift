import Foundation
import CoreFoundation

/// One-tap field trial checklist. All flags refer to recorded evidence only;
/// none authenticate a Pokémon owner, turn, Mega state or battle advice.
enum R545EvidenceReadiness {
    static let schema = "trueplan.r545.device-trial-evidence-readiness.v1"

    private static func nonnegative(_ raw: Any?) -> Int? {
        guard let n=raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue == Double(n.int64Value),
              n.int64Value >= 0, n.int64Value <= Int64(Int.max) else {return nil}
        return Int(n.int64Value)
    }

    static func inspect(_ root: [String: Any], frame: Int64, epoch: Int64) -> [String:Any] {
        let raw = root["image_png_base64"] as? String
        let imageHashed = (root["png_sha256"] as? String)?.count == 64
        let imagePresent = raw?.isEmpty == false && imageHashed &&
            nonnegative(root["frame_id"]).map(Int64.init) == frame &&
            nonnegative(root["epoch"]).map(Int64.init) == epoch
        let candidate = root["research_candidate_envelope"] as? String
        let ocrPresent = candidate?.isEmpty == false
        let spatial = root["r543_spatial_coverage"] as? [String:Any]
        let observations = root["r544_unattributed_observations"] as? [String:Any]
        let inventory = root["r537_inventory"] as? [String:Any]
        let geometry = nonnegative(spatial?["geometry_verified_rows"]) ?? 0
        let unlocated = nonnegative(spatial?["geometry_missing_rows"]) ?? 0
        let invalid = nonnegative(spatial?["geometry_invalid_rows"]) ?? 0
        let mismatch = nonnegative(spatial?["provenance_mismatch_rows"]) ?? 0
        let ocrParsed = (spatial?["status"] as? String) == "GEOMETRY_AUDIT_ONLY" &&
            (observations?["status"] as? String) == "UNATTRIBUTED_TEXT_CANDIDATES_ONLY"
        // Presence of a metrics dictionary is not sufficient: require all four
        // independently scoped diagnostic producers and explicit fail-closed flags.
        let expectedSources = ["r519_vision", "r520_roi_session", "r521_roi_collision", "r532_first_pass"]
        let metrics = root["metrics"] as? [String:Any]
        let sources = metrics?["sources"] as? [String:Any]
        let missingMetricSources = expectedSources.filter { sources?[$0] == nil }
        let metricsPresent = metrics != nil && missingMetricSources.isEmpty && sources?.count == 4 &&
            metrics?["all_sources_same_frame_certified"] as? Bool == false &&
            metrics?["battle_advice_authorized"] as? Bool == false &&
            root["metrics_scope"] as? String == "MULTI_WINDOW_COUNTERS_NOT_SELECTED_FRAME"
        let manifestPresent = inventory != nil
        let located = ocrPresent && ocrParsed && geometry > 0
        var missing: [String] = []
        if !imagePresent {missing.append("RAW_IMAGE_OR_FRAME_RECEIPT_MISSING")}
        if !manifestPresent {missing.append("EXPORT_INVENTORY_MISSING")}
        if !ocrPresent {missing.append("SELECTED_FRAME_OCR_MISSING")}
        else if !ocrParsed {missing.append("OCR_DIAGNOSTIC_PARSE_OR_SOURCE_MISMATCH")}
        if !located {missing.append("NO_PROVENANCE_VERIFIED_OCR_GEOMETRY")}
        if !metricsPresent {
            missing.append("FOUR_WINDOW_METRICS_MISSING_OR_INVALID")
            missing.append(contentsOf: missingMetricSources.map { "DIAGNOSTIC_SOURCE_MISSING_" + $0 })
        }
        // These cannot be certified from OCR text + image coordinates alone.
        missing.append(contentsOf:[
            "OWN_OPP_OWNER_UNCERTIFIED",
            "HP_VS_PP_UNCERTIFIED",
            "MEGA_VISUAL_AND_HISTORY_UNCERTIFIED",
            "WEATHER_TERRAIN_STATUS_OWNER_UNCERTIFIED",
            "TURN_AND_FRESHNESS_UNCERTIFIED",
            "DEVICE_FILES_DESTINATION_UNCONFIRMED"
        ])
        return [
            "schema":schema, "source_frame_id":frame, "source_epoch":epoch,
            "raw_image_attached":imagePresent,
            "selected_frame_ocr_attached":ocrPresent,
            "ocr_source_parsable":ocrParsed,
            "provenance_verified_ocr_rects":geometry,
            "ocr_geometry_missing":unlocated,
            "ocr_geometry_invalid":invalid,
            "ocr_provenance_mismatch":mismatch,
            "diagnostics_attached":metricsPresent,
            "diagnostic_sources_attached":expectedSources.count - missingMetricSources.count,
            "diagnostic_sources_missing":missingMetricSources,
            "export_inventory_attached":manifestPresent,
            "offline_diagnostic_packet_ready":imagePresent && manifestPresent && ocrPresent && located && metricsPresent,
            "missing_or_uncertified":missing,
            "certified_own_opponent":false,
            "certified_hp_pp":false,
            "certified_mega":false,
            "certified_field_state":false,
            "certified_turn":false,
            "files_destination_save_confirmed":false,
            "battle_advice_authorized":false
        ]
    }

    static func verifyAttached(_ bytes:Data,frame:Int64,epoch:Int64) -> Bool {
        guard let root=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let actual=root["r545_device_trial_readiness"] as? [String:Any],
              actual["battle_advice_authorized"] as? Bool == false,
              actual["certified_own_opponent"] as? Bool == false,
              actual["certified_hp_pp"] as? Bool == false,
              actual["files_destination_save_confirmed"] as? Bool == false,
              let left=try? JSONSerialization.data(withJSONObject:actual,options:[.sortedKeys]),
              let right=try? JSONSerialization.data(withJSONObject:inspect(root,frame:frame,epoch:epoch),options:[.sortedKeys]) else {return false}
        return left == right
    }
}
