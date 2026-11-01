import Foundation

// R27.489 diagnostic-only verified geometry and HP/PP ROI segmentation.
// This API MUST NOT authorize live recommendations or Battle State admission.
enum ResearchSpatialROIGate {
    enum Rotation: String { case counterClockwise90, clockwise90 }
    struct Point: Equatable { let x: Double; let y: Double }
    struct Rect: Equatable {
        let x: Double; let y: Double; let width: Double; let height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
    }
    struct Stamp: Equatable {
        let session: String; let epoch: Int64; let frame: Int64
        let observedUptimeMs: Int64
    }
    struct Evidence {
        let stamp: Stamp
        let rawWidth: Int; let rawHeight: Int
        let displayWidth: Int; let displayHeight: Int
        let rotation: Rotation
    }
    enum Reject: String, Error { case invalidGeometry, provenanceMismatch, roiOutside, layoutUnverified,
        corruptLexeme, ambiguousROI, invalidNumericRange }
    struct NumericCandidate {
        let numerator: Int; let denominator: Int
        let source: Stamp
        let researchOnly = true
        let battleStateAdmitted = false
        let adviceEnabled = false
    }
    static func valid(_ v: Double) -> Bool { v.isFinite && v >= 0 }
    static func permitted(_ rect: Rect, width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && valid(rect.x) && valid(rect.y) &&
        valid(rect.width) && valid(rect.height) && rect.width > 0 && rect.height > 0 &&
        rect.maxX <= Double(width) && rect.maxY <= Double(height)
    }
    static func validFrame(_ e: Evidence) -> Bool {
        e.stamp.epoch > 0 && e.stamp.frame > 0 && e.stamp.observedUptimeMs > 0 &&
        !e.stamp.session.isEmpty && e.stamp.session.count <= 128 &&
        e.rawWidth > 0 && e.rawHeight > 0 && e.rawWidth <= 8192 && e.rawHeight <= 8192 &&
        e.displayWidth == e.rawHeight && e.displayHeight == e.rawWidth
    }
    // Half-open pixel rectangle; origin is image top left.
    // Maps RAW portrait sample coordinates to physically rotated DISPLAY pixels.
    static func toDisplay(_ raw: Rect, e: Evidence) -> Rect? {
        guard validFrame(e), permitted(raw, width:e.rawWidth,height:e.rawHeight) else {return nil}
        let transformed: Rect
        switch e.rotation {
        case .counterClockwise90:
            transformed = Rect(x:raw.y,y:Double(e.rawWidth)-raw.maxX,
                               width:raw.height,height:raw.width)
        case .clockwise90:
            transformed = Rect(x:Double(e.rawHeight)-raw.maxY,y:raw.x,
                               width:raw.height,height:raw.width)
        }
        return permitted(transformed,width:e.displayWidth,height:e.displayHeight) ? transformed : nil
    }
    static func toRaw(_ display: Rect,e: Evidence) -> Rect? {
        guard validFrame(e),permitted(display,width:e.displayWidth,height:e.displayHeight) else{return nil}
        let raw: Rect
        switch e.rotation {
        case .counterClockwise90:
            raw=Rect(x:Double(e.rawWidth)-display.maxY,y:display.x,
                     width:display.height,height:display.width)
        case .clockwise90:
            raw=Rect(x:display.y,y:Double(e.rawHeight)-display.maxX,
                     width:display.height,height:display.width)
        }
        return permitted(raw,width:e.rawWidth,height:e.rawHeight) ? raw : nil
    }
    // Caller-supplied rectangles must be independently calibrated to this
    // very frame. Passing guessed rectangles can never make Battle State valid.
    static func candidateSlot(displayROI: Rect, calibratedSlots: [Rect],
                              e: Evidence, layoutCertifiedForThisFrame: Bool) -> Int? {
        guard validFrame(e), layoutCertifiedForThisFrame,
              calibratedSlots.count == 4,
              permitted(displayROI,width:e.displayWidth,height:e.displayHeight) else{return nil}
        for s in calibratedSlots {
            guard permitted(s,width:e.displayWidth,height:e.displayHeight) else{return nil}
        }
        // Overlapping slot regions cannot uniquely identify an OCR candidate.
        for i in 0..<4 {
            for j in (i+1)..<4 {
                let a=calibratedSlots[i],b=calibratedSlots[j]
                if max(a.x,b.x)<min(a.maxX,b.maxX) && max(a.y,b.y)<min(a.maxY,b.maxY) {return nil}
            }
        }
        let containing=calibratedSlots.enumerated().filter { _,s in
            displayROI.x >= s.x && displayROI.y >= s.y &&
            displayROI.maxX <= s.maxX && displayROI.maxY <= s.maxY
        }
        return containing.count==1 ? containing[0].offset : nil
    }
    static func strictInt(_ text: String) -> Int? {
        let chars=Array(text.utf8)
        guard !chars.isEmpty && chars.count <= 4 && chars.allSatisfy({$0>=48 && $0<=57}) else{return nil}
        return Int(text)
    }
    static func strictFraction(_ text: String, maxValue: Int) -> (Int,Int)? {
        let parts=text.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count==2,let n=strictInt(String(parts[0])),let d=strictInt(String(parts[1])),
              d>0,d<=maxValue,n<=d else{return nil}
        return (n,d)
    }


