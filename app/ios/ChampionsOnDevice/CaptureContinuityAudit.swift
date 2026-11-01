import Foundation

// R27.401. Numeric, device-local telemetry ONLY. Never record frame pixels, OCR text,
// game identities, audio, device identifiers, or permissions. Mutate on sampleQueue.
// No timers are required: the OS may suspend app timers when backgrounded.
struct CaptureContinuityAudit {
    enum Verdict: String {
        case accepted = "FRAME_ACCEPTED_RESEARCH_ONLY"
        case inactive = "INACTIVE"
        case wrongEpoch = "RETIRED_SESSION"
        case invalidClock = "INVALID_MONOTONIC_TIME"
        case outOfOrder = "NONINCREASING_FRAME_ID"
        case unexpectedShape = "UNEXPECTED_FRAME_GEOMETRY"
    }

    struct Snapshot: Codable {
        let release: String
        let captureActive: Bool
        let currentEpoch: Int64
        let deliveredFrames: Int64
        let foregroundFrames: Int64
        let backgroundFrames: Int64
        let backgroundTransitions: Int64
        let foregroundReturns: Int64
        let measuredBackgroundMs: Int64
        let longestFrameGapMs: Int64
        let longFrameGaps: Int64
        let wrongEpochRejects: Int64
        let unexpectedShapeRejects: Int64
        let outOfOrderRejects: Int64
        let invalidClockRejects: Int64
        let streamStopEvents: Int64
        let currentlyBackgrounded: Bool
        let currentlyBackgroundForMs: Int64
        let backgroundFrameDeliveryObserved: Bool
        let lastAcceptedFrameAgeMs: Int64?
        let status: String
        let limitations: String
    }

    // This is diagnostic, not a real-time bound for decision making.
    static let longGapMs: Int64 = 2500
    private(set) var epoch: Int64 = 0
    private(set) var active = false
    private(set) var backgrounded = false
    private var startedAtMs: Int64 = 0
    private var lastAcceptedMs: Int64?
    private var lastFrameID: Int64 = 0
    private var backgroundStartedMs: Int64?
    private(set) var deliveredFrames: Int64 = 0
    private(set) var foregroundFrames: Int64 = 0
    private(set) var backgroundFrames: Int64 = 0
    private(set) var backgroundTransitions: Int64 = 0
    private(set) var foregroundReturns: Int64 = 0
    private(set) var measuredBackgroundMs: Int64 = 0
    private(set) var longestFrameGapMs: Int64 = 0
    private(set) var longFrameGaps: Int64 = 0
    private(set) var wrongEpochRejects: Int64 = 0
    private(set) var unexpectedShapeRejects: Int64 = 0
    private(set) var outOfOrderRejects: Int64 = 0
    private(set) var invalidClockRejects: Int64 = 0
    private var requiredWidth = 1108
    private var requiredHeight = 512
    mutating func expectFrameSize(width:Int,height:Int) {
        guard width >= 320,height >= 320,
              width <= 3072,height <= 3072,width*height <= 4_500_000 else {return}
        requiredWidth=width;requiredHeight=height
    }
    private(set) var streamStopEvents: Int64 = 0

    mutating func start(epoch: Int64, atMs: Int64) {
        self = CaptureContinuityAudit()
        self.epoch = epoch
        self.startedAtMs = max(0, atMs)
        self.active = true
    }

    // Foreground return retires queued OCR work without discarding telemetry history.
    mutating func rotateEpochKeepingCounts(from oldEpoch: Int64, to newEpoch: Int64) {
        guard active, epoch == oldEpoch, newEpoch > oldEpoch else { return }
        epoch = newEpoch
    }

    mutating func didEnterBackground(epoch candidate: Int64, atMs: Int64) {
        guard active, epoch == candidate else { return }
        guard !backgrounded, atMs >= startedAtMs, atMs >= (lastAcceptedMs ?? startedAtMs) else {
            invalidClockRejects += 1
            return
        }
        backgrounded = true
        backgroundStartedMs = atMs
        backgroundTransitions += 1
    }

