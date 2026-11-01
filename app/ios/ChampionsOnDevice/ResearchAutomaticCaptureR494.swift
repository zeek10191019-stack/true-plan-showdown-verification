import Foundation

struct TP494AutoSampleGate {
    private(set) var epoch: Int = -1
    private(set) var latestFrame: Int64 = -1
    private(set) var lastAttemptMs: Int64 = -1
    private(set) var inFlight: Bool = false
    private var pendingFrame: Int64? = nil
    private var pendingObservedMs: Int64? = nil
    private(set) var offered: Int = 0
    private(set) var completed: Int = 0
    private(set) var discarded: Int = 0
    private(set) var geometryHeld: Int = 0
    private(set) var maxOCRMs: Int64 = 0
    private(set) var maxAgeMs: Int64 = 0
    private(set) var overBudget: Int = 0
    private let intervalMs: Int64 = 1200
    private let freshnessBudgetMs: Int64 = 1500

    mutating func reset() {
        epoch = -1
        latestFrame = -1
        lastAttemptMs = -1
        inFlight = false
        pendingFrame = nil; pendingObservedMs = nil
    }
    static func supportedRawPixels(_ w: Int, _ h: Int) -> Bool {
        (w == 1290 && h == 2796) || (w == 2796 && h == 1290)
    }
    mutating func offer(epoch ep: Int, frame: Int64, observedMs: Int64,
                        width: Int, height: Int, background: Bool) -> Bool {
        guard ep >= 0, frame > 0, observedMs >= 0, background else {
            discarded += 1; return false
        }
        if ep != epoch {
            guard ep > epoch else { discarded += 1; return false }
            epoch = ep
            latestFrame = -1
            lastAttemptMs = -1
            inFlight = false
            pendingFrame = nil; pendingObservedMs = nil
        }
        guard frame > latestFrame else { discarded += 1; return false }
        latestFrame = frame
        guard Self.supportedRawPixels(width,height) else {
            geometryHeld += 1; return false
        }
        guard !inFlight else { return false }
        guard lastAttemptMs == -1 ||
              (observedMs >= lastAttemptMs && observedMs - lastAttemptMs >= intervalMs)
        else {return false}
        lastAttemptMs = observedMs
        inFlight = true
        pendingFrame = frame; pendingObservedMs = observedMs
        offered += 1
        return true
    }
    mutating func finish(epoch ep: Int, frame: Int64, observedMs: Int64,
                         startedMs: Int64, completedMs: Int64,
                         succeeded: Bool) -> String {
        guard let expectedFrame=pendingFrame,let expectedObserved=pendingObservedMs,
              ep == epoch, inFlight, frame == expectedFrame, observedMs == expectedObserved,
              startedMs >= observedMs, completedMs >= startedMs else {
            discarded += 1; return "OLD_OR_INCONSISTENT_OCR"
        }
        inFlight = false
        pendingFrame = nil; pendingObservedMs = nil
        let elapsed = completedMs - startedMs
        let age = completedMs - observedMs
        maxOCRMs = max(maxOCRMs,elapsed)
        maxAgeMs = max(maxAgeMs,age)
        if age > freshnessBudgetMs { overBudget += 1 }
        if succeeded { completed += 1 }
        else { discarded += 1 }
        return !succeeded ? "VISION_FAILED" :
            age > freshnessBudgetMs ? "HISTORICAL_FRAME_ONLY" :
            frame != latestFrame ? "SUPERSEDED_FRAME_RESEARCH_ONLY" :
            "SAME_EPOCH_RESEARCH_ONLY"
    }
    var concise: String {
        "自動OCR 取得\(offered)／解析\(completed)／廃棄\(discarded)" +
        "／寸法保留\(geometryHeld)／最長解析\(maxOCRMs)ms" +
        "／最大経過\(maxAgeMs)ms／1500ms超過\(overBudget)" +
        "。全件研究候補、対戦助言は無効"
    }
}
