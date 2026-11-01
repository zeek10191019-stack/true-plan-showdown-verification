import Foundation
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#endif

/// R519: application-lifetime research-only telemetry of the *actual* second
/// OCR invocation. Does not interpret a rectangle or promote observations.
enum TP519VisionEvidenceMetrics {
    private static let lock = NSLock()
    private static var attempted = 0
    private static var roiAdded = 0
    private static var empty = 0
    private static var timeout = 0
    private static var busy = 0
    private static var invalid = 0
    private static var sampleMs = [Int]()
    private static let window = 64

    struct Snapshot {
        let attempted: Int
        let roiAdded: Int
        let empty: Int
        let timeout: Int
        let busy: Int
        let invalid: Int
        let samples: Int
        let medianMs: Int?
        let p95Ms: Int?
        let maxMs: Int?
        var ownerCertified: Bool { false }
        var decisionEligible: Bool { false }
        var recognitionCertified: Bool { false }
        var status: String {
            if attempted == 0 { return "NO_SAMPLED_OCR_ATTEMPT" }
            if roiAdded == 0 { return "NO_MATCHED_ROI_YET" }
            return "ROI_CANDIDATES_ONLY_UNCERTIFIED"
        }
        var summary: String {
            let p=p95Ms.map(String.init) ?? "-"
            return "追加Vision: 試行\(attempted)／座標候補取得\(roiAdded)／空\(empty)／時間超過\(timeout)／実行中スキップ\(busy)／不正入力\(invalid)／直近\(samples)件p95 \(p)ms"
        }
        var redactedJSON: String {
            let report: [String: Any] = [
                "schema":"R519_VISION_METRICS_V1",
                "scope":"APP_LIFETIME_RESEARCH_ONLY",
                "attempted":attempted,"roi_added_attempts":roiAdded,
                "empty_attempts":empty,"timeouts":timeout,
                "worker_busy_skips":busy,"invalid_inputs":invalid,
                "latency_window_samples":samples,
                "latency_median_ms":medianMs as Any? ?? NSNull(),
                "latency_p95_ms":p95Ms as Any? ?? NSNull(),
                "latency_max_ms":maxMs as Any? ?? NSNull(),
                "status":status,"owner_certified":false,
                "recognition_certified":false,"decision_eligible":false,
                "image_bytes_included":false,"ocr_text_included":false,
                "battle_id_included":false,"image_sha_included":false
            ]
            guard let b=try? JSONSerialization.data(withJSONObject: report, options:[.sortedKeys]),
                  let s=String(data:b,encoding:.utf8) else {return "{}"}
            return s
        }
    }

    static func record(added: Int, reason: String, elapsedMs: Int) {
        guard (0...120_000).contains(elapsedMs),added>=0,added<=256,
              reason.utf8.count<=96 else{return}
        lock.lock(); defer {lock.unlock()}
        attempted += 1
        if added>0 && reason=="RESEARCH_ROI_CANDIDATES_ONLY" {roiAdded += 1}
        else if reason=="ROI_WORKER_LATENCY_BUDGET_EXCEEDED" {timeout += 1}
        else if reason=="ROI_WORKER_BUSY_DROP" {busy += 1}
        else if reason=="ROI_BUDGET_OR_INPUT_INVALID" {invalid += 1}
        else {empty += 1}
        sampleMs.append(elapsedMs)
        if sampleMs.count>window { sampleMs.removeFirst(sampleMs.count-window) }
    }

    static func snapshot() -> Snapshot {
        lock.lock(); defer {lock.unlock()}
        let ordered=sampleMs.sorted()
        let n=ordered.count
        return Snapshot(attempted:attempted,roiAdded:roiAdded,empty:empty,
                        timeout:timeout,busy:busy,invalid:invalid,
                        samples:n,medianMs:n>0 ? ordered[(n-1)/2] : nil,
                        p95Ms:n>0 ? ordered[(95*n+99)/100-1] : nil,
                        maxMs:ordered.last)
    }
}

#if canImport(UIKit) && canImport(Vision)
extension TP519VisionEvidenceMetrics {
    /// The wrapper is called only at R517's 1/8-frame sampling point.
    /// The result is still a research-only Wire, never a battle decision input.
    static func enrich(wire:String,png:Data,battleID:String,
                       epoch:Int,frameID:Int64) -> TP517VisionROISidecar.Result {
        let start=DispatchTime.now().uptimeNanoseconds
        let result=TP518VisionBudgetGate.enrich(wire:wire,png:png,
                           battleID:battleID,epoch:epoch,frameID:frameID)
        let end=DispatchTime.now().uptimeNanoseconds
        let elapsed=end>=start ? Int(min((end-start)/1_000_000,120_000)) : 120_000
        record(added:result.added,reason:result.reason,elapsedMs:elapsed)
        return result
    }
}
#endif

#if canImport(SwiftUI) && canImport(UIKit)
struct TP519VisionEvidencePanel: View {
    var body: some View {
        TimelineView(.periodic(from:.now,by:1)) { _ in
            let current=TP519VisionEvidenceMetrics.snapshot()
            VStack(alignment:.leading,spacing:4) {
                Text("R27.519｜追加Visionの実測・研究用")
                    .font(.caption).foregroundColor(.orange)
                Text(current.summary).font(.caption2)
                    .textSelection(.enabled)
                Text("ROIの自他帰属・HP/PP・メガ等は未認証")
                    .font(.caption2).foregroundColor(.secondary)
                Button("Vision実測JSONをコピー") {
                    UIPasteboard.general.string=current.redactedJSON
                }.font(.caption2)
            }
        }
    }
}
#endif