    mutating func willEnterForeground(epoch candidate: Int64, atMs: Int64) {
        guard active, epoch == candidate, backgrounded, let started = backgroundStartedMs else { return }
        guard atMs >= started else { invalidClockRejects += 1; return }
        measuredBackgroundMs += atMs - started
        backgrounded = false
        backgroundStartedMs = nil
        foregroundReturns += 1
    }

    // Check the actual CVPixelBuffer geometry, not the configured SCStream dimensions.
    @discardableResult
    mutating func observedFrame(epoch candidate: Int64, frameID: Int64,
                                atMs: Int64, width: Int, height: Int) -> Verdict {
        guard active else { return .inactive }
        guard epoch == candidate else { wrongEpochRejects += 1; return .wrongEpoch }
        guard atMs >= startedAtMs, atMs >= (lastAcceptedMs ?? startedAtMs) else {
            invalidClockRejects += 1
            return .invalidClock
        }
        guard frameID > lastFrameID else { outOfOrderRejects += 1; return .outOfOrder }
        guard width == requiredWidth, height == requiredHeight else {
            unexpectedShapeRejects += 1
            return .unexpectedShape
        }
        if let previous = lastAcceptedMs {
            let interval = atMs - previous
            if interval > longestFrameGapMs { longestFrameGapMs = interval }
            if interval > Self.longGapMs { longFrameGaps += 1 }
        }
        lastFrameID = frameID
        lastAcceptedMs = atMs
        deliveredFrames += 1
        if backgrounded { backgroundFrames += 1 } else { foregroundFrames += 1 }
        return .accepted
    }

    mutating func stopped(epoch candidate: Int64, atMs: Int64) {
        guard active, epoch == candidate else { return }
        if backgrounded, let began = backgroundStartedMs, atMs >= began {
            measuredBackgroundMs += atMs - began
        }
        streamStopEvents += 1
        active = false
        backgrounded = false
        backgroundStartedMs = nil
    }

    func snapshot(nowMs: Int64) -> Snapshot {
        let runningBg = active && backgrounded && backgroundStartedMs != nil
            ? max(0, nowMs - (backgroundStartedMs ?? nowMs)) : 0
        let age: Int64? = active && lastAcceptedMs != nil && nowMs >= (lastAcceptedMs ?? nowMs)
            ? nowMs - (lastAcceptedMs ?? nowMs) : nil
        let label: String
        if !active { label = "STOPPED_NO_ADVICE" }
        else if backgrounded && backgroundFrames == 0 { label = "BACKGROUND_FRAMES_NOT_YET_OBSERVED" }
        else if let age, age > Self.longGapMs { label = "FRAME_DELIVERY_STALE_NO_ADVICE" }
        else if backgroundFrames > 0 { label = "BACKGROUND_FRAMES_SEEN_NOT_E2E_CERTIFIED" }
        else { label = "FOREGROUND_RESEARCH_ONLY" }
        return Snapshot(
            release: "R27.401", captureActive: active, currentEpoch: epoch,
            deliveredFrames: deliveredFrames, foregroundFrames: foregroundFrames,
            backgroundFrames: backgroundFrames, backgroundTransitions: backgroundTransitions,
            foregroundReturns: foregroundReturns,
            measuredBackgroundMs: measuredBackgroundMs,
            longestFrameGapMs: longestFrameGapMs, longFrameGaps: longFrameGaps,
            wrongEpochRejects: wrongEpochRejects,
            unexpectedShapeRejects: unexpectedShapeRejects,
            outOfOrderRejects: outOfOrderRejects,
            invalidClockRejects: invalidClockRejects, streamStopEvents: streamStopEvents,
            currentlyBackgrounded: backgrounded, currentlyBackgroundForMs: runningBg,
            backgroundFrameDeliveryObserved: backgroundFrames > 0,
            lastAcceptedFrameAgeMs: age, status: label,
            limitations: "Local numeric telemetry only. No live iPhone execution, OCR accuracy, sound, battle legality or move recommendations certified."
        )
    }
}
