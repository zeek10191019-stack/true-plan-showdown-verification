import Foundation

// R27.470: fail-closed HP diagnostic path wired from ResearchBattleVision.
// Deliberately independent of legacy inspect(...) to preserve prior regression APIs.
// Never grants a production battle-state key; two matching OCR passes are not
// sufficient to prove ownership, freshness, turn, or accuracy.
extension ResearchHPCandidateConsensus {
    static func inspectStrict(_ passes: [String], side: String,
                              context: ResearchHPContext) -> Result {
        guard side == "own" || side == "opp" else {
            return Result(readings: [], status: "INVALID_SIDE_HOLD")
        }
        let distinct = Array(Set(passes.map {
            $0.precomposedStringWithCompatibilityMapping
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
        guard !distinct.isEmpty else {
            return Result(readings: [], status: "NO_HP_TEXT_HOLD")
        }

        var readings: [ResearchReading] = []
        var rejectionCodes: [String] = []
        var accepted = 0
        for raw in distinct {
            let reason: String?
            if side == "own" {
                switch ResearchHPStrictCandidate.own(raw: raw, context: context) {
                case .hold(let code): reason = code
                case .candidate: reason = nil
                }
            } else {
                switch ResearchHPStrictCandidate.opponentPercent(raw: raw, context: context) {
                case .hold(let code): reason = code
                case .candidate: reason = nil
                }
            }
            if let reason {
                rejectionCodes.append(reason)
                // Keep the literal as diagnostic evidence without publishing
                // an HP numeric value or an own/opp key.
                readings.append(ResearchReading(key: nil, value: .null,
                    raw_text: raw, confidence: nil, reason: reason))
            } else {
                accepted += 1
                // Even with attested context, these are UNVERIFIED candidates.
                // The owner gate strips keys, so no live state can be written.
                readings += ResearchOwnerGate.unverified(
                    ResearchLiteralParser.hp(raw, side: side), side: side)
            }
        }

        if distinct.count > 1 {
            return Result(readings: readings, status: "OCR_HP_DISAGREEMENT_HOLD")
        }
        if let first = rejectionCodes.first {
            return Result(readings: readings, status: first + "_HOLD")
        }
        guard accepted == 1 else {
            return Result(readings: readings, status: "NO_VALID_HP_HOLD")
        }
        return Result(readings: readings, status: "STRICT_HP_CANDIDATE_UNVERIFIED")
    }
}
