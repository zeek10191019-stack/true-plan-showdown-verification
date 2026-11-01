import Foundation

// R27.392 research contract. Recognition agreement is not ground-truth legality.
struct OCRFrameObservation {
    let frameID: Int64
    let timestampMs: Int64
    let fourMoveCandidates: [String?]
}

struct OCRResearchResult {
    let status: String
    let consensusMoves: [String?]
    let reasonCodes: [String]
    let actionAllowed: Bool = false
    let liveE2ECertified: Bool = false
}

enum OCRPairConsensus {
    static func sanitize(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{3000}", with: "")
        guard (1...24).contains(value.count),
              !value.contains("\n"), !value.contains("\r") else { return nil }
        return value
    }

    static func evaluate(_ a: OCRFrameObservation, _ b: OCRFrameObservation) -> OCRResearchResult {
        guard a.frameID != b.frameID else {
            return OCRResearchResult(status: "STOP", consensusMoves: [nil,nil,nil,nil], reasonCodes: ["DUPLICATE_FRAME"])
        }
        guard a.frameID < b.frameID, a.timestampMs >= 0, b.timestampMs > a.timestampMs else {
            return OCRResearchResult(status: "STOP", consensusMoves: [nil,nil,nil,nil], reasonCodes: ["BAD_SEQUENCE"])
        }
        guard (180...450).contains(b.timestampMs - a.timestampMs) else {
            return OCRResearchResult(status: "STOP", consensusMoves: [nil,nil,nil,nil], reasonCodes: ["BAD_INTERVAL"])
        }
        guard a.fourMoveCandidates.count == 4, b.fourMoveCandidates.count == 4 else {
            return OCRResearchResult(status: "STOP", consensusMoves: [nil,nil,nil,nil], reasonCodes: ["BAD_SLOT_COUNT"])
        }
        let agreed: [String?] = zip(a.fourMoveCandidates, b.fourMoveCandidates).map { x,y in
            guard let left = sanitize(x), let right = sanitize(y), left == right else { return nil }
            return left
        }
        var reasons = ["UNVERIFIED_GAME_STATE", "LEGAL_ENGINE_NOT_CONNECTED", "NO_ACTION_RECOMMENDATION"]
        if agreed.contains(where: { $0 == nil }) { reasons.append("INCOMPLETE_FOUR_MOVES") }
        return OCRResearchResult(status: "RESEARCH_CANDIDATE_ONLY", consensusMoves: agreed,
                                 reasonCodes: reasons)
    }
}
