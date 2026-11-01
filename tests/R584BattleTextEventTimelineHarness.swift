import Foundation

@main struct R584BattleTextEventTimelineHarness {
    static var passed=0
    static func check(_ value:Bool,_ label:String) {
        guard value else {fatalError("FAIL_R584_"+label)}
        passed+=1
    }
    static func source(_ sha:String,_ words:[String],alternatives:[String]=[]) -> [String:Any] {
        ["schema":"trueplan.r551.rotation-ocr-evidence.v1",
         "image_sha256":sha,"own_opponent":"UNKNOWN","mega_certified":false,
         "visual_form_certified":false,"orientation_evidence":[["orientation_degrees":0,
            "status":"OCR_CANDIDATES_ONLY","observations":words.map { word in
                ["roi":["x":0.1,"y":0.1,"width":0.5,"height":0.2],
                 "candidates":([word]+alternatives).map{["text":$0,"confidence":0.9] as [String:Any]}] as [String:Any]
            }]]]
    }
    static func index(_ frame:Int64,_ epoch:Int64,_ ms:Int64,_ sha:String,_ words:[String],alternatives:[String]=[])->[String:Any] {
        R583FrameReadabilityIndex.make(frame:frame,epoch:epoch,observedMs:ms,imageSHA:sha,
            ocr:source(sha,words,alternatives:alternatives))
    }
    static func mentions(_ report:[String:Any])->[[String:Any]] {
        report["mentions"] as? [[String:Any]] ?? []
    }
    static func has(_ report:[String:Any],_ kind:String)->Bool {
        mentions(report).contains{$0["kind"] as? String == kind}
    }
    static func main() {
        let sha=String(repeating:"b",count:64),sha2=String(repeating:"c",count:64)
        let a=index(11,2,1000,sha,["メガシンカ","相手のポケモンを引っ込めた","すなあらし","ステルスロック","81%","10/10"])
        let b=index(12,2,1050,sha2,["ポケモンを繰り出した","ミミッキュはシャドークローを使った","ラウドボーンは倒れた","トリックルーム","まひ","リフレクター"])
        let good=R584BattleTextEventTimeline.make(indexes:[a,b])
        check(good["status"] as? String == "HISTORICAL_MENTIONS_ONLY","STATUS")
        check(good["frames_examined"] as? Int == 2,"FRAMES")
        check(has(good,"MEGA_TEXT_MENTION"),"MEGA_TEXT")
        check(has(good,"SWITCH_RECALL_TEXT_MENTION"),"SWITCH_RECALL")
        check(has(good,"SWITCH_SEND_TEXT_MENTION"),"SWITCH_SEND")
        check(has(good,"MOVE_USE_TEXT_MENTION"),"MOVE_USE")
        check(has(good,"FAINT_TEXT_MENTION"),"FAINT_TEXT")
        check(has(good,"WEATHER_TEXT_MENTION"),"WEATHER")
        check(has(good,"HAZARD_TEXT_MENTION"),"HAZARD")
        check(has(good,"ROOM_TEXT_MENTION"),"ROOM")
        check(has(good,"STATUS_TEXT_MENTION"),"STATUS_MENTION")
        check(has(good,"SIDE_EFFECT_TEXT_MENTION"),"SIDE_MENTION")
        check(!mentions(good).contains{$0["text"] as? String == "81%"},"PERCENT_NOT_EVENT")
        check(!mentions(good).contains{$0["text"] as? String == "10/10"},"FRACTION_NOT_EVENT")
        check(mentions(good).allSatisfy{$0["actual_event_confirmed"] as? Bool == false},"NOT_CONFIRMED")
        check(mentions(good).allSatisfy{$0["affected_side"] as? String == "UNKNOWN"},"OWNER_UNKNOWN")
        check(mentions(good).allSatisfy{$0["pokemon_identity"] as? String == "UNKNOWN"},"ID_UNKNOWN")
        check(mentions(good).allSatisfy{$0["game_turn"] is NSNull},"TURN_UNKNOWN")
        check(mentions(good).allSatisfy{$0["current_state_eligible"] as? Bool == false},"NO_STATE")
        check(good["mega_visual_form_certified"] as? Bool == false,"NO_MEGA_VISUAL")
        check(good["battle_advice_authorized"] as? Bool == false,"NO_ADVICE")
        check(good["automatic_upload"] as? Bool == false,"NO_UPLOAD")
        check(JSONSerialization.isValidJSONObject(good),"VALID_JSON")
        let m=mentions(good)
        check(m.allSatisfy{$0["frame_id"] as? Int64 == 11 || $0["frame_id"] as? Int64 == 12},"FRAME_PROVENANCE")
        check(m.allSatisfy{$0["source_png_sha256"] as? String == sha || $0["source_png_sha256"] as? String == sha2},"SHA_PROVENANCE")
        check(m.allSatisfy{$0["epoch"] as? Int64 == 2},"EPOCH_PROVENANCE")
        check(m.allSatisfy{$0["evidence_ref"] as? String == "rotation_0.observations[0]" || ($0["evidence_ref"] as? String)?.hasPrefix("rotation_0.observations[") == true},"OCR_REF")
        check(m.first?["frame_id"] as? Int64 == 11,"ORDER")
        let screens=m.first{$0["kind"] as? String == "SIDE_EFFECT_TEXT_MENTION"}
        let tracks=screens?["related_field_hints_only"] as? [String] ?? []
        check(tracks.contains("own.reflect") && tracks.contains("opponent.reflect"),"NO_FALSE_SIDE_HINT")
        check(R584BattleTextEventTimeline.make(indexes:[]) ["frames_examined"] as? Int == 0,"EMPTY")
        check(R584BattleTextEventTimeline.make(indexes:[])["mention_count"] as? Int == 0,"EMPTY_NO_MENTION")
        check(R584BattleTextEventTimeline.make(indexes:[b,a])["status"] as? String == "HOLD_INVALID_SEQUENCE_OR_INDEX","OUT_OF_ORDER")
        check(mentions(R584BattleTextEventTimeline.make(indexes:[b,a])).isEmpty,"OUT_OF_ORDER_NO_LEAK")
        check(R584BattleTextEventTimeline.make(indexes:[a,a])["status"] as? String == "HOLD_INVALID_SEQUENCE_OR_INDEX","DUP_FRAME")
        let mixed=index(12,3,1100,sha2,["メガシンカ"])
        check(R584BattleTextEventTimeline.make(indexes:[a,mixed])["status"] as? String == "HOLD_INVALID_SEQUENCE_OR_INDEX","MIXED_EPOCH")
        let badClock=index(12,2,900,sha2,["メガシンカ"])
        check(R584BattleTextEventTimeline.make(indexes:[a,badClock])["status"] as? String == "HOLD_INVALID_SEQUENCE_OR_INDEX","CLOCK_REGRESSION")
        var forged=a;forged["source_binding_valid"]=false
        check(R584BattleTextEventTimeline.make(indexes:[forged])["status"] as? String == "HOLD_INVALID_SEQUENCE_OR_INDEX","BAD_SOURCE")
        forged=a;forged["owner_certified"]=true
        check(R584BattleTextEventTimeline.make(indexes:[forged])["mention_count"] as? Int == 0,"FORGED_OWNER")
        forged=a;forged["mega_visual_form_certified"]=true
        check(R584BattleTextEventTimeline.make(indexes:[forged])["mention_count"] as? Int == 0,"FORGED_MEGA")
        forged=a;forged["schema"]="unknown"
        check(R584BattleTextEventTimeline.make(indexes:[forged])["mention_count"] as? Int == 0,"FORGED_SCHEMA")
        let variants=index(13,2,2000,sha,["メガシンカ"],alternatives:["ステルスロック"])
        check(R584BattleTextEventTimeline.make(indexes:[variants])["mention_count"] as? Int == 0,"AMBIGUOUS_ALT")
        let duplicate=index(14,2,2300,sha,["メガシンカ","メガシンカ","メガ進化"])
        let d=R584BattleTextEventTimeline.make(indexes:[duplicate])
        check(d["mention_count"] as? Int == 2,"DEDUP_SAME_TEXT")
        check(d["deduplicated_same_frame_mentions"] as? Int == 1,"DEDUP_COUNT")
        let eight=(0..<8).map { i in index(Int64(i+1),1,Int64(i+100),sha,["トリックルーム"]) }
        check(R584BattleTextEventTimeline.make(indexes:eight)["frames_examined"] as? Int == 8,"MAX_EIGHT")
        check(R584BattleTextEventTimeline.make(indexes:eight+[index(9,1,109,sha,["トリックルーム"])])["status"] as? String == "HOLD_INVALID_SEQUENCE_OR_INDEX","NINE_HOLD")
        let repeated=index(15,2,3000,sha,(0..<120).map { i in "ポケモン\(i)を使った"})
        let capped=R584BattleTextEventTimeline.make(indexes:[repeated])
        check(capped["mention_count"] as? Int == 80,"MAX_MENTIONS")
        check(capped["truncated_by_limit"] as? Bool == true,"TRUNCATION")
        check(capped["candidate_rows_examined"] as? Int == 120,"BOUNDED_FRAME")
        let unrelated=index(21,2,5000,sha,["ミミッキュ","メガシンカできるか？","ステルスロック"])
        // A textual mention must NEVER certify actual Mega evolution or hazards.
        let u=R584BattleTextEventTimeline.make(indexes:[unrelated])
        check(u["mega_visual_form_certified"] as? Bool == false,"MENTION_ONLY_MEGA")
        check(u["effect_duration_certified"] as? Bool == false,"NO_DURATION")
        check(u["actual_game_accuracy_certified"] as? Bool == false,"NO_DEVICE_CERT")
        check(passed>=48,"MINIMUM_ASSERTIONS")
        print("PASS_R584_\(passed)_TEXT_EVENT_MENTIONS_AND_FENCES")
    }
}
