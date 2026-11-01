import Foundation

// R27.417: read-only calibration on UNVERIFIED raw diagnostic frames.
// No image pixels or OCR text are persisted or emitted. These rectangles must
// NEVER enter the production VisionLocalObserver or battle action authorization.
struct MoveROICalibration {
    struct Layout: Equatable {
        var x: Double = 0.73             // actual game move-name strip, avoids right-hand PP
        var top: Double = 0.51
        var width: Double = 0.15
        var height: Double = 0.075
        var gap: Double = 0.055
        static let initial = Layout()
        // R27.427: manual-only ROI measured from ONE sideways Sylveon battle frame.
        // Landscape normalized (x,y,w,h) = (.746, .435, .140, .075).
        // Four slots spaced (.075 + .046) vertically. No game-state inference.
        static let portraitLandscapeDiagnostics = Layout(
  x:0.746,top:0.435,width:0.185,height:0.075,gap:0.046)
    }
    struct Mapping: Equatable {
        let display: FrameOrientationGeometry.Crop
        let sourceTopLeft: FrameOrientationGeometry.Crop
        let visionBottomLeft: FrameOrientationGeometry.Crop
    }
    static func bounded(_ n: Double) -> Bool { n.isFinite && n >= 0 && n <= 1 }
    static func displayed(_ layout: Layout) -> [FrameOrientationGeometry.Crop]? {
        guard [layout.x,layout.top,layout.width,layout.height,layout.gap].allSatisfy(bounded),
              layout.width > 0.001, layout.height > 0.001,
              layout.x + layout.width <= 1,
              layout.top + (4 * layout.height) + (3 * layout.gap) <= 1 else {return nil}
        return (0..<4).map { i in
            FrameOrientationGeometry.Crop(x: layout.x,
                y: layout.top + Double(i) * (layout.height+layout.gap),
                width: layout.width, height: layout.height)
        }
    }
    static func map(layout: Layout,crop: FrameOrientationGeometry.Crop,
                    turn: FrameOrientationGeometry.Turn) -> [Mapping]? {
        guard crop.valid,let slots=displayed(layout) else{return nil}
        var results=[Mapping]()
        for slot in slots {
            guard let native=FrameOrientationGeometry.sourceROI(
                displayX:slot.x,displayY:slot.y,width:slot.width,height:slot.height,
                crop:crop,turn:turn), native.valid else{return nil}
            let vision=FrameOrientationGeometry.Crop(x:native.x,
                y:1-native.y-native.height,width:native.width,height:native.height)
            guard vision.valid else {return nil}
            results.append(Mapping(display:slot,sourceTopLeft:native,
                                   visionBottomLeft:vision))
        }
        return results.count==4 ? results : nil
    }
    // No slot detection, no label matching, no move identification.
    static let certification = "UNVERIFIED_MANUAL_ROI_ONLY_NO_OCR_NO_ACTION"
}
