import Foundation
import CoreFoundation

/// Research-only frame-pixel ROI diagnostics. Spatial bounds != OCR accuracy or side ownership.
/// This component never overrides the R509/R510 fail-closed admission decisions.
enum TP511ROIFrameEvidence {
    enum FrameVerdict: String {
        case pixelProvenanceMissing = "PNG_HASH_NOT_VERIFIED"
        case noDimensions = "CAPTURE_SIZE_MISSING"
        case malformed = "WIRE_MALFORMED"
        case mismatched = "FRAME_CONTEXT_MISMATCH"
        case analyzed = "ROI_PIXEL_BOUNDS_CHECKED"
    }
    struct Report {
        let verdict: FrameVerdict
        let checked: Int
        let missing: Int
        let invalid: Int
        let outside: Int
        let sourceMismatch: Int
        let ownershipUnverified: Int
        let wireSizesMissing: Bool
        var concise: String {
            guard verdict == .analyzed else { return "ROI:" + verdict.rawValue }
            return "ROI:内\(checked) 欠\(missing) 壊\(invalid) 外\(outside) 出典\(sourceMismatch) 帰属未認証\(ownershipUnverified) 寸法欄\(wireSizesMissing ? "欠" : "有")"
        }
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let v = value as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(),
              let n = Int(v.stringValue), n >= 0 else { return nil }
        return n
    }
    private static func unpack(_ wire: String?) -> [String:Any]? {
        guard let wire, wire.utf8.count <= 1_000_000,
              let d=wire.data(using:.utf8),
              let outer=(try? JSONSerialization.jsonObject(with:d)) as? [String:Any]
        else {return nil}
        guard let payload=outer["payload_json"] else {return outer}
        guard let json=payload as? String, json.utf8.count <= 1_000_000,
              let data=json.data(using:.utf8),
              let inner=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        else {return nil}
        return inner
    }
    static func inspect(_ wire: String?, actual: TP510PNGGeometryProof.Dimensions?,
                        battleID: String, epoch: Int, frameID: Int64,
                        pngDigestVerified: Bool) -> Report {
        func invalid(_ result: FrameVerdict) -> Report {
            Report(verdict:result,checked:0,missing:0,invalid:0,outside:0,
                   sourceMismatch:0,ownershipUnverified:0,wireSizesMissing:true)
        }
        guard pngDigestVerified else {return invalid(.pixelProvenanceMissing)}
        guard let actual, actual.width > 0, actual.height > 0 else {return invalid(.noDimensions)}
        guard let root=unpack(wire), let id=root["battle_id"] as? String,
              let e=integer(root["epoch"]), let f=integer(root["frame_id"]),
              let readings=root["readings"] as? [Any]
        else {return invalid(.malformed)}
        guard epoch>=0, frameID > 0, id==battleID, e==epoch, Int64(f)==frameID
        else {return invalid(.mismatched)}
        let sizes=["frame_width","frame_height","image_pixel_width","image_pixel_height"]
        let sizesMissing = sizes.contains { root[$0] == nil || root[$0] is NSNull }
        var checked=0,missing=0,invalidRects=0,outside=0,mismatch=0
        var ownerUnknown=0
        for item in readings.prefix(256) {
            guard let r=item as? [String:Any] else {invalidRects+=1;continue}
            // Per-reading source metadata must never silently override frame metadata.
            if let sourceE=r["source_epoch"], integer(sourceE) != epoch {mismatch+=1;continue}
            if let sourceF=r["source_frame_id"], integer(sourceF).map(Int64.init) != frameID {mismatch+=1;continue}
            if let sourceHash=r["source_image_sha256"] {
                guard let sourceHash=sourceHash as? String,
                      let rootHash=root["image_sha256"] as? String,
                      sourceHash==rootHash else {mismatch+=1;continue}
            }
            guard let rectRaw=r["roi_rect"], !(rectRaw is NSNull) else {missing+=1;continue}
            guard let rect=rectRaw as? [String:Any],
                  let x=integer(rect["x"]), let y=integer(rect["y"]),
                  let width=integer(rect["width"]), let height=integer(rect["height"]),
                  width>0,height>0 else {invalidRects+=1;continue}
            // Subtraction bounds avoids integer overflow on untrusted x+width.
            guard x < actual.width, y < actual.height,
                  width <= actual.width-x, height <= actual.height-y else {outside+=1;continue}
            checked+=1
            // Even a geometrically valid rectangle is not ground truth for side ownership.
            ownerUnknown+=1
        }
        return Report(verdict:.analyzed,checked:checked,missing:missing,
                      invalid:invalidRects,outside:outside,sourceMismatch:mismatch,
                      ownershipUnverified:ownerUnknown,wireSizesMissing:sizesMissing)
    }
}
