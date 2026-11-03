import Foundation

// R671: classify candidate icon glyphs against separately reviewed game-frame
// templates. Labels are hypotheses until actual-game held-out validation.
// A colored blob, HUD position or an unreviewed template proves no condition.
enum R671StatusGlyphMatcher {
    static let schema="trueplan.r671.reviewed-status-glyph-match.v1"
    static let classes:Set<String>=["BURN","PARALYSIS","POISON","TOXIC",
                                    "SLEEP","FREEZE","NONE"]
    static let families:Set<String>=["WARM","YELLOW","GREEN_HP_LIKE",
                                     "BLUE_CYAN","VIOLET"]
    private static func hash(_ s:String)->Bool {
        s.utf8.count==64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func validShape(_ s:String)->Bool {
        s.utf8.count==16 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    private static func distance(_ a:String,_ b:String)->Int {
        zip(a.utf8,b.utf8).reduce(0) { count,pair in
            let l=Int(String(UnicodeScalar(pair.0)),radix:16) ?? 0
            let r=Int(String(UnicodeScalar(pair.1)),radix:16) ?? 0
            return count+(l^r).nonzeroBitCount
        }
    }
    private static func hold(_ why:String)->[String:Any] {
        ["schema":schema,"status":why,"candidates":[[String:Any]](),
         "classified_candidate_count":0,"owner_certified":false,
         "status_icon_class_certified":false,"current_state_eligible":false,
         "battle_advice_authorized":false,"accuracy":"NOT_MEASURED"]
    }
    static func loadReferences(at url:URL)->[[String:Any]] {
        guard let d=try? Data(contentsOf:url),d.count>0,d.count<=200_000,
              let o=try? JSONSerialization.jsonObject(with:d) as? [String:Any],
              o["schema"] as? String=="trueplan.r671.user-reviewed-reference-library.v1",
              let a=o["references"] as? [[String:Any]],a.count<=256 else {return []}
        return a
    }
    static func audit(frames:[[String:Any]],references:[[String:Any]])
        ->[String:Any] {
        guard frames.count<=8,references.count<=256 else {
            return hold("HOLD_CAPACITY")
        }
        guard !references.isEmpty else {return hold("HOLD_NO_REVIEWED_REFERENCES")}
        var byClass=[String:[(shape:String,source:String)]]()
        var ids=Set<String>()
        for r in references {
            guard let label=r["label"] as? String,classes.contains(label),
                  let family=r["color_family"] as? String,families.contains(family),
                  let shape=r["silhouette_8x8_hex"] as? String,validShape(shape),
                  let sha=r["source_image_sha256"] as? String,hash(sha),
                  let id=r["reference_id"] as? String,!id.isEmpty,
                  id.utf8.count<=100,ids.insert(id).inserted,
                  r["review_kind"] as? String=="USER_REVIEWED_REAL_GAME_CROP" else {
                return hold("HOLD_UNREVIEWED_OR_INVALID_REFERENCE")
            }
            byClass[label+"|"+family,default:[]].append((shape,sha))
        }
        // Two distinct source frames per class, plus a NONE control, prevent
        // a duplicate image from fabricating class support.
        let supported=byClass.filter {Set($0.value.map{$0.source}).count>=2}
        guard supported.keys.contains(where:{$0.hasPrefix("NONE|")}),
              supported.keys.contains(where:{!$0.hasPrefix("NONE|")}) else {
            return hold("HOLD_NO_INDEPENDENT_POSITIVE_AND_NEGATIVE_CONTROLS")
        }
        var out=[[String:Any]](),total=0
        for frame in frames {
            guard frame["schema"] as? String==R670HUDPixelGlyphs.schema,
                  frame["status"] as? String ==
                    "HISTORICAL_HUD_RGBA_GLYPH_CANDIDATES_ONLY",
                  let sha=frame["raw_image_sha256"] as? String,hash(sha),
                  let epoch=frame["epoch"] as? Int64,epoch>0,
                  let fid=frame["frame_id"] as? Int64,fid>0,
                  let glyphs=frame["candidates"] as? [[String:Any]],
                  glyphs.count<=96 else {
                return hold("HOLD_FRAME_OR_GLYPH_PROVENANCE")
            }
            for glyph in glyphs {
                guard let shape=glyph["silhouette_8x8_hex_unlabeled"] as? String,
                      validShape(shape),
                      let family=glyph["color_family_unclassified"] as? String,
                      families.contains(family),
                      let region=glyph["position_hint"] as? String,
                      ["OWN_HUD_POSITION_ONLY","OPPONENT_HUD_POSITION_ONLY"].contains(region),
                      glyph["owner_verified"] as? Bool==false,
                      glyph["current_state_eligible"] as? Bool==false else {
                    return hold("HOLD_UNTRUSTED_GLYPH_INPUT")
                }
                // Every distance candidate excludes its own source frame.
                var ranks=[(label:String,d:Int)]()
                for (key,rows) in supported {
                    let pair=key.split(separator:"|",omittingEmptySubsequences:false)
                    guard pair.count==2,String(pair[1])==family else {continue}
                    let usable=rows.filter{$0.source != sha}
                    guard Set(usable.map{$0.source}).count>=2 else {continue}
                    if let best=usable.map({distance(shape,$0.shape)}).min() {
                        ranks.append((String(pair[0]),best))
                    }
                }
                ranks.sort { $0.d == $1.d ? $0.label<$1.label : $0.d<$1.d }
                guard let best=ranks.first else {continue}
                let runner=ranks.first(where:{$0.label != best.label})
                // Missing competitor, close competitor, or weak image match -> UNKNOWN.
                guard let second=runner,best.d<=8,second.d-best.d>=6 else {continue}
                let row:[String:Any]=[
                    "status_label_candidate":best.label,
                    "status":"REVIEWED_TEMPLATE_VISUAL_CANDIDATE_ONLY",
                    "distance":best.d,"competing_distance":second.d,
                    "reference_class_count":supported.count,
                    "image_sha256":sha,"frame_id":fid,"epoch":epoch,
                    "color_family":family,"position_hint":region,
                    "owner":"UNKNOWN","owner_certified":false,
                    "status_icon_class_certified":false,
                    "current_state_eligible":false,
                    "battle_advice_authorized":false]
                out.append(row);total+=1
            }
        }
        return ["schema":schema,
                "status":"REVIEWED_ICON_TEMPLATE_CANDIDATES_NOT_CERTIFIED",
                "candidate_count":total,"candidates":out,
                "supported_label_color_classes":supported.count,
                "owner_certified":false,"status_icon_class_certified":false,
                "current_state_eligible":false,
                "battle_advice_authorized":false,"accuracy":"NOT_MEASURED",
                "limitations":"Only user-reviewed references, no certified " +
                    "screen orientation, player identity or held-out accuracy."]
    }
}
