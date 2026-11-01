import Foundation
import CryptoKit

/// Runs production clock/lease/slot types with synthetic stamps. No Vision or device claim.
@main struct R562ReadClockHarness {
    static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        let appVersion=CommandLine.arguments.count>3 ? CommandLine.arguments[3]:"0.5.62"
        let appBuild=CommandLine.arguments.count>4 ? CommandLine.arguments[4]:"562"
        var checks=0,decisions=[[String:Any]](),sequences=[[String:Any]](),slots=[[String:Any]]()
        func check(_ value:@autoclosure ()->Bool,_ why:String) {
            guard value() else {fatalError("R562_CLOCK_CHECK_FAILED: "+why)};checks+=1
        }
        func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func sha(_ bytes:Data)->String {SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()}
        let verdicts:[ResearchSampleClockAudit.Verdict]=[.relativeOnly,.noActiveStream,.invalidStamp,.epochMismatch,
            .replay,.rollback,.deliveryClockRollback,.missingPTS,.repeatedPTS,.ptsRollback,.excessivePTSJump]
        let retires:[ResearchSampleClockAudit.Verdict]=[.rollback,.deliveryClockRollback,.ptsRollback,.excessivePTSJump]
        func decision(_ id:String,_ verdict:ResearchSampleClockAudit.Verdict,_ delivered:Int64,_ previous:Int64?,
                      _ action:R562ReadClockGate.Action,_ reason:String) {
            let value=R562ReadClockGate.decide(verdict:verdict,epoch:3,frame:17,deliveredMs:delivered,previousDeliveredMs:previous)!
            check(value.action==action && value.reason==reason,id)
            decisions.append(["id":id,"decision":value.object])
        }
        for verdict in verdicts {
            let action:R562ReadClockGate.Action=verdict == .relativeOnly ? .allow : retires.contains(verdict) ? .retire:.hold
            decision(verdict.rawValue,verdict,1100,1000,action,
                     verdict == .relativeOnly ? "RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED":verdict.rawValue)
        }
        decision("first_relative_stamp",.relativeOnly,1000,nil,.allow,"RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED")
        decision("delivery_gap_boundary",.relativeOnly,3500,1000,.allow,"RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED")
        decision("delivery_gap_exceeded",.relativeOnly,3501,1000,.retire,"DELIVERY_GAP_EXCEEDS_2500MS")
        decision("missing_pts_after_delivery_gap",.missingPTS,3501,1000,.retire,"DELIVERY_GAP_EXCEEDS_2500MS")
        decision("repeated_pts_after_delivery_gap",.repeatedPTS,3501,1000,.retire,"DELIVERY_GAP_EXCEEDS_2500MS")
        decision("delivery_rollback_overrides_missing",.missingPTS,999,1000,.retire,"DELIVERY_CLOCK_ROLLBACK")
        decision("maximum_positive_delivery",.relativeOnly,Int64.max,Int64.max-1,.allow,"RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED")
        for (epoch,frame,delivered,previous) in [(Int64(0),Int64(1),Int64(1),Int64(1)),(1,0,1,1),(1,1,0,1),(1,1,1,0)] {
            check(R562ReadClockGate.decide(verdict:.relativeOnly,epoch:epoch,frame:frame,
                deliveredMs:delivered,previousDeliveredMs:previous)==nil,"invalid context withheld")
        }
        typealias Event=(Int64,Int64?,ResearchSampleClockAudit.Verdict)
        func sequence(_ id:String,_ events:[Event]) {
            let audit=ResearchSampleClockAudit();check(audit.beginStream(epoch:3),id+" begin")
            var rows=[[String:Any]]()
            for (index,event) in events.enumerated() {
                let actual=audit.record(epoch:3,frameID:Int64(index+1),deliveredMs:event.0,presentationMs:event.1)
                check(actual==event.2,id+" event \(index)")
                rows.append(["frame_id":index+1,"delivered_ms":event.0,
                    "pts_ms":event.1.map {$0 as Any} ?? NSNull(),"verdict":actual.rawValue])
            }
            sequences.append(["id":id,"events":rows,"summary":try! JSONSerialization.jsonObject(with:Data(audit.json().utf8))])
        }
        sequence("rewind_after_missing",[(1000,1000,.relativeOnly),(1100,nil,.missingPTS),(1200,900,.ptsRollback)])
        sequence("repeat_after_missing",[(1000,1000,.relativeOnly),(1100,nil,.missingPTS),(1200,1000,.repeatedPTS)])
        sequence("source_clock_stalls",[(1000,1000,.relativeOnly),(1601,1001,.excessivePTSJump)])
        sequence("source_clock_jumps",[(1000,1000,.relativeOnly),(1001,1602,.excessivePTSJump)])
        sequence("divergence_boundary",[(1000,1000,.relativeOnly),(1600,1100,.relativeOnly)])
        sequence("missing_then_relative_progress",[(1000,1000,.relativeOnly),(1100,nil,.missingPTS),(1200,1200,.relativeOnly)])
        sequence("delivery_clock_rewinds",[(1000,1000,.relativeOnly),(999,1100,.deliveryClockRollback)])
        sequence("invalid_pts_remembers_reference",[(1000,1000,.relativeOnly),(1100,-1,.missingPTS),(1200,900,.ptsRollback)])
        let rotated=ResearchSampleClockAudit();_=rotated.beginStream(epoch:3)
        _=rotated.record(epoch:3,frameID:1,deliveredMs:1000,presentationMs:5000)
        check(rotated.rotateForClockDiscontinuity(from:3,to:4),"clock retirement rotates source")
        check(!rotated.rotateForClockDiscontinuity(from:3,to:5),"old source cannot rotate current")
        check(rotated.record(epoch:3,frameID:2,deliveredMs:1100,presentationMs:5100) == .epochMismatch,"old epoch rejected")
        check(rotated.record(epoch:4,frameID:3,deliveredMs:1200,presentationMs:100) == .relativeOnly,"new relative reference allowed")
        check(rotated.summary().streamBegins==1 && rotated.summary().epochRotations==1,"logical retirement is not physical restart")

