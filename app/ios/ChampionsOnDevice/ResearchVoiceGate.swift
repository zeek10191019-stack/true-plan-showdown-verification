import Foundation

// R27.400: This is a MANUAL research-audio transport gate, NOT a battle policy.
// It intentionally has no API that accepts recognized text, move names, or strategy.
struct ResearchVoiceGate {
    enum Verdict: String {
        case allowed = "MANUAL_VOICE_TEST_ONLY"
        case disabled = "VOICE_OPT_IN_REQUIRED"
        case replaced = "VOICE_SESSION_REPLACED"
        case invalidClock = "INVALID_MONOTONIC_CLOCK"
        case cooldown = "VOICE_TEST_COOLDOWN"
    }

    static let cooldownMs: Int64 = 3000
    static let approvedPhrase = "音声テストです。行動推薦は無効です。"

    private(set) var enabled = false
    private(set) var epoch: Int64 = 0
    private(set) var lastTestMs: Int64?

    mutating func setOptIn(_ value: Bool) {
        // Invalidate all prior permissions even when the user reselects the same value.
        epoch &+= 1
        enabled = value
        lastTestMs = nil
    }

    mutating func resetSession() {
        epoch &+= 1
        lastTestMs = nil
    }

    mutating func authorizeManualTest(for requestedEpoch: Int64, nowMs: Int64) -> Verdict {
        guard enabled else { return .disabled }
        guard requestedEpoch == epoch else { return .replaced }
        guard nowMs >= 0 else { return .invalidClock }
        if let lastTestMs {
            guard nowMs >= lastTestMs else { return .invalidClock }
            guard nowMs - lastTestMs >= Self.cooldownMs else { return .cooldown }
        }
        lastTestMs = nowMs
        return .allowed
    }
}
