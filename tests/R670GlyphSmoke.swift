import Foundation
@main struct R670GlyphSmoke {
 static func main(){
  let w=960,h=480,sha=String(repeating:"a",count:64)
  var a=[UInt8](repeating:45,count:w*h*4)
  for i in 0..<(w*h){a[i*4+3]=255}
  func box(_ x:Int,_ y:Int,_ dx:Int,_ dy:Int,_ r:UInt8,_ g:UInt8,_ b:UInt8){
   for j in y..<(y+dy){for i in x..<(x+dx){
    let n=(j*w+i)*4;a[n]=r;a[n+1]=g;a[n+2]=b
   }}
  }
  func scan(_ px:[UInt8],_ hash:String=sha)->[String:Any]{
   R670HUDPixelGlyphs.inspect(pixels:px,width:w,height:h,
    rowBytes:w*4,epoch:2,frame:33,ms:450,sha256:hash)
  }
  let none=scan(a)
  precondition(none["candidate_count"] as? Int==0)
  box(260,420,19,14,245,234,18)
  box(760,70,18,16,130,40,223)
  let out=scan(a)
  let rows=out["candidates"] as? [[String:Any]] ?? []
  precondition(rows.contains{$0["color_family_unclassified"] as? String=="YELLOW"})
  precondition(rows.contains{$0["color_family_unclassified"] as? String=="VIOLET"})
  precondition(rows.allSatisfy{$0["is_status_icon"] as? Bool==false})
  precondition(out["owner_certified"] as? Bool==false)
  precondition(out["current_state_eligible"] as? Bool==false)
  precondition((scan([],sha)["status"] as? String)?.hasPrefix("HOLD_")==true)
  precondition((scan(a,"bad")["status"] as? String)?.hasPrefix("HOLD_")==true)
  print("R670_RGBA_PIXEL_GLYPH_SMOKE_PASS 8")
 }
}
