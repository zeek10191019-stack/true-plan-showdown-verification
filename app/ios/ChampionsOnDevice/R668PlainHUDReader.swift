import Foundation
import CoreFoundation

/// Actual OCR-token geometry is used to extract plain move labels, PP and
/// HUD names. Location is a hypothesis, never a verified Pokemon owner.
enum R668PlainHUDReader {
    static let schema = "trueplan.r668.plain-hud-ocr.v1"
    struct Token {
        let ref:String, text:String
        let x:Double,y:Double,w:Double,h:Double
        func rotated(_ deg:Int)->Token {
            let cx=x+w/2, cy=y+h/2
            let pos:(Double,Double)
            if deg==90 {pos=(1-cy,cx)}
            else if deg==180 {pos=(1-cx,1-cy)}
            else if deg==270 {pos=(cy,1-cx)}
            else {pos=(cx,cy)}
            return Token(ref:ref,text:text,x:pos.0,y:pos.1,w:w,h:h)
        }
    }
    private static func hold(_ reason:String)->[String:Any] {
        ["schema":schema,"status":reason,
         "candidate_count":0,"game_fields_certified":0,
         "owner_verified":false,"orientation_verified":false,
         "mega_form_certified":false,"battle_advice_authorized":false,
         "current_state_eligible":false]
    }
    private static func integer(_ v:Any?)->Int? {
        guard let n=v as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,n.doubleValue>=0,
              n.doubleValue<Double(Int32.max),
              n.doubleValue==Double(n.intValue) else{return nil}
        return n.intValue
    }
    private static func sha(_ v:Any?)->String? {
        guard let s=v as? String,s.utf8.count==64,
            s.utf8.allSatisfy({(48...57).contains($0) ||
                (97...102).contains($0)}) else{return nil}
        return s
    }
    private static func fraction(_ s:String,pp:Bool)->[Int]? {
        let t=s.replacingOccurrences(of:" ",with:"")
          .replacingOccurrences(of:"　",with:"")
          .replacingOccurrences(of:"HP",with:"")
          .replacingOccurrences(of:"PP",with:"")
        guard t.range(of:#"^[0-9]{1,4}/[0-9]{1,4}$"#,
              options:.regularExpression) != nil else {return nil}
        let a=t.split(separator:"/").compactMap{Int($0)}
        guard a.count==2,a[1]>0,a[0]<=a[1],
              a[1] <= (pp ? 64 : 9999) else{return nil}
        return a
    }
    private static func percentage(_ s:String)->Int? {
        let t=s.replacingOccurrences(of:" ",with:"")
        guard t.range(of:#"^[0-9]{1,3}%$"#,
              options:.regularExpression) != nil,
              let n=Int(t.dropLast()),n<=100 else{return nil}
        return n
    }
    private static func label(_ s:String)->Bool {
        let t=s.trimmingCharacters(in:.whitespacesAndNewlines)
        if t == "10まんボルト" { return true }
        guard (2...24).contains(t.count),
              t.range(of:#"^[ぁ-ゖァ-ヺー一-龯A-Za-z・♀♂]+$"#,
                      options:.regularExpression) != nil,
              t.range(of:#"[ぁ-ゖァ-ヺ一-龯]"#,
                      options:.regularExpression) != nil else{return false}
        let excluded=["コマンド","わざ","ポケモン","メガシンカ",
                      "こうかあり","こうかばつぐ","ひんし",
                      "たたかう","にげる","ちからをみる"]
        let nonSpeciesHUDWords=["やけど","まひ","ねむり","こおり","どく",
           "もうどく","こんらん","みがわり","ちょうはつ",
           "アンコール","かなしばり","あくび","すなあらし",
           "あめ","雨","ひざしがつよい","ゆき","雪",
           "リフレクター","ひかりのかべ","オーロラベール",
           "トリックルーム","グラスフィールド",
           "エレキフィールド","サイコフィールド",
           "ミストフィールド"]
        let typeLabels=["ノーマル","ほのお","みず","でんき",
            "くさ","こおり","かくとう","どく","じめん",
            "ひこう","エスパー","むし","いわ","ゴースト",
            "ドラゴン","あく","はがね","フェアリー"]
        return !excluded.contains(t) && !nonSpeciesHUDWords.contains(t)
            && !typeLabels.contains(t)
    }
    private static func timer(_ s:String)->Int? {
        guard s.range(of:#"^[0-9]{1,2}:[0-5][0-9]$"#,
                       options:.regularExpression) != nil else {return nil}
        let a=s.split(separator:":").compactMap{Int($0)}
        guard a.count==2,a[0]<=30 else{return nil}
        return a[0]*60+a[1]
    }
    private static func sex(_ s:String)->String? {
        if s.contains("♀") && !s.contains("♂") {return "♀"}
        if s.contains("♂") && !s.contains("♀") {return "♂"}
        return nil
    }
    private static func record(_ key:String,_ v:Token,
                               _ value:Any)->[String:Any] {
        ["field":key,"raw_text":v.text,"value":value,
         "evidence_ref":v.ref,"source":"VISION_OCR_HUD_GEOMETRY",
         "role":"POSITION_HINT_ONLY","owner_verified":false,
         "current_state_eligible":false]
    }
    /// Independent extraction from the full-frame OCR text inventory.
    /// All coordinates refer to a single image; orientation is not assumed.
    static func scan(_ input:[Token],width:Int,height:Int)->[String:Any] {
        guard (400...8192).contains(width),
              (180...8192).contains(height),
              input.count<=288 else{return hold("HOLD_GEOMETRY")}
        guard Set(input.map{$0.ref}).count == input.count,
            input.allSatisfy({ t in
                !t.ref.isEmpty && t.ref.utf8.count<=160 &&
                !t.text.isEmpty && t.text.utf8.count<=160 &&
                [t.x,t.y,t.w,t.h].allSatisfy{$0.isFinite} &&
                (0...1).contains(t.x) && (0...1).contains(t.y) &&
                t.w>0 && t.h>0 && t.w<=1 && t.h<=1
            }) else{return hold("HOLD_INVALID_TOKEN_GEOMETRY")}
        var patterns=[[String:Any]]()
        for deg in [0,90,180,270] {
            let rw=deg%180==0 ? width : height
            let rh=deg%180==0 ? height : width
            let aspect=Double(rw)/Double(rh)
            guard (1.65...2.35).contains(aspect) else{continue}
            let ts=input.map{$0.rotated(deg)}
            let own=ts.filter{$0.x<0.48 && $0.y>0.78 &&
                fraction($0.text,pp:false) != nil}
            let opp=ts.filter{$0.x>0.60 && $0.y<0.31 &&
                percentage($0.text) != nil}
            guard own.count==1,opp.count==1 else{continue}
            let hp=own[0],op=opp[0]
            var matches=[record("own.hp",hp,
                ["current":fraction(hp.text,pp:false)![0],
                 "maximum":fraction(hp.text,pp:false)![1]]),
                record("opponent.hp_percent",op,
                       percentage(op.text)!)]
            let ownNames=ts.filter{label($0.text) && $0.ref != hp.ref &&
                $0.x<0.50 && $0.y>=hp.y-0.15 &&
                $0.y<hp.y-0.008 && abs($0.x-hp.x)<0.20}
            let oppNames=ts.filter{label($0.text) && $0.ref != op.ref &&
                $0.x>0.54 && $0.y>=max(0,op.y-0.15) &&
                $0.y<op.y+0.008 && abs($0.x-op.x)<0.24}
            if ownNames.count==1 {
                matches.append(record("own.active_species",ownNames[0],
                      ownNames[0].text.replacingOccurrences(of:"♀",with:"")
                          .replacingOccurrences(of:"♂",with:"")))
                if let gender=sex(ownNames[0].text) {
                    matches.append(record("own.gender",ownNames[0],gender))
                }
            }
            if oppNames.count==1 {
                matches.append(record("opponent.active_species",oppNames[0],
                      oppNames[0].text.replacingOccurrences(of:"♀",with:"")
                          .replacingOccurrences(of:"♂",with:"")))
                if let gender=sex(oppNames[0].text) {
                    matches.append(record("opponent.gender",oppNames[0],gender))
                }
            }
            let clocks=ts.filter{$0.x>0.58 && $0.y>0.14 &&
                $0.y<0.43 && timer($0.text) != nil}
            if clocks.count==1 {
                matches.append(record("battle.timer",clocks[0],
                                      timer(clocks[0].text)!))
            }
            let pps=ts.filter{$0.x>0.73 && $0.y>0.35 &&
                $0.y<0.97 && fraction($0.text,pp:true) != nil}
            var slots=[[String:Any]](); var used=Set<String>()
            for pp in pps.sorted(by:{$0.y<$1.y}) {
                let left=ts.filter { t in
                    label(t.text) && t.x>0.48 && t.x<pp.x &&
                    t.y>0.33 && abs(t.y-pp.y)<0.041 &&
                    pp.x-t.x<0.36 && !used.contains(t.ref)
                }
                guard left.count==1 else{continue}
                guard slots.allSatisfy({ abs(($0["row"] as? Double ?? -1)-pp.y)>0.065 })
                else{continue}
                let move=left[0]
                guard used.insert(pp.ref).inserted,
                      used.insert(move.ref).inserted else{continue}
                let f=fraction(pp.text,pp:true)!
                slots.append(["row":pp.y,"name":move.text,
                    "name_ref":move.ref,"pp_current":f[0],
                    "pp_maximum":f[1],"pp_ref":pp.ref,
                    "owner_verified":false])
            }
            if !slots.isEmpty {
                matches.append(["field":"own.moves_four",
                    "value":slots.map{$0["name"]!},
                    "evidence_refs":slots.map{$0["name_ref"]!},
                    "role":"SCREEN_MOVE_PANEL_ONLY",
                    "owner_verified":false])
                matches.append(["field":"own.pp_four",
                    "value":slots.map{["current":$0["pp_current"]!,
                         "maximum":$0["pp_maximum"]!]},
                    "evidence_refs":slots.map{$0["pp_ref"]!},
                    "role":"SCREEN_MOVE_PANEL_ONLY",
                    "owner_verified":false])
            }
            patterns.append(["degrees":deg,"matches":matches,
                             "move_slots":slots.count])
        }
        guard patterns.count==1,let candidate=patterns.first else {
            return hold(patterns.isEmpty ? "HOLD_NO_HUD_ANCHORS" :
                "HOLD_AMBIGUOUS_ROTATION")
        }
        return ["schema":schema,"status":"HUD_PLAIN_OCR_HYPOTHESES_ONLY",
            "rotation_candidate_degrees":candidate["degrees"]!,
            "matches":candidate["matches"]!,
            "move_pair_count":candidate["move_slots"]!,
            "candidate_count":(candidate["matches"] as! [[String:Any]]).count,
            "owner_verified":false,"orientation_verified":false,
            "mega_form_certified":false,"game_fields_certified":0,
            "current_state_eligible":false,
            "battle_advice_authorized":false]
    }
    static func audit(_ doc:[String:Any],sourceKind:String)->[String:Any] {
        guard ["LIVE_RETAINED_FRAME",
               "USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
              let prior=doc["r667_expanded_ocr_fields"] as? [String:Any],
              prior["status"] as? String=="EXPANDED_TEXT_CANDIDATES_ONLY",
              prior["owner_verified"] as? Bool==false,
              prior["game_fields_certified"] as? Int==0,
              let snap=doc["screen_read_state"] as? [String:Any],
              snap["source_validation"] as? String=="PASS_FRAME_BINDING_ONLY",
              snap["current_state_eligible"] as? Bool==false,
              snap["battle_advice_authorized"] as? Bool==false,
              let raw=sha(sourceKind=="LIVE_RETAINED_FRAME" ?
                          doc["png_sha256"] : doc["image_sha256"]),
              let analysis=sha(snap["image_sha256"]),
              let session=snap["capture_session_id"] as? String,
              !session.isEmpty,
              let frame=integer(snap["frame_id"]),frame>0,
              let epoch=integer(snap["epoch"]),epoch>0,
              let items=snap["ocr_source_inventory"] as? [[String:Any]],
              items.count<=288,
              let w=integer(doc["image_width"]),
              let h=integer(doc["image_height"]) else {
            return hold("HOLD_UNBOUND_SOURCE")
        }
        var aw=w,ah=h
        if raw != analysis {
            guard let p=doc["analysis_projection"] as? [String:Any],
                  p["status"] as? String=="DECLARED_GEOMETRY_ONLY",
                  p["raw_image_sha256"] as? String==raw,
                  p["analysis_image_sha256"] as? String==analysis,
                  p["capture_session_id"] as? String==session,
                  integer(p["frame_id"])==frame,
                  integer(p["epoch"])==epoch,
                  integer(p["raw_width"])==w,
                  integer(p["raw_height"])==h,
                  p["owner_certified"] as? Bool==false,
                  let pw=integer(p["analysis_width"]),
                  let ph=integer(p["analysis_height"]) else {
                return hold("HOLD_PROJECTION_SOURCE_MISMATCH")
            }
            aw=pw;ah=ph
        }
        var tokens=[Token](),seen=Set<String>()
        for row in items {
            guard let ref=row["evidence_ref"] as? String,
                  !ref.isEmpty,seen.insert(ref).inserted,
                  row["image_sha256"] as? String==analysis,
                  row["capture_session_id"] as? String==session,
                  integer(row["frame_id"])==frame,
                  integer(row["epoch"])==epoch,
                  row["owner_verified"] as? Bool==false,
                  let text=row["raw_text"] as? String,
                  !text.isEmpty,text.utf8.count<=160,
                  let box=row["roi"] as? [String:Any],
                  let x=integer(box["x"]),let y=integer(box["y"]),
                  let width=integer(box["width"]),
                  let height=integer(box["height"]),
                  width>0,height>0,x<aw,y<ah,
                  width<=aw-x,height<=ah-y else {
                return hold("HOLD_CORRUPT_OCR_SOURCE")
            }
            if ref.contains(".ocr_alternatives[") {continue}
            tokens.append(Token(ref:ref,text:text,
                x:(Double(x)+Double(width)/2)/Double(aw),
                y:(Double(y)+Double(height)/2)/Double(ah),
                w:Double(width)/Double(aw),
                h:Double(height)/Double(ah)))
        }
        var result=scan(tokens,width:aw,height:ah)
        result["source_image_sha256"]=raw
        result["analysis_image_sha256"]=analysis
        result["capture_session_id"]=session
        result["frame_id"]=frame
        result["epoch"]=epoch
        result["source_kind"]=sourceKind
        return result
    }
    static func enrich(_ doc:inout [String:Any],sourceKind:String) {
        doc["r668_plain_hud_ocr"]=audit(doc,sourceKind:sourceKind)
    }
}
