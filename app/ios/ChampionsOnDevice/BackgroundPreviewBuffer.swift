import Foundation

// R27.415: 8-frame background timeline, independent from OCR and game certification.
// THIS IMAGE IS NOT AUTHORIZED AS A GAME OBSERVATION OR A MOVE RECOMMENDATION.
// All access serialized on SCStream sample queue; no files, network, or clipboard.
struct BackgroundPreviewBuffer {
    struct Snapshot {
        let epoch: Int64
        let frameID: Int64
        let png: Data
        let observedMs: Int64
    }
    static let sampleSpacingMs: Int64 = 4_000
    static let preferredMinimumAgeMs: Int64 = 1_500
    static let maximumAgeMs: Int64 = 50_000
    static let maximumPNGBytes = 12_000_000
    static let maximumTotalPNGBytes = 48_000_000
    static let maximumSamples = 8
    private(set) var samples = [Snapshot]()
    private(set) var savedCount = 0
    private(set) var consideredCount = 0
    private var lastSampleAttemptMs: Int64?

    func shouldSample(epoch: Int64, atMs: Int64, isBackground: Bool) -> Bool {
        guard epoch > 0, atMs >= 0, isBackground else { return false }
        guard let last = lastSampleAttemptMs else { return true }
        return atMs >= last + Self.sampleSpacingMs
    }

    mutating func offer(epoch: Int64, frameID: Int64, png: Data,
                        observedMs: Int64, isBackground: Bool) -> Bool {
        guard shouldSample(epoch: epoch, atMs: observedMs, isBackground: isBackground) else { return false }
        lastSampleAttemptMs = observedMs
        consideredCount += 1
        guard frameID > 0, png.count <= Self.maximumPNGBytes,
              png.starts(with: [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]) else { return false }
        if let last = samples.last {
            guard last.epoch == epoch && frameID > last.frameID && observedMs > last.observedMs else { return false }
        }
        // Evict oldest background snapshots before a new allocation. This is a
        // hard PNG payload bound; UIKit decoded images also consume RAM, so
        // snapshots are still explicitly short-lived and cleared on stop.
        var totalBytes = samples.reduce(0) { $0 + $1.png.count }
        while !samples.isEmpty &&
              (samples.count >= Self.maximumSamples || totalBytes + png.count > Self.maximumTotalPNGBytes) {
            totalBytes -= samples.removeFirst().png.count
        }
        guard totalBytes + png.count <= Self.maximumTotalPNGBytes else {return false}
        samples.append(Snapshot(epoch: epoch, frameID: frameID, png: png, observedMs: observedMs))
        savedCount += 1
        return true
    }

    // One-shot, RAM-only timeline: permits the user to inspect older background
    // frames even when the last few frames belong to the application switcher.
    // No image becomes an OCR, legal-move, or recommendation observation.
    mutating func takeTimelineAndClear(epoch: Int64, nowMs: Int64) -> [Snapshot] {
        defer { samples.removeAll(keepingCapacity: false); lastSampleAttemptMs = nil }
        guard epoch > 0, nowMs >= 0 else { return [] }
        return samples.filter { item in
            item.epoch == epoch && nowMs >= item.observedMs &&
            nowMs - item.observedMs <= Self.maximumAgeMs
        }
    }

    // Compatibility with the R27.414 single-preview caller and local regression.
    mutating func takeAndClear(epoch: Int64, nowMs: Int64) -> Snapshot? {
        let timeline = takeTimelineAndClear(epoch: epoch, nowMs: nowMs)
        let earlier = timeline.filter { nowMs - $0.observedMs >= Self.preferredMinimumAgeMs }
        return earlier.last ?? timeline.last
    }

    mutating func clear() { samples.removeAll(keepingCapacity: false); lastSampleAttemptMs = nil }
    mutating func resetSession() { clear(); consideredCount = 0; savedCount = 0 }
}
