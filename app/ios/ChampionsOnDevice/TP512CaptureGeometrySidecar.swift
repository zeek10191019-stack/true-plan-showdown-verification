import Foundation
import CoreFoundation

/// R27.512 — source-labelled PNG size sidecar for legacy BattleWire.
/// The original OCR evidence is left unchanged. PNG dimensions are measurements,
/// NOT independent corroboration of an OCR-provided size or of ROI ownership.
enum TP512CaptureGeometrySidecar {
    enum Verdict: String {
        case measuredFromCapturePNG = "PNG_SIZE_CAPTURE_MEASURED_WIRE_ABSENT"
        case preservedOriginalWireSize = "WIRE_SIZE_PRESENT_AND_MATCHED"
        case digestUnverified = "PNG_DIGEST_NOT_VERIFIED"
        case captureDimensionsUnavailable = "PNG_DIMENSIONS_NOT_VERIFIED"
        case malformedWire = "WIRE_INVALID"
        case contextMismatch = "WIRE_FRAME_CONTEXT_MISMATCH"
        case malformedDimensions = "WIRE_DIMENSIONS_PARTIAL_OR_INVALID"
        case conflictingDimensions = "WIRE_DIMENSIONS_CONFLICT"
        case spoofedAnnotation = "WIRE_ANNOTATION_ALREADY_PRESENT"
    }
    struct Result {
        let verdict: Verdict
        let wireForGeometry: String?
        /// Original wire supplied all four dimensions and they matched the PNG.
        /// This is NOT proof of an independent dimension measurement.
        let originalWireSizePresent: Bool
        var concise: String {
            return "PNG寸法由来:" + verdict.rawValue + (originalWireSizePresent ? "／原Wire寸法有" : "／原Wire寸法無")
        }
    }
    private static let keys = ["frame_width", "frame_height", "image_pixel_width", "image_pixel_height"]
    private static func uint(_ any: Any?) -> Int? {
        guard let n=any as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i=Int(n.stringValue), i >= 0 else { return nil }
        return i
    }
    static func prepare(_ wire: String?, actual: TP510PNGGeometryProof.Dimensions?,
                        battleID: String, epoch: Int, frameID: Int64,
                        pngDigestVerified: Bool) -> Result {
        func reject(_ verdict:Verdict)->Result { Result(verdict:verdict,wireForGeometry:nil,originalWireSizePresent:false) }
        guard pngDigestVerified else { return reject(.digestUnverified) }
        guard let actual, actual.width > 0, actual.height > 0 else { return reject(.captureDimensionsUnavailable) }
        guard let wire, wire.utf8.count <= 1_000_000,
              let bytes=wire.data(using:.utf8),
              var outer=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
        else { return reject(.malformedWire) }
        let wrapped = outer.keys.contains("payload_json")
        var content=outer
        if wrapped {
            guard let text=outer["payload_json"] as? String,
                  text.utf8.count <= 1_000_000, let innerData=text.data(using:.utf8),
                  let inner=(try? JSONSerialization.jsonObject(with:innerData)) as? [String:Any]
            else { return reject(.malformedWire) }
            content=inner
        }
        guard let b=content["battle_id"] as? String, !b.isEmpty,
              let e=uint(content["epoch"]),let f=uint(content["frame_id"]),
              content["image_sha256"] is String,
              content["readings"] is [Any]
        else {return reject(.malformedWire)}
        guard epoch>=0, frameID>0, b==battleID, e==epoch, Int64(f)==frameID
        else {return reject(.contextMismatch)}
        guard content["capture_geometry_source"] == nil,
              content["capture_geometry_original_missing"] == nil
        else {return reject(.spoofedAnnotation)}
        let present=keys.filter { content.keys.contains($0) }
        let values=[actual.width,actual.height,actual.width,actual.height]
        if !present.isEmpty {
            guard present.count == 4 else {return reject(.malformedDimensions)}
            for (key, expected) in zip(keys,values) {
                guard let val=uint(content[key]) else {return reject(.malformedDimensions)}
                guard val == expected else {return reject(.conflictingDimensions)}
            }
            // Do not synthesize or relabel independently supplied size fields.
            return Result(verdict:.preservedOriginalWireSize,wireForGeometry:wire,originalWireSizePresent:true)
        }
        for (key,value) in zip(keys,values) {content[key]=value}
        content["capture_geometry_source"]="actual_capture_png_ihdr_imageio"
        content["capture_geometry_original_missing"]=true
        guard let data=try? JSONSerialization.data(withJSONObject:content,options:[.sortedKeys]),
              let normalized=String(data:data,encoding:.utf8) else {return reject(.malformedWire)}
        if wrapped {outer["payload_json"]=normalized} else {outer=content}
        guard let final=try? JSONSerialization.data(withJSONObject:outer,options:[.sortedKeys]),
              let text=String(data:final,encoding:.utf8), text.utf8.count <= 1_100_000 else {
            return reject(.malformedWire)
        }
        return Result(verdict:.measuredFromCapturePNG,wireForGeometry:text,originalWireSizePresent:false)
    }
}
