import Foundation

/// Contract for a bounded sequence of independently retained game frames.
/// This validates provenance only; it never assigns team side or Mega state.
enum R659TemporalInputGate {
    static let schema = "trueplan.r659.auto-vision-input.v1"
    struct Stamp {
        let epoch: Int64
        let frameID: Int64
        let observedMs: Int64
        let sha256: String
        let width: Int
        let height: Int
    }
    private static func shaValid(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    static func validate(_ input: [Stamp]) -> String {
        guard input.count == 4 else { return "HOLD_NEED_FOUR_RETAINED_FRAMES" }
        let first = input[0]
        guard first.epoch > 0, first.frameID > 0, first.observedMs > 0,
              (256...4096).contains(first.width),
              (192...4096).contains(first.height) else {
            return "HOLD_INVALID_INITIAL_FRAME"
        }
        var hashes = Set<String>()
        var prior = first
        for (index, row) in input.enumerated() {
            guard row.epoch == first.epoch,
                  row.width == first.width, row.height == first.height,
                  shaValid(row.sha256), hashes.insert(row.sha256).inserted else {
                return "HOLD_MIXED_SOURCE_OR_DUPLICATE"
            }
            if index > 0 {
                guard row.frameID > prior.frameID,
                      row.observedMs > prior.observedMs else {
                    return "HOLD_NONMONOTONIC_FRAME_PROVENANCE"
                }
                guard row.observedMs - prior.observedMs <= 10000 else {
                    return "HOLD_SPARSE_OR_INTERRUPTED_TIMELINE"
                }
            }
            prior = row
        }
        return "FRAME_PROVENANCE_VALID_VISUAL_IDENTITY_UNKNOWN"
    }
}
