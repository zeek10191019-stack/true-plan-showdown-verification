import Foundation

// Pure-state, Linux-testable, user-triggered read-only diagnostic.
// No calibration output is promoted to a game-recognition or action Gate.
struct ManualOCRDiagnosticGate {
    private(set) var revision: Int64 = 0
    private(set) var frameID: Int64? = nil
    private(set) var manuallyRequested = false
    mutating func invalidate() {
        revision &+= 1
        frameID = nil
        manuallyRequested = false
    }
    mutating func request(frameID: Int64, roiCount: Int) -> Int64? {
        invalidate()
        guard frameID > 0 && roiCount == 4 else {return nil}
        self.frameID = frameID
        manuallyRequested = true
        return revision
    }
    func validCompletion(revision: Int64, frameID: Int64, count: Int) -> Bool {
        manuallyRequested && self.revision == revision &&
        self.frameID == frameID && count == 4
    }
    static func sanitize(_ source: String) -> String? {
        // Deliberately not a Pokémon move parser. Only safe display text.
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 40,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {return nil}
        return text
    }
    static let certification = "USER_TRIGGERED_OCR_DIAGNOSTIC_ONLY_NO_ACTION"
}
