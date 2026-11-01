import Foundation

// R27.428: one OCR patch per move row, with name and PP extracted from
// the SAME Vision result. Diagnostic-only; never confers battle legality.
struct MovePPPairParser {
    struct Token {
        let text: String
        let confidence: Float
    }
    struct Result {
        let moveName: String?
        let moveConfidence: Float?
        let currentPP: Int?
        let maximumPP: Int?
        let ppConfidence: Float?
        var isComplete: Bool {
  moveName != nil && currentPP != nil && maximumPP != nil
        }
    }
    private static let ppExpression = try! NSRegularExpression(
        pattern: #"(?<![0-9])([0-9]{1,2})\s*/\s*([0-9]{1,2})(?![0-9])"#)

    static func parse(_ tokens: [Token]) -> Result? {
        guard !tokens.isEmpty, tokens.count <= 16 else { return nil }
        // NFKC handles full-width numbers and U+FF0F slash. No guesswork
        // from standalone digits, timestamps, or UI ornaments.
        let normalized = tokens.map { $0.text.precomposedStringWithCompatibilityMapping }
        let joined = normalized.joined(separator: " ")
        let matches = ppExpression.matches(in: joined,range:NSRange(joined.startIndex...,in:joined))
        var current: Int? = nil
        var maximum: Int? = nil
        var confidence: Float? = nil
        if matches.count == 1,let match=matches.first,
 let a=Range(match.range(at:1),in:joined),
 let b=Range(match.range(at:2),in:joined),
 let c=Int(joined[a]),let m=Int(joined[b]),
 m > 0 && m <= 99 && c >= 0 && c <= m {
  current=c;maximum=m
  // PP confidence is approximate if OCR split the value into tokens.
  confidence=tokens.map { $0.confidence }.min()
        }
        var validNames = [(String,Float)]()
        for (i,token) in tokens.enumerated() {
  let str=normalized[i]
  let range=NSRange(str.startIndex...,in:str)
  let withoutPP=ppExpression.stringByReplacingMatches(in:str,
      range:range,withTemplate:"")
      .trimmingCharacters(in:.whitespacesAndNewlines)
  guard !withoutPP.isEmpty,
        withoutPP.unicodeScalars.contains(where:{ CharacterSet.letters.contains($0) }),
        !withoutPP.contains(":"),
        !["PP","pp","ＰＰ"].contains(withoutPP),
        withoutPP.count <= 40 else { continue }
  validNames.append((withoutPP,token.confidence))
        }
        // Ambiguous text fragments may be shown as diagnostic, never certified.
        let name=validNames.first?.0
        let nameConfidence=validNames.first?.1
        if name == nil && current == nil { return nil }
        return Result(moveName:name,moveConfidence:nameConfidence,
  currentPP:current,maximumPP:maximum,ppConfidence:confidence)
    }
}
