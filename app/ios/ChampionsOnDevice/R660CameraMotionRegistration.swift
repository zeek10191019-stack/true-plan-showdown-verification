import Foundation
import CoreGraphics
import Vision
import ImageIO

/// Observes whole-scene translation in 4 retained game frames. No owner,
/// species, switch, Mega evolution or camera source may be inferred.
@available(iOS 27.0, *)
enum R660CameraMotionRegistration {
    static let schema = "trueplan.r660.scene-registration.v1"
    typealias Frame = R659AutoVisionTimeline.Frame
    private static func hold(_ reason:String,count:Int) -> [String:Any] {
        ["schema":schema,"status":reason,"frame_count":count,
         "owner_certified":false,"mega_event_certified":false,
         "species_certified":false,"mega_form_certified":false,
         "battle_advice_authorized":false,"current_state_eligible":false,
         "image_registration_is_mega_proof":false,
         "held_out_accuracy":"NOT_MEASURED"]
    }
    static func audit(frames:[Frame], budgetMs:Int = 1200)
        -> [String:Any] {
        let stamps=frames.map {
            R659TemporalInputGate.Stamp(epoch:$0.epoch,
                frameID:$0.frameID,observedMs:$0.observedMs,
                sha256:$0.sha256,width:$0.image.width,
                height:$0.image.height)
        }
        let input=R659TemporalInputGate.validate(stamps)
        guard input == "FRAME_PROVENANCE_VALID_VISUAL_IDENTITY_UNKNOWN"
        else { return hold(input,count:frames.count) }
        guard (200...10000).contains(budgetMs) else {
            return hold("HOLD_INVALID_TIME_BUDGET",count:frames.count)
        }
        let start=ProcessInfo.processInfo.systemUptime
        var shifts=[R660CameraMotionGate.Shift]()
        var aligned=[[String:Any]]()
        do {
            for i in 1..<4 {
                guard (ProcessInfo.processInfo.systemUptime-start)*1000 <
                      Double(budgetMs) else {
                    return hold("HOLD_VISION_REGISTRATION_TIMEOUT",count:4)
                }
                // Both captures were produced from the same retained source
                // orientation. No stored PNG orientation assumptions here.
                let request=VNTranslationalImageRegistrationRequest(
                    targetedCGImage:frames[i-1].image,options:[:])
                request.revision=VNTranslationalImageRegistrationRequestRevision1
                try VNImageRequestHandler(cgImage:frames[i].image,
                                          options:[:]).perform([request])
                guard let observation=request.results?.first else {
                    return hold("HOLD_NO_ALIGNMENT",count:4)
                }
                let transform=observation.alignmentTransform
                let x=Double(transform.tx),y=Double(transform.ty)
                // A translational alignment must not imply rotation,
                // scale or shear. Stop if runtime disagrees.
                guard [Double(transform.a),Double(transform.d),
                       Double(transform.b),Double(transform.c),x,y]
                      .allSatisfy({$0.isFinite}),
                      abs(Double(transform.a)-1)<0.0001,
                      abs(Double(transform.d)-1)<0.0001,
                      abs(Double(transform.b))<0.0001,
                      abs(Double(transform.c))<0.0001 else {
                    return hold("HOLD_NONTRANSLATIONAL_TRANSFORM",count:4)
                }
                shifts.append(.init(dx:x,dy:y))
                aligned.append(["from_frame_id":frames[i-1].frameID,
                    "to_frame_id":frames[i].frameID,
                    "from_sha256":frames[i-1].sha256,
                    "to_sha256":frames[i].sha256,
                    "from_observed_ms":frames[i-1].observedMs,
                    "to_observed_ms":frames[i].observedMs])
            }
        } catch {
            return hold("HOLD_VISION_REGISTRATION_FAILURE",count:4)
        }
        guard (ProcessInfo.processInfo.systemUptime-start)*1000 <=
              Double(budgetMs) else {
            return hold("HOLD_VISION_REGISTRATION_TIMEOUT",count:4)
        }
        let gate=R660CameraMotionGate.check(shifts,
                        width:frames[0].image.width,
                        height:frames[0].image.height,frameCount:frames.count)
        guard gate == "HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY" else {
            return hold(gate,count:4)
        }
        let summary=R660CameraMotionGate.shiftSummary(shifts,
                        width:frames[0].image.width,
                        height:frames[0].image.height)
        guard summary.count == 3 else {
            return hold("HOLD_TRANSLATION_OUTPUT",count:4)
        }
        var rows=[[String:Any]]()
        for i in 0..<3 {
            rows.append(aligned[i].merging(summary[i]) { _,new in new })
        }
        return ["schema":schema,"status":gate,
                "frame_count":4,"pairs":rows,
                "source_kind":"RETAINED_CAPTURE_ONE_TAP_HISTORY",
                "scene_translation_may_include_actor_motion":true,
                "region_calibrated":false,"owner_certified":false,
                "mega_event_certified":false,"species_certified":false,
                "mega_form_certified":false,
                "battle_advice_authorized":false,
                "current_state_eligible":false,
                "image_registration_is_mega_proof":false,
                "held_out_accuracy":"NOT_MEASURED",
                "limitations":"Translation from whole frames may mix " +
                  "UI, camera, model motion and scene changes; " +
                  "no owner or Mega inference"]
    }
}
