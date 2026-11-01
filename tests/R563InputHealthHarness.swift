import Foundation
import CryptoKit

/// Production pure types, synthetic callbacks. UIKit/SCStream dispatch is not exercised here.
@main struct R563InputHealthHarness {
    static func main() throws {
        let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
        var checks=0,cases=[[String:Any]](),snapshots=[[String:Any]](),slots=[[String:Any]]()
        func check(_ value:@autoclosure ()->Bool,_ why:String) {
            guard value() else {fatalError("R563_INPUT_CHECK_FAILED: "+why)};checks+=1
        }
        func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])}
        func sha(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        for current in [false,true] {for screen in [false,true] {for valid in [false,true] {for image in [false,true] {
            let actual=R563InputHealthFence.preflight(currentStream:current,screen:screen,valid:valid,imageAvailable:image)
            let expected:R563InputHealthFence.Preflight = !current || !screen ? .ignore : !valid ? .invalidSample : image ? .ready:.missingImage
            check(actual==expected,"source/screen/valid/image truth table")
            cases.append(["current_stream":current,"screen":screen,"valid":valid,"image_available":image,"result":actual.rawValue])
        }}}}
        var health=R563InputHealthFence(),slot=R562ReadWorkSlot()
        func snapshot(_ id:String) {snapshots.append(["id":id,"health":health.object])}
        snapshot("none");health.accept();snapshot("ready")
        let lease=R554CandidateLease();_=lease.begin(session:"synthetic-input",epoch:1,nowMs:1000)
        let ticket=lease.issue(frame:17,observedMs:1000,nowMs:1000)!
        check(lease.finish(ticket,imageSHA:String(repeating:"a",count:64),admitted:true,nowMs:1001),"fresh baseline research receipt")
        let first=slot.begin()!
        for (current,screen) in [(false,true),(true,false)] {
            let action=R563InputHealthFence.preflight(currentStream:current,screen:screen,valid:false,imageAvailable:false)
            check(action == .ignore && lease.canPublish(ticket,nowMs:1002),"foreign/audio cannot revoke current receipt")
        }
        check(health.reject(.missingImage),"first rejection requests scope retirement")
        lease.invalidate(reason:"CAPTURE_INPUT_HELD",nowMs:1003)
        check(!lease.canPublish(ticket,nowMs:1004),"current bad sample revokes fresh receipt immediately")
        snapshot("held_once")
        let reasons=R563InputHealthFence.Rejection.allCases
        for index in 0..<1000 {
            check(!health.reject(reasons[index%reasons.count]) && !slot.isAvailable,
                "sustained failures do not request extra retirement or release running work")
        }
        snapshot("held_1000_more");slots.append(slot.object)
        health.accept();snapshot("ready_again")
        check(health.reject(.continuity),"healthy input rearms next rejection boundary")
        snapshot("held_again")
        check(slot.finish(first),"own old completion releases worker")
        slots.append(slot.object);let second=slot.begin()!
        check(!slot.finish(first) && slot.isLatest(second) && !slot.isAvailable,"late old completion cannot clear replacement worker")
        slots.append(slot.object)
        let healthBytes=try json(health.object)
        check(healthBytes.count<1024,"input diagnostics bounded after1002 rejects")
        let held=lease.snapshot(nowMs:1100)
        var selected=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        selected["r563_input_health"]=health.object
        selected["r554_candidate_leases"]=["automatic_full_frame":held,"paired_move_candidates":held]
        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {
            entries.append(.init(name:name,bytes:try Data(contentsOf:directory.appendingPathComponent(name))))
        }
        entries=try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,appVersion:"0.5.63",appBuild:"563")
        let path=directory.appendingPathComponent("r563_input_health.zip")
        _=try R548ResearchArchive.write(entries,to:path);let bytes=try Data(contentsOf:path)
        try json(["scope":"SYNTHETIC_INPUT_HEALTH_LEASE_AND_WORK_SLOT_ONLY","checks":checks,
            "preflight_cases":cases,"snapshots":snapshots,"held_lease":held,"work_slots":slots,
            "archive_base64":bytes.base64EncodedString(),"archive_sha256":sha(bytes),
            "Vision_executed":false,"capture_age_certified":false,"game_accuracy_certified":false,
            "device_certified":false,"full_app_CI_certified":false]).write(to:reportURL)
        print("R563_NATIVE_INPUT_HEALTH_CHECKS_PASS=\(checks); SYNTHETIC_CALLBACKS_ONLY")
    }
}
