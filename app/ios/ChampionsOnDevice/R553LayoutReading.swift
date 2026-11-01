import Foundation

/// One development-layout profile. A match proposes regions; it cannot certify
/// an owner, Pokemon identity, move legality, current state or live orientation.
enum R553LayoutReading {
    struct Site {
        let reading: Int
        let rank: Int
        let text: String
        let confidence: Double?
        let reference: String
        let roi: [String:Int64]
    }
    struct Region {
        let x: Double, y: Double, w: Double, h: Double
        func contains(_ site: Site, width: Int, height: Int) -> Bool {
            guard let rx=site.roi["x"],let ry=site.roi["y"],let rw=site.roi["width"],let rh=site.roi["height"],rw>0,rh>0 else {return false}
            let sx=Double(rx)/Double(width),sy=Double(ry)/Double(height)
            let sw=Double(rw)/Double(width),sh=Double(rh)/Double(height)
            let overlap=max(0,min(x+w,sx+sw)-max(x,sx))*max(0,min(y+h,sy+sh)-max(y,sy))
            return overlap/(sw*sh) >= 0.9
        }
    }
    private static let ownHP=Region(x:0.15,y:0.90,w:0.12,h:0.08)
    private static let opponentHP=Region(x:0.84,y:0.10,w:0.09,h:0.07)
    private static let command=Region(x:0.78,y:0.20,w:0.10,h:0.06)
    private static func compact(_ text: String) -> String {
        R552StateValues.normalized(text).replacingOccurrences(of:" ",with:"")
    }
    private static func canonical(_ value: Any) -> String {
        guard let bytes=try? JSONSerialization.data(withJSONObject:[value],options:[.sortedKeys,.withoutEscapingSlashes]),
              let result=String(data:bytes,encoding:.utf8) else {return "INVALID"}
        return result
    }
    private static func fraction(_ raw: String, pp: Bool) -> [String:Int]? {
        var text=compact(raw)
        if text.hasPrefix(pp ? "PP" : "HP") {text=String(text.dropFirst(2))}
        guard text.range(of:pp ? #"^[0-9]{1,2}/[0-9]{1,2}$"# : #"^[0-9]{1,4}/[0-9]{1,4}$"#,options:.regularExpression) != nil else {return nil}
        let pair=text.split(separator:"/").compactMap {Int($0)}
        guard pair.count==2,pair[1]>0,pair[0]<=pair[1] else {return nil}
        return ["current":pair[0],"maximum":pair[1]]
    }
    private static func percent(_ raw: String) -> Double? {
        let text=compact(raw)
        guard text.range(of:#"^[0-9]{1,3}(\.[0-9]{1,2})?%$"#,options:.regularExpression) != nil,
              let value=Double(text.dropLast()),(0...100).contains(value) else {return nil}
        return value
    }
    private static func name(_ raw: String) -> String? {
        let text=R552StateValues.normalized(raw)
        guard (2...24).contains(text.count),
              text.range(of:#"^[ぁ-ゖァ-ヺー一-龯A-Za-z0-9・♀♂]+$"#,options:.regularExpression) != nil,
              text.range(of:#"[ぁ-ゖァ-ヺ一-龯]"#,options:.regularExpression) != nil else {return nil}
        return text
    }
    static func inspect(sites: [Site], width: Int, height: Int, screenKind: String,
                        session: String, frame: Int64, epoch: Int64, imageSHA: String, observedMs: Int64,
                        allowDetailsOverlay: Bool = false) -> [String:Any] {
        var report: [String:Any] = ["schema":"trueplan.screen-read.layout-candidates.v1",
            "profile_id":"LEGACY_VERTICAL_MOVES_216_V1","status":"HOLD_UNSUPPORTED_SCREEN",
            "capture_session_id":session,"frame_id":frame,"epoch":epoch,"image_sha256":imageSHA,
            "receipt_uptime_ms":observedMs,"roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
            "scope":"HISTORICAL_FRAME_LAYOUT_CANDIDATES_ONLY","calibration_certified":false,
            "owner_certified":false,"current_state_eligible":false,"battle_advice_authorized":false,
            "anchors":[[String:Any]](),"associations":[[String:Any]](),"conflict_count":0]
        if allowDetailsOverlay && screenKind == "move_selection_with_move_details_overlay_candidate" {
            report["profile_id"]="LEGACY_VERTICAL_MOVES_216_LEFT_DETAILS_V2"
        }
        guard screenKind == "move_selection_candidate" ||
              (allowDetailsOverlay && screenKind == "move_selection_with_move_details_overlay_candidate") else {return report}
        report["status"]="HOLD_UNSUPPORTED_GEOMETRY"
        guard width>=400,height>=180,abs(Double(width)/Double(height)-578.0/267.0)<0.025 else {return report}
        let primaries=sites.filter {$0.rank==0}
        func members(_ primary: Site) -> [Site] {sites.filter {$0.reading==primary.reading}}
        func common(_ role: String, _ slot: Int?, _ group: [Site]) -> [String:Any] {
            ["role_hint":role,"slot":slot.map {$0 as Any} ?? NSNull(),
             "suggested_owner":role == "opponent_hp" || role == "opponent_name" ? "opponent" : "own",
             "side":"UNKNOWN_OWNER","capture_session_id":session,"frame_id":frame,"epoch":epoch,
             "image_sha256":imageSHA,"receipt_uptime_ms":observedMs,
             "battle_id":NSNull(),"turn":NSNull(),"capture_timestamp_ms":NSNull(),"stale_deadline_ms":NSNull(),
             "orientation":"ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED","roi_coordinate_space":"ANALYSIS_PIXELS_TOP_LEFT",
             "confidence":NSNull(),"source_confidences":group.map {$0.confidence.map {$0 as Any} ?? NSNull()},
             "source":"VISION_OCR_LAYOUT_CANDIDATE",
             "evidence_refs":group.map(\.reference),"raw_texts":group.map(\.text),
             "rois":group.map(\.roi),"verification_status":"UNVERIFIED",
             "current_state_eligible":false,"validity":"HISTORICAL_FRAME_ONLY"]
        }
        func association(_ role: String, _ slot: Int?, _ group: [Site], _ choices: [Any], _ method: String) -> [String:Any] {
            var result=common(role,slot,group)
            let distinct=Set(choices.map {canonical($0)})
            result["knowledge_state"]=distinct.isEmpty ? "UNKNOWN" : (distinct.count==1 ? "INFERRED" : "CONFLICT")
            result["value"]=distinct.count==1 ? choices[0] : NSNull()
            result["method"]=method
            return result
        }
        func names(_ group: [Site]) -> [Any] {
            let values=group.compactMap {name($0.text)}
            return values.count==group.count ? values : []
        }
        let anchorSpecs: [(String,Region,(String)->Any?)] = [
            ("own_hp",ownHP,{fraction($0,pp:false)}),
            ("opponent_hp",opponentHP,{percent($0)}),
            ("command",command,{compact($0).uppercased()=="COMMAND" ? "COMMAND" : nil})]
        var anchors=[[String:Any]](),associations=[[String:Any]]()
        for (role,region,parse) in anchorSpecs {
            report["status"]="HOLD_MISSING_ANCHORS"
            let found=primaries.filter {region.contains($0,width:width,height:height) && ($0.confidence ?? -1)>=0.65 && parse($0.text) != nil}
            guard found.count==1,let primary=found.first else {
                if found.count>1 {report["status"]="HOLD_AMBIGUOUS_ANCHORS"}
                return report
            }
            let group=members(primary),values=group.compactMap {parse($0.text)}
            guard values.count==group.count,Set(values.map {canonical($0)}).count==1 else {
                report["status"]="HOLD_AMBIGUOUS_ANCHORS";return report
            }
            anchors.append(["role_hint":role,"reading_index":primary.reading,"evidence_refs":group.map(\.reference),"value":values[0]])
            if role != "command" {associations.append(association(role,nil,group,values,"UNVERIFIED_LAYOUT_ANCHOR"))}
        }
        if screenKind == "move_selection_with_move_details_overlay_candidate" {
            // Only the known left-side panel is supported. Its labels must be
            // separate, strong, source-bound observations outside the move UI.
            report["status"]="HOLD_UNSUPPORTED_OVERLAY"
            let panel=Region(x:0.08,y:0.14,w:0.49,h:0.24)
            let words=Set(["技分類","威力","命中","効果範囲"])
            let found=primaries.filter {words.contains(compact($0.text)) &&
                ($0.confidence ?? -1)>=0.65 && panel.contains($0,width:width,height:height)}
            guard Set(found.map {compact($0.text)}).count>=2 else {return report}
            report["status"]="HOLD_AMBIGUOUS_OVERLAY"
            guard Set(found.map {compact($0.text)}).count==found.count else {return report}
            for primary in found {
                let group=members(primary),label=compact(primary.text)
                guard group.allSatisfy({compact($0.text)==label}) else {return report}
                anchors.append(["role_hint":"overlay_"+label,"reading_index":primary.reading,
                    "evidence_refs":group.map(\.reference),"value":label])
            }
        }
        for (role,region) in [("own_name",Region(x:0.12,y:0.84,w:0.14,h:0.07)),
                              ("opponent_name",Region(x:0.78,y:0.035,w:0.14,h:0.065))] {
            let group=sites.filter {region.contains($0,width:width,height:height)}
            associations.append(association(role,nil,group,names(group),"UNVERIFIED_NAME_REGION_TEXT"))
        }
        for slot in 0..<4 {
            let nameRegion=Region(x:0.75,y:0.44+Double(slot)*0.12,w:0.13,h:0.065)
            let ppRegion=Region(x:0.88,y:0.43+Double(slot)*0.12,w:0.05,h:0.10)
            let move=sites.filter {nameRegion.contains($0,width:width,height:height)}
            associations.append(association("move_name",slot,move,names(move),"UNVERIFIED_MOVE_REGION_TEXT"))
            let pp=sites.filter {ppRegion.contains($0,width:width,height:height)}
            let whole=pp.compactMap {fraction($0.text,pp:true)}
            let numerators=pp.filter {compact($0.text).range(of:#"^[0-9]{1,2}$"#,options:.regularExpression) != nil}
            let denominators=pp.filter {compact($0.text).range(of:#"^/[0-9]{1,2}$"#,options:.regularExpression) != nil}
            var choices: [Any]=whole.count==pp.count && Set(pp.map(\.reading)).count==1 ? whole : []
            if pp.count<=12 && whole.isEmpty && numerators.count+denominators.count==pp.count &&
                Set(numerators.map(\.reading)).count==1 && Set(denominators.map(\.reading)).count==1 {
                for numerator in numerators {
                    for denominator in denominators where numerator.reading != denominator.reading {
                        guard let ay=numerator.roi["y"],let by=denominator.roi["y"],ay<by,
                              let ax=numerator.roi["x"],let bx=denominator.roi["x"],
                              abs(Double(ax-bx))<=Double(width)*0.04,
                              let pair=fraction(compact(numerator.text)+compact(denominator.text),pp:true) else {continue}
                        choices.append(pair)
                    }
                }
            }
            associations.append(association("move_pp",slot,pp,choices,"LITERAL_OR_EXPLICIT_SLASH_PARTS_ONLY"))
        }
        report["status"]="PROVISIONAL_PROFILE_MATCH_ONLY"
        report["anchors"]=anchors;report["associations"]=associations
        report["conflict_count"]=associations.filter {$0["knowledge_state"] as? String == "CONFLICT"}.count
        return report
    }
    static func displayLines(_ report: [String:Any]) -> [String] {
        if ["HOLD_UNSUPPORTED_OVERLAY","HOLD_AMBIGUOUS_OVERLAY"].contains(report["status"] as? String ?? "") {
            return ["技説明パネルの位置や文字候補が一致せず、HP・技枠の位置対応を保留します"]
        }
        guard report["status"] as? String == "PROVISIONAL_PROFILE_MATCH_ONLY",
              let associations=report["associations"] as? [[String:Any]] else {return []}
        var lines=["位置からの対応候補（自他・技枠は未認証）"]
        for row in associations {
            guard let role=row["role_hint"] as? String,let knowledge=row["knowledge_state"] as? String else {continue}
            let slot=(row["slot"] as? Int).map {"技枠\($0+1)"} ?? ""
            let label=["own_hp":"自分側HP候補","opponent_hp":"相手側HP候補","own_name":"自分側の名前候補",
                       "opponent_name":"相手側の名前候補","move_name":slot+"の文字候補","move_pp":slot+"のPP候補"][role] ?? role
            if knowledge=="CONFLICT" {lines.append(label+"：文字候補が不一致");continue}
            guard knowledge=="INFERRED",let value=row["value"] else {continue}
            if let pair=value as? [String:Int],let current=pair["current"],let maximum=pair["maximum"] {
                lines.append("\(label)：\(current)/\(maximum)")
            } else {lines.append("\(label)：\(value)")}
        }
        return lines
    }
}
