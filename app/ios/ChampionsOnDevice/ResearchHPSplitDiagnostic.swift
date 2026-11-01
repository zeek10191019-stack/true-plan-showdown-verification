import Foundation

// R27.472 — bounded, diagnostic-only split-digit OCR adapter.
// Does not assign HP to a Pokemon, alter canonical data, authorize a move,
// reconstruct digits from a concatenated OCR token, or imply a validated ROI.
struct ResearchHPSplitRect: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var right: Double { x + width }
    var bottom: Double { y + height }
}

struct ResearchHPSplitPlan {
    let numerator: ResearchHPSplitRect
    let denominator: ResearchHPSplitRect
    let separator: ResearchHPSplitRect
    let status: String

    // Measured only on the legacy 578x267 landscape ROI profile.
    // This is a research hypothesis; geometry alone does not authenticate ROI.
    static func own(calibratedLandscapeAspect: Bool, roiWidth: Int,
                    roiHeight: Int) -> ResearchHPSplitPlan? {
        guard calibratedLandscapeAspect, roiWidth >= 80, roiHeight >= 35,
              roiWidth <= 1000, roiHeight <= 500 else { return nil }
        return ResearchHPSplitPlan(
            numerator: ResearchHPSplitRect(x:0.12,y:0.12,width:0.485,height:0.78),
            denominator: ResearchHPSplitRect(x:0.705,y:0.12,width:0.275,height:0.78),
            separator: ResearchHPSplitRect(x:0.61,y:0.12,width:0.10,height:0.78),
            status:"UNVERIFIED_578X267_LAYOUT_PROFILE")
    }
}

enum ResearchHPSplitResult: Equatable {
    case hold(String)
    case candidate(current: Int, maximum: Int, leftRaw: String, rightRaw: String)
}

enum ResearchHPSplitDiagnostic {
    static let productionEnabled = false
    // This intentionally does not accept OCR substitutions (I→1, etc.) or
    // missing digits. Separate OCR tracks must each yield literal digits.
    private static func numeral(_ s: String) -> Int? {
        let text = s.precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 1 && text.count <= 4,
              text.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
              let v = Int(text), v <= 9999 else { return nil }
        return v
    }
    static func inspectOwn(leftRaw: String, rightRaw: String,
                           roiProfileAvailable: Bool) -> ResearchHPSplitResult {
        guard roiProfileAvailable else { return .hold("UNVERIFIED_LAYOUT_PROFILE") }
        guard let n = numeral(leftRaw), let d = numeral(rightRaw),
              d > 0, n <= d else { return .hold("INVALID_SEGMENTED_HP_LITERAL") }
        // A valid candidate is only a suggested string for the diagnostic UI.
        // It has no key and NEVER carries a numeric Battle State value.
        return .candidate(current:n,maximum:d,leftRaw:leftRaw,rightRaw:rightRaw)
    }
    static func diagnosticReading(_ candidate: ResearchHPSplitResult) -> ResearchReading? {
        guard case let .candidate(n,d,left,right) = candidate else { return nil }
        return ResearchReading(key:nil,value:.string("\(n)/\(d)"),
            raw_text:"split-left=\(left);split-right=\(right)",confidence:nil,
            reason:"UNVERIFIED_SPLIT_HP_LAYOUT_OWN_NOT_BATTLE_STATE")
    }
    static func hasLiteralSlashHP(_ raw:String) -> Bool {
        let token = raw.replacingOccurrences(of:"／",with:"/")
            .trimmingCharacters(in:.whitespacesAndNewlines)
        let parts = token.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count == 2 else { return false }
        guard let n = numeral(String(parts[0])), let d = numeral(String(parts[1])) else { return false }
        return d > 0 && n <= d
    }
}
