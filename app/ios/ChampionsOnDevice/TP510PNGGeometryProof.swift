import Foundation
import CoreFoundation
#if canImport(ImageIO)
import ImageIO
#endif

/// R27.510 research-only: independently recover the actual PNG's pixel size.
/// A PNG size match does not certify a Pokémon, OCR text, ROI ownership or game state.
enum TP510PNGGeometryProof {
    struct Dimensions: Equatable { let width: Int; let height: Int }
    enum Verdict: String {
        case verifiedGeometry = "CAPTURE_PNG_GEOMETRY_MATCH"
        case actualPNGUnavailable = "ACTUAL_PNG_DIMENSIONS_UNAVAILABLE"
        case wireMalformed = "WIRE_GEOMETRY_MALFORMED"
        case wireDimensionsMissing = "WIRE_GEOMETRY_MISSING"
        case contextMismatch = "GEOMETRY_CONTEXT_MISMATCH"
        case digestUnverified = "GEOMETRY_PNG_DIGEST_UNVERIFIED"
        case sizeMismatch = "CAPTURE_PNG_GEOMETRY_MISMATCH"
    }
    private static let sig: [UInt8] = [137,80,78,71,13,10,26,10]
    private static func u32(_ b: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(b[offset]) << 24) | (UInt32(b[offset+1]) << 16) |
        (UInt32(b[offset+2]) << 8) | UInt32(b[offset+3])
    }
    private static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc:UInt32 = 0xffffffff
        for b in bytes {
            crc ^= UInt32(b)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ 0xffffffff
    }
    static func actualDimensions(_ png: Data) -> Dimensions? {
        // At least signature(8) + length(4) + IHDR(4+13) + CRC(4)
        guard png.count >= 33, png.count <= 32_000_000 else { return nil }
        let b = [UInt8](png.prefix(33))
        guard Array(b[0..<8]) == sig, u32(b,8) == 13,
              Array(b[12..<16]) == [73,72,68,82],
              crc32(b[12..<29]) == u32(b,29),
              b[26] == 0, b[27] == 0, b[28] == 0 else { return nil }
        let w = Int(u32(b,16)), h = Int(u32(b,20))
        guard (1...8192).contains(w), (1...8192).contains(h),
              [0,2,3,4,6].contains(b[25]),
              ([1,2,4,8,16].contains(b[24])) else { return nil }
        let depth=b[24], color=b[25]
        guard ((color == 0 && [1,2,4,8,16].contains(depth)) ||
               (color == 2 && [8,16].contains(depth)) ||
               (color == 3 && [1,2,4,8].contains(depth)) ||
               (color == 4 && [8,16].contains(depth)) ||
               (color == 6 && [8,16].contains(depth))) else { return nil }
        #if canImport(ImageIO)
        // iOS: require the PNG decoder independently agrees with its IHDR.
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String: Any],
              let decodedW = props[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let decodedH = props[kCGImagePropertyPixelHeight as String] as? NSNumber,
              decodedW.intValue == w, decodedH.intValue == h else { return nil }
        #endif
        return Dimensions(width:w,height:h)
    }
    private static func uint(_ v: Any?) -> UInt64? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let u = UInt64(n.stringValue) else { return nil }
        return u
    }
    static func verify(_ wire: String?, actual: Dimensions?,
                       battleID: String, epoch: Int, frameID: Int64,
                       pngDigestVerified: Bool) -> Verdict {
        guard actual != nil else { return .actualPNGUnavailable }
        guard pngDigestVerified else { return .digestUnverified }
        guard let wire, wire.utf8.count <= 1_000_000,
              let data = wire.data(using:.utf8),
              let outer = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else { return .wireMalformed }
        var body = outer
        if let wrapped = outer["payload_json"] {
            guard let json = wrapped as? String, json.utf8.count <= 1_000_000,
                  let bytes = json.data(using:.utf8),
                  let inner = (try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
            else { return .wireMalformed }
            body = inner
        }
        guard let id = body["battle_id"] as? String, !id.isEmpty,
              let e = uint(body["epoch"]), let f = uint(body["frame_id"]),
              epoch >= 0, frameID > 0 else { return .wireMalformed }
        guard id == battleID && e == UInt64(epoch) && f == UInt64(frameID)
        else { return .contextMismatch }
        guard let width=uint(body["frame_width"]), let height=uint(body["frame_height"]),
              let pixelW=uint(body["image_pixel_width"]),
              let pixelH=uint(body["image_pixel_height"]) else { return .wireDimensionsMissing }
        let a = actual!
        return width == UInt64(a.width) && height == UInt64(a.height) && pixelW == UInt64(a.width) && pixelH == UInt64(a.height)
            ? .verifiedGeometry : .sizeMismatch
    }
}
