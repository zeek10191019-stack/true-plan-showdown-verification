import Foundation

/// sampleQueue owns this state. Foreign streams/audio never change current input health.
struct R563InputHealthFence {
    enum Preflight:String {
        case ignore="IGNORE_FOREIGN_OR_NONSCREEN",ready="READY_INPUT_ONLY"
        case invalidSample="HOLD_INVALID_SAMPLE",missingImage="HOLD_MISSING_IMAGE"
    }
    enum Rejection:String,CaseIterable {
        case invalidSample="INVALID_CURRENT_SCREEN_SAMPLE"
        case missingImage="CURRENT_SCREEN_IMAGE_MISSING"
        case continuity="CURRENT_STREAM_CONTINUITY_REJECTED"
        case ingress="CURRENT_STREAM_INGRESS_REJECTED"
    }
    private var accepted:Int64=0,rejected:Int64=0,consecutive:Int64=0,retirements:Int64=0
    private var lastReason:Rejection?
    static func preflight(currentStream:Bool,screen:Bool,valid:Bool,imageAvailable:Bool)->Preflight {
        guard currentStream,screen else {return .ignore}
        guard valid else {return .invalidSample}
        return imageAvailable ? .ready:.missingImage
    }
    mutating func accept() {
        if accepted<Int64.max {accepted+=1}
        consecutive=0;lastReason=nil
    }
    /// Exactly one scope retirement is requested per uninterrupted rejection episode.
    mutating func reject(_ reason:Rejection)->Bool {
        let first=consecutive==0
        if rejected<Int64.max {rejected+=1}
        if consecutive<Int64.max {consecutive+=1}
        if first,retirements<Int64.max {retirements+=1}
        lastReason=reason
        return first
    }
    var object:[String:Any] {
        ["schema":"trueplan.screen-read.input-health.v1",
         "scope":"CURRENT_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_PROOF",
         "status":consecutive>0 ? "INPUT_HELD":accepted>0 ? "READY_DELIVERY_ONLY":"NOT_OBSERVED",
         "accepted_inputs":accepted,"rejected_inputs":rejected,"consecutive_rejections":consecutive,
         "retirement_requests":retirements,"last_reason":lastReason.map {$0.rawValue as Any} ?? NSNull(),
         "capture_timestamp_calibrated":false,"current_state_eligible":false,
         "owner_certified":false,"battle_advice_authorized":false]
    }
    var display:String {
        if let lastReason {
            let reason:String
            switch lastReason {
            case .invalidSample:reason="画像サンプルが無効です"
            case .missingImage:reason="画像が届いていません"
            case .continuity:reason="画像の寸法・順序を確認できません"
            case .ingress:reason="配信の出典・順序を確認できません"
            }
            return "自動読取を保留："+reason
        }
        return accepted>0 ? "取得入力の配信整合のみ確認。ゲーム状態は未認証です":"取得入力を確認しています"
    }
}
