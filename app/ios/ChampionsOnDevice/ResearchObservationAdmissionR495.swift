import Foundation

/// Research-only admission filter. It never authorizes battle actions.
struct TP495ObservationAdmission {
    private(set) var epoch: Int = -1
    private(set) var lastAcceptedFrame: Int64 = -1
    private(set) var lastAcceptedObservedMs: Int64 = -1
    private(set) var admitted: Int = 0
    private(set) var rejected: Int = 0
    private(set) var rejectedExpired: Int = 0
    private(set) var rejectedOrder: Int = 0
    private let freshnessMs: Int64 = 1500

    mutating func reset() {
        epoch = -1
        lastAcceptedFrame = -1
        lastAcceptedObservedMs = -1
    }

    mutating func admit(result: String, epoch incomingEpoch: Int,
                        frame: Int64, observedMs: Int64,
                        completedMs: Int64, matchingSession: Bool) -> Bool {
        // Raw capture normally advances during OCR. It does not invalidate an
        // in-order, same-source result within the explicit receipt-age budget.
        // This admits research candidates only, never a certified current state.
        guard matchingSession, ["SAME_EPOCH_RESEARCH_ONLY","SUPERSEDED_FRAME_RESEARCH_ONLY"].contains(result),
              incomingEpoch >= 0, frame > 0,
              observedMs >= 0, completedMs >= observedMs else {
            rejected += 1
            return false
        }
        guard completedMs - observedMs <= freshnessMs else {
            rejected += 1
            rejectedExpired += 1
            return false
        }
        if incomingEpoch != epoch {
            guard incomingEpoch > epoch else {
                rejected += 1
                rejectedOrder += 1
                return false
            }
            epoch = incomingEpoch
            lastAcceptedFrame = -1
            lastAcceptedObservedMs = -1
        }
        guard frame > lastAcceptedFrame,
              observedMs > lastAcceptedObservedMs else {
            rejected += 1
            rejectedOrder += 1
            return false
        }
        lastAcceptedFrame = frame
        lastAcceptedObservedMs = observedMs
        admitted += 1
        return true
    }

    var concise: String {
        "R495 時系列採用\(admitted)／棄却\(rejected)" +
        "／期限超過\(rejectedExpired)／順序異常\(rejectedOrder)" +
        "。研究情報のみ、対戦助言は無効"
    }
}
