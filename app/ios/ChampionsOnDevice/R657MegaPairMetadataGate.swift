import Foundation

/// R657 safety gate for offline PNG feature-print geometry.
/// This is a metadata gate, NOT a Pokémon or Mega classifier.
enum R657MegaPairMetadataGate {
    static let schema = "trueplan.r657.pair-metadata.v1"
    static func audit(orientation: Int?, width: Int,
                      height: Int, byteCount: Int) -> String {
        // ImageIO orientation absent -> CGImage pixel order is used as-is.
        // EXIF orientation 2...8 is not automatically applied by CGImage.
        if let orientation = orientation, orientation != 1 {
            return "HOLD_EXIF_ORIENTATION_NOT_UP"
        }
        if width < 256 || height < 192 ||
           width > 4096 || height > 4096 {
            return "HOLD_IMAGE_GEOMETRY"
        }
        if byteCount < 45 || byteCount > 12 * 1024 * 1024 {
            return "HOLD_IMAGE_BYTES"
        }
        return "PIXEL_GEOMETRY_ONLY_NOT_FORM_CERTIFICATION"
    }
}
