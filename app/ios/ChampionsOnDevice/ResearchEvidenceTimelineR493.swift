import Foundation

// Research evidence only. Neither an OCR hint nor repeated frames certify a
// battle event, a Mega form, or a recommended move.
struct TP493FrameAudit: Codable {
    let schema: String
    let accepted: Bool
    let reason: String
    let epoch: Int?
    let frameID: Int?
    let context: String
    let effectHints: Int
    let stableTextDomains: [String]
    let sameImageAsPrevious: Bool
    let certifiedEvents: Int
    let adviceAllowed: Bool
}
struct TP493ObservationTimeline {
    private(set) var battleID = ""
    private(set) var epoch = -1
    private(set) var lastFrame = -1
    private(set) var lastObservedMS: Int64 = -1
    private var lastHash = ""
    private var history = [(String, Set<String>)]()
    private(set) var heldFrames = 0
    private(set) var acceptedFrames = 0
    private(set) var epochTransitions = 0
    private static let schema = "trueplan.observation-timeline.v1"

    mutating func reset(battle: String, sourceEpoch: Int) {
        guard !battle.isEmpty, sourceEpoch >= 0 else { return }
        battleID = battle; epoch = sourceEpoch
        lastFrame = -1; lastObservedMS = -1; lastHash = ""
        history.removeAll(keepingCapacity: true)
    }
    mutating func observe(_ wire: String) -> TP493FrameAudit {
        let a = TP492BattleEffectOCRBridge.audit(wire)
        func report(_ yes: Bool, _ reason: String, _ kind: String = "UNKNOWN",
                    _ stable: [String] = [], _ same: Bool = false) -> TP493FrameAudit {
            TP493FrameAudit(schema: Self.schema, accepted: yes, reason: reason,
                epoch:a.epoch,frameID:a.frameID,context:kind,
                effectHints:a.effectTextHintCounts.values.reduce(0,+),
                stableTextDomains:stable,sameImageAsPrevious:same,
                certifiedEvents:0,adviceAllowed:false)
        }
        guard a.inputValid, let ep=a.epoch, let fr=a.frameID,
              let data=wire.data(using:.utf8),
              let top=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else { heldFrames += 1; return report(false,"INVALID_ENVELOPE") }
        let p:[String:Any]
        if let wrapped=top["payload_json"] as? String,
           let d=wrapped.data(using:.utf8),
           let inner=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any] { p=inner }
        else { p=top }
        guard let battle=p["battle_id"] as? String, !battle.isEmpty,
              let observed=p["observed_at_ms"] as? Int64, observed >= 0,
              let sha=p["image_sha256"] as? String,
              sha.count == 64,sha.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) else {
            heldFrames += 1; return report(false,"UNVERIFIABLE_IMAGE_PROVENANCE")
        }
        guard !battleID.isEmpty else {
            heldFrames += 1
            return report(false,"EXPLICIT_SESSION_START_REQUIRED")
        }
        guard battle == battleID else {
            heldFrames += 1; return report(false,"BATTLE_ID_MISMATCH")
        }
        guard ep >= epoch else {
            heldFrames += 1; return report(false,"OLD_EPOCH")
        }
        if ep > epoch {
            reset(battle:battle,sourceEpoch:ep)
            epochTransitions += 1
        }
        guard fr > lastFrame, observed >= lastObservedMS else {
            heldFrames += 1; return report(false,"STALE_FRAME_OR_CLOCK_ORDER")
        }
        lastFrame=fr;lastObservedMS=observed
        let same=sha==lastHash
        lastHash=sha;acceptedFrames += 1
        let kind=p["screen_kind"] as? String ?? "UNKNOWN"
        let domains=Set(a.effectTextHintCounts.keys)
        // Menu labels (including Mega, weather or hazard moves) never become
        // events. Message/animation also remain unverified without ROI, actor,
        // turn and independent visual evidence.
        if kind.contains("move_selection") || kind.contains("move_menu") {
            return report(true,"MOVE_MENU_TEXT_NOT_EVENT",kind,[],same)
        }
        if kind.contains("animation") {
            return report(true,"ANIMATION_UNCLASSIFIED",kind,[],same)
        }
        if !same {
            history.append((sha,domains))
            if history.count > 12 { history.removeFirst() }
        }
        let seen=domains.filter { d in
            history.reduce(0) { $0 + ($1.1.contains(d) ? 1 : 0) } >= 2
        }.sorted()
        return report(true,seen.isEmpty ? "TEXT_HINT_RESEARCH_ONLY" :
            "REPEATED_TEXT_STILL_NOT_EVENT",kind,seen,same)
    }
    // A single selected historical screenshot is not a live observation.
    static func display(_ wire:String) -> String {
        let a=TP492BattleEffectOCRBridge.audit(wire)
        guard a.inputValid else {return "R493時系列：観測なし／未認証"}
        return "R493時系列：Epoch \(a.epoch ?? -1)・Frame \(a.frameID ?? -1)。これは選択した過去フレームの候補。最新画面・メガ使用済み・効果発動は未認証。"
    }
}
