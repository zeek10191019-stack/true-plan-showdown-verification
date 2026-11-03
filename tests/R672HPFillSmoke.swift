import Foundation
@main struct R672HPFillSmoke {
  static func main() {
    let W=640,H=300,sha=String(repeating:"a",count:64)
    func image()->[UInt8] {Array(repeating:0,count:W*H*4)}
    func bar(_ p:inout [UInt8],x:Int,y:Int,filled:Int,total:Int,
             shade:(UInt8,UInt8,UInt8)=(29,188,64)) {
      for j in y..<(y+5) {for i in x..<(x+total) {
        let k=(j*W+i)*4
        let c:(UInt8,UInt8,UInt8)=i<x+filled ? shade:(77,76,75)
        p[k]=c.0;p[k+1]=c.1;p[k+2]=c.2;p[k+3]=255
      }}
    }
    func run(_ p:[UInt8],w:Int=W,h:Int=H)->[String:Any] {
      R672PixelHPFillReader.inspect(pixels:p,width:w,height:h,rowBytes:w*4,
         epoch:2,frame:42,ms:100,sha256:sha)
    }
    var p=image()
    bar(&p,x:90,y:252,filled:60,total:100)
    bar(&p,x:502,y:30,filled:25,total:100,shade:(219,39,32))
    let a=run(p)
    let t=a["tracks"] as? [[String:Any]] ?? []
    precondition(t.contains(where: {abs(($0["fill_percentage_candidate_not_hp"] as? Double ?? -1)-60)<1}))
    precondition(t.contains(where: {abs(($0["fill_percentage_candidate_not_hp"] as? Double ?? -1)-25)<1}))
    precondition(a["hp_percent_certified"] as? Bool==false)
    precondition(a["owner_certified"] as? Bool==false)
    var noise=image()
    for x in 90..<170 {let k=(250*W+x)*4;noise[k]=20;noise[k+1]=200;noise[k+2]=30;noise[k+3]=255}
    precondition((run(noise)["track_count"] as? Int)==0)
    precondition((run(image())["track_count"] as? Int)==0)
    precondition((R672PixelHPFillReader.inspect(pixels:p,width:640,height:300,rowBytes:2559,
           epoch:2,frame:42,ms:100,sha256:sha)["status"] as? String)=="HOLD_INVALID_RGBA_SOURCE")
    precondition((R672PixelHPFillReader.inspect(pixels:p,width:640,height:300,rowBytes:2560,
           epoch:2,frame:42,ms:100,sha256:"wrong")["status"] as? String)=="HOLD_INVALID_RGBA_SOURCE")
    // Same bar evidence survives a quarter-turn of the raw buffer.
    var rotated=[UInt8](repeating:0,count:p.count)
    for yy in 0..<H {for xx in 0..<W {
      let source=(yy*W+xx)*4
      let dest=((W-1-xx)*H+yy)*4
      rotated[dest]=p[source]
      rotated[dest+1]=p[source+1]
      rotated[dest+2]=p[source+2]
      rotated[dest+3]=p[source+3]
    }}
    let turn=run(rotated,w:H,h:W)
    precondition((turn["tracks"] as? [[String:Any]] ?? []).contains(where:{
      abs(($0["fill_percentage_candidate_not_hp"] as? Double ?? -1)-60)<1
    }))
    let invalid=R672PixelHPFillReader.unavailable(epoch:2,frame:42,ms:100,sha256:sha)
    precondition(invalid["status"] as? String=="HOLD_RGBA_RENDER_UNAVAILABLE")
    let one=Array(repeating:UInt8(80),count:W*H*4)
    precondition((run(one)["track_count"] as? Int)==0)
    // Full bar alone does not prove full HP.
    var full=image();bar(&full,x:90,y:252,filled:100,total:100)
    precondition((run(full)["track_count"] as? Int)==0)
    // Wrong location is ignored.
    var elsewhere=image();bar(&elsewhere,x:280,y:140,filled:60,total:100)
    precondition((run(elsewhere)["track_count"] as? Int)==0)
    print("R672_RGBA_HP_FILL_SMOKE_PASS 12")
  }
}
