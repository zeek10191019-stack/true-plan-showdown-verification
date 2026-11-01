import Foundation
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// R520: freshness guard for research-only second-pass Vision OCR.
/// No battle IDs, image bytes, image hashes or OCR text are exported.
/// A reservation is invalidated on any newer frame, epoch or battle change.
/// Pixel rectangles and HP/PP owner identity remain UNVERIFIED.
enum TP520VisionSessionFence {
    struct Ticket {
        fileprivate let generation: UInt64
        fileprivate let epoch: Int
        fileprivate let frameID: Int64
    }
    struct Snapshot {
        let hasSession: Bool
        let resets: Int
        let started: Int
        let finished: Int
        let roiCandidateFrames: Int
        let candidateRects: Int
        let empty: Int
        let timeout: Int
        let busy: Int
        let invalid: Int
        let duplicateOrStale: Int
        let supersededResults: Int
        let latestFrameID: Int64?
        let epoch: Int?
        var ownerCertified: Bool {false}
        var decisionEligible: Bool {false}
        var recognitionCertified: Bool {false}
        var status: String {
            if !hasSession { return "NO_SESSION_VISION_SAMPLE" }
            if finished == 0 { return "NO_FRESH_VISION_RESULT" }
            if roiCandidateFrames == 0 { return "NO_FRESH_ROI_CANDIDATE" }
            return "FRESH_RESEARCH_ROI_ONLY_UNCERTIFIED"
        }
        var summary: String {
            "現セッション: 取得予約\(started)／新鮮結果\(finished)／座標候補\(candidateRects)／時間超過\(timeout)／重複・古いフレーム\(duplicateOrStale)／古い処理結果\(supersededResults)／認証なし"
        }
        var redactedJSON: String {
            let o: [String:Any] = [
                "schema":"R520_VISION_SESSION_FENCE_V1",
                "scope":"CURRENT_CAPTURE_SESSION_RESEARCH_ONLY",
                "has_session":hasSession,
                "session_reset_count":resets,
                "accepted_sample_reservations":started,
                "fresh_sample_results":finished,
                "fresh_roi_candidate_frames":roiCandidateFrames,
                "fresh_roi_candidate_rects":candidateRects,
                "empty_results":empty,"latency_timeouts":timeout,
                "busy_drops":busy,"invalid_results":invalid,
                "duplicate_or_stale_frames":duplicateOrStale,
                "superseded_results":supersededResults,
                "last_sample_frame_id":latestFrameID as Any? ?? NSNull(),
                "capture_epoch":epoch as Any? ?? NSNull(),
                "status":status,
                "owner_certified":false,"recognition_certified":false,
                "decision_eligible":false,
                "battle_id_included":false,"image_sha_included":false,
                "image_bytes_included":false,"ocr_text_included":false
            ]
            guard let data=try? JSONSerialization.data(withJSONObject:o,options:[.sortedKeys]),
                  let s=String(data:data,encoding:.utf8) else {return "{}"}
            return s
        }
    }
    private static let lock=NSLock()
    private static var sessionID: String?
    private static var currentEpoch: Int?
    private static var lastFrameID: Int64?
    private static var generation: UInt64 = 0
    private static var resets=0
    private static var started=0
    private static var finished=0
    private static var roiFrames=0
    private static var rects=0
    private static var empty=0
    private static var timeout=0
    private static var busy=0
    private static var invalid=0
    private static var stale=0
    private static var superseded=0

