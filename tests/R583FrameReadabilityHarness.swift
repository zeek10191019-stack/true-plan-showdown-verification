import Foundation

@main struct R583FrameReadabilityHarness {
    static var passed = 0
    static func check(_ condition: Bool, _ name: String) {
        guard condition else {fatalError("FAIL_R583_\(name)")}
        passed += 1
    }
    static func field(_ report:[String:Any], _ name:String)->[String:Any] {
        (report["fields"] as? [[String:Any]])?.first{$0["field"] as? String == name} ?? [:]
    }
    static func observation(_ text:String, alternatives:[String]=[], x:Double=0.1) -> [String:Any] {
        let variants=[text]+alternatives
        return ["roi":["x":x,"y":0.1,"width":0.25,"height":0.2],
                "candidates":variants.map{["text":$0,"confidence":0.9] as [String:Any]}]
    }
    static func source(_ hash:String,_ observations:[[String:Any]])->[String:Any] {
        ["schema":"trueplan.r551.rotation-ocr-evidence.v1",
         "image_sha256":hash,"own_opponent":"UNKNOWN","mega_certified":false,
         "visual_form_certified":false,"orientation_evidence":[[
            "orientation_degrees":0,"status":"OCR_CANDIDATES_ONLY","observations":observations]]]
    }
    static func main(){
        let sha=String(repeating:"a",count:64)
        let alt=String(repeating:"b",count:64)
        let original=source(sha,[observation("81%",alternatives:["８１％"]),
            observation("メガシンカ"),observation("トリックルーム"),
            observation("すなあらし"),observation("リフレクター"),
            observation("ステルスロック"),observation("まひ"),observation("10/10")])
        let r=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:original)
        check(r["source_binding_valid"] as? Bool == true,"SOURCE_BOUND")
        check(r["indexed_observations"] as? Int == 8,"EIGHT_ROWS")
        check(r["field_count"] as? Int == 79,"ALL_79_FIELDS")
        check(field(r,"own.hp_percent")["status"] as? String == "OCR_CANDIDATE_UNBOUND","OWN_HP_PERCENT_CANDIDATE")
        check(field(r,"opponent.hp_percent")["status"] as? String == "OCR_CANDIDATE_UNBOUND","OPP_HP_PERCENT_CANDIDATE")
        check(field(r,"own.hp_percent")["owner_verified"] as? Bool == false,"NO_OWNER")
        check(field(r,"own.hp")["status"] as? String == "UNKNOWN","FRACTION_NOT_HP")
        check(field(r,"own.pp_four")["status"] as? String == "UNKNOWN","FRACTION_NOT_PP")
        check(field(r,"own.mega_trigger")["status"] as? String == "OCR_CANDIDATE_UNBOUND","MEGA_TEXT_CANDIDATE")
        check(field(r,"own.mega_visual_form")["status"] as? String == "UNKNOWN","NO_MEGA_FORM")
        check(field(r,"field.trick_room")["status"] as? String == "OCR_CANDIDATE_UNBOUND","ROOM_TEXT")
        check(field(r,"field.weather")["status"] as? String == "OCR_CANDIDATE_UNBOUND","WEATHER_TEXT")
        check(field(r,"own.reflect")["status"] as? String == "OCR_CANDIDATE_UNBOUND","WALL_UNBOUND")
        check(field(r,"opponent.entry_hazards")["status"] as? String == "OCR_CANDIDATE_UNBOUND","HAZARD_UNBOUND")
        check(field(r,"opponent.major_status")["status"] as? String == "OCR_CANDIDATE_UNBOUND","STATUS_UNBOUND")
        check(field(r,"battle.turn")["status"] as? String == "UNKNOWN","TURN_UNKNOWN")
        check(field(r,"own.active_species")["status"] as? String == "UNKNOWN","SPECIES_UNKNOWN")
        check(r["mega_visual_form_certified"] as? Bool == false,"MEGA_UNCERTIFIED")
        check(r["battle_advice_authorized"] as? Bool == false,"ADVICE_DISABLED")
        check(r["automatic_upload"] as? Bool == false,"NO_UPLOAD")
        check(JSONSerialization.isValidJSONObject(r),"JSON_VALID")
        let rows = r["observations"] as! [[String:Any]]
        check(rows.allSatisfy{$0["owner"] as? String == "UNKNOWN"},"EACH_ROW_UNBOUND")
        check(rows.last?["provisional_domains"] as? [String] == ["UNBOUND_HP_OR_PP_FRACTION"],"FRACTION_AMBIGUOUS")
        let wrong=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:alt,ocr:original)
        check(wrong["source_binding_valid"] as? Bool == false,"HASH_MISMATCH")
        check(wrong["indexed_observations"] as? Int == 0,"HASH_MISMATCH_NO_ROWS")
        let badSHA=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:"notsha",ocr:original)
        check(badSHA["source_binding_valid"] as? Bool == false,"INVALID_SHA")
        let badFrame=R583FrameReadabilityIndex.make(frame:0,epoch:2,observedMs:7777,imageSHA:sha,ocr:original)
        check(badFrame["source_binding_valid"] as? Bool == false,"BAD_FRAME")
        let badClock=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:0,imageSHA:sha,ocr:original)
        check(badClock["source_binding_valid"] as? Bool == false,"BAD_CLOCK")
        var forged=original;forged["mega_certified"]=true
        check(R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)["source_binding_valid"] as? Bool == false,"FORGED_MEGA")
        forged=original;forged["own_opponent"]="OWN"
        check(R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)["source_binding_valid"] as? Bool == false,"FORGED_OWNER")
        forged=original;forged["orientation_evidence"]=[["orientation_degrees":0,"status":"OCR_CANDIDATES_ONLY","observations":[]],
                                                      ["orientation_degrees":0,"status":"OCR_CANDIDATES_ONLY","observations":[]]]
        check(R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)["source_binding_valid"] as? Bool == false,"DUPLICATE_ORIENTATION")
        forged=original;forged["orientation_evidence"]=[["orientation_degrees":45,"status":"OCR_CANDIDATES_ONLY","observations":[]]]
        check(R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)["source_binding_valid"] as? Bool == false,"INVALID_ORIENTATION")
        forged=source(sha,[observation("リフレクター",alternatives:["しんぴのまもり"]),observation("81%",alternatives:["ステルスロック"])])
        let conflict=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)
        check(conflict["ambiguous_variant_observations"] as? Int == 1,"ALTERNATIVE_DOMAIN_CONFLICT")
        check(field(conflict,"own.hp_percent")["status"] as? String == "UNKNOWN","NO_CONFLICT_PROMOTION")
        check(field(conflict,"own.reflect")["status"] as? String == "OCR_CANDIDATE_UNBOUND","SAME_DOMAIN_VARIANT_ACCEPT")
        forged=source(sha,[observation("81%",x:0.99)])
        check(R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)["rejected_observations"] as? Int == 1,"BAD_ROI_REJECT")
        forged=source(sha,[observation("81%")]);var groups=forged["orientation_evidence"] as! [[String:Any]]
        var obs=groups[0]["observations"] as! [[String:Any]];obs[0]["candidates"]=[["text":"81%","confidence":2.0]]
        groups[0]["observations"]=obs;forged["orientation_evidence"]=groups
        check(R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)["rejected_observations"] as? Int == 1,"BAD_CONFIDENCE_REJECT")
        let huge=source(sha,(0..<200).map{_ in observation("81%")})
        let capped=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:huge)
        check(capped["indexed_observations"] as? Int == 128,"BOUNDED_ROWS")
        check(capped["truncated_by_limit"] as? Bool == true,"TRUNCATION_DECLARED")
        check((field(capped,"own.hp_percent")["candidate_refs"] as? [String])?.count == 12,"FIELD_REFS_BOUNDED")
        forged=source(sha,[observation("メガシンカ")]);groups=forged["orientation_evidence"] as! [[String:Any]]
        groups[0]["status"]="LATE_OR_CANCELLED_RAW_EVIDENCE";forged["orientation_evidence"]=groups
        let late=R583FrameReadabilityIndex.make(frame:11,epoch:2,observedMs:7777,imageSHA:sha,ocr:forged)
        check(late["indexed_observations"] as? Int == 0,"NO_LATE_PROMOTION")
        check(field(late,"own.mega_trigger")["status"] as? String == "UNKNOWN","LATE_MEGA_UNKNOWN")
        check(passed >= 40,"CHECK_COVERAGE")
        print("PASS_R583_\(passed)_FRAME_TEXT_INDEX_SAFETY_CHECKS")
    }
}
