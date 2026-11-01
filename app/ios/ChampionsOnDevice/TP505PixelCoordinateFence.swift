import Foundation
import CoreFoundation

/// R27.505: research-only coordinate provenance audit. "Plausible" is never "certified".
/// A preview-point / normalized region must not be consumed as captured-image pixels.
final class TP505PixelCoordinateFence: @unchecked Sendable {
    static let shared = TP505PixelCoordinateFence()
    enum Status: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Result {
        let status: Status
        let readings: Int
        let missingPixelGeometry: Int
        let pixelGeometryMismatch: Int
        let missingOrientation: Int
        let orientationMismatch: Int
        let coordinateSpaceUnspecified: Int
        let nonPixelCoordinates: Int
        let missingROI: Int
        let invalidROI: Int
        let missingProvenance: Int
        let conflictingProvenance: Int
        let plausiblePixelCandidates: Int
        var concise: String {
            guard status == .research else { return "R505:" + status.rawValue }
            return "R505画素候補\(readings)／画像寸法欠\(missingPixelGeometry)／寸法矛盾\(pixelGeometryMismatch)／向き欠\(missingOrientation)／向き矛盾\(orientationMismatch)／座標系不明\(coordinateSpaceUnspecified)／非画素座標\(nonPixelCoordinates)／ROI欠\(missingROI)／ROI不正\(invalidROI)／出典欠\(missingProvenance)／出典矛盾\(conflictingProvenance)／要実機較正\(plausiblePixelCandidates)／研究のみ"
        }
    }
    private let lock = NSLock()
    private static func number(_ dict: [String:Any], _ key:String)->Double? {
        guard let x=dict[key] as? NSNumber,CFGetTypeID(x) != CFBooleanGetTypeID() else{return nil}
        let v=x.doubleValue
        return v.isFinite ? v : nil
    }
    private static func integer(_ dict:[String:Any], _ key:String)->UInt64? {
        guard let x=dict[key] as? NSNumber,CFGetTypeID(x) != CFBooleanGetTypeID(),
              let v=UInt64(x.stringValue) else{return nil}
        return v
    }
    private static func sha(_ value:Any?)->String? {
        guard let x=value as? String,x.utf8.count==64,
              x.utf8.allSatisfy({($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)}) else{return nil}
        return x
    }
    func inspect(_ wire:String?,admitted:Bool)->Result {
        lock.lock();defer{lock.unlock()}
        func empty(_ status:Status)->Result {
            Result(status:status,readings:0,missingPixelGeometry:0,pixelGeometryMismatch:0,
                missingOrientation:0,orientationMismatch:0,coordinateSpaceUnspecified:0,
                nonPixelCoordinates:0,missingROI:0,invalidROI:0,missingProvenance:0,
                conflictingProvenance:0,plausiblePixelCandidates:0)
        }
        guard admitted else {return empty(.withheld)}
        guard let wire, wire.utf8.count<=1_000_000,
              let bytes=wire.data(using:.utf8),
              let top=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else{return empty(.malformed)}
        var body=top
        if let wrapped=top["payload_json"] {
            guard let s=wrapped as? String,s.utf8.count<=1_000_000,
                  let data=s.data(using:.utf8),
                  let inner=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {return empty(.malformed)}
            body=inner
        }
        guard let battle=body["battle_id"] as? String,!battle.isEmpty,battle.utf8.count<=128,
              let frame=Self.integer(body,"frame_id"),
              let epoch=Self.integer(body,"epoch"),
              Self.integer(body,"observed_at_ms") != nil,
              let imageHash=Self.sha(body["image_sha256"]),
              let rows=body["readings"] as? [Any],rows.count<=128 else {return empty(.malformed)}
        let fw=Self.integer(body,"frame_width"),fh=Self.integer(body,"frame_height")
        let iw=Self.integer(body,"image_pixel_width"),ih=Self.integer(body,"image_pixel_height")
        func sane(_ w:UInt64?,_ h:UInt64?)->Bool {
            guard let w,let h else{return false}
            return w>0 && h>0 && w<=8192 && h<=8192
        }
        let frameSane=sane(fw,fh), imageSane=sane(iw,ih)
        let geometryMissing=(!frameSane || !imageSane) ? 1 : 0
        let dimensionMismatch=(frameSane && imageSane && (fw != iw || fh != ih)) ? 1 : 0
        let claimedOrientation=(body["capture_orientation"] as? String)?.uppercased()
        let orientationMissing=(claimedOrientation == nil || !["PORTRAIT","LANDSCAPE"].contains(claimedOrientation!)) ? 1 : 0
        let orientationMismatch:Int
        if frameSane, let orientation=claimedOrientation, ["PORTRAIT","LANDSCAPE"].contains(orientation) {
            orientationMismatch=((fw!>fh!) == (orientation == "PORTRAIT")) ? 1 : 0
        } else {orientationMismatch=0}
        var noSpace=0,notPixels=0,missingROI=0,invalidROI=0,noSource=0,badSource=0,plausible=0
        for row in rows {
            guard let candidate=row as? [String:Any] else {
                missingROI+=1;noSpace+=1;noSource+=1;continue
            }
            let space=candidate["roi_coordinate_space"] as? String
            if space == nil || space!.isEmpty {noSpace+=1}
            else if space != "CAPTURE_PIXELS" {notPixels+=1}
            let sourceFrame=Self.integer(candidate,"source_frame_id")
            let sourceEpoch=Self.integer(candidate,"source_epoch")
            let sourceHash=Self.sha(candidate["source_image_sha256"])
            if sourceFrame == nil || sourceEpoch == nil || sourceHash == nil {noSource+=1}
            if (candidate["source_frame_id"] != nil && sourceFrame != frame) ||
               (candidate["source_epoch"] != nil && sourceEpoch != epoch) ||
               (candidate["source_image_sha256"] != nil && sourceHash != imageHash) {badSource+=1}
            var validRect=false
            if let v=candidate["roi_rect"] {
                if let rect=v as? [String:Any],frameSane,
                   let x=Self.number(rect,"x"),let y=Self.number(rect,"y"),
                   let w=Self.number(rect,"width"),let h=Self.number(rect,"height"),
                   x>=0,y>=0,w>0,h>0,x+w<=Double(fw!),y+h<=Double(fh!) {
                    validRect=true
                } else {invalidROI+=1}
            } else {missingROI+=1}
            if geometryMissing==0 && dimensionMismatch==0 && orientationMissing==0 && orientationMismatch==0 &&
               space == "CAPTURE_PIXELS" && validRect && sourceFrame==frame && sourceEpoch==epoch && sourceHash==imageHash {
                plausible+=1 // Not certified. Owner and gameplay semantics remain unverified.
            }
        }
        return Result(status:.research,readings:rows.count,missingPixelGeometry:geometryMissing,
            pixelGeometryMismatch:dimensionMismatch,missingOrientation:orientationMissing,
            orientationMismatch:orientationMismatch,coordinateSpaceUnspecified:noSpace,
            nonPixelCoordinates:notPixels,missingROI:missingROI,invalidROI:invalidROI,
            missingProvenance:noSource,conflictingProvenance:badSource,plausiblePixelCandidates:plausible)
    }
}
