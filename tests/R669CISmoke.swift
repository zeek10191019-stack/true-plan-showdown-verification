import Foundation
@main struct R669CISmoke {
 static func main() {
  typealias T=R668PlainHUDReader.Token
  func t(_ id:String,_ raw:String,_ x:Double,_ y:Double)->T {
   T(ref:id,text:raw,x:x,y:y,w:0.04,h:0.026)
  }
  let xs=[t("h","148/197",0.17,0.92),
          t("p","81%",0.85,0.11),
          t("n","ガブリアス♂",0.12,0.83),
          t("s","まひ",0.23,0.86),
          t("q","やけど",0.83,0.17),
          t("b","こうげき+1",0.20,0.78),
          t("v","こんらん",0.78,0.24)]
  let hud=R668PlainHUDReader.scan(xs,width:1920,height:1080)
  precondition(hud["status"] as? String=="HUD_PLAIN_OCR_HYPOTHESES_ONLY")
  let names=hud["matches"] as! [[String:Any]]
  precondition(names.contains{$0["field"] as? String=="own.active_species"})
  let z=R669HUDAdjacentText.scan(tokens:xs,hud:hud,width:1920,height:1080)
  precondition(z["status"] as? String=="HUD_ADJACENT_TEXT_CANDIDATES_ONLY")
  let a=z["records"] as! [[String:Any]]
  precondition(a.count==4)
  precondition(a.contains{$0["field"] as? String=="own.major_status"})
  precondition(a.contains{$0["field"] as? String=="opponent.major_status"})
  precondition(a.contains{$0["field"] as? String=="own.boost_seven"})
  precondition(a.contains{$0["field"] as? String=="opponent.volatile_status"})
  precondition(z["game_fields_certified"] as? Int==0)
  let rot=xs.map{T(ref:$0.ref,text:$0.text,
      x:1-$0.y,y:$0.x,w:$0.w,h:$0.h)}
  let h2=R668PlainHUDReader.scan(rot,width:1080,height:1920)
  precondition((R669HUDAdjacentText.scan(tokens:rot,hud:h2,
      width:1080,height:1920)["records"] as? [[String:Any]])?.count==4)
  let conflict=xs+[t("d","どく",0.21,0.85)]
  precondition(R669HUDAdjacentText.scan(tokens:conflict,hud:hud,
      width:1920,height:1080)["status"] as? String ==
      "HOLD_CONFLICTING_SIDE_STATUS_TEXT")
  precondition(R669HUDAdjacentText.audit([:],
      sourceKind:"LIVE_RETAINED_FRAME")["status"] as? String ==
      "HOLD_SOURCE_HUD_MISMATCH")
  print("R669_ADJACENT_SWIFT_SMOKE_PASS 12")
 }
}
