import Foundation
import CoreGraphics

/// Selected-frame diagnostics only. Integral pixels, no interpolation/scaling.
enum R556PixelTransform {
    static func apply(_ source: CGImage,plan: R556AnalysisProjection.Plan,work: R551EvidenceWork?=nil) throws -> CGImage {
        try work?.check()
        guard plan.valid,source.width==plan.rawWidth,source.height==plan.rawHeight,
              source.bitsPerComponent==8,let space=source.colorSpace,space.model == .rgb,
              let crop=source.cropping(to:CGRect(x:plan.crop.x,y:plan.crop.y,width:plan.crop.width,height:plan.crop.height)),
              crop.width==plan.crop.width,crop.height==plan.crop.height else {
            throw ResearchBattleVisionGeometryError.invalidTransform
        }
        let w=plan.crop.width,h=plan.crop.height
        var input=[UInt8](repeating:0,count:w*h*4)
        let format=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let decoded=input.withUnsafeMutableBytes {bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:w,height:h,bitsPerComponent:8,
                bytesPerRow:w*4,space:space,bitmapInfo:format) else {return false}
            context.interpolationQuality = .none;context.setBlendMode(.copy)
            context.draw(crop,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard decoded else {throw ResearchBattleVisionGeometryError.invalidTransform}
        try work?.check()
        var output=Data(count:input.count)
        try output.withUnsafeMutableBytes {(bytes:UnsafeMutableRawBufferPointer) in
            let target=bytes.bindMemory(to:UInt8.self)
            for y in 0..<h {
                try work?.check()
                for x in 0..<w {
                    let dx:Int,dy:Int
                    switch plan.quarterTurnsCCW {
                    case 0:(dx,dy)=(x,y)
                    case 1:(dx,dy)=(y,w-1-x)
                    case 2:(dx,dy)=(w-1-x,h-1-y)
                    default:(dx,dy)=(h-1-y,x)
                    }
                    let from=(y*w+x)*4,to=(dy*plan.analysisWidth+dx)*4
                    for channel in 0..<4 {target[to+channel]=input[from+channel]}
                }
            }
        }
        guard let provider=CGDataProvider(data:output as CFData),let result=CGImage(width:plan.analysisWidth,
            height:plan.analysisHeight,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:plan.analysisWidth*4,
            space:space,bitmapInfo:CGBitmapInfo(rawValue:format),provider:provider,decode:nil,
            shouldInterpolate:false,intent:.defaultIntent) else {throw ResearchBattleVisionGeometryError.invalidTransform}
        try work?.check();return result
    }
    enum ResearchBattleVisionGeometryError: Error {case invalidTransform}
}
