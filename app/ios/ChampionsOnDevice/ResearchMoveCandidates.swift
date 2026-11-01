import Foundation

// Research-only exact dictionary and narrowly-scoped OCR alias. Never authorizes an action.
enum ResearchMoveCandidates {
    static let aliases: [String:String] = ["ハイパーポイス":"ハイパーボイス"]
    static func candidate(_ raw: String, legalNames: Set<String>) -> String? {
        let normalized = raw.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        if legalNames.contains(normalized) { return normalized }
        guard let corrected = aliases[normalized], legalNames.contains(corrected) else { return nil }
        return corrected
    }
}
