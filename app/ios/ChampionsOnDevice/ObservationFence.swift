import Foundation

// R27.399 - no UI, clock or network dependency; mutation is confined to sampleQueue.
// This gate authorizes publication of research-only OCR text, NEVER a battle action.
struct ObservationFence {
    enum Verdict: String {
        case accept = "FRESH_RESEARCH_ONLY"
        case inactive = "CAPTURE_INACTIVE"
        case replaced = "STALE_SESSION"
        case badClock = "INVALID_MONOTONIC_CLOCK"
        case expired = "OCR_RESULT_EXPIRED"
    }

    static let maximumResultAgeMs: Int64 = 1500
    private(set) var epoch: Int64 = 0
    private(set) var active = false

    @discardableResult
    mutating func start() -> Int64 {
        epoch &+= 1
        active = true
        return epoch
    }

    mutating func stop() {
        epoch &+= 1
        active = false
    }

    func inspect(epoch candidateEpoch: Int64, latestFrameMs: Int64, nowMs: Int64) -> Verdict {
        guard active else { return .inactive }
        guard candidateEpoch == epoch else { return .replaced }
        guard latestFrameMs >= 0, nowMs >= latestFrameMs else { return .badClock }
        guard nowMs - latestFrameMs <= Self.maximumResultAgeMs else { return .expired }
        return .accept
    }
}
