import Foundation

@main struct R589PixelHUDProbeHarness {
 static func main() {
  var passed=0
  func check(_ condition: Bool,_ description:String) {
   guard condition else {fatalError("R589_TEST_FAILED_\(description)")}
   passed+=1
  }
  let w=480,h=240,sha=String(repeating:"a",count:64)
  func pixel(own:Bool=true,opp:Bool=true,invert:Bool=false,
             lowColor:Bool=false,alpha:UInt8=255)->[UInt8] {
   var b=[UInt8](repeating:0,count:w*h*4)
   for y in 0..<h {
    for x in 0..<w {
     let yy=invert ? h-1-y : y
     let ownArea=own && (x>=65 && x<132 && yy>=208 && yy<=212)
     let oppArea=opp && (x>=384 && x<435 && yy>=26 && yy<=29)
     if ownArea || oppArea {
      let i=(y*w+x)*4
      b[i]=lowColor ? 220 : 35
      b[i+1]=lowColor ? 60 : 205
      b[i+2]=38;b[i+3]=alpha
     } else {b[(y*w+x)*4+3]=255}
    }
   }
   return b
  }
  func report(_ bytes:[UInt8],width:Int=w,height:Int=h,stride:Int=w*4,
              epoch:Int64=1,frame:Int64=1,time:Int64=20,hash:String=sha)->[String:Any] {
   R589PixelHUDProbe.inspect(pixels:bytes,width:width,height:height,rowBytes:stride,
         epoch:epoch,frame:frame,observedMs:time,imageSHA:hash)
  }
  let both=report(pixel())
  check(both["status"] as? String == "PIXEL_LAYOUT_PAIR_HYPOTHESIS_ONLY","both")
  check(both["candidate_count"] as? Int == 2,"two-candidates")
  check((both["pair_row_order_hypotheses"] as? [String])?.count==1,"one-raster-hypothesis")
  let frames=both["green_run_candidates"] as! [[String:Any]]
  check(Set(frames.compactMap{$0["region_hypothesis"] as? String}) == Set(["LOWER_LEFT_HUD_REGION","UPPER_RIGHT_HUD_REGION"]),"regions")
  check(frames.allSatisfy{$0["owner"] as? String == "UNKNOWN"},"no-owner")
  check(frames.allSatisfy{$0["status"] as? String == "UNVERIFIED_GREEN_PIXEL_RUN_ONLY"},"no-certification")
  check(both["orientation_certified"] as? Bool == false,"no-orientation-cert")
  check(both["hp_certified"] as? Bool == false,"no-hp-cert")
  check(both["current_state_eligible"] as? Bool == false,"no-live")
  check(both["automatic_upload"] as? Bool == false,"no-upload")
  check(both["image_sha256"] as? String == sha,"sha")
  check(both["image_width"] as? Int == w,"width")
  check(both["image_height"] as? Int == h,"height")
  check(both["frame_id"] as? Int64 == 1,"frame")
  check(both["epoch"] as? Int64 == 1,"epoch")
  check(both["observed_ms_monotonic"] as? Int64 == 20,"timestamp")
  let reverse=report(pixel(invert:true))
  check(reverse["status"] as? String == "PIXEL_LAYOUT_PAIR_HYPOTHESIS_ONLY","reverse")
  check((reverse["pair_row_order_hypotheses"] as? [String])==["MEMORY_LAST_ROW_TOP_HYPOTHESIS"],"reverse-axis")
  let one=report(pixel(own:false))
  check(one["status"] as? String == "AMBIGUOUS_OR_PARTIAL_GREEN_PIXEL_CANDIDATES","one")
  check(one["candidate_count"] as? Int == 1,"one-count")
  let none=report(pixel(own:false,opp:false))
  check(none["status"] as? String == "NO_GREEN_PIXEL_HUD_ANCHORS","none")
  check(none["candidate_count"] as? Int == 0,"none-count")
  check(report(pixel(lowColor:true))["candidate_count"] as? Int == 0,"non-green-held")
  check(report(pixel(alpha:100))["candidate_count"] as? Int == 0,"transparent-held")
  for (name,bad) in [
    ("bad-sha",report(pixel(),hash:String(repeating:"A",count:64))),
    ("bad-frame",report(pixel(),frame:0)),
    ("bad-epoch",report(pixel(),epoch:0)),
    ("bad-time",report(pixel(),time:0)),
    ("bad-width",report(pixel(),width:0)),
    ("bad-height",report(pixel(),height:0)),
    ("bad-stride",report(pixel(),stride:w*4-1)),
    ("bad-memory",report(Array(pixel().dropLast()))),
    ("bad-size",report(pixel(),width:5000))
  ] {
   check(bad["status"] as? String == "HOLD_INVALID_PIXEL_INPUT",name)
   check(bad["candidate_count"] as? Int == 0,name+"-no-candidates")
  }
  print("R589_PIXEL_HUD_DIRECT_VISUAL_TESTS_PASS \(passed)/\(passed)")
 }
}
