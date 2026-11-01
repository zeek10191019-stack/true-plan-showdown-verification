import Foundation
import UIKit
import Vision
import CoreImage

// R27.423: proof-carrying manual OCR. Each displayed thumbnail is precisely
// the same CGImage crop submitted to Vision (before optional enlargement).
// Never save pictures, send images online, infer battle state, or issue moves.
@available(iOS 27.0, *)
enum ManualROIOCRProbe {
    struct Result {
        let recognized: String?
        let confidence: Float?
        let processedRecognized: String?
        let processedConfidence: Float?
        let crop: UIImage
        let width: Int
        let height: Int
        let rawCurrentPP: Int?
        let rawMaximumPP: Int?
        let enhancedCurrentPP: Int?
        let enhancedMaximumPP: Int?
        let targetedCurrentPP: Int?
        let targetedMaximumPP: Int?
    }

    static func inspect(image: CGImage, plan: ManualOCRDisplayGeometry.Plan,
                        layout: MoveROICalibration.Layout) -> [Result] {
        guard ManualOCRDisplayGeometry.pixelCrop(
                    width:image.width,height:image.height,
                    crop:FrameOrientationGeometry.full) != nil,
              plan.visionROIs.count==4,
              let dimensions=ManualOCRDirectPixelGeometry.orientedDimensions(
                    crop:plan.pixelCrop,turn:plan.turn),
              let rects=ManualOCRDirectPixelGeometry.rectangles(
                    width:dimensions.width,height:dimensions.height,layout:layout)
        else {return []}
        let p=plan.pixelCrop
        guard p.x>=0,p.y>=0,p.width>0,p.height>0,
              p.x+p.width<=image.width,p.y+p.height<=image.height,
              let cut=image.cropping(to:CGRect(x:p.x,y:p.y,width:p.width,height:p.height))
        else{return []}
        let uiOrientation:UIImage.Orientation
        switch plan.turn {
        case .none:uiOrientation = .up
        case .left:uiOrientation = .left
        case .right:uiOrientation = .right
        case .half:uiOrientation = .down
        }
        // Render the SAME crop + orientation metadata used for the SwiftUI
        // preview into a physical .up CGImage. This is deliberately NOT a
        // VNImageRequestHandler with an inverse-transformed source ROI.
        let oriented=UIImage(cgImage:cut,scale:1,orientation:uiOrientation)
        let fmt=UIGraphicsImageRendererFormat()
        fmt.scale=1
        fmt.opaque=true
        let size=CGSize(width:dimensions.width,height:dimensions.height)
        let flattened=UIGraphicsImageRenderer(size:size,format:fmt).image { _ in
            oriented.draw(in:CGRect(origin:.zero,size:size))
        }
        guard let physical=flattened.cgImage,
              physical.width==dimensions.width,physical.height==dimensions.height
        else{return []}
        var results=[Result]()
        for box in rects {
            guard let patch=physical.cropping(to:CGRect(x:box.x,y:box.y,
                                      width:box.width,height:box.height)) else{return []}
            let ui=UIImage(cgImage:patch)
            // Upscaling changes sampling resolution, not information content.
            // Compare raw-vs-contrast separately; never silently choose a
            // higher-scoring result or treat it as certified accuracy.
            let upscaled=scaled(patch,multiplier:3)
            // One primary Vision request contains move name and PP.
            let raw=upscaled.flatMap(readCombined)
            // Retry the same cropped frame with preprocessing only if incomplete.
            let enhanced=raw?.isComplete == true ? nil :
                upscaled.flatMap(contrastGray).flatMap(readCombined)
            // Only if both full-row OCR passes fail PP, examine PP subregion.
            // This is an extra Vision request, not an extra source capture.
            let targetedPP=(raw?.currentPP != nil || enhanced?.currentPP != nil)
                ? nil : upscaled.flatMap(readPPOnly)
            results.append(Result(recognized:raw?.moveName,
                confidence:raw?.moveConfidence,
                processedRecognized:enhanced?.moveName,
                processedConfidence:enhanced?.moveConfidence,
                crop:ui,width:patch.width,height:patch.height,
                rawCurrentPP:raw?.currentPP,rawMaximumPP:raw?.maximumPP,
                enhancedCurrentPP:enhanced?.currentPP,
                enhancedMaximumPP:enhanced?.maximumPP,
                targetedCurrentPP:targetedPP?.0,
                targetedMaximumPP:targetedPP?.1))
        }
        return results.count==4 ? results : []
    }
    // R27.429: bounded PP-only fallback on the SAME cropped move row.
    // Requires an explicit current/max slash pattern; never extrapolates PP.
    private static func readPPOnly(_ source:CGImage)->(Int,Int)? {
        let start=Int((Double(source.width)*0.66).rounded(.down))
        guard source.width>=300,source.height>=60,
              start>=0,start<source.width-24,
              let ppImage=source.cropping(to:CGRect(x:start,y:0,
                  width:source.width-start,height:source.height)) else{return nil}
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        let handler=VNImageRequestHandler(cgImage:ppImage,orientation:.up,options:[:])
        do {
            try handler.perform([request])
            let candidates=(request.results ?? []).sorted {
                if abs($0.boundingBox.midY-$1.boundingBox.midY)>0.12 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }.compactMap { result -> MovePPPairParser.Token? in
                guard let candidate=result.topCandidates(1).first else{return nil}
                return MovePPPairParser.Token(text:candidate.string,
                   confidence:candidate.confidence)
            }
            guard let parsed=MovePPPairParser.parse(candidates),
                  let current=parsed.currentPP,
                  let maximum=parsed.maximumPP else {return nil}
            return (current,maximum)
        } catch {return nil}
    }
    private static func scaled(_ source:CGImage,multiplier:Int)->CGImage? {
        guard source.width>=8,source.height>=8,multiplier==3,
              source.width<=1024,source.height<=1024 else {return nil}
        let w=source.width*multiplier,h=source.height*multiplier
        let fmt=UIGraphicsImageRendererFormat();fmt.scale=1;fmt.opaque=true
        let sourceUI=UIImage(cgImage:source)
        let ui=UIGraphicsImageRenderer(size:CGSize(width:w,height:h),format:fmt)
            .image { ctx in
                ctx.cgContext.interpolationQuality = .high
                sourceUI.draw(in:CGRect(x:0,y:0,width:w,height:h))
            }
        return ui.cgImage
    }
    private static func contrastGray(_ source:CGImage)->CGImage? {
        let input=CIImage(cgImage:source)
        guard let filter=CIFilter(name:"CIColorControls") else{return nil}
        filter.setValue(input,forKey:kCIInputImageKey)
        filter.setValue(0,forKey:kCIInputSaturationKey)
        filter.setValue(1.45,forKey:kCIInputContrastKey)
        guard let output=filter.outputImage else{return nil}
        let context=CIContext(options:[.useSoftwareRenderer:false])
        return context.createCGImage(output,from:output.extent)
    }
    private static func readCombined(_ source:CGImage)->MovePPPairParser.Result? {
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP","en-US"]
        request.usesLanguageCorrection = false
        let handler=VNImageRequestHandler(cgImage:source,orientation:.up,options:[:])
        do {
            try handler.perform([request])
            let tokens=(request.results ?? []).sorted {
                $0.boundingBox.minX < $1.boundingBox.minX
            }.compactMap { observation -> MovePPPairParser.Token? in
                guard let candidate=observation.topCandidates(1).first else{return nil}
                return MovePPPairParser.Token(text:candidate.string,
                    confidence:candidate.confidence)
            }
            return MovePPPairParser.parse(tokens)
        } catch {return nil}
    }
}
