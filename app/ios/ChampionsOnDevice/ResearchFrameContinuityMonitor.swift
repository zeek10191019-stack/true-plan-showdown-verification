import Foundation

// R27.474: retains the last DIAGNOSTICALLY observed, structurally valid selected
// frame. This is not a continuous ScreenCaptureKit feed, proof of clock-domain
// identity, ROI ownership, turn identity or authorization for a recommendation.
// Synchronize observations from multiple Swift UI tasks with NSLock.
final class ResearchFrameContinuityMonitor {
    static let productionEnabled = false
    private let mutex = NSLock()
    private var latest: ResearchFrameStamp?
    private var examined: UInt64 = 0
    private var acceptedForHistory: UInt64 = 0

    struct Snapshot {
        let latest: ResearchFrameStamp?
        let examined: UInt64
        let acceptedForHistory: UInt64
    }

    func snapshot() -> Snapshot {
        mutex.lock()
        defer { mutex.unlock() }
        return Snapshot(latest: latest, examined: examined,
                        acceptedForHistory: acceptedForHistory)
    }

    func inspectSelectedFrame(_ frame: ResearchFrameStamp) -> ResearchFrameEvidenceResult {
        mutex.lock()
        defer { mutex.unlock() }
        if examined < UInt64.max { examined += 1 }
        // Clock provenance and battle transitions have no verified attestation
        // in the current selected-frame UI path, so never set these to true.
        let context = ResearchFrameEvidenceContext(
            sameMonotonicClockAttested: false,
            previous: latest,
            battleTransitionAttested: false,
            ageBudgetMs: 1500)
        let result = ResearchObservationFence.evaluate(frame, context: context)
        // Retain only a structurally valid, strictly progressing frame in the
        // SAME battle. UNKNOWN_CLOCK_DOMAIN_HOLD remains a HOLD; retaining the
        // stamp is for replay detection only and does not certify freshness.
        if result.verdict == .unknownClockDomainHold {
            latest = frame
            if acceptedForHistory < UInt64.max { acceptedForHistory += 1 }
        }
        return result
    }

    // Intentionally no automatic reset. A new battle/epoch cannot silently
    // clear replay history without a trusted transition event. An app restart
    // starts a new provisional diagnostic session, not a certification.
}

// One instance per app process; no disk/network persistence or hidden export.
// R27.474 research-only selected-frame evidence registry.
enum ResearchFrameHistoryRegistry {
    static let selected = ResearchFrameContinuityMonitor()
}
