import Foundation
@main struct R576GateHarness {
 static func main() {
  func sample(_ w:Int,_ h:Int)->Data {
   var a:[UInt8]=[137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82]
   for v in [w,h] {for shift in [24,16,8,0] {a.append(UInt8((v>>shift)&255))}}
   a += [8,6,0,0,0,0,0,0,0,0,0,0,0]
   a += [0,0,0,0,73,69,78,68,174,66,96,130]
   return Data(a)
  }
  let good=sample(1108,512)
  assert(R576OfflinePNGImportGate.validate(good) == .accepted(width:1108,height:512))
  let proof=R576OfflinePNGImportGate.proof(width:1108,height:512,sha:String(repeating:"a",count:64),byteCount:good.count)
  for key in ["current_state_eligible","owner_certified","identity_certified","mega_form_visual_certified","battle_advice_authorized","game_accuracy_certified","capture_time_calibrated"] {
   assert(proof[key] as? Bool == false,"Unsafe offline certification "+key)
  }
  assert(proof["source_kind"] as? String == "OFFLINE_EXACT_PNG")
  assert(R576OfflinePNGImportGate.validate(Data()) == .rejected)
  var bad=good;bad[0]=0;assert(R576OfflinePNGImportGate.validate(bad) == .rejected)
  bad=good;bad[12]=0;assert(R576OfflinePNGImportGate.validate(bad) == .rejected)
  bad=good;bad[good.count-1]=0;assert(R576OfflinePNGImportGate.validate(bad) == .rejected)
  assert(R576OfflinePNGImportGate.validate(sample(0,512)) == .rejected)
  assert(R576OfflinePNGImportGate.validate(sample(10000,512)) == .rejected)
  assert(R576OfflinePNGImportGate.validate(sample(8192,8192)) == .rejected)
  assert(R576OfflinePNGImportGate.validate(sample(4096,4096)) == .accepted(width:4096,height:4096))
  assert(R576OfflinePNGImportGate.validate(Data(repeating:0,count:12_000_001)) == .rejected)
  assert(R576OfflinePNGImportGate.validate(Data(repeating:0,count:20)) == .rejected)
  print("PASS_R576_12_CASES_OFFLINE_PNG_IMPORT_NEVER_LIVE")
 }
}
