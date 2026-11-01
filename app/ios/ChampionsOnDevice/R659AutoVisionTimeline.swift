import Foundation
import CoreGraphics
import Vision

/// One-button historical Vision measurement from *actual retained* frames.
/// No human BEFORE/AFTER labels are fabricated, and no Mega event is inferred.
@available(iOS 27.0, *)
enum R659AutoVisionTimeline {
    static let schema = "trueplan.r659.historical-vision-timeline.v1"
    struct Frame {
        let epoch: Int64
        let frameID: Int64
        let observedMs: Int64
        let image: CGImage
        let sha256: String
    }
    private static let regions: [(String,Double,Double,Double,Double)] = [
        ("LEFT_ACTOR_HYPOTHESIS",0.06,0.30,0.60,0.80),
        ("RIGHT_ACTOR_HYPOTHESIS",0.60,0.35,0.78,0.82),
        ("BACKGROUND_CONTROL",0.40,0.05,0.60,0.20)
    ]
    private static func hold(_ reason: String,
                             frames: Int) -> [String:Any] {
        ["schema":schema,"status":reason,"retained_frame_count":frames,
         "owner_certified":false,"species_certified":false,
         "mega_event_certified":false,"mega_form_certified":false,
         "current_state_eligible":false,"battle_advice_authorized":false,
         "original_images_exported":false,
         "held_out_accuracy":"NOT_MEASURED"]
    }
    private static func crop(_ image: CGImage,
                             _ r: (String,Double,Double,Double,Double))
        throws -> CGImage {
        let w = image.width, h = image.height
        let x = Int(Double(w)*r.1)
        let y = Int(Double(h)*r.2)
        let width = Int(Double(w)*(r.3-r.1))
        let height = Int(Double(h)*(r.4-r.2))
        guard width >= 16, height >= 16,
              let piece = image.cropping(to:
                CGRect(x:x,y:y,width:width,height:height)) else {
            throw NSError(domain:"R659_CROP_FAILURE",code:1)
        }
        return piece
    }
    private static func imprint(_ image: CGImage) throws
        -> VNFeaturePrintObservation {
        let req = VNGenerateImageFeaturePrintRequest()
        req.revision = VNGenerateImageFeaturePrintRequestRevision1
        req.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([req])
        guard let row = req.results?.first,
              row.elementCount > 0, !row.data.isEmpty else {
            throw NSError(domain:"R659_NO_FEATURE_PRINT",code:2)
        }
        return row
    }
    static func audit(frames: [Frame],budgetMs: Int = 1600)
        -> [String:Any] {
        let stamps = frames.map {
            R659TemporalInputGate.Stamp(epoch:$0.epoch,
                frameID:$0.frameID,observedMs:$0.observedMs,
                sha256:$0.sha256,width:$0.image.width,
                height:$0.image.height)
        }
        let status = R659TemporalInputGate.validate(stamps)
        guard status == "FRAME_PROVENANCE_VALID_VISUAL_IDENTITY_UNKNOWN" else {
            return hold(status,frames:frames.count)
        }
        guard (200...30000).contains(budgetMs) else {
            return hold("HOLD_INVALID_BUDGET",frames:frames.count)
        }
        let start = ProcessInfo.processInfo.systemUptime
        var measurements = [[String:Any]]()
        do {
            for area in regions {
                var prints = [VNFeaturePrintObservation]()
                for frame in frames {
                    guard (ProcessInfo.processInfo.systemUptime-start)*1000
                          < Double(budgetMs) else {
                        return hold("HOLD_VISION_TIME_BUDGET",frames:4)
                    }
                    prints.append(try imprint(crop(frame.image,area)))
                }
                for i in 1..<4 {
                    let previous=prints[i-1],next=prints[i]
                    guard previous.elementCount == next.elementCount,
                          previous.elementType == next.elementType,
                          previous.requestRevision == next.requestRevision else {
                        return hold("HOLD_FEATURE_PRINT_REVISION",frames:4)
                    }
                    var distance:Float=0
                    try previous.computeDistance(&distance,to:next)
                    guard distance.isFinite,distance>=0 else {
                        return hold("HOLD_INVALID_FEATURE_DISTANCE",frames:4)
                    }
                    measurements.append([
                        "region":area.0,"from_frame_id":frames[i-1].frameID,
                        "to_frame_id":frames[i].frameID,
                        "from_sha256":frames[i-1].sha256,
                        "to_sha256":frames[i].sha256,
                        "from_observed_ms":frames[i-1].observedMs,
                        "to_observed_ms":frames[i].observedMs,
                        "feature_distance_unscaled":Double(distance),
                        "vision_revision":previous.requestRevision,
                        "region_calibrated":false,"owner":"UNKNOWN",
                        "mega_event_confirmed":false])
                }
            }
        } catch {
            return hold("HOLD_VISION_PROCESSING_FAILURE",frames:4)
        }
        guard measurements.count == 9 else {
            return hold("HOLD_INCOMPLETE_MEASUREMENTS",frames:4)
        }
        return ["schema":schema,
          "status":"HISTORICAL_UNLABELED_VISUAL_MOTION_ONLY",
          "source_kind":"RETAINED_CAPTURE_ONE_TAP_HISTORY",
          "retained_frame_count":4,
          "frame_ids":frames.map{$0.frameID},
          "epochs":frames.map{$0.epoch},
          "image_sha256":frames.map{$0.sha256},
          "observed_ms_monotonic":frames.map{$0.observedMs},
          "regions":measurements,
          "region_calibrated":false,"owner_certified":false,
          "species_certified":false,"mega_event_certified":false,
          "mega_form_certified":false,"current_state_eligible":false,
          "battle_advice_authorized":false,
          "original_images_exported":false,
          "held_out_accuracy":"NOT_MEASURED",
          "limitations":"Four most recent retained frames only; no before/after " +
            "labels, no actor ownership, no form classification, " +
            "no calibrated game-view ROIs. Motion and camera can dominate."]
    }
}
