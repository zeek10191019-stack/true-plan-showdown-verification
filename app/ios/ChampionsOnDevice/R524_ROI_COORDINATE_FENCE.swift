import Foundation

/// Geometry-only correction for the 1290x2796 raw capture observed in R521.
/// This type NEVER creates certified observations or enables battle advice.
public enum R524GeometryError: Error, Equatable {
    case invalidDimensions, invalidRect, orientationNotVerified
    case epochMismatch, staleFrame, historicalFrame
}

public struct R524Size: Equatable {
    public let width: Int
    public let height: Int
    public init(_ width: Int, _ height: Int) { self.width=width; self.height=height }
}
public struct R524Rect: Equatable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double,y: Double,width: Double,height: Double) {
        self.x=x;self.y=y;self.width=width;self.height=height
    }
}
public enum R524Rotation: String, Codable {
    case up, left90, right90, down180
}
public struct R524CapturedFrame {
    public let epoch: Int
    public let id: Int
    public let raw: R524Size
    public let rotation: R524Rotation
    public let orientationVerified: Bool
    public let historicalSelection: Bool
    public let monotonicAgeMilliseconds: Int?
    public init(epoch:Int,id:Int,raw:R524Size,rotation:R524Rotation,
                orientationVerified:Bool,historicalSelection:Bool,
                monotonicAgeMilliseconds:Int?) {
        self.epoch=epoch;self.id=id;self.raw=raw;self.rotation=rotation
        self.orientationVerified=orientationVerified
        self.historicalSelection=historicalSelection
        self.monotonicAgeMilliseconds=monotonicAgeMilliseconds
    }
    public var oriented: R524Size {
        switch rotation {
        case .left90,.right90: return R524Size(raw.height, raw.width)
        case .up,.down180: return raw
        }
    }
    /// normalized UI-preview rect -> raw pixel rect for Vision/OCR.
    /// Coordinates are image-local, top-left origin. No screen points or safe-area offsets.
    public func rawPixelRect(fromNormalizedPreview r:R524Rect) throws -> R524Rect {
        guard raw.width>0,raw.height>0 else { throw R524GeometryError.invalidDimensions }
        guard orientationVerified else { throw R524GeometryError.orientationNotVerified }
        let nums=[r.x,r.y,r.width,r.height]
        guard nums.allSatisfy({$0.isFinite}),r.x>=0,r.y>=0,
              r.width>0,r.height>0,r.x+r.width<=1.00000001,r.y+r.height<=1.00000001
        else {throw R524GeometryError.invalidRect}
        let w=Double(raw.width),h=Double(raw.height)
        let x=r.x*Double(oriented.width),y=r.y*Double(oriented.height)
        let rw=r.width*Double(oriented.width),rh=r.height*Double(oriented.height)
        switch rotation {
        case .up: return R524Rect(x:x,y:y,width:rw,height:rh)
        case .left90: return R524Rect(x:w-(y+rh),y:x,width:rh,height:rw)
        case .right90: return R524Rect(x:y,y:h-(x+rw),width:rh,height:rw)
        case .down180: return R524Rect(x:w-(x+rw),y:h-(y+rh),width:rw,height:rh)
        }
    }
    public func researchROIs(_ rects:[R524Rect],requestEpoch:Int,requestFrame:Int,
                             liveOnly:Bool=true,maxAgeMs:Int=1500) throws -> [R524Rect] {
        guard requestEpoch==epoch else {throw R524GeometryError.epochMismatch}
        guard requestFrame==id else {throw R524GeometryError.staleFrame}
        if liveOnly {
            guard !historicalSelection else {throw R524GeometryError.historicalFrame}
            guard let age=monotonicAgeMilliseconds,age>=0,age<=maxAgeMs
            else {throw R524GeometryError.staleFrame}
        }
        return try rects.map{try rawPixelRect(fromNormalizedPreview:$0)}
    }
}

/// Initial visual measurements from the user's R521 preview, NOT certified ROIs.
/// Four boxes approximate the move NAME line only. They exclude the right PP numbers
/// and status icons. Must be user/calibration verified on the same layout before use.
public enum R524RoiSeed {
    public static let moveNames: [R524Rect] = [
        R524Rect(x:0.719,y:0.426,width:0.167,height:0.072),
        R524Rect(x:0.719,y:0.548,width:0.167,height:0.072),
        R524Rect(x:0.719,y:0.668,width:0.167,height:0.072),
        R524Rect(x:0.719,y:0.789,width:0.167,height:0.072)
    ]
}
