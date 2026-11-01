import Foundation

// R27.419: VOLATILE, MANUAL GROUND-TRUTH evaluation only.
// This is a comparison against text entered by the user, not certified game legality.
// Keep all output outside the battle AI / speech recommendation channel.
struct ManualOCRAccuracyAudit {
    enum Outcome: String {
        case match = "MATCH"
        case mismatch = "MISMATCH"
        case missing = "NOT_READ"
    }
    struct Result {
        let outcomes: [Outcome]
        let correct: Int
        let missing: Int
        let mismatched: Int
        let total: Int
        var accuracy: Double { Double(correct) / Double(total) }
        var perfect: Bool { correct == total }
    }
    static let scope = "USER_ANNOTATED_ONE_FRAME_ONLY_NOT_A_LEGAL_MOVE_CERTIFICATION"

    // NFKC folds half-/full-width Unicode forms; trim outer whitespace only.
    // Do not perform fuzzy/substring matching: false positives are dangerous.
    static func normalize(_ source: String) -> String? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping.lowercased()
        guard !value.isEmpty, value.count <= 40,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return value
    }

    // All 4 human-entered references must be supplied, or the comparison is invalid.
    // A missing OCR candidate counts as incorrect and MUST NOT be ignored.
    static func score(reference: [String], observed: [String?]) -> Result? {
        guard reference.count == 4, observed.count == 4 else { return nil }
        let expected = reference.map { normalize($0) }
        guard expected.allSatisfy({ $0 != nil }) else { return nil }
        let outcomes = (0..<4).map { i -> Outcome in
            guard let candidate = observed[i].flatMap({ normalize($0) }) else { return .missing }
            return candidate == expected[i] ? .match : .mismatch
        }
        let correct = outcomes.filter({ $0 == .match }).count
        let missing = outcomes.filter({ $0 == .missing }).count
        return Result(outcomes: outcomes, correct: correct,
                      missing: missing, mismatched: 4 - correct - missing, total: 4)
    }
}
