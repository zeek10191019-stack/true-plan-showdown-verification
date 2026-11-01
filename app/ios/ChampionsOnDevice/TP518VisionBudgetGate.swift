import Foundation
#if canImport(UIKit) && canImport(Vision)
import UIKit
import Vision
#endif

/// R518: bounded research-only second-pass OCR; no late result is ever published.
/// Never makes OWN/OPP, HP/PP or battle-decision assertions.
enum TP518VisionBudgetGate {
    private static let lock = NSLock()
    private static var busy = false
    private static var requested = 0
    private static var completed = 0
    private static var timeouts = 0
    private static var skipped = 0
    private static var failures = 0
    struct Counters {
        let requested: Int
        let completed: Int
        let timeouts: Int
        let skipped: Int
        let failures: Int
        var ownerCertified: Bool { false }
        var decisionEligible: Bool { false }
    }
    private final class Box: @unchecked Sendable {
        private let lock=NSLock()
        private var value: TP517VisionROISidecar.Result?
        func save(_ value: TP517VisionROISidecar.Result) {
            lock.lock(); self.value=value; lock.unlock()
        }
        func load() -> TP517VisionROISidecar.Result? {
            lock.lock(); defer { lock.unlock() }; return value
        }
    }
    static func counters() -> Counters {
        lock.lock(); defer { lock.unlock() }
        return Counters(requested:requested,completed:completed,timeouts:timeouts,
                        skipped:skipped,failures:failures)
    }
    static func inspect(wire: String, budgetMs: Int = 85,
                        operation: @escaping () -> TP517VisionROISidecar.Result)
                        -> TP517VisionROISidecar.Result {
        func rejected(_ message: String) -> TP517VisionROISidecar.Result {
            .init(wire:wire,added:0,reason:message)
        }
        guard (1...200).contains(budgetMs),wire.utf8.count<=1_000_000 else {
            return rejected("ROI_BUDGET_OR_INPUT_INVALID")
        }
        lock.lock()
        guard !busy else {
            skipped += 1
            lock.unlock()
            return rejected("ROI_WORKER_BUSY_DROP")
        }
        busy = true
        requested += 1
        lock.unlock()
        let box=Box()
        let semaphore=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async {
            // The worker never writes to the original OCR wire, UI, or Battle State.
            let value=operation()
            box.save(value)
            lock.lock()
            completed += 1
            if value.added==0 { failures += 1 }
            busy = false
            lock.unlock()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + .milliseconds(budgetMs)) == .success,
           let value=box.load() {
            return value
        }
        lock.lock(); timeouts += 1; lock.unlock()
        return rejected("ROI_WORKER_LATENCY_BUDGET_EXCEEDED")
    }
}

#if canImport(UIKit) && canImport(Vision)
extension TP518VisionBudgetGate {
    static func enrich(wire: String,png: Data,battleID: String,
                       epoch:Int,frameID:Int64) -> TP517VisionROISidecar.Result {
        inspect(wire:wire,budgetMs:85) {
            TP517VisionROISidecar.enrich(wire:wire,png:png,
                  battleID:battleID,epoch:epoch,frameID:frameID)
        }
    }
}
#endif
