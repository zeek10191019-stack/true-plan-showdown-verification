import Foundation
import Vision
import UIKit

// Runs entirely on-device. No network, external Python, cloud, or ChatGPT connection.
// Inference is research-only; move-slot readings alone never authorize a battle action.
@available(iOS 27.0, *)
final class VisionLocalObserver {
    private let moveBoxes: [CGRect] = [
        CGRect(x: 0.744, y: 0.468, width: 0.145, height: 0.106),
        CGRect(x: 0.744, y: 0.350, width: 0.145, height: 0.104),
        CGRect(x: 0.744, y: 0.235, width: 0.145, height: 0.105),
        CGRect(x: 0.744, y: 0.119, width: 0.145, height: 0.109)
    ]

    // Coordinates are research calibrations on 1108 x 512 captures, not general-purpose OCR.
    // On unknown resolutions, explicit rejection prevents applying unsafe coordinates.
    func read(_ png: Data, frameID: Int64, timestampMs: Int64) -> OCRFrameObservation {
        guard let image = UIImage(data: png)?.cgImage,
              image.width == 1108, image.height == 512 else {
            return OCRFrameObservation(frameID: frameID, timestampMs: timestampMs,
                                       fourMoveCandidates: [nil,nil,nil,nil])
        }
        let names = moveBoxes.map { box in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.regionOfInterest = box
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                guard let observations = request.results,
                      observations.count == 1,
                      let first = observations[0].topCandidates(1).first,
                      first.confidence >= 0.70 else { return nil as String? }
                return OCRPairConsensus.sanitize(first.string)
            } catch {
                return nil as String?
            }
        }
        return OCRFrameObservation(frameID: frameID, timestampMs: timestampMs,
                                   fourMoveCandidates: names)
    }

    func readPair(first: Data, second: Data, firstID: Int64, secondID: Int64,
                  firstMs: Int64, secondMs: Int64) -> OCRResearchResult {
        let one = read(first, frameID: firstID, timestampMs: firstMs)
        let two = read(second, frameID: secondID, timestampMs: secondMs)
        return OCRPairConsensus.evaluate(one, two)
    }
}
