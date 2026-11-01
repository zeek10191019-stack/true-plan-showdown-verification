import Foundation
import CoreFoundation

/// R27.508: frame-bound research diagnostics for live OCR + geometric ROI candidates.
/// This module intentionally NEVER validates the screenshot itself, trusts a self-
/// supplied calibration anchor, promotes a Battle State, or chooses a battle action.
final class TP508FrameEvidenceBridge: @unchecked Sendable {
    static let shared = TP508FrameEvidenceBridge()
    enum Verdict: String { case withheld = "WITHHELD", malformed = "MALFORMED", stale = "STALE_FRAME", research = "RESEARCH_ONLY" }
    struct Report {
        let verdict: Verdict
        let frames: Int
        let readingCount: Int
        let anchorCandidates: Int
        let missingActualCaptureProof: Int
        let geometryOrOwnershipUnresolved: Int
        let duplicateOrStaleRejects: Int
        let resetCount: Int
        var concise: String {
            guard verdict == .research else { return "R508:" + verdict.rawValue }
            return "R508実観測診断F\(frames)／OCR\(readingCount)／領域候補\(anchorCandidates)" +
                "／実画像ハッシュ未照合\(missingActualCaptureProof)／帰属未証明\(geometryOrOwnershipUnresolved)" +
                "／旧重複拒否\(duplicateOrStaleRejects)／研究のみ"
        }
    }
    private let lock = NSLock()
    private var battle: String? = nil
    private var lastEpoch: UInt64 = 0
    private var lastFrame: UInt64 = 0
    private var lastHash: String? = nil
    private var frames: Int = 0
    private var readings: Int = 0
    private var candidates: Int = 0
    private var missingCaptureHash: Int = 0
    private var unresolved: Int = 0
    private var stale: Int = 0
    private var resets: Int = 0
    private static func u64(_ d:[String:Any],_ k:String)->UInt64? {
        guard let n=d[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else {return nil}
        return UInt64(n.stringValue)
    }
    private static func sha(_ value:Any?)->String? {
        guard let s=value as? String,s.utf8.count==64,
            s.utf8.allSatisfy({ ($0>=48 && $0<=57) || ($0>=97 && $0<=102) }) else {return nil}
        return s
    }
    private func report(_ v:Verdict)->Report {
        Report(verdict:v,frames:frames,readingCount:readings,anchorCandidates:candidates,
               missingActualCaptureProof:missingCaptureHash,geometryOrOwnershipUnresolved:unresolved,
               duplicateOrStaleRejects:stale,resetCount:resets)
    }
    /// `anchor` is a research candidate, NOT independent confirmation of OCR owner.
    /// `image_sha256` is merely declared by the wire, not recomputed from captured image bytes.
    func inspect(_ wire:String?, admitted:Bool, anchor:TP507ROIAnchorAssociation.Report, verifiedActualCapture:Bool = false)->Report {
        lock.lock(); defer {lock.unlock()}
        guard admitted else {return report(.withheld)}
        guard let wire,wire.utf8.count<=1_000_000,let raw=wire.data(using:.utf8),
              let top=try? JSONSerialization.jsonObject(with:raw) as? [String:Any]
        else {return report(.malformed)}
        var body=top
        if let wrapper=top["payload_json"] {
            guard let value=wrapper as? String, value.utf8.count<=1_000_000,
                  let d=value.data(using:.utf8),
                  let inner=try? JSONSerialization.jsonObject(with:d) as? [String:Any] else {return report(.malformed)}
            body=inner
        }
        guard let id=body["battle_id"] as? String,!id.isEmpty,id.utf8.count<=128,
              let epoch=Self.u64(body,"epoch"),let frame=Self.u64(body,"frame_id"),frame>0,
              Self.u64(body,"observed_at_ms") != nil,
              let hash=Self.sha(body["image_sha256"]),
              let rows=body["readings"] as? [Any],rows.count<=128,
              rows.allSatisfy({$0 is [String:Any]})
        else {return report(.malformed)}
        if battle == id {
            if epoch < lastEpoch || (epoch == lastEpoch && frame <= lastFrame) {
                stale+=1
                return report(.stale)
            }
            if epoch > lastEpoch { resets+=1; frames=0;readings=0;candidates=0;missingCaptureHash=0;unresolved=0 }
        } else if battle != nil {
            resets+=1;frames=0;readings=0;candidates=0;missingCaptureHash=0;unresolved=0
        }
        battle=id;lastEpoch=epoch;lastFrame=frame;lastHash=hash
        frames+=1;readings+=rows.count
        let matched = anchor.verdictCompatible ? min(anchor.researchMatches.count,rows.count) : 0
        candidates+=matched
        // Current pipeline has NO independently recomputed image hash, so no certified owner.
        if !verifiedActualCapture { missingCaptureHash+=1 }
        unresolved+=rows.count
        return report(.research)
    }
}

private extension TP507ROIAnchorAssociation.Report {
    var verdictCompatible:Bool { status == .research }
}
