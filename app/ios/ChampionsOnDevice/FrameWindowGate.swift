import Foundation

// Pure state machine: all mutations MUST run on the SCStream sampleHandlerQueue.
// This file uses Foundation only, allowing Swift validation without an iOS SDK.
struct FrameWindowGate {
    enum OfferResult {
        case wait
        case rejected(String)
        case pair(FramePacket, FramePacket)
    }

    private(set) var halted = false
    private(set) var inFlight = false
    private(set) var mostRecentMs: Int64 = -1
    private var first: FramePacket?

    mutating func offer(_ frame: FramePacket) -> OfferResult {
        if halted { return .rejected("CAPTURE_STOPPED") }
        if inFlight { return .rejected("BACKPRESSURE") }
        if frame.monotonicMs <= mostRecentMs { return .rejected("NONMONOTONIC_FRAME") }
        mostRecentMs = frame.monotonicMs
        guard let old = first else { first = frame; return .wait }
        let delta = frame.monotonicMs - old.monotonicMs
        if delta < 180 { return .wait }
        if delta > 450 || old.png == frame.png {
            first = frame
            return .rejected(delta > 450 ? "PAIR_WINDOW_EXPIRED" : "DUPLICATE_IMAGE")
        }
        first = nil
        inFlight = true
        return .pair(old, frame)
    }

    mutating func completePair() {
        inFlight = false
        // Never reuse a frame captured before an async network/recognition interval.
        first = nil
    }

    mutating func halt() {
        halted = true
        inFlight = false
        first = nil
    }
}
