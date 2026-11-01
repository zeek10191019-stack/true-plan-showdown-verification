import Foundation
import CoreFoundation

/// R27.506 — research-only map of a preview-point OCR rectangle onto original capture pixels.
/// The map is deliberately not a Pokémon / HP / mega ownership certification.
/// It refuses implicit crop, unknown rotation, missing metadata, stale frame origins,
/// and incompatible view/image aspect ratios (e.g. an unreported aspect-fill crop).
final class TP506PreviewGeometryFence: @unchecked Sendable {
    static let shared = TP506PreviewGeometryFence()
    enum Status: String { case withheld = "WITHHELD", malformed = "MALFORMED", research = "RESEARCH_ONLY" }
    struct Rect {
        var x: Double; var y: Double; var w: Double; var h: Double
        var right: Double { x+w }; var bottom: Double { y+h }
        func contains(_ other: Rect) -> Bool {
            let eps = 0.00001
            return other.x >= x-eps && other.y >= y-eps && other.right <= right+eps && other.bottom <= bottom+eps
        }
    }
    struct Candidate {
        let readingIndex: Int
        let sourcePixels: Rect
        let rotationCW: Int
        let mirrored: Bool
    }
    struct Report {
        let status: Status
        let totalReadings: Int
        let noGeometry: Int
        let invalidGeometry: Int
        let staleOrUnproven: Int
        let notPreviewPoints: Int
        let invalidROI: Int
        let outsideImage: Int
        let transformCandidates: [Candidate]
        var concise: String {
            guard status == .research else { return "R506:" + status.rawValue }
            return "R506補正候補\(transformCandidates.count)／幾何不足\(noGeometry)／幾何矛盾\(invalidGeometry)／出典不足\(staleOrUnproven)／非プレビュー\(notPreviewPoints)／ROI不正\(invalidROI)／画像外\(outsideImage)／要実機較正／研究のみ"
        }
    }
    private let lock = NSLock()
    private static func n(_ d:[String:Any],_ k:String)->Double? {
        guard let v=d[k] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { return nil }
        let x=v.doubleValue; return x.isFinite ? x:nil
    }
    private static func u(_ d:[String:Any],_ k:String)->UInt64? {
        guard let v=d[k] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { return nil }
        return UInt64(v.stringValue)
    }
    private static func rect(_ any:Any?) -> Rect? {
        guard let d=any as? [String:Any], let x=n(d,"x"),let y=n(d,"y"),
              let w=n(d,"width"),let h=n(d,"height"),w>0,h>0,
              abs(x)<1_000_000,abs(y)<1_000_000,w<1_000_000,h<1_000_000 else {return nil}
        return Rect(x:x,y:y,w:w,h:h)
    }
    private static func hash(_ a:Any?)->String? {
        guard let s=a as? String,s.utf8.count==64,
          s.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}) else {return nil}
        return s
    }
    private static func inverse(_ u:Double,_ v:Double,rotation:Int,mirror:Bool)->(Double,Double) {
        let x=mirror ? 1-u : u
        switch rotation {
        case 0: return (x,v)
        case 90: return (v,1-x)
        case 180: return (1-x,1-v)
        default: return (1-v,x) // 270 degrees
        }
    }
    func inspect(_ wire:String?,admitted:Bool)->Report {
        lock.lock();defer {lock.unlock()}
        func empty(_ status:Status)->Report {
            return Report(status:status,totalReadings:0,noGeometry:0,invalidGeometry:0,
                staleOrUnproven:0,notPreviewPoints:0,invalidROI:0,outsideImage:0,transformCandidates:[])
        }
        guard admitted else { return empty(.withheld) }
        guard let wire,wire.utf8.count<=1_000_000,
              let data=wire.data(using:.utf8),
              let outer=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {return empty(.malformed)}
        var root=outer
        if let wrapped=outer["payload_json"] {
            guard let v=wrapped as? String,v.utf8.count<=1_000_000,
                  let bytes=v.data(using:.utf8),
                  let d=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else {return empty(.malformed)}
            root=d
        }
        guard let battle=root["battle_id"] as? String,!battle.isEmpty,battle.utf8.count<=128,
              let frame=Self.u(root,"frame_id"),let epoch=Self.u(root,"epoch"),
              Self.u(root,"observed_at_ms") != nil,let hash=Self.hash(root["image_sha256"]),
              let rows=root["readings"] as? [Any],rows.count<=128 else {return empty(.malformed)}
        let pw=Self.u(root,"frame_width"),ph=Self.u(root,"frame_height"),
            iw=Self.u(root,"image_pixel_width"),ih=Self.u(root,"image_pixel_height")
        let pixelOK = pw != nil && ph != nil && pw!>0 && ph!>0 && pw!<=8192 && ph!<=8192 && pw==iw && ph==ih
        let view=Self.rect(root["preview_view_rect"])
        let image=Self.rect(root["preview_image_rect"])
        let rotNumber=Self.u(root,"preview_rotation_cw")
        let rot=rotNumber.flatMap { $0<=270 && $0%90==0 ? Int($0):nil }
        let mirror=root["preview_mirrored"] as? Bool
        let orientation=(root["capture_orientation"] as? String)?.uppercased()
        let orientationOK = pixelOK && ((pw!<ph! && orientation=="PORTRAIT") || (pw!>ph! && orientation=="LANDSCAPE"))
        // Zero-sized or square frames do not justify inferring an orientation.
        let geometryPresent=pw != nil && ph != nil && iw != nil && ih != nil && view != nil && image != nil && rot != nil && mirror != nil && orientation != nil
        var geometryOK=false
        if geometryPresent,orientationOK,let view,let image,let rot,let pw,let ph {
            let rw=(rot == 90 || rot == 270) ? Double(ph):Double(pw)
            let rh=(rot == 90 || rot == 270) ? Double(pw):Double(ph)
            let relativeAspect = abs((image.w/image.h)/(rw/rh)-1)
            geometryOK=view.contains(image) && relativeAspect<=0.015
        }
        var noGeometry=0,invalidGeometry=0,stale=0,notPreview=0,badROI=0,outside=0
        var candidates:[Candidate]=[]
        for (index,any) in rows.enumerated() {
            guard let row=any as? [String:Any] else {stale+=1;badROI+=1;continue}
            if !geometryPresent {noGeometry+=1;continue}
            if !geometryOK {invalidGeometry+=1;continue}
            guard Self.u(row,"source_frame_id")==frame,Self.u(row,"source_epoch")==epoch,
                  Self.hash(row["source_image_sha256"])==hash else {stale+=1;continue}
            guard row["roi_coordinate_space"] as? String == "PREVIEW_POINTS" else {notPreview+=1;continue}
            guard let roi=Self.rect(row["roi_rect"]) else {badROI+=1;continue}
            guard let image, image.contains(roi) else {outside+=1;continue}
            let corners=[(roi.x,roi.y),(roi.right,roi.y),(roi.x,roi.bottom),(roi.right,roi.bottom)]
            let uv=corners.map { Self.inverse(($0.0-image.x)/image.w,($0.1-image.y)/image.h,rotation:rot!,mirror:mirror!) }
            let xvalues=uv.map{$0.0},yvalues=uv.map{$0.1}
            let x0=max(0,xvalues.min()!*Double(pw!)),x1=min(Double(pw!),xvalues.max()!*Double(pw!))
            let y0=max(0,yvalues.min()!*Double(ph!)),y1=min(Double(ph!),yvalues.max()!*Double(ph!))
            if x1<=x0 || y1<=y0 {badROI+=1;continue}
            candidates.append(Candidate(readingIndex:index,sourcePixels:Rect(x:x0,y:y0,w:x1-x0,h:y1-y0),rotationCW:rot!,mirrored:mirror!))
        }
        return Report(status:.research,totalReadings:rows.count,noGeometry:noGeometry,invalidGeometry:invalidGeometry,
            staleOrUnproven:stale,notPreviewPoints:notPreview,invalidROI:badROI,outsideImage:outside,transformCandidates:candidates)
    }
}
