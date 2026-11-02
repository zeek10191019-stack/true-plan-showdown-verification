import Foundation

/// Non-certifying, dimension-normalized camera-translation measurement.
/// The values cannot distinguish camera, Pokémon or UI movement on their own.
enum R660CameraMotionGate {
    static let schema = "trueplan.r660.camera-motion-gate.v1"
    struct Shift {
        let dx: Double
        let dy: Double
    }
    static func check(_ motion: [Shift], width: Int, height: Int,
                      frameCount: Int) -> String {
        guard frameCount == 4, motion.count == 3 else {
            return "HOLD_NEED_THREE_FRAME_PAIRS"
        }
        guard (256...4096).contains(width),
              (192...4096).contains(height) else {
            return "HOLD_INVALID_IMAGE_GEOMETRY"
        }
        for vector in motion {
            guard vector.dx.isFinite, vector.dy.isFinite else {
                return "HOLD_NONFINITE_REGISTRATION"
            }
            // Full-frame displacement larger than one frame is not a valid
            // small-translation alignment for this research analysis.
            guard abs(vector.dx) <= Double(width),
                  abs(vector.dy) <= Double(height) else {
                return "HOLD_UNBOUNDED_TRANSLATION"
            }
        }
        // No arbitrary pixel threshold is advertised as a learned game rule.
        return "HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY"
    }
    static func shiftSummary(_ motion: [Shift], width: Int,
                             height: Int) -> [[String: Any]] {
        guard check(motion,width:width,height:height,
                    frameCount:4) ==
            "HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY" else {
            return []
        }
        return motion.enumerated().map { index,shift in
            let x = shift.dx / Double(width)
            let y = shift.dy / Double(height)
            return ["pair_index": index,
                    "translation_x_px": shift.dx,
                    "translation_y_px": shift.dy,
                    "translation_x_fraction": x,
                    "translation_y_fraction": y,
                    "translation_magnitude_fraction": hypot(x,y),
                    "alignment_is_actor_or_mega_proof": false]
        }
    }
}
