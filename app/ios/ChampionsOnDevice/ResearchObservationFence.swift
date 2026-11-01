import Foundation

// R27.473: provenance-aware observation fence. No move recommendation, no
// battle-state authorization, and NO ability to certify an OCR ROI owner.
// The packet's capture and receipt timestamps are monotonic-clock CANDIDATES:
// equality of clock domains must be attested separately.
struct ResearchFrameStamp: Equatable {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let observedMs: Int64
    let receivedMs: Int64
}

struct ResearchFrameEvidenceContext {
    let sameMonotonicClockAttested: Bool
    let previous: ResearchFrameStamp?
    let battleTransitionAttested: Bool
    let ageBudgetMs: Int64

    static let researchDefault = ResearchFrameEvidenceContext(
        sameMonotonicClockAttested: false,
        previous: nil,
        battleTransitionAttested: false,
        ageBudgetMs: 1500
    )
}

enum ResearchFrameEvidenceVerdict: String {
    case invalidStampHold = "INVALID_STAMP_HOLD"
    case unknownClockDomainHold = "UNKNOWN_CLOCK_DOMAIN_HOLD"
    case impossibleClockHold = "IMPOSSIBLE_CLOCK_HOLD"
    case staleFrameHold = "STALE_FRAME_HOLD"
    case sameFrameReplayHold = "SAME_FRAME_REPLAY_HOLD"
    case epochRollbackHold = "EPOCH_ROLLBACK_HOLD"
    case frameRollbackHold = "FRAME_ROLLBACK_HOLD"
    case captureClockRollbackHold = "CAPTURE_CLOCK_ROLLBACK_HOLD"
    case battleTransitionUnverifiedHold = "BATTLE_TRANSITION_UNVERIFIED_HOLD"
    case frameCandidateUnverified = "FRAME_CANDIDATE_UNVERIFIED"
}

struct ResearchFrameEvidenceResult {
    let verdict: ResearchFrameEvidenceVerdict
    let deltaMs: Int64?
    // Deliberately NO `authorized`, `verified`, or `production` flag.
}

enum ResearchObservationFence {
    static let productionEnabled = false

    static func evaluate(_ frame: ResearchFrameStamp,
                         context: ResearchFrameEvidenceContext = .researchDefault
    ) -> ResearchFrameEvidenceResult {
        func hold(_ reason: ResearchFrameEvidenceVerdict,
                  _ delta: Int64? = nil) -> ResearchFrameEvidenceResult {
            ResearchFrameEvidenceResult(verdict: reason, deltaMs: delta)
        }
        guard !frame.battleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              frame.epoch >= 0, frame.frameID > 0,
              frame.observedMs > 0, frame.receivedMs > 0,
              context.ageBudgetMs > 0, context.ageBudgetMs <= 60000 else {
            return hold(.invalidStampHold)
        }
        if let old = context.previous {
            guard !old.battleID.isEmpty, old.epoch >= 0, old.frameID > 0,
                  old.observedMs > 0, old.receivedMs > 0 else {
                return hold(.invalidStampHold)
            }
            if frame.battleID != old.battleID {
                if !context.battleTransitionAttested {
                    return hold(.battleTransitionUnverifiedHold)
                }
            } else {
                if frame.epoch < old.epoch { return hold(.epochRollbackHold) }
                if frame.epoch == old.epoch && frame.frameID == old.frameID {
                    return hold(.sameFrameReplayHold)
                }
                if frame.epoch == old.epoch && frame.frameID < old.frameID {
                    return hold(.frameRollbackHold)
                }
                if context.sameMonotonicClockAttested &&
                   frame.observedMs < old.observedMs {
                    return hold(.captureClockRollbackHold)
                }
            }
        }
        // Never subtract untrusted timestamp domains or claim freshness when
        // their relationship has not been independently established.
        guard context.sameMonotonicClockAttested else {
            return hold(.unknownClockDomainHold)
        }
        // Both values are positive; reject clock reversal *before* subtraction
        // to avoid overflow and negative age misclassification.
        guard frame.receivedMs >= frame.observedMs else {
            return hold(.impossibleClockHold)
        }
        let age = frame.receivedMs - frame.observedMs
        guard age <= context.ageBudgetMs else { return hold(.staleFrameHold, age) }
        return ResearchFrameEvidenceResult(
            verdict: .frameCandidateUnverified, deltaMs: age)
    }

    // No existing ResearchBattleVision diagnostic may silently turn an
    // uncalibrated candidate into a battle-state assignment.
    static func allReadingsProvisional(_ readings: [ResearchReading]) -> Bool {
        readings.allSatisfy { reading in
            reading.key == nil && !reading.reason.isEmpty
        }
    }

    static func diagnostic(_ result: ResearchFrameEvidenceResult,
                           rawObservedMs: Int64, rawReceivedMs: Int64) -> ResearchReading {
        let delta = result.deltaMs.map(String.init) ?? "unverified"
        return ResearchReading(key: nil, value: .null,
            raw_text: "observedMs=\(rawObservedMs);receivedMs=\(rawReceivedMs);deltaMs=\(delta)",
            confidence: nil, reason: result.verdict.rawValue)
    }
}