    // R27.490: Strict lexical gating for the narrow PP crop, not a game-state proof.
    // Never "fix" 1577771 into 151/171 or silently infer 11/12 from 1112.
    enum PPLexicalDiagnostic {
        static func normalized(_ text: String) -> String {
            text.replacingOccurrences(of:"／",with:"/")
                .replacingOccurrences(of:"⁄",with:"/")
                .replacingOccurrences(of:" ",with:"")
                .replacingOccurrences(of:"\n",with:"")
                .replacingOccurrences(of:"\t",with:"")
        }
        static func direct(_ strings: [String]) -> (Int,Int)? {
            let pairs = strings.compactMap { strictFraction(normalized($0),maxValue:64) }
            guard let first=pairs.first,
                  pairs.allSatisfy({ $0.0 == first.0 && $0.1 == first.1 }) else {return nil}
            return first
        }
        static func stacked(upper:String, lower:String) -> (Int,Int)? {
            let a=normalized(upper),b=normalized(lower)
            // Require the denominator's visible slash. Bare 11 and 12 are ambiguous.
            guard let n=strictInt(a),b.hasPrefix("/"),let d=strictInt(String(b.dropFirst())),
                  n<=d,d>0,d<=64 else {return nil}
            return (n,d)
        }
        static func report(directStrings:[String],upper:String?,lower:String?) -> String {
            if let v=direct(directStrings) {return "PP形状候補=\(v.0)/\(v.1)（専用OCR・未認証）"}
            if let upper,let lower,let v=stacked(upper:upper,lower:lower) {
                return "PP上下配置候補=\(v.0)/\(v.1)（斜線検出・未認証）"
            }
            return "PP未確定（数字の推測結合はしない）"
        }
    }

