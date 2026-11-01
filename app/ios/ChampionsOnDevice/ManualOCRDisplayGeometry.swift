import Foundation

// R27.420. Pure, display-aligned MANUAL diagnostics geometry.
// UIImage's metadata rotation is not applied automatically to a bare CGImage
// submitted to Vision. The manual probe must crop and specify the same
// orientation used by the on-screen preview. NEVER feeds battle decisions.
struct ManualOCRDisplayGeometry {
    struct PixelCrop: Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }
    struct Plan {
        let pixelCrop: PixelCrop
        let turn: FrameOrientationGeometry.Turn
        let visionROIs: [FrameOrientationGeometry.Crop]
    }
    static func pixelCrop(width: Int, height: Int,
                          crop: FrameOrientationGeometry.Crop) -> PixelCrop? {
        guard width>=320,height>=320,width<=3072,height<=3072,
              width*height<=4_500_000, crop.valid,
              crop.x.isFinite,crop.y.isFinite,crop.width.isFinite,crop.height.isFinite
        else { return nil }
        let x=max(0, Int((crop.x*Double(width)).rounded(.down)))
        let y=max(0, Int((crop.y*Double(height)).rounded(.down)))
        let right=min(width, Int(((crop.x+crop.width)*Double(width)).rounded(.up)))
        let bottom=min(height, Int(((crop.y+crop.height)*Double(height)).rounded(.up)))
        guard right>x && bottom>y else { return nil }
        return PixelCrop(x:x,y:y,width:right-x,height:bottom-y)
    }
    static func prepare(sourceWidth: Int,sourceHeight: Int,
                        crop: FrameOrientationGeometry.Crop,
                        turn: FrameOrientationGeometry.Turn,
                        layout: MoveROICalibration.Layout) -> Plan? {
        guard let pixels=pixelCrop(width:sourceWidth,height:sourceHeight,crop:crop),
              let display=MoveROICalibration.displayed(layout),display.count==4,
              // Guard against empty/tiny image data rather than fake readings.
              pixels.width>=32 && pixels.height>=32 else { return nil }
        let rois=display.map { r in
            FrameOrientationGeometry.Crop(x:r.x,y:1-r.y-r.height,
                                           width:r.width,height:r.height)
        }
        let orientedWidth = turn == .left || turn == .right ? pixels.height : pixels.width
        let orientedHeight = turn == .left || turn == .right ? pixels.width : pixels.height
        guard rois.allSatisfy({ r in r.valid && r.x.isFinite && r.y.isFinite &&
               r.width*Double(orientedWidth)>=5 && r.height*Double(orientedHeight)>=5 })
        else { return nil }
        return Plan(pixelCrop:pixels,turn:turn,visionROIs:rois)
    }
}
