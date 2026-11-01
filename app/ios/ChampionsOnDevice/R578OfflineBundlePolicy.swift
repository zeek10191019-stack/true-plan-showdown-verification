import Foundation

/// Validate that the offline image and diagnostic belong to the same import.
/// SHA *of actual bytes* is verified by the writer, never just this metadata gate.
enum R578OfflineBundlePolicy {
    static let schema = "trueplan.r578.offline-source-diagnostic-bundle.v1"
    static func accepts(_ png:Data,_ diagnostic:Data,sourceSHA:String)->Bool {
        guard case .accepted(let width,let height)=R576OfflinePNGImportGate.validate(png),
            diagnostic.count>0, diagnostic.count<=R577OfflineEvidenceReport.maximumReportBytes,
            sourceSHA.utf8.count==64,
            sourceSHA.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}),
            let document=(try? JSONSerialization.jsonObject(with:diagnostic)) as? [String:Any],
            document["schema"] as? String==R577OfflineEvidenceReport.schema,
            document["source_kind"] as? String=="USER_IMPORTED_PNG_OFFLINE_ONLY",
            document["image_sha256"] as? String==sourceSHA,
            (document["image_width"] as? NSNumber)?.intValue==width,
            (document["image_height"] as? NSNumber)?.intValue==height,
            (document["png_bytes"] as? NSNumber)?.intValue==png.count,
            document["source_png_in_report"] as? Bool == false,
            document["user_opt_in_share_required"] as? Bool == true,
            document["current_state_eligible"] as? Bool == false,
            document["owner_certified"] as? Bool == false,
            document["turn_certified"] as? Bool == false,
            document["mega_form_visual_certified"] as? Bool == false,
            document["real_game_accuracy_certified"] as? Bool == false,
            document["battle_advice_authorized"] as? Bool == false,
            let packet=document["payload"] as? [String:Any],
            packet["image_sha256"] as? String==sourceSHA,
            (packet["frame_id"] as? NSNumber)?.int64Value==1,
            (packet["epoch"] as? NSNumber)?.int64Value==1,
            packet["source_ref"] as? String == "user-imported-exact-png-not-live",
            let snapshot=document["snapshot"] as? [String:Any],
            snapshot["image_sha256"] as? String==sourceSHA,
            snapshot["current_state_eligible"] as? Bool == false,
            snapshot["battle_advice_authorized"] as? Bool == false,
            let mega=document["mega_text_probe"] as? [String:Any],
            mega["image_sha256"] as? String==sourceSHA,
            mega["mega_certified"] as? Bool == false,
            mega["visual_form_certified"] as? Bool == false else {return false}
        return true
    }
}
