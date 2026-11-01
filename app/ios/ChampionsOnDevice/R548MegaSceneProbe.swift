import Foundation
import Vision
import ImageIO
import CryptoKit

/// Retained-frame OCR evidence. Neither a name hit nor an orientation score proves Mega.
enum R548MegaSceneProbe {
    static func inspect(_ png: Data, budgetMs: Int = 1800,
                        work: R551EvidenceWork? = nil) -> [String: Any] {
        let start = ProcessInfo.processInfo.systemUptime
        let budget = min(6000, max(0, budgetMs))
        let deadline = start + Double(budget) / 1000
        let rotations: [(CGImagePropertyOrientation, Int)] =
            [(.up, 0), (.right, 90), (.down, 180), (.left, 270)]
        var allTexts = [String]()
        var completed = [Int](), failed = [Int](), skipped = [Int]()
        var evidence = [[String: Any]]()
        var scores = [(degrees: Int, score: Double)]()
        var examined = 0
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        guard !png.isEmpty, png.count <= FrameEvidenceExportGate.maximumPNGBytes else {
            return ["state": "INVALID_IMAGE_SIZE", "image_sha256": digest,
                    "own_opponent": "UNKNOWN", "mega_certified": false,
                    "rotations_completed": [], "rotations_failed": [],
                    "rotations_skipped": [0,90,180,270], "orientation_evidence": []]
        }
        for (orientation, degrees) in rotations {
            guard work?.isCancelled != true, ProcessInfo.processInfo.systemUptime < deadline else {
                skipped.append(degrees); continue
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let languages = (try? request.supportedRecognitionLanguages()) ?? []
            guard languages.contains("ja-JP") else {
                failed.append(degrees)
                evidence.append(["orientation_degrees": degrees,
                                 "status": "JAPANESE_OCR_UNAVAILABLE", "observations": []])
                continue
            }
            request.recognitionLanguages = languages.contains("en-US") ? ["ja-JP", "en-US"] : ["ja-JP"]
            let remaining = max(1, Int((deadline - ProcessInfo.processInfo.systemUptime) * 1000))
            let requestBudget = min(900, remaining)
            let cancelRequest = DispatchWorkItem { request.cancel() }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + .milliseconds(requestBudget), execute: cancelRequest)
            defer { cancelRequest.cancel() }
            let requestStart = ProcessInfo.processInfo.systemUptime
            do {
                try VNImageRequestHandler(data: png, orientation: orientation, options: [:]).perform([request])
                cancelRequest.cancel()
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - requestStart) * 1000)
                var rows = [[String: Any]]()
                var score = 0.0
                for observation in (request.results ?? []).prefix(250) {
                    let candidates = observation.topCandidates(3).filter {
                        $0.confidence.isFinite && (0...1).contains($0.confidence)
                    }.map { candidate -> [String: Any] in
                        ["text": String(candidate.string.prefix(256)), "confidence": Double(candidate.confidence)]
                    }
                    guard !candidates.isEmpty else { continue }
                    let rect = observation.boundingBox
                    guard [rect.minX,rect.minY,rect.width,rect.height].allSatisfy({ $0.isFinite }),
                          rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1.000001,
                          rect.maxY <= 1.000001, rect.width > 0, rect.height > 0 else { continue }
                    rows.append(["candidates": candidates,
                                 "roi": ["x": Double(rect.minX), "y": Double(rect.minY),
                                         "width": Double(rect.width), "height": Double(rect.height)]])
                    if let text = candidates[0]["text"] as? String,
                       let confidence = candidates[0]["confidence"] as? Double {
                        allTexts.append(text)
                        score += confidence * Double(min(text.count, 24))
                    }
                }
                examined += rows.count
                // Late results stay raw evidence; their orientation is not selected.
                let timely = elapsed <= requestBudget && work?.isCancelled != true
                if timely { completed.append(degrees); scores.append((degrees, score)) }
                else { failed.append(degrees) }
                evidence.append(["orientation_degrees": degrees,
                    "status": timely ? "OCR_CANDIDATES_ONLY" : "LATE_OR_CANCELLED_RAW_EVIDENCE",
                    "elapsed_ms": elapsed, "score": score, "observations": rows,
                    "roi_coordinate_space": "VISION_ORIENTED_NORMALIZED_BOTTOM_LEFT"])
            } catch {
                cancelRequest.cancel()
                failed.append(degrees)
                evidence.append(["orientation_degrees": degrees,
                                 "status": "OCR_FAILED_OR_TIMED_OUT", "observations": []])
            }
        }
        let ranked = scores.sorted { $0.score > $1.score }
        let preferred: Int? = {
            guard let best = ranked.first, best.score > 0 else { return nil }
            guard ranked.count == 1 || best.score - ranked[1].score >= 1 else { return nil }
            return best.degrees
        }()
        let complete = completed.count == rotations.count
        let hits = R548MegaTextRules.hints(allTexts)
        return ["schema": "trueplan.r551.rotation-ocr-evidence.v1",
                "state": work?.isCancelled == true ? "CANCELLED" :
                    (complete ? (hits.isEmpty ? "NO_MEGA_TEXT_HINT" : "TEXT_HINTS_ONLY") : "PARTIAL_OCR_EVIDENCE"),
                "image_sha256": digest, "text_hints": hits,
                "own_opponent": "UNKNOWN", "mega_certified": false,
                "megascene_observed": NSNull(), "mega_event_status": "UNKNOWN",
                "visual_form_certified": false, "orientation_certified": false,
                "preferred_orientation_degrees": preferred.map { $0 as Any } ?? NSNull(),
                "orientation_selection_basis": "OCR_QUALITY_CANDIDATE_ONLY",
                "rotations_completed": completed, "rotations_failed": failed,
                "rotations_skipped": skipped, "orientation_evidence": evidence,
                "analyzed_observation_count": examined, "budget_ms": budget,
                "elapsed_ms": Int((ProcessInfo.processInfo.systemUptime - start) * 1000)]
    }
}
