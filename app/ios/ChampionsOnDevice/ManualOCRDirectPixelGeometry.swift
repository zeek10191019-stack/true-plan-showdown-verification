import Foundation

// R27.423: direct top-left pixel rectangles for the ACTUAL displayed raster.
// NO inverse-mapping into the rotated source; NEVER an action-authorization input.
struct ManualOCRDirectPixelGeometry {
    struct Rect: Equatable {
        let x: Int; let y: Int; let width: Int; let height: Int
    }
    static func orientedDimensions(crop: ManualOCRDisplayGeometry.PixelCrop,
                                   turn: FrameOrientationGeometry.Turn) -> (width:Int,height:Int)? {
        guard crop.width>=32, crop.height>=32 else{return nil}
        if turn == .left || turn == .right {return(crop.height,crop.width)}
        return(crop.width,crop.height)
    }
    static func rectangles(width:Int,height:Int,
                           layout:MoveROICalibration.Layout)->[Rect]? {
        guard width>=32,height>=32,
              let rois=MoveROICalibration.displayed(layout),rois.count==4 else{return nil}
        var result=[Rect]()
        for roi in rois {
            guard roi.valid,[roi.x,roi.y,roi.width,roi.height].allSatisfy({$0.isFinite}) else{return nil}
            let x=Int((roi.x*Double(width)).rounded(.down))
            let y=Int((roi.y*Double(height)).rounded(.down))
            let right=Int(((roi.x+roi.width)*Double(width)).rounded(.up))
            let bottom=Int(((roi.y+roi.height)*Double(height)).rounded(.up))
            let w=right-x,h=bottom-y
            guard x>=0,y>=0,right<=width,bottom<=height,w>=8,h>=8 else{return nil}
            result.append(Rect(x:x,y:y,width:w,height:h))
        }
        // Reject overlapping ROIs; a slot must not silently read its neighbor.
        for i in 0..<4 { for j in i+1..<4 {
            let a=result[i],b=result[j]
            guard a.x+a.width<=b.x || b.x+b.width<=a.x ||
                  a.y+a.height<=b.y || b.y+b.height<=a.y else {return nil}
        }}
        return result
    }
}
