import Foundation
#if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
import Vision
import ImageIO
import CoreGraphics
#endif

// R609 experimental evidence, NEVER a battle-state certification.
// OCR and pixel evidence are tied to exactly the same archived original PNG
// and original epoch/frame ID; coordinate systems remain hypotheses.
enum R609VisionTextSpatialEvidence {
    static let memberName = "r609_vision_text_spatial_evidence.json"
    static let maxFrames = 3
    static let maxOCR = 32
    static let maxAssociations = 32
    static let maxBytes = 8_000_000 // avoid unbounded OCR input/memory on one-button export
    private static let maxReportBytes = 160_000

    private static func validName(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 160 && !s.hasPrefix("/") &&
        !s.contains("..") && !s.contains("\\") && !s.contains("//") &&
        s.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
    }
    private static func finiteUnit(_ x: Double) -> Bool { x.isFinite && x >= 0 && x <= 1 }
    private static func validRect(_ box: [String:Any]) -> (Double,Double,Double,Double)? {
        guard let x=box["x"] as? Double, let y=box["y"] as? Double,
              let w=box["width"] as? Double, let h=box["height"] as? Double,
              finiteUnit(x),finiteUnit(y),finiteUnit(w),finiteUnit(h),
              w>0,h>0,x+w<=1.000001,y+h<=1.000001 else {return nil}
        return (x,y,w,h)
    }
    static func spatialHypotheses(
        text: [String:Any], rawColor: [String:Any]) -> [[String:Any]] {
        guard let t=validRect(text),
              let x=rawColor["x_norm"] as? Double,
              let y=rawColor["y_norm"] as? Double,
              let w=rawColor["width_norm"] as? Double,
              let h=rawColor["height_norm"] as? Double,
              finiteUnit(x),finiteUnit(y),finiteUnit(w),finiteUnit(h),
              w>0,h>0,x+w<=1.000001,y+h<=1.000001 else {return []}
        let overlap=max(0,min(t.0+t.2,x+w)-max(t.0,x))
        let horizontal=overlap/min(t.2,w)
        if horizontal < 0.15 {return []}
        let cy=t.1+t.3/2
        // Vision's coordinate origin is bottom-left. R608's bitmap-row
        // orientation is not calibrated. Neither mapping can be certified.
        let models:[(String,Double)] = [
            ("RAW_ROW_EQUALS_VISION_BOTTOM",y+h/2),
            ("RAW_ROW_FLIPPED_VERTICALLY",1-y-h/2)
        ]
        return models.compactMap { model, colorCY -> [String:Any]? in
            let distance=abs(cy-colorCY)
            guard distance<=0.12 else{return nil}
            return ["coordinate_hypothesis":model,
                    "horizontal_overlap_fraction":horizontal,
                    "vertical_center_delta_normalized":distance,
                    "spatial_relation":"UNVERIFIED_PROXIMITY_NOT_HUD_BINDING"]
        }
    }
    private static func readOCR(_ data: Data) -> ([String:Any],[[String:Any]]) {
        #if canImport(Vision) && canImport(ImageIO) && canImport(CoreGraphics)
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["ja-JP","en-US"]
        // .up is an explicit REPLAY HYPOTHESIS, not measured screen orientation.
        do {
            let handler=VNImageRequestHandler(data:data,orientation:.up,options:[:])
            try handler.perform([request])
            let results = Array((request.results ?? []).prefix(maxOCR))
            var ocr=[[String:Any]]()
            for result in results {
                guard let best=result.topCandidates(1).first else {continue}
                let rect=result.boundingBox
                let x=Double(rect.origin.x), y=Double(rect.origin.y)
                let w=Double(rect.width), h=Double(rect.height)
                let box:[String:Any] = ["x":x,"y":y,"width":w,"height":h]
                guard validRect(box) != nil else {continue}
                let txt=String(best.string.prefix(96))
                guard !txt.isEmpty, best.confidence.isFinite else {continue}
                ocr.append(["text":txt,"confidence":Double(best.confidence),
                    "rect_norm_bottom_left":box,
                    "label":"VISION_OCR_UNVERIFIED_TEXT_REGION"])
            }
            return (["status":ocr.isEmpty ? "HOLD_OCR_NO_TEXT" : "HOLD_OCR_REGIONS_UNCALIBRATED",
                     "ocr_request_orientation_assumption":"UP_NOT_SCREEN_VERIFIED",
                     "ocr_coordinate_origin":"BOTTOM_LEFT_NORMALIZED",
                     "ocr_observations_truncated":(request.results?.count ?? 0)>maxOCR],ocr)
        } catch {
            return (["status":"HOLD_VISION_OCR_UNAVAILABLE_OR_FAILED",
                     "ocr_request_orientation_assumption":"UP_NOT_SCREEN_VERIFIED",
                     "ocr_error_domain":"VISION_REQUEST_FAILED_OR_LANGUAGE_UNSUPPORTED"],[])
        }
        #else
        return (["status":"HOLD_VISION_FRAMEWORK_UNAVAILABLE",
                 "ocr_request_orientation_assumption":"NOT_EXECUTED"],[])
        #endif
    }
    static func beforeZip(_ entries:[R548ResearchArchive.Entry]) -> [R548ResearchArchive.Entry] {
        let names=entries.map(\.name)
        guard entries.count < R548ResearchArchive.maximumMembers,
              names.count == Set(names).count,
              names.allSatisfy({validName($0)}),
              !names.contains(memberName) else {return entries}
        var overall="HOLD_R608_PIXEL_EVIDENCE_MISSING_OR_INVALID"
        var rows=[[String:Any]]()
        var framesTruncated=false
        if let evidence=entries.first(where:{$0.name=="r608_original_pixel_evidence.json"}),
           evidence.bytes.count<=maxReportBytes,
           let doc=(try? JSONSerialization.jsonObject(with:evidence.bytes)) as? [String:Any],
           doc["schema"] as? String == "trueplan.r608.raw_png_visual_evidence.v1",
           doc["certified_for_battle"] as? Bool == false,
           doc["owner_verified"] as? Bool == false,
           doc["roi_verified"] as? Bool == false,
           doc["mega_verified"] as? Bool == false,
           doc["frame_identity_verified"] as? Bool == false,
           doc["display_orientation_verified"] as? Bool == false,
           doc["status"] as? String == "HOLD_VISUAL_OWNER_ROI_AND_ORIENTATION_UNCERTIFIED",
           let bindings=doc["bindings"] as? [[String:Any]],
           bindings.count<=8 {
            overall="HOLD_OCR_AND_SPATIAL_RELATIONS_NOT_CALIBRATED"
            framesTruncated=bindings.count>maxFrames
            var seen=Set<String>()
            var seenImages=Set<String>()
            for original in bindings.prefix(maxFrames) {
                guard let epoch=original["epoch"] as? Int64,epoch>0,
                      let frame=original["frame_id"] as? Int64,frame>0,
                      let hash=original["original_png_sha256"] as? String,
                      hash.count==64,hash.utf8.allSatisfy({($0>=48 && $0<=57) || ($0>=97 && $0<=102)}) else {
                    overall="HOLD_R608_FRAME_BINDING_INVALID";rows=[];break
                }
                guard seen.insert("\(epoch):\(frame)").inserted else {
                    overall="HOLD_DUPLICATE_FRAME_ID";rows=[];break
                }
                var row:[String:Any] = ["epoch":epoch,"frame_id":frame,
                    "original_png_sha256":hash,"certified_for_battle":false,
                    "owner_verified":false,"roi_verified":false,
                    "display_orientation_verified":false,"mega_verified":false,
                    "text_color_associations":[[String:Any]](),
                    "ocr_observations":[[String:Any]]()]
                guard let png=original["archive_png"] as? String,validName(png),
                      png.hasSuffix(".png"),
                      original["png_ihdr_crc_verified"] as? Bool == true,
                      original["decoded_pixels_verified"] as? Bool == true,
                      original["owner_verified"] as? Bool == false,
                      original["roi_verified"] as? Bool == false,
                      original["mega_verified"] as? Bool == false,
                      original["frame_identity_verified"] as? Bool == false,
                      original["display_orientation_verified"] as? Bool == false,
                      let image=entries.first(where:{$0.name==png}),
                      image.bytes.count<=maxBytes,
                      R598OneButtonFormAttachment.testDigest(image.bytes)==hash,
                      let color=original["unverified_region_candidates"] as? [[String:Any]],
                      color.count<=12 else {
                    row["status"]="HOLD_ORIGINAL_PNG_OR_R608_BINDING_NOT_VERIFIED"
                    rows.append(row);continue
                }
                guard seenImages.insert(png).inserted else {
                    overall="HOLD_REUSED_ARCHIVE_PNG";rows=[];break
                }
                let (result,observations)=readOCR(image.bytes)
                for (k,v) in result {row[k]=v}
                row["archive_png"]=png
                row["ocr_observations"]=observations
                var relations=[[String:Any]]()
                for (oi,obs) in observations.enumerated() {
                    guard let box=obs["rect_norm_bottom_left"] as? [String:Any] else {continue}
                    for (bi,bar) in color.enumerated() {
                        for var relation in spatialHypotheses(text:box,rawColor:bar) {
                            relation["ocr_index"]=oi
                            relation["color_candidate_index"]=bi
                            relations.append(relation)
                            if relations.count>=maxAssociations {break}
                        }
                        if relations.count>=maxAssociations {break}
                    }
                    if relations.count>=maxAssociations {break}
                }
                row["text_color_associations"]=relations
                row["association_count_truncated"]=relations.count>=maxAssociations
                rows.append(row)
            }
        }
        let report:[String:Any] = [
            "schema":"trueplan.r609.vision_text_spatial_evidence.v1",
            "status":overall,"certified_for_battle":false,"owner_verified":false,
            "roi_verified":false,"display_orientation_verified":false,
            "mega_verified":false,"orientation_verified":false,
            "bindings":rows,"max_ocr_frames":maxFrames,
            "frames_truncated":framesTruncated,
            "limitations":"OCR and color proximity may be false; Vision origin is bottom-left, PNG row origin uncalibrated. No actor, HP, HUD ROI, orientation or Mega assertion."
        ]
        guard let json=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),
              json.count<=maxReportBytes else{return entries}
        return entries+[.init(name:memberName,bytes:json)]
    }
}
