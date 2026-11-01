import Foundation

// R27.476: Research-only PTS-vs-delivery *relative* continuity audit.
// PTS and ProcessInfo.systemUptime are independent clock domains until
// a documented calibration proves otherwise. NEVER subtract their absolute
// values, never infer frame freshness, owner, battle ID, turn, or legal move.
final class ResearchSampleClockAudit {
    static let productionEnabled = false
    enum Verdict: String, Codable {
        case relativeOnly = "RELATIVE_PTS_ORDER_ONLY_UNCERTIFIED"
        case noActiveStream = "PTS_STREAM_NOT_STARTED_HOLD"
        case invalidStamp = "PTS_INVALID_STAMP_HOLD"
        case epochMismatch = "PTS_EPOCH_MISMATCH_HOLD"
        case replay = "PTS_FRAME_REPLAY_HOLD"
        case rollback = "PTS_FRAME_ROLLBACK_HOLD"
        case deliveryClockRollback = "PTS_DELIVERY_CLOCK_ROLLBACK_HOLD"
        case missingPTS = "PTS_MISSING_OR_UNCALIBRATED_HOLD"
        case repeatedPTS = "PTS_REPEATED_HOLD"
        case ptsRollback = "PTS_ROLLBACK_HOLD"
        case excessivePTSJump = "PTS_DELTA_DIVERGENCE_HOLD"
    }
    struct Stamp: Codable, Equatable {
        let epoch: Int64
        let frameID: Int64
        let deliveredMs: Int64
        let presentationMs: Int64?
    }
    struct Summary: Codable {
        let schema: String
        let source: String
        let activeEpoch: Int64?
        let lastSample: Stamp?
        let lastValidPTSSample: Stamp?
        let streamBegins: UInt64
        let epochRotations: UInt64
        let observed: UInt64
        let relativeAccepted: UInt64
        let relativeHeld: UInt64
        let lastVerdict: String
        let presentationToUptimeOffsetVerified: Bool
        let liveBattleStateCertified: Bool
        let productionEnabled: Bool
    }
    private let lock = NSLock()
    private var activeEpoch: Int64?
    private var last: Stamp?
    private var lastValidPTS: Stamp?
    private var begins: UInt64 = 0
    private var rotates: UInt64 = 0
    private var seen: UInt64 = 0
    private var accepted: UInt64 = 0
    private var held: UInt64 = 0
    private var lastResult: Verdict = .noActiveStream
    private func increment(_ v: inout UInt64) { if v < UInt64.max { v += 1 } }

    func beginStream(epoch: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard epoch > 0 else { return false }
        activeEpoch = epoch
        last = nil
        lastValidPTS = nil
        increment(&begins)
        lastResult = .missingPTS
        return true
    }
    @discardableResult
    func rotateAfterForeground(from oldEpoch: Int64, to newEpoch: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard oldEpoch > 0, newEpoch > oldEpoch, activeEpoch == oldEpoch else {
            lastResult = .epochMismatch
            return false
        }
        activeEpoch = newEpoch
        last = nil
        lastValidPTS = nil
        increment(&rotates)
        lastResult = .missingPTS
        return true
    }
    @discardableResult
    func rotateForClockDiscontinuity(from oldEpoch:Int64,to newEpoch:Int64) -> Bool {
        rotateAfterForeground(from:oldEpoch,to:newEpoch)
    }
    @discardableResult
    func record(epoch: Int64, frameID: Int64, deliveredMs: Int64,
                presentationMs: Int64?) -> Verdict {
        lock.lock(); defer { lock.unlock() }
        increment(&seen)
        func decline(_ verdict: Verdict) -> Verdict {
            if held < UInt64.max { held += 1 }
            lastResult = verdict
            return verdict
        }
        guard let activeEpoch else { return decline(.noActiveStream) }
        guard epoch > 0, frameID > 0, deliveredMs > 0 else {
            return decline(.invalidStamp)
        }
        guard epoch == activeEpoch else { return decline(.epochMismatch) }
        if let previous = last {
            guard frameID > previous.frameID else {
                return decline(frameID == previous.frameID ? .replay : .rollback)
            }
            guard deliveredMs >= previous.deliveredMs else {
                return decline(.deliveryClockRollback)
            }
        }
        // Preserve the delivery boundary even when a sample lacks PTS, so an
        // unverified sample cannot be silently skipped to hide a replay.
        let prior = lastValidPTS
        last = Stamp(epoch: epoch, frameID: frameID,
                     deliveredMs: deliveredMs, presentationMs: presentationMs)
        guard let pts = presentationMs, pts >= 0 else {
            return decline(.missingPTS)
        }
        if let priorPTS = prior?.presentationMs {
            if pts == priorPTS { return decline(.repeatedPTS) }
            if pts < priorPTS { return decline(.ptsRollback) }
            let (dPTS, ptsOverflow) = pts.subtractingReportingOverflow(priorPTS)
            let (dDelivery, deliveryOverflow) = deliveredMs.subtractingReportingOverflow(prior?.deliveredMs ?? deliveredMs)
            guard !ptsOverflow, !deliveryOverflow else { return decline(.invalidStamp) }
            // Either clock can diverge. Remember the last valid PTS across
            // missing stamps; do not let a gap hide a replay or source stall.
            // This does not estimate an absolute capture-time offset.
            let divergence=dPTS>dDelivery ? dPTS-dDelivery:dDelivery-dPTS
            if divergence>500 {return decline(.excessivePTSJump)}
        }
        lastValidPTS = last
        increment(&accepted)
        lastResult = .relativeOnly
        return .relativeOnly
    }
    func summary() -> Summary {
        lock.lock(); defer { lock.unlock() }
        return Summary(schema:"trueplan.sample-clock-audit.v1",
                       source:"CMSampleBuffer.PTS_AND_LOCAL_DELIVERY_DIFFERENT_DOMAINS",
                       activeEpoch:activeEpoch, lastSample:last,lastValidPTSSample:lastValidPTS,
                       streamBegins:begins, epochRotations:rotates, observed:seen,
                       relativeAccepted:accepted, relativeHeld:held,
                       lastVerdict:lastResult.rawValue,
                       presentationToUptimeOffsetVerified:false,
                       liveBattleStateCertified:false, productionEnabled:false)
    }
    func json() -> String {
        let coder=JSONEncoder(); coder.outputFormatting=[.sortedKeys]
        guard let data=try? coder.encode(summary()),
              let text=String(data:data,encoding:.utf8) else { return "{}" }
        return text
    }
}
