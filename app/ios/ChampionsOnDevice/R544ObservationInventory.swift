import Foundation
import CoreFoundation

/// Research-only: inventory possible numeric / field-effect observations from
/// the SAME selected frame. It never assigns own/opponent, HP versus PP,
/// Pokemon identity, turn, state or a battle command.
enum R544ObservationInventory {
    static let schema = "trueplan.r544.unattributed-observation-inventory.v1"
    private static let categories = [
        "AMBIGUOUS_FRACTION_HP_OR_PP", "UNATTRIBUTED_PERCENT",
        "WEATHER_TEXT", "TERRAIN_TEXT", "STATUS_TEXT",
        "MEGA_TEXT", "SCREENS_TEXT", "STAT_CHANGE_TEXT"
    ]
    private static let lexical: [(String,[String])] = [
        ("WEATHER_TEXT", ["すなあらし","あめ","雨","ひざしがつよい","にほんばれ","はれ","晴れ","ゆき","雪","あられ"]),
        ("TERRAIN_TEXT", ["グラスフィールド","エレキフィールド","サイコフィールド","ミストフィールド"]),
        ("STATUS_TEXT", ["やけど","どく","もうどく","まひ","ねむり","こおり","ねむっている","こんらん"]),
        ("MEGA_TEXT", ["メガシンカ","メガ進化","メガバンギラス","メガギャラドス","メガグソクムシャ"]),
        ("SCREENS_TEXT", ["リフレクター","ひかりのかべ","オーロラベール"]),
        ("STAT_CHANGE_TEXT", ["こうげきがあがった","ぼうぎょがあがった","すばやさがあがった","とくこうがあがった","とくぼうがあがった","こうげきがさがった","ぼうぎょがさがった","すばやさがさがった","とくこうがさがった","とくぼうがさがった"])
    ]
    private static func int(_ value:Any?) -> Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,n.doubleValue==Double(n.int64Value),
              n.int64Value>=0,n.int64Value<=Int64(Int.max) else {return nil}
        return Int(n.int64Value)
    }
    private static func sourceVerified(_ row:[String:Any],frame:Int,epoch:Int,sha:String,
                                       width:Int,height:Int) -> Bool {
        guard int(row["source_frame_id"]) == frame,
              int(row["source_epoch"]) == epoch,
              row["source_image_sha256"] as? String == sha,
              row["roi_source"] as? String != nil,
              let roi=row["roi_rect"] as? [String:Any],
              let x=int(roi["x"]),let y=int(roi["y"]),
              let w=int(roi["width"]),let h=int(roi["height"]),
              w>0,h>0,x<width,y<height,w<=width-x,h<=height-y else {return false}
        return true
    }
    private static func classify(_ raw:String) -> [String] {
        let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=128 else {return []}
        let decimal=CharacterSet.decimalDigits
        func digits(_ s:Substring) -> Bool {
            !s.isEmpty && s.count<=5 && s.unicodeScalars.allSatisfy {decimal.contains($0)}
        }
        var found:[String]=[]
        let compact=text.replacingOccurrences(of:" ",with:"")
        let frac=compact.split(separator:"/",omittingEmptySubsequences:false)
        if frac.count==2 && digits(frac[0]) && digits(frac[1]) {
            found.append("AMBIGUOUS_FRACTION_HP_OR_PP")
        }
        let percent=compact.split(separator:"%",omittingEmptySubsequences:false)
        if percent.count==2 && digits(percent[0]) && percent[1].isEmpty {
            found.append("UNATTRIBUTED_PERCENT")
        }
        let lowered=text.lowercased()
        for (key,words) in lexical where words.contains(where:{ lowered == $0.lowercased() }) {
            found.append(key)
        }
        return found
    }
    static func inspect(_ root:[String:Any], frame:Int64,epoch:Int64) -> [String:Any] {
        var counts:[String:Int]=[:]
        var located:[String:Int]=[:]
        var unlocated:[String:Int]=[:]
        for key in categories {counts[key]=0;located[key]=0;unlocated[key]=0}
        var result:[String:Any] = [
            "schema":schema,"source_frame_id":frame,"source_epoch":epoch,
            "status":"NO_SAME_FRAME_OCR", "text_rows":0,"classified_rows":0,
            "classification_counts":counts,"located_counts":located,"unlocated_counts":unlocated,
            "max_rows":256,"owner_certified":false,"hp_pp_disambiguated":false,
            "mega_visual_certified":false,"field_state_certified":false,
            "battle_advice_authorized":false,
            "limitations":["TEXT_ONLY","NOT_OWNER_ASSIGNED","NOT_HP_PP_DISAMBIGUATED","NO_ICON_OR_ANIMATION_CLASSIFICATION"]
        ]
        guard let env=root["research_candidate_envelope"] as? String else {return result}
        result["status"]="INVALID_OR_MISMATCHED_OCR"
        guard let wrapper=try? JSONSerialization.jsonObject(with:Data(env.utf8)) as? [String:Any],
              let payload=wrapper["payload_json"] as? String,
              let object=try? JSONSerialization.jsonObject(with:Data(payload.utf8)) as? [String:Any],
              let rows=object["readings"] as? [[String:Any]],rows.count<=256,
              let f=int(object["frame_id"]),Int64(f)==frame,
              let e=int(object["epoch"]),Int64(e)==epoch,
              let analysis=root["analysis_image"] as? [String:Any],
              let sha=analysis["png_sha256"] as? String,sha.count==64,
              object["image_sha256"] as? String == sha,
              let width=int(analysis["width"]),let height=int(analysis["height"]),
              width>0,height>0,width<=8192,height<=8192 else {return result}
        var total=0,classified=0
        for row in rows {
            guard let raw=row["raw_text"] as? String,!raw.isEmpty else {continue}
            total += 1
            let types=classify(raw)
            guard !types.isEmpty else {continue}
            classified += 1
            let proven=sourceVerified(row,frame:f,epoch:e,sha:sha,width:width,height:height)
            for kind in types {
                counts[kind,default:0] += 1
                if proven {located[kind,default:0] += 1}
                else {unlocated[kind,default:0] += 1}
            }
        }
        result["status"]="UNATTRIBUTED_TEXT_CANDIDATES_ONLY"
        result["text_rows"]=total
        result["classified_rows"]=classified
        result["classification_counts"]=counts
        result["located_counts"]=located
        result["unlocated_counts"]=unlocated
        return result
    }
    static func verifyAttached(_ bytes:Data,frame:Int64,epoch:Int64) -> Bool {
        guard let root=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],
              let saved=root["r544_unattributed_observations"] as? [String:Any],
              saved["owner_certified"] as? Bool == false,
              saved["battle_advice_authorized"] as? Bool == false,
              saved["hp_pp_disambiguated"] as? Bool == false,
              saved["mega_visual_certified"] as? Bool == false,
              let left=try? JSONSerialization.data(withJSONObject:saved,options:[.sortedKeys]),
              let right=try? JSONSerialization.data(withJSONObject:inspect(root,frame:frame,epoch:epoch),options:[.sortedKeys])
        else {return false}
        return left==right
    }
}
