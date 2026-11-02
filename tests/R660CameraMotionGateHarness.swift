import Foundation
@main struct R660CameraMotionGateHarness {
    static func main() {
        var n=0
        func check(_ ok:Bool,_ name:String) {
            precondition(ok,"R660_MOTION_FAIL_"+name);n+=1
        }
        let zero=R660CameraMotionGate.Shift(dx:0,dy:0)
        let small=R660CameraMotionGate.Shift(dx:4,dy:-3)
        let normal=[zero,small,zero]
        let ok="HISTORICAL_CAMERA_TRANSLATION_MEASURE_ONLY"
        check(R660CameraMotionGate.schema ==
              "trueplan.r660.camera-motion-gate.v1","schema")
        check(R660CameraMotionGate.check(normal,width:512,
                 height:256,frameCount:4)==ok,"normal")
        let rows=R660CameraMotionGate.shiftSummary(normal,
                 width:512,height:256)
        check(rows.count==3,"three_pairs")
        check(rows[1]["translation_x_px"] as? Double == 4,"x")
        check(rows[1]["translation_y_px"] as? Double == -3,"y")
        check(rows[0]["translation_magnitude_fraction"] as? Double
              == 0,"zero")
        check((rows[1]["translation_x_fraction"] as? Double ?? -1)
              == 4/512,"x_norm")
        check(rows[1]["alignment_is_actor_or_mega_proof"] as? Bool
              == false,"no_promotion")
        check(R660CameraMotionGate.check(normal,width:512,
                height:256,frameCount:3 ) ==
              "HOLD_NEED_THREE_FRAME_PAIRS","wrong_frames")
        check(R660CameraMotionGate.check([zero],width:512,
                height:256,frameCount:4 ) ==
              "HOLD_NEED_THREE_FRAME_PAIRS","short")
        check(R660CameraMotionGate.check(normal,width:255,
                height:256,frameCount:4 ) ==
              "HOLD_INVALID_IMAGE_GEOMETRY","low_width")
        check(R660CameraMotionGate.check(normal,width:512,
                height:191,frameCount:4 ) ==
              "HOLD_INVALID_IMAGE_GEOMETRY","low_height")
        check(R660CameraMotionGate.check([zero,
                .init(dx:Double.nan,dy:0),zero],width:512,
                height:256,frameCount:4 ) ==
              "HOLD_NONFINITE_REGISTRATION","nan")
        check(R660CameraMotionGate.check([zero,
                .init(dx:0,dy:Double.infinity),zero],width:512,
                height:256,frameCount:4 ) ==
              "HOLD_NONFINITE_REGISTRATION","infinite")
        check(R660CameraMotionGate.check([zero,
                .init(dx:513,dy:0),zero],width:512,
                height:256,frameCount:4 ) ==
              "HOLD_UNBOUNDED_TRANSLATION","over_range")
        check(R660CameraMotionGate.shiftSummary([zero],
               width:512,height:256).isEmpty,"empty_on_failure")
        check(R660CameraMotionGate.check(normal,width:4096,
                height:4096,frameCount:4)==ok,"upper_bounds")
        check(R660CameraMotionGate.check(normal,width:4097,
                height:256,frameCount:4 ) ==
              "HOLD_INVALID_IMAGE_GEOMETRY","oversized")
        print("R660_CAMERA_TRANSLATION_GATE_PASS",n)
    }
}
