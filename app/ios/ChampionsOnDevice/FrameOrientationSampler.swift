import Foundation
import UIKit
import CoreGraphics

// Diagnostic-only. Never route a transformed preview to the production OCR
// observer or any legal-action/recommendation pipeline.
@available(iOS 27.0, *)
enum FrameOrientationSampler {
    static func inspect(_ image: UIImage) -> FrameOrientationGeometry.Proposal {
        guard let source=image.cgImage else {
            return FrameOrientationGeometry.inspect(rgb: [])
        }
        let w=FrameOrientationGeometry.columns,h=FrameOrientationGeometry.rows
        var rgba=[UInt8](repeating:0,count:w*h*4)
        let ok=rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx=CGContext(data:buf.baseAddress,width:w,height:h,
                   bitsPerComponent:8,bytesPerRow:w*4,
                   space:CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue |
                              CGBitmapInfo.byteOrder32Big.rawValue) else {return false}
            ctx.interpolationQuality = .medium
            ctx.draw(source,in:CGRect(x:0,y:0,width:w,height:h))
            return true
        }
        guard ok else {return FrameOrientationGeometry.inspect(rgb: [])}
        var rgb=[UInt8]()
        rgb.reserveCapacity(w*h*3)
        for i in stride(from:0,to:rgba.count,by:4) {
            rgb.append(rgba[i]);rgb.append(rgba[i+1]);rgb.append(rgba[i+2])
        }
        let proposal=FrameOrientationGeometry.inspect(rgb:rgb)
        // Only display/explicit manual OCR; NEVER authorizes advice.
        // ScreenCaptureKit delivered a portrait pixel frame for a sideways game.
        // If the diagnostic sampling does not find a rotated central strip,
        // provisionally render portrait captures LEFT 90 degrees.
        // User can override rotation; no automatic game-screen certificate.
        if source.height > source.width * 3 / 2 &&
 proposal.suggestedTurn == .none {
  return FrameOrientationGeometry.Proposal(
      crop:proposal.crop,suggestedTurn:.left,
      sidePillarSuspected:proposal.sidePillarSuspected,
      status:"縦フレームを診断用に左90°回転（ゲーム画面の認証ではありません）")
        }
        return proposal
    }
    static func rendered(_ image:UIImage,
                         crop:FrameOrientationGeometry.Crop,
                         turn:FrameOrientationGeometry.Turn) -> UIImage? {
        guard let source=image.cgImage,crop.valid else{return nil}
        guard let p=ManualOCRDisplayGeometry.pixelCrop(
                width:source.width,height:source.height,crop:crop),
              let cg=source.cropping(to:CGRect(x:p.x,y:p.y,width:p.width,height:p.height))
        else{return nil}
        let orientation: UIImage.Orientation
        switch turn {
        case .none: orientation = .up
        case .left: orientation = .left
        case .right: orientation = .right
        case .half: orientation = .down
        }
        return UIImage(cgImage:cg,scale:1,orientation:orientation)
    }
}
