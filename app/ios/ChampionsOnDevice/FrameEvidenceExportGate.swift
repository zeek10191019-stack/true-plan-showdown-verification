import Foundation

// R27.441. Main-thread value gate; file encoding runs on a separate serial queue.
// Selection/session changes invalidate in-flight work before it can publish a URL.
struct FrameEvidenceExportGate {
    struct Token: Equatable {
        let revision: Int64
        let epoch: Int64
        let frame: Int64
        let observedMs: Int64
        let candidateRevision: Int64
    }
    static let maximumPixels = 4_500_000
    static let maximumDimension = 3072
    static let maximumPNGBytes = 12_000_000
    static let maximumJSONBytes = 20_000_000
    // Two individually permitted PNGs are embedded as base64 in one JSON.
    // A 14 MB aggregate leaves ~1.3 MB headroom in the 20 MB JSON cap.
    static let maximumEmbeddedPNGBytes = 14_000_000
    static func rejectReason(rawBytes: Int?, analysisBytes: Int?,
                             candidatePresent: Bool) -> String? {
        guard let raw=rawBytes, raw > 0 else { return "RAW_PNG_ENCODE_FAILED" }
        guard raw <= maximumPNGBytes else { return "RAW_PNG_TOO_LARGE" }
        if candidatePresent && analysisBytes == nil { return "ANALYSIS_PNG_MISSING" }
        let analysis=analysisBytes ?? 0
        guard analysis >= 0 && analysis <= maximumPNGBytes else { return "ANALYSIS_PNG_TOO_LARGE" }
        guard raw <= maximumEmbeddedPNGBytes - analysis else {
            return "EMBEDDED_PNG_SUM_TOO_LARGE"
        }
        return nil
    }
    // R538: preserve the original selected frame if secondary analysis cannot
    // fit. An omitted candidate is never silently represented as recognized.
    static func candidateDisposition(rawBytes: Int?, analysisBytes: Int?,
                                     candidatePresent: Bool) -> String {
        guard candidatePresent else { return "NONE" }
        guard let problem = rejectReason(rawBytes: rawBytes, analysisBytes: analysisBytes,
                                         candidatePresent: true) else { return "NONE" }
        if ["ANALYSIS_PNG_MISSING", "ANALYSIS_PNG_TOO_LARGE",
            "EMBEDDED_PNG_SUM_TOO_LARGE"].contains(problem),
           rejectReason(rawBytes: rawBytes, analysisBytes: nil,
                        candidatePresent: false) == nil {
            return "ANALYSIS_IMAGE_OMITTED_SIZE_OR_MISSING"
        }
        return "UNRECOVERABLE_EXPORT_LIMIT"
    }
    private(set) var revision: Int64 = 0
    private(set) var pending: Token?

    static func sameSource(candidateFrame: Int64?, candidateEpoch: Int64?,
                           candidateObservedMs: Int64?, rawFrame: Int64,
                           rawEpoch: Int64, rawObservedMs: Int64) -> Bool {
        guard let frame=candidateFrame, let epoch=candidateEpoch,
              let observedMs=candidateObservedMs, frame > 0, epoch > 0,
              observedMs > 0 else { return false }
        return frame == rawFrame && epoch == rawEpoch && observedMs == rawObservedMs
    }
    static func permitted(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maximumDimension &&
        height <= maximumDimension && width * height <= maximumPixels
    }
    mutating func request(epoch: Int64, frame: Int64, observedMs: Int64,
                          candidateRevision: Int64, width: Int, height: Int) -> Token? {
        guard pending == nil, epoch > 0, frame > 0, observedMs > 0,
              Self.permitted(width: width, height: height) else { return nil }
        revision &+= 1
        let token = Token(revision: revision, epoch: epoch, frame: frame,
                          observedMs: observedMs, candidateRevision: candidateRevision)
        pending = token
        return token
    }
    func accepts(_ token: Token, epoch: Int64, frame: Int64,
                 candidateRevision: Int64) -> Bool {
        pending == token && revision == token.revision && epoch == token.epoch &&
        frame == token.frame && candidateRevision == token.candidateRevision
    }
    mutating func finish(_ token: Token) {
        if pending == token { pending = nil }
    }
    mutating func invalidate() { revision &+= 1; pending = nil }
}
