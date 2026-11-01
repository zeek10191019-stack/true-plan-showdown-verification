import Foundation
@main struct R582AutoCaptureCoverageHarness {
    static func main() {
        var n=0
        func check(_ ok:Bool,_ label:String) {
            precondition(ok,"R582_FAIL_"+label);n+=1
        }
        var c=R582AutoCaptureCoverage()
        check(!c.observe(epoch:1,frame:0,observedMs:4,width:100,height:100,background:true,clockAccepted:true),"zero-frame")
        check(!c.observe(epoch:1,frame:1,observedMs:0,width:100,height:100,background:true,clockAccepted:true),"zero-clock")
        check(!c.observe(epoch:1,frame:1,observedMs:1,width:0,height:100,background:true,clockAccepted:true),"zero-width")
        check(!c.observe(epoch:1,frame:1,observedMs:1,width:16385,height:100,background:true,clockAccepted:true),"oversized")
        check(c.observe(epoch:1,frame:1,observedMs:1,width:1170,height:2532,background:true,clockAccepted:true),"accept-one")
        check(!c.observe(epoch:1,frame:1,observedMs:2,width:1170,height:2532,background:true,clockAccepted:true),"duplicate-frame")
        check(!c.observe(epoch:1,frame:2,observedMs:0,width:1170,height:2532,background:true,clockAccepted:true),"timestamp-reversal")
        check(!c.observe(epoch:0,frame:2,observedMs:2,width:1170,height:2532,background:true,clockAccepted:true),"epoch-regression")
        check(!c.markRetained(epoch:1,frame:5,pngSHA:String(repeating:"a",count:64)),"unknown-frame")
        check(!c.markRetained(epoch:1,frame:1,pngSHA:"A"+String(repeating:"a",count:63)),"uppercase-hash")
        check(!c.markRetained(epoch:1,frame:1,pngSHA:"abc"),"short-hash")
        check(c.markRetained(epoch:1,frame:1,pngSHA:String(repeating:"a",count:64)),"attach-real-digest")
        check(!c.markRetained(epoch:1,frame:1,pngSHA:String(repeating:"b",count:64)),"no-hash-overwrite")
        check(c.observe(epoch:1,frame:3,observedMs:3,width:1170,height:2532,background:false,clockAccepted:false),"gap-visible")
        let p=c.snapshot(epoch:1)
        check(p["in_memory_records_for_epoch"] as? Int == 2,"count")
        check(p["stored_png_samples_within_ring"] as? Int == 1,"samples")
        check(p["unretained_deliveries_within_ring"] as? Int == 1,"unsampled")
        check(p["every_frame_pixels_archived"] as? Bool == false,"no-full-pixel-claim")
        check(p["game_state_certified"] as? Bool == false,"no-game-claim")
        check((p["records"] as? [[String:Any]])?.count == 2,"rows")
        check((p["records"] as? [[String:Any]])?.first?["png_sha256"] as? String == String(repeating:"a",count:64),"digest")
        check(c.observe(epoch:2,frame:1,observedMs:1,width:640,height:480,background:false,clockAccepted:false),"epoch-rotate")
        check(c.snapshot(epoch:1)["in_memory_records_for_epoch"] as? Int == 2,"no-leak-epoch")
        for i in 2...1132 {check(c.observe(epoch:2,frame:Int64(i),observedMs:Int64(i),width:640,height:480,background:false,clockAccepted:true),"bounded-\(i)")}
        let last=c.snapshot(epoch:2)
        check(c.droppedRecords>0,"eviction-visible")
        check(last["exported_records_for_epoch"] as? Int == 128,"export-bound")
        check(last["full_session_history_guaranteed"] as? Bool == false,"no-continuity-claim")
        c.reset()
        check(c.totalObserved==0 && c.droppedRecords==0,"reset-counts")
        check(c.snapshot(epoch:2)["in_memory_records_for_epoch"] as? Int == 0,"reset-empty")
        print("R582_AUTOMATIC_FRAME_COVERAGE_PASS_\(n)")
    }
}
