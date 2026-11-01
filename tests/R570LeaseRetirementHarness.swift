import Foundation

@main struct R570LeaseRetirementHarness {
  static func main() {
    let a=String(repeating:"a",count:64),b=String(repeating:"b",count:64)
    var count=0
    func check(_ okay:Bool,_ label:String) {
      guard okay else {fatalError("R570_LEASE_"+label)}
      count+=1
    }
    func status(_ lease:R554CandidateLease,_ time:Int64)->String {
      lease.snapshot(nowMs:time)["view_status"] as? String ?? "BROKEN"
    }
    let live=R554CandidateLease(ttlMs:2000,retireOnNewRequest:true)
    check(live.begin(session:"test",epoch:1,nowMs:1000),"source_started")
    let first=live.issue(frame:1,observedMs:1000,nowMs:1000)!
    check(status(live,1000)=="PENDING","first_pending")
    check(live.finish(first,imageSHA:a,admitted:true,nowMs:1010),"first_accepted")
    check(live.canPublish(first,nowMs:1010),"first_fresh")
    let second=live.issue(frame:2,observedMs:1020,nowMs:1020)!
    check(status(live,1020)=="PENDING","old_hidden_as_soon_as_new_requested")
    check(!live.canPublish(first,nowMs:1020),"old_cannot_publish_during_new_ocr")
    check(live.snapshot(nowMs:1020)["latest"] is NSNull,"old_digest_removed_from_public_snapshot")
    check(live.snapshot(nowMs:1020)["strict_retirement_on_new_request"] as? Bool == true,"strict_mode_reported")
    check(!live.finish(first,imageSHA:b,admitted:true,nowMs:1021),"late_result_rejected")
    check(!live.finish(second,imageSHA:a,admitted:true,nowMs:1030),"duplicate_pixels_do_not_renew")
    check(status(live,1030)=="EMPTY","duplicate_stays_hidden")
    check(!live.canPublish(first,nowMs:1030),"duplicate_cannot_restore_old")
    let third=live.issue(frame:3,observedMs:1040,nowMs:1040)!
    check(live.finish(third,imageSHA:b,admitted:true,nowMs:1050),"new_pixels_accepted")
    check(status(live,1050)=="FRESH_RECEIPT_ONLY","new_fresh")
    check(!live.canPublish(first,nowMs:1050),"superseded_first_not_authorized")
    check(live.canPublish(third,nowMs:1050),"latest_can_publish")
    live.invalidate(reason:"APP_BACKGROUND",nowMs:1060)
    check(status(live,1060)=="EMPTY","background_invalidates")
    check(!live.canPublish(third,nowMs:1060),"background_retired_ticket")
    check(live.begin(session:"new",epoch:2,nowMs:1070),"new_epoch")
    let fourth=live.issue(frame:1,observedMs:1070,nowMs:1070)!
    check(live.finish(fourth,imageSHA:b,admitted:true,nowMs:1080),"old_digest_does_not_poison_new_epoch")
    check(live.canPublish(fourth,nowMs:1080),"new_epoch_publish")
    check(status(live,1080)=="FRESH_RECEIPT_ONLY","new_epoch_fresh")
    // Legacy diagnostic leases preserve old pending behavior and must remain backwards-compatible.
    let legacy=R554CandidateLease(ttlMs:2000)
    check(legacy.begin(session:"legacy",epoch:1,nowMs:1000),"legacy_begin")
    let x=legacy.issue(frame:1,observedMs:1000,nowMs:1000)!
    check(legacy.finish(x,imageSHA:a,admitted:true,nowMs:1010),"legacy_finish")
    let y=legacy.issue(frame:2,observedMs:1020,nowMs:1020)!
    check(status(legacy,1020)=="FRESH_RECEIPT_ONLY","legacy_snapshot_unchanged")
    check(legacy.canPublish(x,nowMs:1020),"legacy_can_publish_x")
    check(!legacy.finish(y,imageSHA:a,admitted:true,nowMs:1030),"legacy_duplicate_rejected")
    check(legacy.canPublish(x,nowMs:1030),"legacy_original_deadline_kept")
    check(legacy.snapshot(nowMs:1030)["strict_retirement_on_new_request"] as? Bool == false,"legacy_declared")
    // A pending lease cannot be prematurely reset by another issue.
    let race=R554CandidateLease(retireOnNewRequest:true)
    check(race.begin(session:"race",epoch:1,nowMs:1000),"race_begin")
    let z=race.issue(frame:1,observedMs:1000,nowMs:1000)!
    check(race.issue(frame:2,observedMs:1001,nowMs:1001)==nil,"race_single_flight")
    check(race.finish(z,imageSHA:a,admitted:true,nowMs:1010),"race_first_result")
    check(race.issue(frame:2,observedMs:1011,nowMs:1011) != nil,"race_second_request")
    check(!race.canPublish(z,nowMs:1011),"race_old_result_retired")
    print("PASS_R570_ALL_\(count)_LEASE_RETIREMENT_CHECKS")
  }
}
