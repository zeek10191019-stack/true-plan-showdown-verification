import Foundation
@main struct R659InputGateHarness {
    static func main() {
        let s = "a"+String(repeating:"0",count:63)
        let t = "b"+String(repeating:"0",count:63)
        let u = "c"+String(repeating:"0",count:63)
        let v = "d"+String(repeating:"0",count:63)
        func row(_ id:Int64,_ time:Int64,_ hash:String,
                 _ epoch:Int64=1,_ w:Int=512,_ h:Int=256)
            -> R659TemporalInputGate.Stamp {
            .init(epoch:epoch,frameID:id,observedMs:time,
                  sha256:hash,width:w,height:h)
        }
        let base=[row(1,100,s),row(2,200,t),row(3,300,u),row(4,400,v)]
        var count=0
        func check(_ input:[R659TemporalInputGate.Stamp],_ expect:String) {
            let result=R659TemporalInputGate.validate(input)
            guard result==expect else {fatalError("R659_\(result)_NOT_\(expect)")}
            count += 1
        }
        let pass="FRAME_PROVENANCE_VALID_VISUAL_IDENTITY_UNKNOWN"
        let wrong="HOLD_MIXED_SOURCE_OR_DUPLICATE"
        let order="HOLD_NONMONOTONIC_FRAME_PROVENANCE"
        check(base,pass)
        check([],"HOLD_NEED_FOUR_RETAINED_FRAMES")
        check(Array(base.prefix(3)),"HOLD_NEED_FOUR_RETAINED_FRAMES")
        check(base+[base[0]],"HOLD_NEED_FOUR_RETAINED_FRAMES")
        check([row(0,100,s),base[1],base[2],base[3]],"HOLD_INVALID_INITIAL_FRAME")
        check([row(1,0,s),base[1],base[2],base[3]],"HOLD_INVALID_INITIAL_FRAME")
        check([row(1,100,s,0),base[1],base[2],base[3]],"HOLD_INVALID_INITIAL_FRAME")
        check([row(1,100,s,1,20),base[1],base[2],base[3]],"HOLD_INVALID_INITIAL_FRAME")
        check([row(1,100,s,1,512,20),base[1],base[2],base[3]],"HOLD_INVALID_INITIAL_FRAME")
        check([base[0],row(2,200,t,2),base[2],base[3]],wrong)
        check([base[0],row(2,200,t,1,640),base[2],base[3]],wrong)
        check([base[0],row(2,200,t,1,512,512),base[2],base[3]],wrong)
        check([base[0],row(2,200,s),base[2],base[3]],wrong)
        check([base[0],row(2,200,"z"+String(repeating:"0",count:63)),base[2],base[3]],wrong)
        check([base[0],row(2,200,"G"+String(repeating:"0",count:63)),base[2],base[3]],wrong)
        check([base[0],row(2,200,"a"),base[2],base[3]],wrong)
        check([base[0],row(1,200,t),base[2],base[3]],order)
        check([base[0],row(2,100,t),base[2],base[3]],order)
        check([base[0],row(2,10101,t),row(3,10201,u),row(4,10301,v)],"HOLD_SPARSE_OR_INTERRUPTED_TIMELINE")
        check([base[0],row(20,10100,t),row(30,10200,u),row(40,10300,v)],pass)
        check([base[0],row(3,200,t),row(2,300,u),base[3]],order)
        check([base[0],base[1],row(3,300,u),row(4,300,v)],order)
        print("R659_FRAME_PROVENANCE_PASS",count)
    }
}
