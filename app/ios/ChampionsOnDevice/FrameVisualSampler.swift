import CoreGraphics
import Foundation
import UIKit

// R27.412: downsample only in process memory; expose 24x12 RGB values to the
// pure-Fountain negative-screening gate. Never write image-derived bytes to JSON.
@available(iOS 27.0, *)
enum FrameVisualSampler {
    static func inspect(_ png: Data) -> FrameVisualGate.Verdict {
        guard let image = UIImage(data: png)?.cgImage else { return .invalidSample }
        let w = FrameVisualGate.columns, h = FrameVisualGate.rows
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                            CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return .invalidSample }
        var rgb = [UInt8](); rgb.reserveCapacity(w * h * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgb.append(rgba[i]); rgb.append(rgba[i+1]); rgb.append(rgba[i+2])
        }
        return FrameVisualGate.inspect(rgb: rgb)
    }
}
