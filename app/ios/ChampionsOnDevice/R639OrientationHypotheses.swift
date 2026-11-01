import Foundation
import CoreFoundation

/// Four-way geometric OCR anchor probe. Never treats an orientation hypothesis
/// as a physical device calibration, player identity, or live battle state.
enum R639OrientationHypotheses {
    static let schema = "trueplan.r639.orientation-anchor-probe.v1"
    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,n.doubleValue >= 0,
              n.doubleValue < Double(Int.max),
              n.doubleValue == Double(n.intValue) else {return nil}
        return n.intValue
    }
    private static func validSHA(_ s:String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    struct Rect {
        let x:Int, y:Int, w:Int, h:Int
        init?(_ raw:Any?, width:Int,height:Int) {
            guard let r=raw as? [String:Any],
                  let x=integer(r["x"]),let y=integer(r["y"]),
                  let w=integer(r["width"]),let h=integer(r["height"]),
                  width>0,height>0,x<width,y<height,w>0,h>0,
                  w<=width-x,h<=height-y else {return nil}
            self.x=x;self.y=y;self.w=w;self.h=h
        }
        private init(x:Int,y:Int,w:Int,h:Int) {
            self.x=x;self.y=y;self.w=w;self.h=h
        }
        func rotated(_ turn:Int,width:Int,height:Int)->Rect {
            switch turn {
            case 90: return Rect(x:height-y-h,y:x,w:h,h:w)
            case 180: return Rect(x:width-x-w,y:height-y-h,w:w,h:h)
            case 270: return Rect(x:y,y:width-x-w,w:h,h:w)
            default: return self
            }
        }
        func inside(_ area:(Double,Double,Double,Double), width:Int,height:Int)->Bool {
            let sx=Double(x)/Double(width),sy=Double(y)/Double(height)
            let sw=Double(w)/Double(width),sh=Double(h)/Double(height)
            let overlap=max(0,min(area.0+area.2,sx+sw)-max(area.0,sx)) *
                        max(0,min(area.1+area.3,sy+sh)-max(area.1,sy))
            return overlap/(sw*sh) >= 0.90
        }
    }
    private static func kind(_ text:String)->Set<String> {
        var s=text.replacingOccurrences(of:" ",with:"")
        s=s.replacingOccurrences(of:"　",with:"")
        if s.hasPrefix("HP") {s=String(s.dropFirst(2))}
        var out=Set<String>()
        if s.range(of:#"^[0-9]{1,4}/[0-9]{1,4}$"#,options:.regularExpression) != nil {
            let parts=s.split(separator:"/").compactMap{Int($0)}
            if parts.count==2 && parts[1]>0 && parts[0]<=parts[1] {out.insert("own_hp")}
        }
        if s.range(of:#"^[0-9]{1,3}(\.[0-9]{1,2})?%$"#,options:.regularExpression) != nil,
           let percent=Double(s.dropLast()),(0...100).contains(percent) {
            out.insert("opponent_percent")
        }
        if s.uppercased()=="COMMAND" {out.insert("command")}
        return out
    }
    private static let regions:[(String,(Double,Double,Double,Double))] = [
        ("own_hp",(0.15,0.90,0.12,0.08)),
        ("opponent_percent",(0.84,0.10,0.09,0.07)),
        ("command",(0.78,0.20,0.10,0.06))
    ]
    static func enrich(_ doc:inout [String:Any],sourceKind:String) {
        doc["r639_status"]="HOLD_SOURCE_AND_ORIENTATION_UNVERIFIED"
        guard ["LIVE_RETAINED_FRAME","USER_IMPORTED_PNG_OFFLINE_ONLY"].contains(sourceKind),
              doc["r638_status"] as? String == "SOURCE_AND_LAYOUT_BOUND_HISTORICAL_ONLY",
              let audit=doc["r638_binding_audit"] as? [String:Any],
              audit["schema"] as? String == "trueplan.r638.full-ocr-layout-binding.v1",
              audit["source_kind"] as? String == sourceKind,
              integer(audit["game_fields_certified"]) == 0,
              audit["owner_verified"] as? Bool == false,
              audit["source_orientation_verified"] as? Bool == false,
              let snapshot=doc["screen_read_state"] as? [String:Any],
              snapshot["current_state_eligible"] as? Bool == false,
              snapshot["battle_advice_authorized"] as? Bool == false,
              let hash=snapshot["image_sha256"] as? String,validSHA(hash),
              audit["image_sha256"] as? String == hash,
              let session=snapshot["capture_session_id"] as? String,!session.isEmpty,
              let frame=integer(snapshot["frame_id"]),frame>0,
              let epoch=integer(snapshot["epoch"]),epoch>0,
              let w=integer(doc["image_width"]),let h=integer(doc["image_height"]),
              (180...8192).contains(w),(180...8192).contains(h),
              let inventory=snapshot["ocr_source_inventory"] as? [[String:Any]],
              inventory.count<=288 else {return}
        var tokens=[(Rect,Set<String>)]()
        var seen=Set<String>()
        for row in inventory {
            guard row["image_sha256"] as? String == hash,
                  row["capture_session_id"] as? String == session,
                  integer(row["frame_id"]) == frame,
                  integer(row["epoch"]) == epoch,
                  row["owner_verified"] as? Bool == false,
                  let ref=row["evidence_ref"] as? String,!ref.isEmpty,
                  ref.utf8.count<=160,seen.insert(ref).inserted,
                  let raw=row["raw_text"] as? String,raw.utf8.count<=160,
                  let r=Rect(row["roi"],width:w,height:h) else {
                doc["r639_status"]="HOLD_BAD_OCR_INVENTORY";return
            }
            tokens.append((r,kind(raw)))
        }
        var profiles=[[String:Any]]()
        var unique=[Int]()
        for turn in [0,90,180,270] {
            let rw=turn%180==0 ? w : h
            let rh=turn%180==0 ? h : w
            let aspect=Double(rw)/Double(rh)
            let supported=rw>=400 && rh>=180 &&
                          abs(aspect-578.0/267.0)<0.025
            var counts=[String:Int]()
            for (name,area) in regions {
                counts[name]=supported ? tokens.filter{
                    $0.1.contains(name) && $0.0.rotated(turn,width:w,height:h)
                      .inside(area,width:rw,height:rh)
                }.count : 0
            }
            let anchors=regions.filter{counts[$0.0]==1}.count
            let candidate=supported && anchors==3
            if candidate {unique.append(turn)}
            profiles.append(["clockwise_degrees":turn,
                             "rotated_image_width":rw,
                             "rotated_image_height":rh,
                             "landscape_profile_supported":supported,
                             "own_hp_anchor_count":counts["own_hp"] ?? 0,
                             "opponent_percent_anchor_count":counts["opponent_percent"] ?? 0,
                             "command_anchor_count":counts["command"] ?? 0,
                             "three_anchor_candidate":candidate,
                             "orientation_verified":false])
        }
        let status=unique.count==1 ? "UNIQUE_ROTATION_HYPOTHESIS_NOT_CERTIFIED" :
          unique.isEmpty ? "HOLD_NO_THREE_ANCHOR_ROTATION" :
                           "HOLD_MULTIPLE_ROTATION_MATCHES"
        doc["r639_orientation_probe"]=[
            "schema":schema,"source_kind":sourceKind,"image_sha256":hash,
            "frame_id":frame,"epoch":epoch,"capture_session_id":session,
            "profiles":profiles,"candidate_rotation_clockwise":
                unique.count==1 ? unique[0] as Any : NSNull(),
            "orientation_verified":false,"owner_verified":false,
            "game_fields_certified":0,"battle_advice_authorized":false,
            "requires_real_frame_orientation_calibration":true,"status":status
        ] as [String:Any]
        doc["r639_status"]=status
    }
}