        var slot=R562ReadWorkSlot()
        func snapshot(_ id:String) {slots.append(["id":id,"slot":slot.object])}
        snapshot("idle")
        let first=slot.begin()!;snapshot("first_running")
        let lease=R554CandidateLease();_=lease.begin(session:"synthetic-clock",epoch:1,nowMs:1000)
        let ticket=lease.issue(frame:1,observedMs:1000,nowMs:1000)!
        lease.invalidate(reason:"CAPTURE_CLOCK_HELD",nowMs:1001)
        check(!lease.finish(ticket,imageSHA:String(repeating:"a",count:64),admitted:true,nowMs:1002),"held pending result cannot publish")
        check(!lease.canPublish(ticket,nowMs:1002),"held prior ticket withheld")
        let invalidatedPending=lease.snapshot(nowMs:1002)
        let published=R554CandidateLease();_=published.begin(session:"synthetic-published",epoch:1,nowMs:1000)
        let publishedTicket=published.issue(frame:1,observedMs:1000,nowMs:1000)!
        check(published.finish(publishedTicket,imageSHA:String(repeating:"b",count:64),admitted:true,nowMs:1001),"fresh result before clock hold")
        published.invalidate(reason:"CAPTURE_CLOCK_HELD",nowMs:1002)
        check(!published.canPublish(publishedTicket,nowMs:1003),"clock hold retires already published value")
        let invalidatedPublished=published.snapshot(nowMs:1003)
        check(lease.begin(session:"synthetic-clock-new",epoch:2,nowMs:1003),"new epoch starts independent lease")
        for epoch in 2...1001 {
            check(slot.begin()==nil,"epoch \(epoch) cannot queue a second live worker")
        }
        snapshot("after_1000_epoch_offer_attempts")
        check(slot.finish(first),"old worker completion releases its own slot")
        snapshot("first_finished")
        let second=slot.begin()!;snapshot("second_running")
        check(!slot.finish(first) && !slot.isAvailable,"late old completion cannot release new worker")
        check(!slot.isLatest(first) && slot.isLatest(second),"UI token identifies latest live work")
        snapshot("wrong_old_finish")
        check(slot.finish(second),"second worker finishes")
        for _ in 1...1000 {let ticket=slot.begin()!;check(slot.finish(ticket),"bounded work sequence")}
        snapshot("after_1000_completed_workers")
        let slotBytes=try json(slot.object)
        check(slotBytes.count<1024,"work slot diagnostics stay bounded")
        let held=lease.snapshot(nowMs:1004)
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let diagnostics:[String:Any]=["scope":"CAPTURE_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_CLOCK_PROOF",
            "clock_decision":decisions.first!["decision"]!,"live_work_slot":slot.object]
        selected["r562_read_clock_diagnostics"]=diagnostics
        selected["r554_candidate_leases"]=["automatic_full_frame":held,"paired_move_candidates":held]
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {
            entries.append(.init(name:name,bytes:try Data(contentsOf:directory.appendingPathComponent(name))))
        }
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:appVersion,appBuild:appBuild)
        let archiveURL=directory.appendingPathComponent("r562_clock.zip")
        _=try R548ResearchArchive.write(entries,to:archiveURL)
        let bytes=try Data(contentsOf:archiveURL)
        try json(["scope":"SYNTHETIC_RELATIVE_CLOCK_AND_LIVE_WORKER_ONLY","checks":checks,
            "decisions":decisions,"sequences":sequences,"work_slot_snapshots":slots,"lease_snapshot":held,
            "invalidated_lease_snapshots":[invalidatedPending,invalidatedPublished],
            "retired_clock_summary":try JSONSerialization.jsonObject(with:Data(rotated.json().utf8)),
            "diagnostics":diagnostics,"archive_sha256":sha(bytes),"archive_base64":bytes.base64EncodedString(),
            "Vision_executed":false,"capture_age_certified":false,"game_accuracy_certified":false,
            "device_certified":false,"full_app_CI_certified":false]).write(to:reportURL)
        print("R562_NATIVE_CLOCK_AND_LIVE_WORK_SLOT_PASS=\(checks); SYNTHETIC_STAMPS_ONLY")
    }
}