    // The iPhone display or user-supplied screenshot is not the authoritative
    // SCStream/CMSampleBuffer image. All ROI calculations originate from a
    // SAME-FRAME capture buffer, never a screenshot or a SwiftUI view pixel.
    enum GeometrySource { case onDeviceSample, externalScreenshot }
    enum ContentMode { case aspectFit, aspectFill }
    struct Preview: Equatable {
        let width: Double; let height: Double
        let contentMode: ContentMode
    }
    static func validPreview(_ p: Preview) -> Bool {
        p.width.isFinite && p.height.isFinite &&
        p.width > 0 && p.height > 0 && p.width <= 8192 && p.height <= 8192
    }
    static func previewTransform(_ p: Preview, e: Evidence) -> (scale:Double, offsetX:Double, offsetY:Double)? {
        guard validFrame(e), validPreview(p) else { return nil }
        let sx=p.width/Double(e.displayWidth), sy=p.height/Double(e.displayHeight)
        let scale=p.contentMode == .aspectFit ? min(sx,sy) : max(sx,sy)
        guard scale.isFinite && scale>0 else { return nil }
        return (scale,(p.width-Double(e.displayWidth)*scale)/2,
                (p.height-Double(e.displayHeight)*scale)/2)
    }
    static func displayToPreview(_ r: Rect, preview p: Preview, e: Evidence,
                                 source: GeometrySource, verifiedSameFramePixelTransform: Bool) -> Rect? {
        guard source == .onDeviceSample, verifiedSameFramePixelTransform,
              permitted(r,width:e.displayWidth,height:e.displayHeight),
              let t=previewTransform(p,e:e) else {return nil}
        let v=Rect(x:r.x*t.scale+t.offsetX,y:r.y*t.scale+t.offsetY,
                   width:r.width*t.scale,height:r.height*t.scale)
        // Do not silently clip an ROI. An aspectFill crop can make ROI invisible.
        return permitted(v,width:Int(ceil(p.width)),height:Int(ceil(p.height))) ? v : nil
    }
    static func previewToDisplay(_ r: Rect, preview p: Preview, e: Evidence,
                                 source: GeometrySource, verifiedSameFramePixelTransform: Bool) -> Rect? {
        guard source == .onDeviceSample, verifiedSameFramePixelTransform,
              permitted(r,width:Int(ceil(p.width)),height:Int(ceil(p.height))),
              let t=previewTransform(p,e:e) else {return nil}
        let v=Rect(x:(r.x-t.offsetX)/t.scale,y:(r.y-t.offsetY)/t.scale,
                   width:r.width/t.scale,height:r.height/t.scale)
        return permitted(v,width:e.displayWidth,height:e.displayHeight) ? v : nil
    }
    static func diagnosticSummary(_ e: Evidence, pixelTransformVerified: Bool,
                                  preview: Preview?, source: GeometrySource) -> [String:Any] {
        var result=diagnosticSummary(e,pixelTransformVerified:pixelTransformVerified)
        let correctOrigin=source == .onDeviceSample
        let previewUsable=preview.flatMap {previewTransform($0,e:e)} != nil
        result["source_is_ondevice_capture_buffer"]=correctOrigin
        result["external_screenshot_used_for_calibration"] = !correctOrigin
        result["preview_projection_geometry_available"]=previewUsable
        result["coordinate_mapping_usable"] = validFrame(e) && pixelTransformVerified && correctOrigin
        result["layout_calibrated_for_this_frame"]=false
        result["ocr_latency_measured_for_this_frame"]=false
        result["roi_keys_promoted_to_battle_state"]=false
        return result
    }
    // Only use text fragments from the EXACT same frame/epoch and a proven
    // display-space HP fraction layout. ROI ordering is necessary, not sufficient.
    static func splitFraction(left: String,right: String,
                              leftRect: Rect,rightRect: Rect,layout: Rect,
                              leftSource: Stamp,rightSource: Stamp,e: Evidence,
                              layoutCertifiedForThisFrame: Bool,
                              maxValue: Int=9999) -> Result<NumericCandidate,Reject> {
        guard leftSource==e.stamp && rightSource==e.stamp else {return .failure(.provenanceMismatch)}
        guard validFrame(e) else{return .failure(.invalidGeometry)}
        guard layoutCertifiedForThisFrame else{return .failure(.layoutUnverified)}
        guard permitted(layout,width:e.displayWidth,height:e.displayHeight),
              permitted(leftRect,width:e.displayWidth,height:e.displayHeight),
              permitted(rightRect,width:e.displayWidth,height:e.displayHeight),
              leftRect.x >= layout.x,rightRect.maxX <= layout.maxX,
              leftRect.y >= layout.y,rightRect.y >= layout.y,
              leftRect.maxY <= layout.maxY,rightRect.maxY <= layout.maxY else{return .failure(.roiOutside)}
        guard leftRect.maxX <= rightRect.x,
              leftRect.y < rightRect.maxY && rightRect.y < leftRect.maxY else{return .failure(.ambiguousROI)}
        guard let n=strictInt(left),let d=strictInt(right) else{return .failure(.corruptLexeme)}
        guard d>0 && d<=maxValue && n<=d else{return .failure(.invalidNumericRange)}
        return .success(NumericCandidate(numerator:n,denominator:d,source:e.stamp))
    }
    // Explicit evidence of pixel-exact alignment must be supplied per-frame;
    // dimension matching alone is NOT orientation certification.
    static func diagnosticSummary(_ e: Evidence, pixelTransformVerified: Bool) -> [String:Any] {
        let possible=validFrame(e)
        return ["schema":"trueplan.r489-spatial-roi.v1",
                "geometry_compatible":possible,
                "rotation": e.rotation.rawValue,
                "coordinate_mapping_usable": possible && pixelTransformVerified,
                "pixel_transform_verified_for_same_frame":pixelTransformVerified,
                "owner_or_turn_certified":false,
                "battle_state_admission_allowed":false,
                "real_time_advice_enabled":false]
    }
}
