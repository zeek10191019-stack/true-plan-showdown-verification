import Foundation

// R27.412: conservative *negative* screening of a tiny volatile RGB thumbnail.
// Not a game detector. "candidateUnverified" never proves Pokémon Champions content.
// Use the same two source frames that produced the OCR pair; never infer from OCR text.
struct FrameVisualGate {
    static let columns = 24
    static let rows = 12

    enum Verdict: String {
        case candidateUnverified = "VISUAL_CANDIDATE_UNVERIFIED"
        case appSwitcherLike = "APP_SWITCHER_LIKE_REJECTED"
        case blankLike = "BLANK_OR_UNIFORM_REJECTED"
        case invalidSample = "INVALID_THUMBNAIL_REJECTED"
    }

    // RGB 24x12 thumbnail, row-major, 3 bytes per pixel. No source frame is saved.
    static func inspect(rgb: [UInt8], width: Int = columns,
                        height: Int = rows) -> Verdict {
        guard width == columns, height == rows, rgb.count == columns * rows * 3 else {
            return .invalidSample
        }
        var darkCount = 0
        var leftDark = 0
        var rightDark = 0
        var centerVisible = 0
        var sum = 0.0
        var squareSum = 0.0
        for row in 0..<rows {
            for col in 0..<columns {
                let i = (row * columns + col) * 3
                let r = Int(rgb[i]), g = Int(rgb[i+1]), b = Int(rgb[i+2])
                let dark = r < 32 && g < 32 && b < 32
                if dark { darkCount += 1 }
                if col < 5 && dark { leftDark += 1 }
                if col >= columns - 5 && dark { rightDark += 1 }
                if col >= 9 && col < 15 && !dark { centerVisible += 1 }
                let y = 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
                sum += y
                squareSum += y * y
            }
        }
        let n = Double(columns * rows)
        let variance = max(0, squareSum / n - (sum / n) * (sum / n))
        if darkCount >= 275 || variance < 16 { return .blankLike }
        // iOS task-switcher/portrait UI in a landscape stream often occupies a
        // narrow central vertical band with mostly dark side pillars.
        // False rejections are allowed, false "game certified" never is.
        if leftDark >= 54 && rightDark >= 38 && centerVisible >= 14 {
            return .appSwitcherLike
        }
        return .candidateUnverified
    }

    static func paired(_ first: Verdict, _ second: Verdict) -> Verdict {
        // Both images must be visually eligible; never bypass a rejected first frame.
        if first == .invalidSample || second == .invalidSample { return .invalidSample }
        if first == .appSwitcherLike || second == .appSwitcherLike { return .appSwitcherLike }
        if first == .blankLike || second == .blankLike { return .blankLike }
        return .candidateUnverified
    }
}
