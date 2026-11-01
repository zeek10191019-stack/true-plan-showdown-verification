import Foundation
import CoreGraphics
import CoreVideo
import CryptoKit

/// One bounded, immutable-for-the-request BGRA raster. No resize or rotation.
/// The original PNG remains the source evidence; this conversion is declared.
enum R559VisionInput {
    struct Prepared {
        let buffer: CVPixelBuffer
        let audit: ResearchOCRVisionInput
    }
    enum Failure: Error {case unsupportedColor, allocation, lock, context, unlock}
    static func prepare(_ image: CGImage,work: R551EvidenceWork?=nil) throws -> Prepared {
        try work?.check()
        guard FrameEvidenceExportGate.permitted(width:image.width,height:image.height),
              image.bitsPerComponent==8,image.colorSpace?.model == .rgb,
              let space=CGColorSpace(name:CGColorSpace.sRGB) else {throw Failure.unsupportedColor}
        let width=image.width,height=image.height
        var output: CVPixelBuffer?
        let attrs: [String:Any]=[kCVPixelBufferCGImageCompatibilityKey as String:true,
                   kCVPixelBufferCGBitmapContextCompatibilityKey as String:true,
                   kCVPixelBufferIOSurfacePropertiesKey as String:[:] as [String:Any]]
        guard CVPixelBufferCreate(kCFAllocatorDefault,width,height,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&output)==kCVReturnSuccess,
              let buffer=output else {throw Failure.allocation}
        let rowBytes=CVPixelBufferGetBytesPerRow(buffer),allocation=CVPixelBufferGetDataSize(buffer)
        guard rowBytes>=width*4,rowBytes<=16384,allocation>=rowBytes*height,allocation<=20_000_000,
              CVPixelBufferGetWidth(buffer)==width,CVPixelBufferGetHeight(buffer)==height,
              CVPixelBufferGetPixelFormatType(buffer)==kCVPixelFormatType_32BGRA else {throw Failure.allocation}
        guard CVPixelBufferLockBaseAddress(buffer,[])==kCVReturnSuccess else {throw Failure.lock}
        var locked=true
        defer {if locked {_=CVPixelBufferUnlockBaseAddress(buffer,[])}}
        guard let base=CVPixelBufferGetBaseAddress(buffer) else {throw Failure.lock}
        // Initializing padding also avoids passing allocator residue to Vision.
        memset(base,0,allocation)
        let format=CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context=CGContext(data:base,width:width,height:height,bitsPerComponent:8,
            bytesPerRow:rowBytes,space:space,bitmapInfo:format) else {throw Failure.context}
        context.interpolationQuality = .none
        context.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1))
        context.fill(CGRect(x:0,y:0,width:width,height:height))
        context.setBlendMode(.normal)
        context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        context.flush()
        var digest=SHA256()
        for y in 0..<height {
            try work?.check()
            // Hash only visible BGRA pixels, excluding platform alignment bytes.
            digest.update(data:Data(bytes:base.advanced(by:y*rowBytes),count:width*4))
        }
        let hash=digest.finalize().map {String(format:"%02x",$0)}.joined()
        guard CVPixelBufferUnlockBaseAddress(buffer,[])==kCVReturnSuccess else {throw Failure.unlock}
        locked=false
        try work?.check()
        return Prepared(buffer:buffer,audit:.init(schema:"trueplan.ocr.vision-input.v1",handler:"CVPIXELBUFFER_BGRA8_UP",
            normalization:"SRGB8_WHITE_COMPOSITE_NO_GEOMETRY_CHANGE",width:width,height:height,
            bytes_per_row:rowBytes,allocation_bytes:allocation,visible_pixel_bytes:width*height*4,
            visible_pixel_sha256:hash,source_pixel_equality_certified:false))
    }
}
