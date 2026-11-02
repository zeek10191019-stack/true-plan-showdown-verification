import Foundation
import CoreGraphics
import ImageIO
import Vision

/// VNTrackObjectRequest applied to unverified screen regions.
/// This is a sequence tracker, NOT object discovery or Mega identification.
@available(iOS 27.0, *)
enum R662VisionRegionTracking {
    static let schema = "trueplan.r662.historical-region-tracking.v1"
    typealias Frame = R659AutoVisionTimeline.Frame
    private static func hold(_ reason: String) -> [String:Any] {
        return ["schema":schema,"status":reason,
            "owner_certified":false,"species_certified":false,
            "mega_event_certified":false,"mega_form_certified":false,
            "region_calibrated":false,"battle_advice_authorized":false,
            "current_state_eligible":false,
            "held_out_accuracy":"NOT_MEASURED"]
    }
    static func audit(frames: [Frame],
                      evidence: [String:Any],
                      budgetMs: Int = 1600) -> [String:Any] {
        let stamps=frames.map {
            R659TemporalInputGate.Stamp(epoch:$0.epoch,
                frameID:$0.frameID, observedMs:$0.observedMs,
                sha256:$0.sha256,width:$0.image.width,
                height:$0.image.height)
        }
        let input=R659TemporalInputGate.validate(stamps)
        guard input == "FRAME_PROVENANCE_VALID_VISUAL_IDENTITY_UNKNOWN"
        else { return hold(input) }
        let source=R662TrackingEvidenceGate.provenance(
            frameIDs:frames.map{$0.frameID},
            times:frames.map{$0.observedMs},
            hashes:frames.map{$0.sha256},evidence:evidence)
        guard source == "TRACK_SOURCE_BOUND_RESEARCH_ONLY"
        else { return hold(source) }
        let regions=R662TrackingEvidenceGate.seeds
        let regionGate=R662TrackingEvidenceGate.geometry(regions)
        guard regionGate == "REGION_GEOMETRY_HYPOTHESIS_ONLY"
        else { return hold(regionGate) }
        guard (200...10000).contains(budgetMs) else {
            return hold("HOLD_TRACK_TIME_BUDGET_INVALID")
        }
        let start=ProcessInfo.processInfo.systemUptime
        let handler=VNSequenceRequestHandler()
        // R659 retains CGImages, but no independently calibrated game
        // orientation. `.up` is an explicit research assumption.
        let requests: [VNTrackObjectRequest] = regions.map { region in
            let normalized=CGRect(x:region.x,
                y:1.0-region.y-region.height,
                width:region.width,height:region.height)
            let seed=VNDetectedObjectObservation(boundingBox:normalized)
            let req=VNTrackObjectRequest(detectedObjectObservation:seed)
            req.trackingLevel = .accurate
            return req
        }
        var samples=[[String:Any]]()
        do {
            for idx in 1..<4 {
                guard (ProcessInfo.processInfo.systemUptime-start)*1000
                      < Double(budgetMs) else {
                    return hold("HOLD_TRACK_TIME_BUDGET_EXCEEDED")
                }
                try handler.perform(requests,on:frames[idx].image,
                                    orientation:.up)
                for j in 0..<requests.count {
                    guard let result=requests[j].results?.first
                          as? VNDetectedObjectObservation,
                          result.confidence.isFinite,
                          (0...1).contains(result.confidence) else {
                        return hold("HOLD_TRACK_NO_VALID_OBSERVATION")
                    }
                    let r=result.boundingBox
                    let values=[Double(r.minX),Double(r.minY),
                                Double(r.width),Double(r.height)]
                    guard R662TrackingEvidenceGate.box(values) ==
                           "NORMALIZED_BOX_DIAGNOSTIC_ONLY" else {
                        return hold("HOLD_TRACK_INVALID_BOX")
                    }
                    samples.append([
                        "region":regions[j].name,
                        "from_frame_id":frames[idx-1].frameID,
                        "to_frame_id":frames[idx].frameID,
                        "from_sha256":frames[idx-1].sha256,
                        "to_sha256":frames[idx].sha256,
                        "from_observed_ms":frames[idx-1].observedMs,
                        "to_observed_ms":frames[idx].observedMs,
                        "box_x_lower_left":values[0],
                        "box_y_lower_left":values[1],
                        "box_width":values[2],"box_height":values[3],
                        "tracker_confidence_unvalidated":Double(result.confidence),
                        "source_is_pokemon":false,
                        "owner_verified":false,
                        "camera_vs_actor_distinguished":false,
                        "mega_form_identified":false])
                    // Must continue each tracker from its OWN observation.
                    requests[j].inputObservation=result
                }
            }
        } catch {
            return hold("HOLD_VISION_TRACK_REQUEST_FAILED")
        }
        guard samples.count == 6 else {
            return hold("HOLD_TRACK_INCOMPLETE_HISTORY")
        }
        guard (ProcessInfo.processInfo.systemUptime-start)*1000
              <= Double(budgetMs) else {
            return hold("HOLD_TRACK_TIME_BUDGET_EXCEEDED")
        }
        return ["schema":schema,
                "status":"HISTORICAL_UNLABELED_REGION_TRACKS_ONLY",
                "source_kind":"RETAINED_CAPTURE_ONE_TAP_HISTORY",
                "frame_count":4,"samples":samples,
                "seed_coordinates":"TOP_LEFT_FRACTIONS",
                "vision_boxes":"BOTTOM_LEFT_FRACTIONS",
                "assumed_image_orientation":"UP_UNVERIFIED",
                "region_calibrated":false,"owner_certified":false,
                "species_certified":false,"mega_event_certified":false,
                "mega_form_certified":false,
                "battle_advice_authorized":false,
                "current_state_eligible":false,
                "held_out_accuracy":"NOT_MEASURED",
                "limitations":"Tracking guesses not object detection. " +
                  "No calibrated actor regions or orientation, " +
                  "no camera/actor separation and no Mega classifier."]
    }
}
