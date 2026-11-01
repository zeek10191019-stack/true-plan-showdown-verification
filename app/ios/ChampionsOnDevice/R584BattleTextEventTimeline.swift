import Foundation

/// R584: extracts auditable *text mentions* of potential battle events from the
/// already collected R583 per-frame OCR indexes. It NEVER infers actual state,
/// owner, turn count, mega visual identity, or a completed action from OCR alone.
/// No new Vision call, network call, background export or image retention.
enum R584BattleTextEventTimeline {
    static let schema = "trueplan.r584.historical-battle-text-mentions.v1"
    static let maximumFrames = 8
    static let maximumMentions = 80

    private static func validSHA(_ v:String)->Bool {
        v.utf8.count == 64 && v.utf8.allSatisfy{ (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func normalized(_ v:String)->String {
        v.trimmingCharacters(in:.whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .folding(options:[.widthInsensitive],locale:Locale(identifier:"ja_JP"))
    }
    /// These strings are mentions only: "ステルスロック" could be a move name;
    /// "メガシンカ" does not prove that the selected Pokemon actually Mega evolved.
    private static func categories(_ raw:String, domains:[String])->[(String,[String])] {
        let t=normalized(raw)
        guard !t.isEmpty && t.utf8.count<=256 else{return []}
        var result=[(String,[String])]()
        let explicit:[(String,[String],[String])] = [
            ("MEGA_TEXT_MENTION",["メガシンカ","メガ進化"],["battle.mega_history"]),
            ("SWITCH_RECALL_TEXT_MENTION",["ひっこめた","引っ込めた","もどした","戻した"],["battle.switch_history"]),
            ("SWITCH_SEND_TEXT_MENTION",["くりだした","繰り出した"],["battle.switch_history"]),
            ("FAINT_TEXT_MENTION",["たおれた","倒れた","ひんしになった","戦闘不能"],["battle.faint_history"]),
            ("MOVE_USE_TEXT_MENTION",["をつかった","を使った"],["battle.move_history"])
        ]
        for (kind,words,field) in explicit where words.contains(where:t.contains) {
            result.append((kind,field))
        }
        let domainKinds:[(String,String,[String])] = [
            ("weather","WEATHER_TEXT_MENTION",["field.weather"]),
            ("terrain","TERRAIN_TEXT_MENTION",["field.terrain"]),
            ("room","ROOM_TEXT_MENTION",["field.trick_room","field.other_rooms"]),
            ("screen_or_side_effect","SIDE_EFFECT_TEXT_MENTION",["own.reflect","opponent.reflect","own.light_screen","opponent.light_screen","own.aurora_veil","opponent.aurora_veil","own.tailwind","opponent.tailwind"]),
            ("entry_hazard","HAZARD_TEXT_MENTION",["own.entry_hazards","opponent.entry_hazards"]),
            ("major_status","STATUS_TEXT_MENTION",["own.major_status","opponent.major_status"]),
            ("visible_volatile","VOLATILE_TEXT_MENTION",["own.volatile_status","opponent.volatile_status"])
        ]
        for (domain,kind,field) in domainKinds where domains.contains(domain) {
            // The field is only a taxonomy hint, not the affected side or value.
            result.append((kind,field))
        }
        return result
    }
    static func make(indexes:[[String:Any]]) -> [String:Any] {
        var failReason:String?=nil
        var accepted=[(frame:Int64,epoch:Int64,time:Int64,sha:String,rows:[[String:Any]])]()
        if indexes.count > maximumFrames {failReason="TOO_MANY_FRAME_INDEXES"}
        if failReason == nil {
            for index in indexes {
                guard index["schema"] as? String == R583FrameReadabilityIndex.schema,
                      index["status"] as? String == "HISTORICAL_OCR_INDEX_ONLY",
                      index["source_binding_valid"] as? Bool == true,
                      index["owner_certified"] as? Bool == false,
                      index["turn_certified"] as? Bool == false,
                      index["mega_visual_form_certified"] as? Bool == false,
                      index["current_state_eligible"] as? Bool == false,
                      let frame=index["frame_id"] as? Int64, frame>0,
                      let epoch=index["epoch"] as? Int64,epoch>0,
                      let time=index["observed_ms_monotonic"] as? Int64,time>0,
                      let sha=index["image_sha256"] as? String,validSHA(sha),
                      let rows=index["observations"] as? [[String:Any]],rows.count<=128 else {
                    failReason="UNVERIFIED_FRAME_INDEX"; break
                }
                if let previous=accepted.last {
                    guard previous.epoch==epoch,previous.frame<frame,previous.time<=time else {
                        failReason="NON_MONOTONIC_OR_MIXED_CAPTURE_EPOCH";break
                    }
                }
                accepted.append((frame,epoch,time,sha,rows))
            }
        }
        var mentions=[[String:Any]]()
        var candidateRowsExamined=0
        var deduplicated=0
        var truncated=false
        if failReason == nil {
            for source in accepted {
                var seen=Set<String>()
                for row in source.rows {
                    candidateRowsExamined += 1
                    guard row["status"] as? String == "UNBOUND_TEXT_CANDIDATE",
                          row["source_image_sha256"] as? String == source.sha,
                          row["owner"] as? String == "UNKNOWN",
                          row["visual_mega_certified"] as? Bool == false,
                          let raw=row["primary_text"] as? String,raw.utf8.count<=256,
                          let ref=row["ref"] as? String,ref.utf8.count<=128,ref.hasPrefix("rotation_"),
                          let domains=row["provisional_domains"] as? [String] else {continue}
                    for (kind,track) in categories(raw,domains:domains) {
                        let key=kind+"|"+normalized(raw)
                        guard seen.insert(key).inserted else {deduplicated+=1;continue}
                        guard mentions.count < maximumMentions else {truncated=true;continue}
                        mentions.append([
                            "kind":kind,"related_field_hints_only":track,
                            "text":raw,"evidence_ref":ref,
                            "frame_id":source.frame,"epoch":source.epoch,
                            "observed_ms_monotonic":source.time,
                            "source_png_sha256":source.sha,
                            "source":"R583_VERIFIED_INDEX_OF_EXISTING_OCR",
                            "status":"HISTORICAL_OCR_TEXT_MENTION_ONLY",
                            "affected_side":"UNKNOWN","pokemon_identity":"UNKNOWN",
                            "game_turn":NSNull(),"actual_event_confirmed":false,
                            "current_state_eligible":false
                        ])
                    }
                }
            }
        }
        return ["schema":schema,
                "status":failReason == nil ? "HISTORICAL_MENTIONS_ONLY" : "HOLD_INVALID_SEQUENCE_OR_INDEX",
                "hold_reason":failReason as Any? ?? NSNull(),
                "frames_examined":accepted.count,
                "candidate_rows_examined":candidateRowsExamined,
                "mention_count":mentions.count,
                "deduplicated_same_frame_mentions":deduplicated,
                "truncated_by_limit":truncated,
                "mentions":mentions,
                "mega_visual_form_certified":false,"owner_certified":false,
                "turn_certified":false,"effect_duration_certified":false,
                "actual_game_accuracy_certified":false,
                "current_state_eligible":false,"battle_advice_authorized":false,
                "automatic_upload":false,"requires_real_game_ground_truth":true]
    }
}