    /// IMPORTANT: battle ID is used only as a private session separator.
    /// It is never present in the exported JSON or SwiftUI text.
    static func begin(battleID: String,epoch: Int,frameID: Int64) -> Ticket? {
        lock.lock(); defer {lock.unlock()}
        guard !battleID.isEmpty,battleID.utf8.count<=128,
              epoch>=0,frameID>0 else {
            invalid += 1
            return nil
        }
        if sessionID != battleID || currentEpoch == nil {
            if sessionID != nil {resets+=1}
            generation &+= 1
            sessionID=battleID
            currentEpoch=epoch
            lastFrameID=nil
            started=0;finished=0;roiFrames=0;rects=0
            empty=0;timeout=0;busy=0;invalid=0;stale=0;superseded=0
        } else if epoch < currentEpoch! {
            stale+=1
            return nil
        } else if epoch > currentEpoch! {
            resets+=1
            generation &+= 1
            currentEpoch=epoch
            lastFrameID=nil
            started=0;finished=0;roiFrames=0;rects=0
            empty=0;timeout=0;busy=0;invalid=0;stale=0;superseded=0
        }
        if let previous=lastFrameID,frameID<=previous {
            stale+=1
            return nil
        }
        lastFrameID=frameID
        started+=1
        return Ticket(generation:generation,epoch:epoch,frameID:frameID)
    }

    /// Caller must discard uncommitted asynchronous results, even when OCR
    /// succeeded, because the capture session may have advanced meanwhile.
    @discardableResult
    static func finish(_ ticket: Ticket, added: Int,reason: String) -> Bool {
        lock.lock(); defer {lock.unlock()}
        guard generation==ticket.generation,currentEpoch==ticket.epoch,
              lastFrameID==ticket.frameID else {
            superseded+=1
            return false
        }
        guard (0...256).contains(added),reason.utf8.count<=96 else {
            invalid+=1
            return false
        }
        finished+=1
        if added>0 && reason=="RESEARCH_ROI_CANDIDATES_ONLY" {
            roiFrames+=1
            rects+=added
        } else if reason=="ROI_WORKER_LATENCY_BUDGET_EXCEEDED" {timeout+=1}
        else if reason=="ROI_WORKER_BUSY_DROP" {busy+=1}
        else if reason=="ROI_BUDGET_OR_INPUT_INVALID" {invalid+=1}
        else {empty+=1}
        return true
    }

    static func snapshot() -> Snapshot {
        lock.lock(); defer {lock.unlock()}
        return Snapshot(hasSession:sessionID != nil,resets:resets,
                        started:started,finished:finished,
                        roiCandidateFrames:roiFrames,candidateRects:rects,
                        empty:empty,timeout:timeout,busy:busy,invalid:invalid,
                        duplicateOrStale:stale,supersededResults:superseded,
                        latestFrameID:lastFrameID,epoch:currentEpoch)
    }
}

#if canImport(UIKit) && canImport(Vision)
extension TP520VisionSessionFence {
    /// The existing R519 pass remains rate-limited by R518's 85ms timeout.
    /// Never publishes a stale asynchronous research result into the Wire.
    static func enrich(wire:String,png:Data,battleID:String,epoch:Int,
                       frameID:Int64) -> TP517VisionROISidecar.Result {
        guard let t=begin(battleID:battleID,epoch:epoch,frameID:frameID) else {
            return .init(wire:wire,added:0,reason:"STALE_OR_INVALID_VISION_SAMPLE")
        }
        let result=TP519VisionEvidenceMetrics.enrich(wire:wire,png:png,
                                battleID:battleID,epoch:epoch,frameID:frameID)
        guard finish(t,added:result.added,reason:result.reason) else {
            return .init(wire:wire,added:0,reason:"SUPERSEDED_VISION_SAMPLE")
        }
        return result
    }
}
#endif

#if canImport(SwiftUI) && canImport(UIKit)
struct TP520VisionSessionPanel: View {
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) { _ in
            let s=TP520VisionSessionFence.snapshot()
            VStack(alignment:.leading,spacing:4) {
                Text("R27.520｜対戦・Epoch単位のROI鮮度検証")
                    .font(.caption).foregroundColor(.orange)
                Text(s.summary).font(.caption2).textSelection(.enabled)
                Text("HP・PPの自他帰属、メガ、天候などの認識は未認証")
                    .font(.caption2).foregroundColor(.secondary)
                Button("ROIセッション診断JSONをコピー") {
                    UIPasteboard.general.string=s.redactedJSON
                }.font(.caption2)
            }
        }
    }
}
#endif
