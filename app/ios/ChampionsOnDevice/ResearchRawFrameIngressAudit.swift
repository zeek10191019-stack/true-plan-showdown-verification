import Foundation

// R27.475: genuine SCStreamOutput callback delivery history, NOT frame capture
// timestamps and NOT Pokémon battle/turn/owner authentication. Research-only.
// No pixels, OCR strings, Pokémon names or private game data are stored here.
final class ResearchRawFrameIngressAudit {
    static let productionEnabled = false

    enum Verdict: String {
        case acceptedDeliveryOnly = "ACCEPTED_DELIVERY_ONLY_UNCERTIFIED"
        case streamNotStartedHold = "STREAM_NOT_STARTED_HOLD"
        case invalidStampHold = "INVALID_RAW_STAMP_HOLD"
        case epochMismatchHold = "UNATTESTED_EPOCH_CHANGE_HOLD"
        case frameReplayHold = "RAW_FRAME_REPLAY_HOLD"
        case frameRollbackHold = "RAW_FRAME_ROLLBACK_HOLD"
        case deliveryClockRollbackHold = "DELIVERY_CLOCK_ROLLBACK_HOLD"
        case invalidTransitionHold = "UNVERIFIED_EPOCH_TRANSITION_HOLD"
    }

    struct Stamp: Equatable {
        let epoch: Int64
        let frameID: Int64
        let deliveredMs: Int64
        let width: Int
        let height: Int
        let isBackground: Bool
    }

    struct Snapshot {
        let activeEpoch: Int64?
        let lastDelivered: Stamp?
        let streamBegins: UInt64
        let epochRotations: UInt64
        let presentedFrames: UInt64
        let deliveryAccepted: UInt64
        let deliveryRejected: UInt64
        let invalidTransitions: UInt64
        // No claim of frame age, game identity, battle identity, or valid advice.
        let eligibleForBattleState: Bool
    }

    private let lock = NSLock()
    private var epoch: Int64?
    private var last: Stamp?
    private var begins: UInt64 = 0
    private var rotates: UInt64 = 0
    private var presented: UInt64 = 0
    private var accepted: UInt64 = 0
    private var rejected: UInt64 = 0
    private var transitionsRejected: UInt64 = 0

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(activeEpoch: epoch, lastDelivered: last,
                        streamBegins: begins, epochRotations: rotates,
                        presentedFrames: presented, deliveryAccepted: accepted,
                        deliveryRejected: rejected, invalidTransitions: transitionsRejected,
                        eligibleForBattleState: false)
    }

    // Called ONLY when a new SCStream has been assigned as the active stream.
    // A new stream is a new capture *transport* session, not a new battle.
    @discardableResult
    func beginStream(epoch newEpoch: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard newEpoch > 0 else { return false }
        epoch = newEpoch
        last = nil
        if begins < UInt64.max { begins += 1 }
        return true
    }

    // Called ONLY from the existing verified foreground-epoch transition path.
    // It is not permission to switch battle identities or reset selected-frame
    // provenance; the older R27.474 monitor still holds its previous history.
    @discardableResult
    func rotateAfterForeground(from oldEpoch: Int64, to newEpoch: Int64) -> Verdict {
        lock.lock(); defer { lock.unlock() }
        guard oldEpoch > 0, newEpoch > oldEpoch, epoch == oldEpoch else {
            if transitionsRejected < UInt64.max { transitionsRejected += 1 }
            return .invalidTransitionHold
        }
        epoch = newEpoch
        last = nil
        if rotates < UInt64.max { rotates += 1 }
        return .acceptedDeliveryOnly
    }

    // Only screen samples that the existing continuity gate accepts arrive here.
    @discardableResult
    func rotateForClockDiscontinuity(from oldEpoch:Int64,to newEpoch:Int64) -> Verdict {
        rotateAfterForeground(from:oldEpoch,to:newEpoch)
    }

    // deliveredMs is ProcessInfo.systemUptime sampled at callback delivery,
    // not a verified CMSampleBuffer capture timestamp.
    func observe(epoch e: Int64, frameID id: Int64, deliveredMs ms: Int64,
                 width: Int, height: Int, isBackground: Bool) -> Verdict {
        lock.lock(); defer { lock.unlock() }
        if presented < UInt64.max { presented += 1 }
        func decline(_ reason: Verdict) -> Verdict {
            if rejected < UInt64.max { rejected += 1 }
            return reason
        }
        guard let active = epoch else { return decline(.streamNotStartedHold) }
        guard e > 0, id > 0, ms > 0,
              width >= 64, height >= 64,
              width <= 16384, height <= 16384 else {
            return decline(.invalidStampHold)
        }
        guard e == active else { return decline(.epochMismatchHold) }
        if let old = last {
            if id == old.frameID { return decline(.frameReplayHold) }
            if id < old.frameID { return decline(.frameRollbackHold) }
            if ms < old.deliveredMs { return decline(.deliveryClockRollbackHold) }
        }
        last = Stamp(epoch: e, frameID: id, deliveredMs: ms, width: width,
                     height: height, isBackground: isBackground)
        if accepted < UInt64.max { accepted += 1 }
        return .acceptedDeliveryOnly
    }
}
