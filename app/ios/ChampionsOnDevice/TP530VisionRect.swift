import Foundation

/// First-pass Vision bounding-box geometry only. Coordinates are based on the
/// *same physically oriented PNG* supplied to the OCR request. No owner inference.
/// Normalized Vision coordinates are bottom-left; pixel coordinates are top-left.
enum TP530VisionRect {
    static let source = "VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED"
    struct Rect: Equatable {
        let x:Int; let y:Int; let width:Int; let height:Int
        var dictionary:[String:Int] { ["x":x,"y":y,"width":width,"height":height] }
    }
    static func convert(minX:Double,minY:Double,maxX:Double,maxY:Double,
                        width:Int,height:Int)->Rect? {
        let coords=[minX,minY,maxX,maxY]
        guard (1...8192).contains(width),(1...8192).contains(height),
              coords.allSatisfy({$0.isFinite && $0>=0 && $0<=1}),
              minX<maxX,minY<maxY else {return nil}
        let x0=Int(floor(minX*Double(width)))
        let y0=Int(floor((1-maxY)*Double(height)))
        let x1=Int(ceil(maxX*Double(width)))
        let y1=Int(ceil((1-minY)*Double(height)))
        guard x0>=0,y0>=0,x1<=width,y1<=height,x1>x0,y1>y0 else{return nil}
        return Rect(x:x0,y:y0,width:x1-x0,height:y1-y0)
    }
    /// Prevent accidental approval of geometry that lies outside the decoded PNG.
    static func isBounded(_ r:Rect, width:Int,height:Int)->Bool {
        r.width>0 && r.height>0 && r.x>=0 && r.y>=0 &&
        r.x<width && r.y<height && r.width<=width-r.x && r.height<=height-r.y
    }
}
