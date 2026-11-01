import Foundation

// R27.469 research safety module. Integration into iOS project is NOT yet certified.
// A parseable OCR token is never enough to authorize a battle-state update.
enum ResearchHPParseResult: Equatable {
    case hold(String)
    case candidate(current: Int, maximum: Int)
}

enum ResearchHPPctResult: Equatable {
    case hold(String)
    case candidate(percent: Int)
}

struct ResearchHPContext {
    let owner: String?
    let ownerROIAttested: Bool
    let frameAgeMs: Int?
    let epochConsistent: Bool
    let liveTurnKnown: Bool
}

struct ResearchHPStrictCandidate {
    // No fuzzy digit reconstruction: corrupted concatenated OCR like "1777371" is rejected.
    // The bound of 9999 is a hard lexical plausibility guard, not a species HP inference.
    private static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "／", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func contextHold(_ context: ResearchHPContext, requiredOwner: String) -> String? {
        guard context.owner == requiredOwner && context.ownerROIAttested else {
            return "UNVERIFIED_ROI_OWNER_\(requiredOwner.uppercased())"
        }
        guard context.epochConsistent else { return "STALE_EPOCH" }
        guard let age = context.frameAgeMs, age >= 0, age <= 1_500 else {
            return "STALE_OR_UNKNOWN_FRAME_AGE"
        }
        guard context.liveTurnKnown else { return "TURN_UNKNOWN" }
        return nil
    }

    static func own(raw: String, context: ResearchHPContext) -> ResearchHPParseResult {
        guard let regex = try? NSRegularExpression(pattern: #"^([0-9]{1,4})\s*/\s*([0-9]{1,4})$"#) else {
            return .hold("PARSER_UNAVAILABLE")
        }
        let token = clean(raw)
        let ns = token as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: token, range: range), m.range == range,
              let current = Int(ns.substring(with: m.range(at: 1))),
              let maximum = Int(ns.substring(with: m.range(at: 2))),
              maximum > 0, current <= maximum else {
            return .hold("INVALID_HP_LEXEME_OR_RANGE")
        }
        if let issue = contextHold(context, requiredOwner: "own") { return .hold(issue) }
        // Even after provenance, return CANDIDATE: image/ground-truth validation is distinct.
        return .candidate(current: current, maximum: maximum)
    }

    static func opponentPercent(raw: String, context: ResearchHPContext) -> ResearchHPPctResult {
        let token = clean(raw)
        guard let regex = try? NSRegularExpression(pattern: #"^([0-9]{1,3})%$"#) else {
            return .hold("PARSER_UNAVAILABLE")
        }
        let ns = token as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: token, range: range), m.range == range,
              let v = Int(ns.substring(with: m.range(at: 1))), v <= 100 else {
            return .hold("INVALID_HP_PERCENT")
        }
        if let issue = contextHold(context, requiredOwner: "opp") { return .hold(issue) }
        return .candidate(percent: v)
    }
}
