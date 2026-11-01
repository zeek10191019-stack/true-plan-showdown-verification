import Foundation
import CoreGraphics
import ImageIO
import Vision
import CryptoKit

/// Offline two-PNG feature-print measurement. The candidate identifier
/// is a manual hypothesis, not a classification or certified Mega event.
/// No network operations and no raw PNGs in the exported evidence.
@available(iOS 27.0, *)
enum R656MegaVisionPair {
    static let schema = "trueplan.r656.vision-pair-research.v1"
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ reason: String) { description = reason }
    }
    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    private static func decoded(_ data: Data) throws -> CGImage {
        guard data.count >= 45 && data.count <= 12 * 1024 * 1024,
              data.prefix(8).elementsEqual([UInt8](
                  [137,80,78,71,13,10,26,10])),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(src) == 1,
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              image.width >= 256 && image.height >= 192,
              image.width <= 4096 && image.height <= 4096 else {
            throw Failure("HOLD_INVALID_PNG")
        }
        return image
    }
    private static func printFor(_ image: CGImage) throws
        -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: image, options: [:])
            .perform([request])
        guard let observation = request.results?.first,
              observation.elementCount > 0,
              !observation.data.isEmpty else {
            throw Failure("HOLD_VISION_PRINT_UNAVAILABLE")
        }
        return observation
    }
    /// R594 regions are *unverified* game UI coordinates. The rectangle
    /// names do not say which team owns the model or whether it is a Pokémon.
    private static let regions: [(String, Double, Double, Double, Double)] = [
        ("WHOLE_FRAME", 0, 0, 1, 1),
        ("LEFT_ACTOR_HYPOTHESIS", 0.06, 0.30, 0.60, 0.80),
        ("RIGHT_ACTOR_HYPOTHESIS", 0.60, 0.35, 0.78, 0.82),
        ("BACKGROUND_CONTROL", 0.40, 0.05, 0.60, 0.20)
    ]
    private static func cut(_ image: CGImage,
                            _ r: (String, Double, Double, Double, Double))
        throws -> CGImage {
        let width = image.width, height = image.height
        let x = Int((Double(width) * r.1).rounded(.down))
        let y = Int((Double(height) * r.2).rounded(.down))
        let w = Int((Double(width) * (r.3 - r.1)).rounded(.down))
        let h = Int((Double(height) * (r.4 - r.2)).rounded(.down))
        guard w >= 16, h >= 16,
              let sub = image.cropping(to: CGRect(x:x, y:y, width:w, height:h))
        else { throw Failure("HOLD_CROP_UNAVAILABLE") }
        return sub
    }
    static func compare(before: Data, after: Data,
                        proposedMegaID: String,
                        manuallyReviewed: Bool) throws -> [String: Any] {
        guard R649MegaRegistryAudit.validCatalog(),
              R649MegaRegistryAudit.entries.contains(where: {$0.id == proposedMegaID})
        else { throw Failure("HOLD_UNKNOWN_MEGA_FORM") }
        guard before != after else { throw Failure("HOLD_IDENTICAL_IMAGE") }
        let beforeImage = try decoded(before)
        let afterImage = try decoded(after)
        guard beforeImage.width == afterImage.width &&
              beforeImage.height == afterImage.height else {
            throw Failure("HOLD_GEOMETRY_MISMATCH")
        }
        var distances = [[String: Any]]()
        for region in regions {
            let first = try printFor(cut(beforeImage, region))
            let second = try printFor(cut(afterImage, region))
            guard first.elementCount == second.elementCount,
                  first.elementType == second.elementType,
                  first.requestRevision == second.requestRevision else {
                throw Failure("HOLD_VISION_REVISION_MISMATCH")
            }
            var score: Float = 0
            try first.computeDistance(&score, to: second)
            guard score.isFinite && score >= 0 else {
                throw Failure("HOLD_INVALID_FEATURE_DISTANCE")
            }
            distances.append([
                "region": region.0,
                "feature_distance_unscaled": Double(score),
                "feature_count": first.elementCount,
                "request_revision": first.requestRevision,
                "region_calibrated": false,
                "owner": "UNKNOWN",
                "mega_event_confirmed": false
            ])
        }
        return [
            "schema": schema,
            "status": "OFFLINE_VISION_DISTANCE_ONLY",
            "source_kind": "TWO_USER_SELECTED_LOCAL_PNGS",
            "before_sha256": digest(before),
            "after_sha256": digest(after),
            "width": beforeImage.width,
            "height": beforeImage.height,
            "proposed_mega_form_id": proposedMegaID,
            "human_pair_claim_reviewed": manuallyReviewed,
            "label_independently_verified": false,
            "distances": distances,
            "region_calibrated": false,
            "owner_certified": false,
            "species_certified": false,
            "mega_event_certified": false,
            "mega_form_certified": false,
            "current_state_eligible": false,
            "battle_advice_authorized": false,
            "original_images_exported": false,
            "held_out_accuracy": "NOT_MEASURED",
            "limitations": "Vision distances uncalibrated. " +
                "R594 ROIs are unverified; motion/camera/FX may dominate."
        ]
    }
}
