import Foundation

// R27.412: volatile, one-sample diagnostic storage. Caller must serialize access
// on the SCStream sample queue. Neither the picture nor OCR text is encoded into
// telemetry JSON, sent to a server, placed on UIPasteboard, or saved to disk.
struct DiagnosticFrameMemory {
    struct Snapshot {
        let epoch: Int64
        let frameID: Int64
        let png: Data
        let fourMoveCandidates: [String]
        let observationMs: Int64
        let processingMs: Int64
        let visualVerdict: FrameVisualGate.Verdict
    }

    enum Verdict: String {
        case accepted = "BACKGROUND_OCR_SAMPLE_STAGED"
        case foreground = "NOT_BACKGROUND_FRAME"
        case invalidEpoch = "INVALID_EPOCH"
        case invalidFrame = "INVALID_FRAME_ID"
        case invalidTimestamp = "INVALID_TIMESTAMP"
        case invalidSlots = "INVALID_SLOT_COUNT"
        case tooLarge = "IMAGE_TOO_LARGE"
        case invalidImage = "INVALID_PNG_SIGNATURE"
        case badText = "INVALID_OCR_TEXT"
        case screenRejected = "SCREEN_NOT_DIAGNOSTIC_CANDIDATE"
    }

    // PNG size maximum is deliberately well above an RGB 1108x512 PNG in most cases,
    // but limits memory growth and rejects malformed large payloads.
    static let maximumPNGBytes = 5_000_000
    private(set) var latest: Snapshot?
    private(set) var rejectedScreens: Int = 0
    private(set) var stagedScreens: Int = 0
    static let maximumSampleAgeMs: Int64 = 12_000

    @discardableResult
    mutating func stage(epoch: Int64, frameID: Int64, png: Data,
                        candidates: [String], observedMs: Int64,
                        processedMs: Int64, isBackground: Bool,
                        screenVerdict: FrameVisualGate.Verdict = .candidateUnverified) -> Verdict {
        guard isBackground else { return .foreground }
        guard screenVerdict == .candidateUnverified else {
            rejectedScreens += 1
            return .screenRejected
        }
        guard epoch > 0 else { return .invalidEpoch }
        guard frameID > 0 else { return .invalidFrame }
        guard observedMs >= 0, processedMs >= observedMs else { return .invalidTimestamp }
        guard candidates.count == 4 else { return .invalidSlots }
        guard png.count <= Self.maximumPNGBytes else { return .tooLarge }
        guard png.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
            else { return .invalidImage }
        guard candidates.allSatisfy({ $0 == "—" || OCRPairConsensus.sanitize($0) == $0 })
            else { return .badText }
        if let previous = latest, previous.epoch == epoch,
           frameID <= previous.frameID { return .invalidFrame }
        latest = Snapshot(epoch: epoch, frameID: frameID, png: png,
                          fourMoveCandidates: candidates,
                          observationMs: observedMs,
                          processingMs: processedMs - observedMs,
                          visualVerdict: screenVerdict)
        stagedScreens += 1
        return .accepted
    }

    // An epoch rotation, failed stream or user stop may never expose old pixels.
    mutating func takeAndClear(expectedEpoch: Int64, nowMs: Int64) -> Snapshot? {
        defer { latest = nil }
        guard let sample = latest, sample.epoch == expectedEpoch,
              nowMs >= sample.observationMs,
              nowMs - sample.observationMs <= Self.maximumSampleAgeMs else { return nil }
        return sample
    }

    mutating func clear() { latest = nil }

    mutating func resetSession() {
        latest = nil
        rejectedScreens = 0
        stagedScreens = 0
    }
}
