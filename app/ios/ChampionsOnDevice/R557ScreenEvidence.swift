import Foundation

/// Text-screen candidates with exact source references. OCR alternatives can
/// veto a primary classification, but cannot independently promote one.
enum R557ScreenEvidence {
    struct Decision {
        let primary: String
        let allVariants: String
        let kind: String
        let status: String
    }
    static func decide(primary: [String], allVariants: [String]) -> Decision {
        let first=ResearchScreenClassifier.classify(primary)
        let union=ResearchScreenClassifier.classify(allVariants)
        if first == "unknown" {
            return Decision(primary:first,allVariants:union,kind:"unknown",status:"HOLD_UNKNOWN_PRIMARY")
        }
        if union != first {
            return Decision(primary:first,allVariants:union,kind:"unknown",status:"HOLD_OCR_SCREEN_CONFLICT")
        }
        return Decision(primary:first,allVariants:union,kind:first,status:"PRIMARY_AND_ALTERNATIVES_AGREE")
    }
    static func report(sites: [R553LayoutReading.Site], omitted: [String], declared: Any?,
                       session: String, frame: Int64, epoch: Int64, imageSHA: String,
                       observedMs: Int64) -> [String:Any] {
        let decision=decide(primary:sites.filter {$0.rank==0}.map(\.text),allVariants:sites.map(\.text))
        var kind=decision.kind,status=decision.status
        if let declared,!(declared is NSNull) {
            if let label=declared as? String {
                if label != kind {kind="unknown";status="HOLD_PACKET_KIND_DISAGREEMENT"}
            } else {kind="unknown";status="HOLD_MALFORMED_PACKET_KIND"}
        }
        return ["schema":"trueplan.screen-read.screen-evidence.v1",
            "policy_id":"STRICT_LABELS_BOUND_ROIS_ALL_VARIANTS_V1",
            "capture_session_id":session,"frame_id":frame,"epoch":epoch,
            "image_sha256":imageSHA,"receipt_uptime_ms":observedMs,
            "battle_id":NSNull(),"turn":NSNull(),
            "scope":"HISTORICAL_TEXT_SCREEN_CANDIDATES_ONLY",
            "roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
            "status":status,"primary_kind":decision.primary,"all_variants_kind":decision.allVariants,
            "screen_kind":kind,"declared_packet_kind":declared ?? NSNull(),
            "evaluated_evidence_refs":sites.map(\.reference),"omitted_reading_refs":omitted,
            "owner_certified":false,"game_accuracy_certified":false,
            "current_state_eligible":false,"battle_advice_authorized":false]
    }
    static func isConflict(_ report: [String:Any]) -> Bool {
        ["HOLD_OCR_SCREEN_CONFLICT","HOLD_PACKET_KIND_DISAGREEMENT"].contains(report["status"] as? String ?? "")
    }
    static func displayLines(_ report: [String:Any]) -> [String] {
        if isConflict(report) {return ["画面の文字候補が食い違うため、画面分類と位置の対応を保留します"]}
        return []
    }
}
