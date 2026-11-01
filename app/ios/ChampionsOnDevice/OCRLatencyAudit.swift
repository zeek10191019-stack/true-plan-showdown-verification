import Foundation

// Only numerical durations, epoch and counters. No pixels, OCR text, game state or action advice.
// Mutations are confined to the serial capture sample queue.
struct OCRLatencyAudit {
    enum Verdict: String { case measured, overBudget, inactive, staleEpoch, invalidClock }
    private(set) var epoch: Int64 = 0
    private(set) var active = false
    private(set) var measured = 0
    private(set) var withinBudget = 0
    private(set) var overBudget = 0
    private(set) var staleEpoch = 0
    private(set) var invalidClock = 0
    private(set) var maximumAgeMs: Int64 = 0
    private(set) var maximumOCRMs: Int64 = 0
    private var last32Ages: [Int64] = []
    static let ageBudgetMs: Int64 = 1500
    static let capacity = 32

    mutating func start(epoch newEpoch: Int64) {
        epoch = newEpoch
        active = true
        measured = 0
        withinBudget = 0
        overBudget = 0
        staleEpoch = 0
        invalidClock = 0
        maximumAgeMs = 0
        maximumOCRMs = 0
        last32Ages.removeAll(keepingCapacity: true)
    }

    mutating func stop(epoch expectedEpoch: Int64) {
        guard expectedEpoch == epoch else { return }
        active = false
    }

    // completedMs includes the handoff back onto the serial capture queue; all are monotonic.
    @discardableResult
    mutating func observe(epoch inputEpoch: Int64, frameMs: Int64,
                          ocrStartedMs: Int64, completedMs: Int64) -> Verdict {
        guard active else { return .inactive }
        guard epoch == inputEpoch else {
            staleEpoch += 1
            return .staleEpoch
        }
        guard frameMs >= 0, ocrStartedMs >= frameMs, completedMs >= ocrStartedMs,
              completedMs - frameMs >= 0 else {
            invalidClock += 1
            return .invalidClock
        }
        let age = completedMs - frameMs
        let ocr = completedMs - ocrStartedMs
        measured += 1
        maximumAgeMs = max(maximumAgeMs, age)
        maximumOCRMs = max(maximumOCRMs, ocr)
        last32Ages.append(age)
        if last32Ages.count > Self.capacity { last32Ages.removeFirst() }
        if age <= Self.ageBudgetMs {
            withinBudget += 1
            return .measured
        }
        overBudget += 1
        return .overBudget
    }

    func snapshot() -> OCRLatencySnapshot {
        let ages = last32Ages.sorted()
        let p95: Int64? = ages.isEmpty ? nil : ages[((ages.count * 95 + 99) / 100) - 1]
        return OCRLatencySnapshot(epoch: epoch, active: active, budgetMs: Self.ageBudgetMs,
                                  measuredPairs: measured, withinBudgetPairs: withinBudget,
                                  overBudgetPairs: overBudget, staleEpochRejects: staleEpoch,
                                  invalidClockRejects: invalidClock, maxFrameAgeMs: maximumAgeMs,
                                  maxOCRStageMs: maximumOCRMs, p95FrameAgeMsLast32: p95,
                                  windowPairs: ages.count)
    }
}

struct OCRLatencySnapshot: Codable, Equatable {
    let epoch: Int64
    let active: Bool
    let budgetMs: Int64
    let measuredPairs: Int
    let withinBudgetPairs: Int
    let overBudgetPairs: Int
    let staleEpochRejects: Int
    let invalidClockRejects: Int
    let maxFrameAgeMs: Int64
    let maxOCRStageMs: Int64
    let p95FrameAgeMsLast32: Int64?
    let windowPairs: Int
}
