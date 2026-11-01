import Foundation
import CryptoKit

/// Native literal/provenance tests using synthetic OCR rows and a 2x2 test PNG.
/// This never measures real-game OCR accuracy.
@main struct R552StateValueHarness {
    static func main() throws {
        let directory = URL(fileURLWithPath:CommandLine.arguments[1], isDirectory:true)
        var selected = try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("selected_evidence.json"))) as! [String:Any]
        let image = selected["analysis_image"] as! [String:Any]
        let imageSHA = image["png_sha256"] as! String
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else {fatalError("R552_CHECK_FAILED: " + name)}
            checks += 1
        }
        func json(_ object: Any) throws -> Data {
            try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes])
        }
        var lastEnvelope = ""
        func make(_ texts: [String], transform: ((inout [[String:Any]]) -> Void)? = nil) -> [String:Any] {
            var rows: [[String:Any]] = texts.map { ["raw_text":$0,"confidence":0.8,
                "reason":"FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND","source_frame_id":17,"source_epoch":3,
                "source_image_sha256":imageSHA,"roi_rect":["x":0,"y":0,"width":2,"height":2]] }
            transform?(&rows)
            let packet: [String:Any] = ["schema":"trueplan.mobile-observation.v1","battle_id":"capture-test",
                "frame_id":17,"epoch":3,"observed_at_ms":1200,"received_at_ms":1250,
                "image_sha256":imageSHA,"production_enabled":false,"turn":NSNull(),"readings":rows]
            let payload = try! json(packet)
            let wrapper = ["schema":"trueplan.mobile-envelope.v1","payload_json":String(data:payload,encoding:.utf8)!,
                "payload_sha256":SHA256.hash(data:payload).map {String(format:"%02x",$0)}.joined()]
            lastEnvelope = String(data:try! json(wrapper),encoding:.utf8)!
            return R551ScreenReadState.make(envelope:lastEnvelope,captureSessionID:"capture-test",frame:17,
                epoch:3,observedMs:1200,imageSHA:imageSHA,width:2,height:2)
        }
        func rows(_ state: [String:Any]) -> [[String:Any]] {state["candidates"] as? [[String:Any]] ?? []}
        func value(_ state: [String:Any]) -> [String:Any] {rows(state).first?["value"] as? [String:Any] ?? [:]}
        func conflicts(_ state: [String:Any]) -> [[String:Any]] {state["conflicts"] as? [[String:Any]] ?? []}

        check(value(make(["トリックルーム：残り３ターン"]))["remaining_turns"] as? Int == 3,"explicit remaining and NFKC")
        check(value(make(["トリックルームあと0ターン"]))["remaining_turns"] as? Int == 0,"explicit zero, no default")
        check(value(make(["トリックルーム残り99ターン"]))["remaining_turns"] as? Int == 99,"literal bound, not mechanics limit")
        check(value(make(["トリックルーム3ターン"]))["remaining_turns"] is NSNull,"duration is not remaining")
        check(value(make(["トリックルーム"]))["remaining_turns"] is NSNull,"label gives no duration")
        check(rows(make(["トリックルームあと100ターン"])).isEmpty,"reject excessive counter")
        check(rows(make(["トリックルームあと-1ターン"])).isEmpty,"reject negative counter")
        check(rows(make(["トリックルームはあと3ターン続く"])).isEmpty,"message is not a field counter")
        check(value(make(["おいかぜ あと ４ ターン"]))["label"] as? String == "おいかぜ","spaces in literal counter")
        for (name,stat) in [("こうげき","atk"),("ぼうぎょ","def"),("とくこう","spa"),("とくぼう","spd"),
                            ("すばやさ","spe"),("命中","accuracy"),("回避","evasion")] {
            let result = value(make([name + " +6"]))
            check(result["stat"] as? String == stat && result["stage"] as? Int == 6,"absolute stat " + stat)
        }
        check(value(make(["こうげき −６"]))["stage"] as? Int == -6,"Unicode minus")
        check(value(make(["こうげき:0"]))["stage"] as? Int == 0,"explicit zero stage")
        for raw in ["こうげき +7","ぼうぎょ -7","こうげきが 1段階 あがった","こうげき+1"] {
            check(rows(make([raw])).isEmpty,"no event-to-absolute inference: " + raw)
        }
        check(value(make(["どく"]))["poison_severity"] as? String == "UNKNOWN","poison severity ambiguous")
        check(value(make(["もうどく"]))["poison_severity"] as? String == "BAD_POISON_TEXT_CANDIDATE","explicit toxic still provisional")
        check(value(make(["やけど"]))["poison_severity"] is NSNull,"non-poison has no poison class")
        check(value(make(["特性：ふゆう"]))["label"] as? String == "ふゆう","visible ability")
        check(value(make(["持ち物: オボンのみ"]))["label"] as? String == "オボンのみ","visible item")
        check(rows(make(["特性:"])).isEmpty,"empty ability unknown")
        check(rows(make(["持ち物： "])).isEmpty,"empty item unknown")

        let collision = make(["81%","82%"])
        check(conflicts(collision).count == 1,"two interpretations of exactly one bound ROI")
        check(collision["knowledge_state"] as? String == "CONFLICT","root conflict")
        check(collision["current_state_eligible"] as? Bool == false,"conflict never current")
        check(R551ScreenReadState.displayLines(collision).contains(where:{$0.contains("不一致")}),"visible Japanese conflict")
        check(((collision["own"] as? [String:Any])?["hp"] as? [String:Any])?["value"] is NSNull,"no owner promotion on conflict")
        check(conflicts(make(["80%","80.00%"])).isEmpty,"equivalent numeric values")
        check(conflicts(make(["あめ","はれ"])).count == 1,"incompatible weather labels in one ROI")
        check(conflicts(make(["トリックルームあと3ターン","トリックルーム残り4ターン"])).count == 1,"explicit remaining disagreement")
        check(conflicts(make(["トリックルーム3ターン","トリックルーム残り3ターン"])).isEmpty,"unknown duration compatible with explicit")
        check(conflicts(make(["こうげき +1","ぼうぎょ +2"])).isEmpty,"different stats are not a conflict")
        check(conflicts(make(["トリックルームあと3ターン","マジックルームあと4ターン"])).isEmpty,"different rooms may coexist")
        check(conflicts(make(["どく","もうどく"])).isEmpty,"unknown poison severity is not a contradiction")
        let noROI = make(["81%","82%"]) {$0[1].removeValue(forKey:"roi_rect")}
        check(conflicts(noROI).isEmpty && rows(noROI)[1]["roi"] is NSNull,"unlocated text cannot conflict")
        let differentROI = make(["81%","82%"]) {$0[1]["roi_rect"] = ["x":0,"y":0,"width":1,"height":1]}
        check(conflicts(differentROI).isEmpty,"different ROI cannot conflict")
        for (key,other) in [("source_frame_id",18 as Any),("source_epoch",4 as Any),("source_image_sha256",String(repeating:"0",count:64) as Any)] {
            let result = make(["81%","82%"]) {$0[1][key] = other}
            check(result["source_validation"] as? String=="HOLD" && rows(result).isEmpty,"reject foreign source " + key)
        }
        for rect in [["x":true,"y":0,"width":1,"height":1] as [String:Any],
                     ["x":0,"y":0,"width":1.5,"height":1] as [String:Any]] {
            let result = make(["81%","82%"]) {$0[1]["roi_rect"] = rect}
            check(conflicts(result).isEmpty && rows(result)[1]["roi"] is NSNull,"reject boolean/fractional ROI")
        }
        for (key,other) in [("capture_session_id","another" as Any),("frame_id",18 as Any),("epoch",4 as Any),
                            ("image_sha256",String(repeating:"0",count:64) as Any)] {
            var candidates = rows(collision); candidates[1][key] = other
            check(R552StateValues.conflicts(candidates).isEmpty,"no cross-source conflict " + key)
        }
        let sample = make(["81%","82%","トリックルームあと3ターン","こうげき −2","どく","特性:ふゆう","持ち物:オボンのみ"])
        check(rows(sample).allSatisfy {$0["side"] as? String == "UNKNOWN_OWNER" && $0["knowledge_state"] as? String == "INFERRED"},"all interpretations remain provisional")
        selected["screen_read_state"] = sample
        selected["research_candidate_envelope"] = lastEnvelope
        var entries = [R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:try json(selected))]
        for name in ["capture_manifest.json","frames/frame_17.png"] {
            entries.append(.init(name:name,bytes:try Data(contentsOf:directory.appendingPathComponent(name))))
        }
        entries = try R551EvidenceIntegrity.appendingIndex(entries,captureSessionID:"capture-test",frame:17,epoch:3,
            appVersion:"0.5.52",appBuild:"552")
        _ = try R548ResearchArchive.write(entries,to:directory.appendingPathComponent("r552_values.zip"))
        try json(sample).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("R552_NATIVE_STATE_VALUE_CHECKS_PASS=\(checks)")
    }
}
