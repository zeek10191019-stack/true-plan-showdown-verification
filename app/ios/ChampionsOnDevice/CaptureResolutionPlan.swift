import Foundation

// R27.424. Select a capture OUTPUT geometry from the sharing filter's current
// point-size and point-to-pixel scale. This is a requested resolution, NOT proof
// that the source orientation or original game pixels were preserved.
// No source, OCR text, device identifiers or screenshot data are persisted.
struct CaptureResolutionPlan: Equatable {
    let width: Int
    let height: Int
    let derivedFromFilter: Bool
    static let fallback = CaptureResolutionPlan(width:1108,height:512,derivedFromFilter:false)
    static let maximumDimension = 3072
    static let maximumPixels = 4_500_000
    static let minimumDimension = 320
    var legacyGeometry: Bool { width == 1108 && height == 512 }
    var aspect: Double { Double(width)/Double(height) }
    var numberOfPixels: Int { width*height }

    static func permitted(width:Int,height:Int)->Bool {
        width >= minimumDimension && height >= minimumDimension &&
        width <= maximumDimension && height <= maximumDimension &&
        width*height <= maximumPixels
    }
    static func resolve(pointsWidth:Double,pointsHeight:Double,pointPixelScale:Double)
        -> CaptureResolutionPlan {
        guard pointsWidth.isFinite,pointsHeight.isFinite,pointPixelScale.isFinite,
              pointsWidth>0,pointsHeight>0,pointPixelScale>0 else {return fallback}
        let rawWidth=pointsWidth*pointPixelScale
        let rawHeight=pointsHeight*pointPixelScale
        // Bound arithmetic before Double-to-Int conversion.
        guard rawWidth.isFinite,rawHeight.isFinite,
              rawWidth>=Double(minimumDimension),rawHeight>=Double(minimumDimension),
              rawWidth < 1_000_000,rawHeight < 1_000_000 else {return fallback}
        let dimFactor=min(1.0,Double(maximumDimension)/max(rawWidth,rawHeight))
        let pxFactor=min(1.0,sqrt(Double(maximumPixels)/(rawWidth*rawHeight)))
        let factor=min(dimFactor,pxFactor)
        // Even dimensions reduce encoder/IOSurface incompatibilities.
        let w=Int((rawWidth*factor).rounded(.down))/2*2
        let h=Int((rawHeight*factor).rounded(.down))/2*2
        guard permitted(width:w,height:h) else {return fallback}
        return CaptureResolutionPlan(width:w,height:h,derivedFromFilter:true)
    }
}
