import Foundation
@main struct TP518Tests {
 static func main() {
  var t=0
  func ok(_ p: @autoclosure ()->Bool,_ why:String){
    guard p() else { fatalError("R518 fail \(t): \(why)") };t+=1
  }
  func result(_ text:String="base", _ n:Int=1)->TP517VisionROISidecar.Result {
    .init(wire:text,added:n,reason:"RESEARCH_ROI_CANDIDATES_ONLY")
  }
  for i in 0..<1600 {
    let raw="example\(i)"
    let o=TP518VisionBudgetGate.inspect(wire:raw,budgetMs:175) {result("enriched\(i)")}
    ok(o.added==1,"accepted result \(i)")
    ok(o.wire=="enriched\(i)","wire \(i)")
    ok(!o.ownerCertified && !o.decisionEligible,"no promotion \(i)")
  }
  let before=TP518VisionBudgetGate.counters()
  ok(before.completed>=1600,"complete jobs")
  ok(!before.ownerCertified && !before.decisionEligible,"global no promotion")
  let invalid=TP518VisionBudgetGate.inspect(wire:"base",budgetMs:0){result()}
  ok(invalid.added==0 && invalid.wire=="base","invalid budget")
  let slow=TP518VisionBudgetGate.inspect(wire:"unmodified",budgetMs:5){
    Thread.sleep(forTimeInterval:0.085);return result("SHOULD_NOT_APPEAR")
  }
  ok(slow.wire=="unmodified" && slow.reason=="ROI_WORKER_LATENCY_BUDGET_EXCEEDED","bounded timeout")
  let drop=TP518VisionBudgetGate.inspect(wire:"next",budgetMs:100){result("SHOULD_NOT_RUN")}
  ok(drop.wire=="next" && drop.reason=="ROI_WORKER_BUSY_DROP","single flight")
  // R539: wait for an observed completion, not a fixed scheduling interval.
  // The original work sleeps for 85 ms, but an overloaded CI runner can delay
  // execution even after the nominal 110 ms test sleep has elapsed.
  let deadline=Date().addingTimeInterval(2.0)
  while TP518VisionBudgetGate.counters().completed < before.completed+1 && Date()<deadline {
    Thread.sleep(forTimeInterval:0.005)
  }
  guard TP518VisionBudgetGate.counters().completed >= before.completed+1 else { fatalError("R518 fail \(t): bounded worker completion") }
  let fresh=TP518VisionBudgetGate.inspect(wire:"new",budgetMs:100){result("accepted")}
  ok(fresh.wire=="accepted","recovery after completion")
  let after=TP518VisionBudgetGate.counters()
  ok(after.requested>=before.requested+2,"requested metered")
  ok(after.timeouts>=1,"timeout metered")
  ok(after.skipped>=1,"skipped metered")
  ok(after.completed>=before.completed+2,"worker completion metered")
  ok(after.failures<=after.completed,"failure counter bounded")
  print("R518_VISION_ASYNC_BUDGET_ASSERTIONS_PASS=\(t)")
 }
}
