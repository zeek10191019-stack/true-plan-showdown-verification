import Foundation

// The following mappings are a research OCR lexicon, NOT the frozen canonical DB.
// A mapping is never used as proof of a name or inserted as a battle state.
enum ResearchNameCandidates {
    private static let spellingAliases = [
        "ガプリアス": "ガブリアス", // older battle
        "プリジュラス": "ブリジュラス", // frame 5289
        "ラウドポーン": "ラウドボーン" // frame 5289
    ]
    static func propose(_ observed: String, permitted: Set<String>) -> String? {
        let raw = observed.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if permitted.contains(raw) { return raw }
        guard let suggested = spellingAliases[raw], permitted.contains(suggested) else { return nil }
        return suggested
    }
    // Only literal OCR hit; retains raw misspelling. Does not assert this Pokemon's owner.
    static func diagnostic(_ raw: String) -> ResearchReading? {
        guard let proposed=propose(raw, permitted:["ガブリアス", "ブリジュラス", "ラウドボーン"]) ,
              proposed != raw else { return nil }
        return ResearchReading(key:nil,value:.string(proposed),raw_text:raw,
                confidence:nil,reason:"SPELLING_ALIAS_ONLY_NOT_BATTLE_STATE")
    }
}

enum ResearchGenderCandidates {
    static func observed(_ raw: String, side: String) -> ResearchReading? {
        guard side=="own" || side=="opp" else { return nil }
        let t=raw.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in:.whitespacesAndNewlines)
        guard t=="♂" || t=="♀" else { return nil }
        return ResearchReading(key:nil,value:.string(t=="♂" ? "male" : "female"),
            raw_text:raw,confidence:nil,reason:"UNVERIFIED_GENDER_SYMBOL_ROI_"+side.uppercased())
    }
}
