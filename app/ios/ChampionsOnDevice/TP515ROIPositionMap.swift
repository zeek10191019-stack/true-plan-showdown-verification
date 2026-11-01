import Foundation
import CoreFoundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// R515: graphical *diagnostic* of positions supplied by R514 redacted JSON.
/// It is a raw-capture-pixel map, not an image analysis nor proof of ownership.
/// Never consume this model as a battle decision or a Pokémon identification.
enum TP515ROIPositionMap {
    enum Verdict: String {
        case ready = "R515_REFERENCE_MAP_UNCERTIFIED"
        case incomplete = "R515_PACKET_NOT_READY"
        case invalid = "R515_PACKET_INVALID"
    }
    struct Box: Identifiable {
        let id: Int
        let kind: String
        let claimOnly: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        var ownerCertified: Bool { false }
    }
    struct Model {
        let verdict: Verdict
        let width: Int
        let height: Int
        let boxes: [Box]
        let missing: Int
        let outside: Int
        let total: Int
        var decisionEligible: Bool { false }
        var concise: String {
            "R515位置図:" + verdict.rawValue + " 表示\(boxes.count)/\(total) 欠落\(missing) 画外\(outside) 自他未認証"
        }
    }
    private static func nonnegative(_ raw: Any?) -> Int? {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i = Int(n.stringValue), i >= 0 else { return nil }
        return i
    }
    private static func failed(_ verdict: Verdict) -> Model {
        Model(verdict:verdict,width:0,height:0,boxes:[],missing:0,outside:0,total:0)
    }
    static func parse(_ packet: String?) -> Model {
        guard let packet, packet.utf8.count <= 12_000,
              let bytes=packet.data(using:.utf8),
              let data=(try? JSONSerialization.jsonObject(with:bytes)) as? [String: Any]
        else { return failed(.invalid) }
        guard data["schema"] as? String == "R514_REDACTED_V1",
              let status = data["status"] as? String else { return failed(.invalid) }
        guard status == "R514_REDACTED_PACKET_READY_UNCERTIFIED" else { return failed(.incomplete) }
        guard data["owner_certified"] as? Bool == false,
              data["decision_eligible"] as? Bool == false,
              data["ocr_text_included"] as? Bool == false,
              data["image_bytes_included"] as? Bool == false,
              let w=nonnegative(data["capture_width"]),
              let h=nonnegative(data["capture_height"]),
              (1...16_384).contains(w), (1...16_384).contains(h),
              let total=nonnegative(data["readings_total"]), total<=256,
              let missing=nonnegative(data["missing_roi_total"]), missing<=total,
              let outside=nonnegative(data["outside_roi_total"]), outside<=total,
              let rows=data["exported"] as? [[String:Any]], rows.count<=10,
              rows.count<=total else {return failed(.invalid)}
        var seen=Set<Int>(), boxes=[Box]()
        for row in rows {
            guard let id=nonnegative(row["i"]), id<total, seen.insert(id).inserted,
                  row["owner_certified"] as? Bool == false,
                  let state=row["roi_state"] as? String,
                  ["inside","outside","missing","invalid","source_mismatch"].contains(state),
                  let rect=row["rect_xywh"] as? [Any], rect.count<=4,
                  let kind=row["kind"] as? String,
                  ["HP","PP","UNKNOWN"].contains(kind),
                  let claim=row["claim_only"] as? String,
                  ["OWN_HINT_ONLY","OPP_HINT_ONLY","OWN_KEY_CLAIM","OPP_KEY_CLAIM","UNKNOWN"].contains(claim)
            else {return failed(.invalid)}
            if state == "inside" {
                guard rect.count==4,
                      let x=nonnegative(rect[0]), let y=nonnegative(rect[1]),
                      let rw=nonnegative(rect[2]), let rh=nonnegative(rect[3]),
                      rw>0,rh>0,x<w,y<h,rw<=w-x,rh<=h-y else {return failed(.invalid)}
                boxes.append(Box(id:id,kind:kind,claimOnly:claim,
                                 x:x,y:y,width:rw,height:rh))
            } else if !rect.isEmpty && rect.count != 4 {
                return failed(.invalid)
            }
        }
        return Model(verdict:.ready,width:w,height:h,boxes:boxes,
                     missing:missing,outside:outside,total:total)
    }
}

#if canImport(SwiftUI)
/// Displayed next to the numeric R514 evidence; no capture image is retained.
/// ROI x/y are *capture PNG pixels*; orientation/mirroring are not yet calibrated.
struct TP515ROIPositionMapView: View {
    let packetJSON: String
    private var data: TP515ROIPositionMap.Model { TP515ROIPositionMap.parse(packetJSON) }
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            Text("R27.515｜ROI画素位置参照図（帰属未認証）")
                .font(.caption).foregroundColor(.orange)
            if data.verdict == .ready {
                Text("PNG \(data.width)×\(data.height)｜検出ROI \(data.boxes.count)/\(data.total)｜回転・鏡像未較正")
                    .font(.caption2)
                GeometryReader { geometry in
                    let scale = min(geometry.size.width/CGFloat(data.width),
                                    geometry.size.height/CGFloat(data.height))
                    ZStack(alignment:.topLeading) {
                        Rectangle().fill(Color.gray.opacity(0.15))
                            .overlay(Rectangle().stroke(Color.secondary,lineWidth:1))
                            .frame(width:CGFloat(data.width)*scale,
                                   height:CGFloat(data.height)*scale)
                        ForEach(data.boxes) { roi in
                            Rectangle().stroke(roi.kind == "HP" ? Color.orange : Color.blue,
                                                lineWidth:2)
                                .frame(width:CGFloat(roi.width)*scale,
                                       height:CGFloat(roi.height)*scale)
                                .position(x:(CGFloat(roi.x)+CGFloat(roi.width)/2)*scale,
                                          y:(CGFloat(roi.y)+CGFloat(roi.height)/2)*scale)
                        }
                    }
                    .frame(width:CGFloat(data.width)*scale,
                           height:CGFloat(data.height)*scale,
                           alignment:.topLeading)
                }
                .frame(height:200)
                Text("枠は未検証の座標候補のみ。HP=橙、PP=青。画面実画像との一致・自他帰属は未認証。")
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                Text("位置図生成保留："+data.verdict.rawValue)
                    .font(.caption2).foregroundColor(.orange)
            }
        }
    }
}
#endif
