import Foundation
import CoreFoundation

/// Reads displayed status and boost text near independently source-bound HUD
/// anchors. Position is only a hypothesis, NEVER game-side ownership proof.
/// No pixels are classified here: icons without OCR remain UNKNOWN.
enum R669HUDAdjacentText {
    static let schema = "trueplan.r669.hud-adjacent-text.v1"
    typealias Token = R668PlainHUDReader.Token
    private static let statuses: [String:String] = [
        "やけど":"BRN", "BRN":"BRN", "まひ":"PAR", "PAR":"PAR",
        "ねむり":"SLP", "SLP":"SLP", "こおり":"FRZ", "FRZ":"FRZ",
        "どく":"PSN", "PSN":"PSN", "もうどく":"TOX"
    ]
    private static let volatile: [String:String] = [
        "こんらん":"CONFUSION", "混乱":"CONFUSION",
        "やどりぎ":"LEECH_SEED", "みがわり":"SUBSTITUTE",
        "ちょうはつ":"TAUNT", "アンコール":"ENCORE",
        "かなしばり":"DISABLE", "あくび":"YAWN"
    ]
    private static let boostStat: [String:String] = [
        "こうげき":"atk", "攻撃":"atk", "ぼうぎょ":"def", "防御":"def",
        "とくこう":"spa", "特攻":"spa", "とくぼう":"spd", "特防":"spd",
        "すばやさ":"spe", "素早さ":"spe", "命中":"accuracy",
        "かいひ":"evasion", "回避":"evasion"
    ]
    private static func hold(_ reason:String)->[String:Any] {
        ["schema":schema, "status":reason, "records":[[String:Any]](),
         "game_fields_certified":0,"owner_verified":false,
         "turn_verified":false,"mega_form_certified":false,
         "battle_advice_authorized":false,"current_state_eligible":false]
    }
    private static func exactInt(_ x:Any?)->Int? {
        guard let n=x as? NSNumber,
            CFGetTypeID(n) != CFBooleanGetTypeID(),
            n.doubleValue.isFinite,n.doubleValue>=0,
            n.doubleValue<Double(Int32.max),
            n.doubleValue==Double(n.intValue) else{return nil}
        return n.intValue
    }
    private static func hash(_ x:Any?)->String? {
        guard let s=x as? String,s.utf8.count==64,
            s.utf8.allSatisfy({(48...57).contains($0) ||
                                  (97...102).contains($0)}) else{return nil}
        return s
    }
    private static func compact(_ raw:String)->String {
        raw.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:"　",with:"")
            .replacingOccurrences(of:" ",with:"")
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private static func parse(_ raw:String)->(String,Any)? {
        let s=compact(raw)
        if let v=statuses[s] {return ("major_status",v)}
        if let v=volatile[s] {return ("volatile_status",v)}
        let regex=#"^([ぁ-ゖ一-龯]+)([+-][1-6])$"#
        if let m=s.range(of:regex,options:.regularExpression),
           m==s.startIndex..<s.endIndex {
            // Regex groups are separated only to avoid substring guessing.
            let groups=try? NSRegularExpression(pattern:regex)
            if let match=groups?.firstMatch(in:s,range:NSRange(s.startIndex...,in:s)),
               let k=Range(match.range(at:1),in:s),
               let n=Range(match.range(at:2),in:s),
               let stat=boostStat[String(s[k])],
               let stage=Int(s[n]),(-6...6).contains(stage),stage != 0 {
                return ("boost_seven",["stat":stat,"stage":stage] as [String:Any])
            }
        }
        return nil
    }
    private static func anchor(_ matches:[[String:Any]],
                               field:String)->String? {
        let targets=matches.filter {$0["field"] as? String == field}
        guard targets.count==1,let ref=targets[0]["evidence_ref"] as? String,
              !ref.isEmpty,targets[0]["owner_verified"] as? Bool==false,
              targets[0]["current_state_eligible"] as? Bool==false
        else{return nil}
        return ref
    }
    /// Pure geometry parser; requires two distinct, exact OCR anchor refs.
    static func scan(tokens:[Token],hud:[String:Any],
                     width:Int,height:Int)->[String:Any] {
        guard (400...8192).contains(width),(180...8192).contains(height),
              tokens.count<=288,
              hud["schema"] as? String == R668PlainHUDReader.schema,
              hud["status"] as? String == "HUD_PLAIN_OCR_HYPOTHESES_ONLY",
              hud["owner_verified"] as? Bool == false,
              hud["orientation_verified"] as? Bool == false,
              hud["mega_form_certified"] as? Bool == false,
              hud["game_fields_certified"] as? Int == 0,
              hud["current_state_eligible"] as? Bool == false,
              hud["battle_advice_authorized"] as? Bool == false,
              let deg=exactInt(hud["rotation_candidate_degrees"]),
              [0,90,180,270].contains(deg),
              let matches=hud["matches"] as? [[String:Any]],
              let ownRef=anchor(matches,field:"own.hp"),
              let oppRef=anchor(matches,field:"opponent.hp_percent"),
              ownRef != oppRef else{return hold("HOLD_HUD_ANCHORS")}
        let rw=deg%180==0 ? width : height
        let rh=deg%180==0 ? height : width
        guard (1.65...2.35).contains(Double(rw)/Double(rh)),
              Set(tokens.map{$0.ref}).count==tokens.count,
              tokens.allSatisfy({ t in
                  !t.ref.isEmpty && t.ref.utf8.count<=160 &&
                  !t.text.isEmpty && t.text.utf8.count<=160 &&
                  [t.x,t.y,t.w,t.h].allSatisfy{$0.isFinite} &&
                  (0...1).contains(t.x) && (0...1).contains(t.y) &&
                  t.w>0 && t.h>0 && t.w<=1 && t.h<=1 &&
                  t.x-t.w/2>=0 && t.y-t.h/2>=0 &&
                  t.x+t.w/2<=1 && t.y+t.h/2<=1
              }) else{return hold("HOLD_TOKEN_GEOMETRY")}
        let rotated=tokens.map{$0.rotated(deg)}
        let byRef=Dictionary(uniqueKeysWithValues:rotated.map{($0.ref,$0)})
        guard let own=byRef[ownRef],let opp=byRef[oppRef],
              own.x<0.50,own.y>0.75,
              opp.x>0.58,opp.y<0.35 else {
            return hold("HOLD_ANCHORS_NOT_IN_EXPECTED_HUD")
        }
        var output=[[String:Any]]()
        var seen=Set<String>()
        for t in rotated where t.ref != ownRef && t.ref != oppRef {
            guard let (kind,value)=parse(t.text) else{continue}
            let odx=abs(t.x-own.x), ody=abs(t.y-own.y)
            let pdx=abs(t.x-opp.x), pdy=abs(t.y-opp.y)
            let isOwn=odx<=0.23 && ody<=0.17
            let isOpp=pdx<=0.23 && pdy<=0.17
            if isOwn == isOpp {continue} // ambiguous or unlocated
            let side=isOwn ? "own" : "opponent"
            let key=side+"."+kind
            // One unambiguous glyph per side/field; conflicting icons HOLD.
            guard seen.insert(key).inserted else {
                return hold("HOLD_CONFLICTING_SIDE_STATUS_TEXT")
            }
            output.append(["field":key,"value":value,
                "raw_text":t.text,"evidence_ref":t.ref,
                "anchor_ref":isOwn ? ownRef : oppRef,
                "side_hint":isOwn ? "OWN_HUD_POSITION_ONLY" :
                                   "OPPONENT_HUD_POSITION_ONLY",
                "status":"UNVERIFIED_HUD_ADJACENCY",
                "owner_verified":false,"turn_verified":false,
                "game_value_certified":false,
                "current_state_eligible":false])
        }
        output.sort {($0["field"] as? String ?? "") <
                     ($1["field"] as? String ?? "")}
        return ["schema":schema,
            "status":"HUD_ADJACENT_TEXT_CANDIDATES_ONLY",
            "records":output,"candidate_count":output.count,
            "unread_icons_without_text":"UNKNOWN",
            "orientation_candidate_degrees":deg,
            "source_kind":"SOURCE_BOUND_HUD_OCR_TOKENS",
            "game_fields_certified":0,"owner_verified":false,
            "turn_verified":false,"mega_form_certified":false,
            "battle_advice_authorized":false,
            "current_state_eligible":false]
    }
    static func audit(_ doc:[String:Any],sourceKind:String)->[String:Any] {
        guard ["LIVE_RETAINED_FRAME", "USER_IMPORTED_PNG_OFFLINE_ONLY"]
                .contains(sourceKind),
              let hud=doc["r668_plain_hud_ocr"] as? [String:Any],
              hud["source_kind"] as? String == sourceKind,
              let snap=doc["screen_read_state"] as? [String:Any],
              snap["source_validation"] as? String ==
                "PASS_FRAME_BINDING_ONLY",
              snap["current_state_eligible"] as? Bool == false,
              snap["battle_advice_authorized"] as? Bool == false,
              let raw=hash(sourceKind=="LIVE_RETAINED_FRAME" ?
                doc["png_sha256"] : doc["image_sha256"]),
              let analysis=hash(snap["image_sha256"]),
              raw == hash(hud["source_image_sha256"]),
              analysis == hash(hud["analysis_image_sha256"]),
              let session=snap["capture_session_id"] as? String,
              !session.isEmpty,session==hud["capture_session_id"] as? String,
              let frame=exactInt(snap["frame_id"]),frame>0,
              let epoch=exactInt(snap["epoch"]),epoch>0,
              exactInt(hud["frame_id"])==frame,
              exactInt(hud["epoch"])==epoch,
              let inv=snap["ocr_source_inventory"] as? [[String:Any]],
              inv.count<=288,
              let w=exactInt(doc["image_width"]),
              let h=exactInt(doc["image_height"]) else {
            return hold("HOLD_SOURCE_HUD_MISMATCH")
        }
        var aw=w,ah=h
        if raw != analysis {
            guard let p=doc["analysis_projection"] as? [String:Any],
                  p["status"] as? String=="DECLARED_GEOMETRY_ONLY",
                  p["raw_image_sha256"] as? String==raw,
                  p["analysis_image_sha256"] as? String==analysis,
                  p["capture_session_id"] as? String==session,
                  exactInt(p["frame_id"])==frame,
                  exactInt(p["epoch"])==epoch,
                  exactInt(p["raw_width"])==w,
                  exactInt(p["raw_height"])==h,
                  p["owner_certified"] as? Bool==false,
                  let pw=exactInt(p["analysis_width"]),
                  let ph=exactInt(p["analysis_height"]) else {
                return hold("HOLD_ANALYSIS_TRANSFORM")
            }
            aw=pw;ah=ph
        }
        var tokens=[Token](),used=Set<String>()
        for row in inv {
            guard let ref=row["evidence_ref"] as? String,
                !ref.isEmpty,used.insert(ref).inserted,
                row["image_sha256"] as? String==analysis,
                row["capture_session_id"] as? String==session,
                exactInt(row["frame_id"])==frame,
                exactInt(row["epoch"])==epoch,
                row["owner_verified"] as? Bool==false,
                let s=row["raw_text"] as? String,!s.isEmpty,
                s.utf8.count<=160,
                let rect=row["roi"] as? [String:Any],
                let x=exactInt(rect["x"]),let y=exactInt(rect["y"]),
                let dx=exactInt(rect["width"]),
                let dy=exactInt(rect["height"]),
                x<aw,y<ah,dx>0,dy>0,
                dx<=aw-x,dy<=ah-y else {
                return hold("HOLD_OCR_SOURCE_CONTRADICTION")
            }
            if ref.contains(".ocr_alternatives[") {continue}
            tokens.append(Token(ref:ref,text:s,
                x:(Double(x)+Double(dx)/2)/Double(aw),
                y:(Double(y)+Double(dy)/2)/Double(ah),
                w:Double(dx)/Double(aw),h:Double(dy)/Double(ah)))
        }
        var result=scan(tokens:tokens,hud:hud,width:aw,height:ah)
        result["source_image_sha256"]=raw
        result["analysis_image_sha256"]=analysis
        result["capture_session_id"]=session
        result["frame_id"]=frame
        result["epoch"]=epoch
        result["source_kind"]=sourceKind
        return result
    }
    static func enrich(_ doc:inout [String:Any],sourceKind:String) {
        doc["r669_hud_adjacent_text"] = audit(doc,sourceKind:sourceKind)
    }
}
