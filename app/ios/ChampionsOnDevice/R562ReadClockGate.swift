import Foundation

/// Relative continuity is an admission prerequisite, never capture-time calibration.
enum R562ReadClockGate {
    enum Action: String {case allow="ALLOW_RELATIVE_ONLY",hold="HOLD_AUTOMATIC_OCR",retire="RETIRE_READ_SCOPE"}
    struct Decision {
        let epoch:Int64,frame:Int64,delivered:Int64,previous:Int64?
        let verdict:ResearchSampleClockAudit.Verdict,action:Action,reason:String
        var allowsAutomaticOCR:Bool {action == .allow}
        var requiresNewEpoch:Bool {action == .retire}
        var object:[String:Any] {
            ["schema":"trueplan.screen-read.clock-admission.v1","policy_id":"RELATIVE_PTS_FENCE_V1",
             "scope":"LAST_CALLBACK_CLOCK_DIAGNOSTICS_NOT_SELECTED_FRAME_CERTIFICATION",
             "epoch":epoch,"frame_id":frame,"delivered_uptime_ms":delivered,
             "previous_delivered_uptime_ms":previous.map {$0 as Any} ?? NSNull(),
             "delivery_delta_ms":previous.map {(delivered-$0) as Any} ?? NSNull(),
             "pts_verdict":verdict.rawValue,"action":action.rawValue,"reason":reason,
             "allows_automatic_ocr":allowsAutomaticOCR,"requires_new_epoch":requiresNewEpoch,
             "capture_timestamp_calibrated":false,"owner_certified":false,
             "current_state_eligible":false,"battle_advice_authorized":false]
        }
        var display:String {
            switch action {
            case .allow:return "映像時刻は相対監査のみ。撮影時刻は未校正です"
            case .hold:return "映像時刻を確認できないため、自動読取を保留しています"
            case .retire:return "映像時刻の不連続を検出し、読取を区切りました"
            }
        }
    }
    static func decide(verdict:ResearchSampleClockAudit.Verdict,epoch:Int64,frame:Int64,
                       deliveredMs:Int64,previousDeliveredMs:Int64?) -> Decision? {
        guard epoch>0,frame>0,deliveredMs>0,previousDeliveredMs.map({$0>0}) ?? true else {return nil}
        let action:Action,reason:String
        if let previous=previousDeliveredMs,deliveredMs<previous {
            action = .retire;reason="DELIVERY_CLOCK_ROLLBACK"
        } else if [.deliveryClockRollback,.ptsRollback,.excessivePTSJump,.rollback].contains(verdict) {
            action = .retire;reason=verdict.rawValue
        } else if let previous=previousDeliveredMs,deliveredMs-previous>2500 {
            action = .retire;reason="DELIVERY_GAP_EXCEEDS_2500MS"
        } else if verdict == .relativeOnly {
            action = .allow;reason="RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED"
        } else {
            action = .hold;reason=verdict.rawValue
        }
        return Decision(epoch:epoch,frame:frame,delivered:deliveredMs,previous:previousDeliveredMs,
                        verdict:verdict,action:action,reason:reason)
    }
}
