import Foundation
import CoreFoundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// R516: field-test readiness of the R514 redacted ROI evidence packet.
/// Not a classifier: an in-bounds rectangle never proves OWN/OPP or HP/PP.
/// A missing source ROI in live OCR must not be silently called ready.
enum TP516ROIReadiness {
    enum Status: String {
        case malformed = "INVALID_PACKET"
        case blocked = "SOURCE_PROOF_BLOCKED"
        case noObservations = "NO_OCR_READINGS"
        case roiMetadataAbsent = "ROI_METADATA_ABSENT"
        case roiMetadataIncomplete = "ROI_METADATA_INCOMPLETE"
        case locationUnresolved = "ROI_LOCATION_UNRESOLVED"
        case ownerUncertified = "ROI_OWNER_UNCERTIFIED"
    }
    struct Result {
        let status: Status
        let total: Int
        let sample: Int
        let missing: Int
        let outside: Int
        let inside: Int
        let sourceMismatch: Int
        let invalidROI: Int
        let unknownKind: Int
        let untrustedSideClaims: Int
        let truncated: Bool
        let captureWidth: Int
        let captureHeight: Int
        var decisionEligible: Bool { false }
        var ownerCertified: Bool { false }
        var hint: String {
            switch status {
            case .malformed: return "診断JSON形式に矛盾。元の証拠を確認"
            case .blocked: return "PNGハッシュ等が未認証。画像証拠の検証が先"
            case .noObservations: return "OCR観測が0件。画面取得/OCR起動を確認"
            case .roiMetadataAbsent: return "OCRにroi_rect画素座標がない。座標出力元の実装が必要"
            case .roiMetadataIncomplete: return "OCRのROI座標が欠落。フレーム別の取得箇所を確認"
            case .locationUnresolved: return "ROIが画外/不正/別フレーム。座標系・回転・時刻を確認"
            case .ownerUncertified: return "ROI候補はあるが、自他の帰属は実画面で未認証"
            }
        }
        var summary: String {
            "R516 \(status.rawValue)｜OCR\(total)件／表示対象\(sample)件／位置有\(inside)件／欠落\(missing)件／画外\(outside)件／出典不一致\(sourceMismatch)件／種別不明\(unknownKind)件／自他未認証"
        }
    }
    private static func unsigned(_ raw: Any?) -> Int? {
        guard let n=raw as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(),
              let i=Int(n.stringValue), i>=0 else{return nil}
        return i
    }
    private static func fail(_ reason: Status) -> Result {
        Result(status:reason,total:0,sample:0,missing:0,outside:0,
               inside:0,sourceMismatch:0,invalidROI:0,unknownKind:0,
               untrustedSideClaims:0,truncated:false,captureWidth:0,captureHeight:0)
    }
    static func parse(_ json: String?) -> Result {
        guard let json,json.utf8.count<=12_000,
              let bytes=json.data(using:.utf8),
              let root=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],
              root["schema"] as? String == "R514_REDACTED_V1",
              let rawStatus=root["status"] as? String,
              root["owner_certified"] as? Bool == false,
              root["decision_eligible"] as? Bool == false,
              root["ocr_text_included"] as? Bool == false
        else{return fail(.malformed)}
        if rawStatus == "R514_FRAME_OR_PNG_EVIDENCE_NOT_VERIFIED" ||
           rawStatus == "R514_WIRE_UNPARSABLE" {return fail(.blocked)}
        guard rawStatus == "R514_REDACTED_PACKET_READY_UNCERTIFIED",
              root["image_bytes_included"] as? Bool == false,
              let width=unsigned(root["capture_width"]), (1...16_384).contains(width),
              let height=unsigned(root["capture_height"]), (1...16_384).contains(height),
              let total=unsigned(root["readings_total"]),total<=256,
              let missing=unsigned(root["missing_roi_total"]),missing<=total,
              let outside=unsigned(root["outside_roi_total"]),outside<=total,
              missing+outside<=total,
              let truncated=root["truncated"] as? Bool,
              let rows=root["exported"] as? [[String:Any]],rows.count<=10,
              rows.count<=total,
              truncated == (total>rows.count)
        else{return fail(.malformed)}
        var seen=Set<Int>()
        var inside=0,sourceMismatch=0,invalidROI=0,unknown=0,claim=0
        var sampleMissing=0,sampleOutside=0
        for row in rows {
            guard let id=unsigned(row["i"]),id<total,seen.insert(id).inserted,
                  row["owner_certified"] as? Bool == false,
                  let category=row["kind"] as? String,
                  ["HP","PP","UNKNOWN"].contains(category),
                  let claimValue=row["claim_only"] as? String,
                  ["OWN_HINT_ONLY","OPP_HINT_ONLY","OWN_KEY_CLAIM","OPP_KEY_CLAIM","UNKNOWN"].contains(claimValue),
                  let roiState=row["roi_state"] as? String,
                  ["inside","outside","missing","invalid","source_mismatch"].contains(roiState),
                  let rect=row["rect_xywh"] as? [Any]
            else{return fail(.malformed)}
            if category == "UNKNOWN" {unknown+=1}
            if claimValue != "UNKNOWN" {claim+=1}
            switch roiState {
            case "inside":
                guard rect.count==4,
                      let x=unsigned(rect[0]),let y=unsigned(rect[1]),
                      let w=unsigned(rect[2]),let h=unsigned(rect[3]),
                      w>0,h>0,x<width,y<height,w<=width-x,h<=height-y
                else{return fail(.malformed)}
                inside+=1
            case "missing":
                guard rect.isEmpty else{return fail(.malformed)}
                sampleMissing+=1
            case "outside":
                guard rect.count==4,rect.allSatisfy({unsigned($0) != nil}) else{return fail(.malformed)}
                sampleOutside+=1
            case "source_mismatch":
                guard rect.isEmpty || rect.count==4 else{return fail(.malformed)}
                sourceMismatch+=1
            case "invalid":
                guard rect.isEmpty else{return fail(.malformed)}
                invalidROI+=1
            default: return fail(.malformed)
            }
        }
        guard sampleMissing<=missing,sampleOutside<=outside else{return fail(.malformed)}
        // These are *sampling* diagnostics. Truncation never proves an unseen ROI is absent.
        let status:Status
        if total==0 {status = .noObservations}
        else if missing==total {status = .roiMetadataAbsent}
        else if missing>0 {status = .roiMetadataIncomplete}
        else if inside==0 || sourceMismatch>0 || invalidROI>0 || outside>0 {status = .locationUnresolved}
        else {status = .ownerUncertified}
        return Result(status:status,total:total,sample:rows.count,missing:missing,
                      outside:outside,inside:inside,sourceMismatch:sourceMismatch,
                      invalidROI:invalidROI,unknownKind:unknown,
                      untrustedSideClaims:claim,truncated:truncated,
                      captureWidth:width,captureHeight:height)
    }
}

#if canImport(SwiftUI)
struct TP516ROIReadinessPanel: View {
    let packetJSON: String
    private var result: TP516ROIReadiness.Result {TP516ROIReadiness.parse(packetJSON)}
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text("R27.516｜実機OCR座標の不足原因（判定利用禁止）")
                .font(.caption).foregroundColor(.orange)
            Text(result.hint).font(.caption2)
            Text(result.summary).font(.caption2).textSelection(.enabled)
            if result.truncated {
                Text("先頭10件だけの表示。残りのROI位置は推定・合格判定しません")
                    .font(.caption2).foregroundColor(.orange)
            }
            if result.unknownKind>0 {
                Text("HP/PP未分類:先頭対象\(result.unknownKind)件（OCRキー欠落の可能性）")
                    .font(.caption2).foregroundColor(.orange)
            }
            Text("自他帰属・OCR正答率は未認証。Stage/Gateへ加算禁止")
                .font(.caption2).foregroundColor(.secondary)
        }
    }
}
#endif
