import Foundation

/// Merge two independently scoped research sources, not a certification bridge.
/// A source image can be useful for review without being a verified game screen.
enum R535UnifiedEvidenceGate {
    enum Failure: Error { case invalidProvenance, invalidMetrics, unsafeClaim }

    /// R541: diagnostic failure must not destroy independently valid raw-frame evidence.
    /// Never assign a successful metrics claim if merging fails or telemetry is absent.
    static func mergeOrOmit(_ image: [String:Any], diagnostics: Data?,
                            expectedFrame: Int64, expectedEpoch: Int64,
                            candidateExclusionReason: String) -> [String:Any] {
        guard let diagnostics else {
            var packet = image
            packet["metrics_omission_reason"] = "DIAGNOSTICS_UNAVAILABLE"
            return packet
        }
        do {
            return try merge(image, diagnostics: diagnostics,
                             expectedFrame: expectedFrame, expectedEpoch: expectedEpoch,
                             candidateExclusionReason: candidateExclusionReason)
        } catch {
            var packet = image
            packet["metrics_omission_reason"] = "DIAGNOSTIC_MERGE_REJECTED"
            packet["battle_advice_authorized"] = false
            packet["production_enabled"] = false
            return packet
        }
    }

    static func merge(_ image: [String:Any], diagnostics: Data,
                      expectedFrame: Int64, expectedEpoch: Int64,
                      candidateExclusionReason: String) throws -> [String:Any] {
        guard expectedFrame > 0, expectedEpoch > 0,
              (image["frame_id"] as? Int64) == expectedFrame,
              (image["epoch"] as? Int64) == expectedEpoch,
              (image["observed_ms_monotonic"] as? Int64 ?? 0) > 0,
              let png = image["image_png_base64"] as? String, !png.isEmpty,
              let digest = image["png_sha256"] as? String, digest.count == 64,
              image["verified_game_screen"] as? Bool == false,
              image["production_enabled"] as? Bool == false,
              image["battle_advice_authorized"] as? Bool == false else {
            throw Failure.invalidProvenance
        }
        guard let packet = try JSONSerialization.jsonObject(with:diagnostics) as? [String:Any],
              let sources=packet["sources"] as? [String:Any], sources.count == 4,
              Set(["r519_vision","r520_roi_session","r521_roi_collision","r532_first_pass"])
                .isSubset(of: Set(sources.keys)),
              packet["all_sources_same_frame_certified"] as? Bool == false,
              packet["battle_advice_authorized"] as? Bool == false,
              packet["recognition_certified"] as? Bool == false,
              packet["image_bytes_included"] as? Bool == false else {
            throw Failure.invalidMetrics
        }
        guard ["NONE","DIFFERENT_FRAME_CANDIDATE_OMITTED",
               "ANALYSIS_IMAGE_OMITTED_SIZE_OR_MISSING"].contains(candidateExclusionReason) else {
            throw Failure.invalidProvenance
        }
        if candidateExclusionReason != "NONE" {
            guard image["research_candidate_envelope"] is NSNull,
                  image["analysis_image"] is NSNull else { throw Failure.unsafeClaim }
        }
        var packetImage=image
        packetImage["schema"]="R535_UNIFIED_SELECTED_FRAME_AND_DIAGNOSTICS_V1"
        packetImage["metrics"] = packet
        packetImage["metrics_scope"]="MULTI_WINDOW_COUNTERS_NOT_SELECTED_FRAME"
        packetImage["metrics_match_selected_frame_certified"]=false
        packetImage["candidate_exclusion_reason"] = candidateExclusionReason
        packetImage["recognition_certified"]=false
        packetImage["owner_certified"]=false
        packetImage["mega_visual_certified"]=false
        packetImage["battle_advice_authorized"]=false
        packetImage["decision_eligible"]=false
        packetImage["production_enabled"]=false
        return packetImage
    }
}
import Foundation

/// Honest per-section inventory; never promotes a research candidate to Battle State.
/// Operates on the same selected-frame packet that will be written to disk.
enum R537EvidenceManifest {
    enum Failure: Error { case sourceMismatch, invalidPayload }

    static func attach(_ packet: [String:Any], frame: Int64, epoch: Int64,
                       candidateExcluded: Bool) throws -> [String:Any] {
        guard frame > 0, epoch > 0,
              (packet["frame_id"] as? Int64) == frame,
              (packet["epoch"] as? Int64) == epoch,
              let encoded = packet["image_png_base64"] as? String, !encoded.isEmpty,
              (packet["verified_game_screen"] as? Bool) == false,
              (packet["battle_advice_authorized"] as? Bool) == false
        else { throw Failure.sourceMismatch }
        let candidate = packet["research_candidate_envelope"] as? String
        if candidateExcluded && candidate != nil { throw Failure.invalidPayload }
        let hasAnalysis = packet["analysis_image"] is [String:Any]
        let hasMetrics = packet["metrics"] is [String:Any]
        var missing = [String]()
        if candidate == nil { missing.append("same_frame_ocr_candidate") }
        if !hasAnalysis { missing.append("analysis_image") }
        if !hasMetrics { missing.append("diagnostic_counters") }
        // These fields are explicitly not certified in the current implementation.
        missing += ["own_hp_certified", "opponent_hp_certified", "move_pp_certified",
                    "mega_form_certified", "ability_item_certified", "status_certified",
                    "stat_stages_certified", "weather_terrain_rooms_screens_certified",
                    "hazards_certified", "turn_action_history_certified", "legal_actions_certified"]
        var result = packet
        result["schema"] = "R537_UNIFIED_FRAME_EVIDENCE_V1"
        result["r537_inventory"] = [
            "selected_frame_id": frame, "selected_epoch": epoch,
            "raw_image_included": true,
            "analysis_image_included": hasAnalysis,
            "same_frame_research_candidate_included": candidate != nil,
            "diagnostics_included": hasMetrics,
            "diagnostics_match_selected_frame_certified": false,
            "save_to_files_confirmed": false,
            "share_activity_completed": false,
            "missing_or_uncertified_fields": missing,
            "evidence_generated_at_utc": ISO8601DateFormatter().string(from: Date()),
            "no_battle_advice": true
        ] as [String:Any]
        result["recognition_certified"] = false
        result["owner_certified"] = false
        result["decision_eligible"] = false
        result["battle_advice_authorized"] = false
        return result
    }

    static func verifyData(_ bytes: Data, frame: Int64, epoch: Int64) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String:Any],
              object["schema"] as? String == "R537_UNIFIED_FRAME_EVIDENCE_V1",
              object["frame_id"] as? Int64 == frame,
              object["epoch"] as? Int64 == epoch,
              object["battle_advice_authorized"] as? Bool == false,
              let inventory = object["r537_inventory"] as? [String:Any],
              inventory["selected_frame_id"] as? Int64 == frame,
              inventory["selected_epoch"] as? Int64 == epoch,
              inventory["raw_image_included"] as? Bool == true,
              inventory["save_to_files_confirmed"] as? Bool == false
        else { return false }
        return true
    }
}
