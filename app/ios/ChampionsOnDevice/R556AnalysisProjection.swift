import Foundation
import CoreFoundation
import CryptoKit

/// Declared image operations and integer ROI mapping. This never establishes
/// game orientation, owner, capture age, or the truth of OCR text.
enum R556AnalysisProjection {
    struct Rect: Equatable {
        let x: Int,y: Int,width: Int,height: Int
        var object: [String:Int] {["x":x,"y":y,"width":width,"height":height]}
        func fits(width w: Int,height h: Int) -> Bool {
            x>=0 && y>=0 && width>0 && height>0 && x<=w && y<=h && width<=w-x && height<=h-y
        }
    }
    struct Plan: Equatable {
        let rawWidth: Int,rawHeight: Int,crop: Rect,quarterTurnsCCW: Int
        var valid: Bool {
            rawWidth>0 && rawHeight>0 && rawWidth<=3072 && rawHeight<=3072 &&
            rawWidth*rawHeight<=4_500_000 && (0...3).contains(quarterTurnsCCW) && crop.fits(width:rawWidth,height:rawHeight)
        }
        var analysisWidth: Int {quarterTurnsCCW%2==0 ? crop.width : crop.height}
        var analysisHeight: Int {quarterTurnsCCW%2==0 ? crop.height : crop.width}
        func sourceRect(_ analysis: Rect) -> Rect? {
            guard valid,analysis.fits(width:analysisWidth,height:analysisHeight) else {return nil}
            let rect: Rect
            switch quarterTurnsCCW {
            case 0:rect=analysis
            case 1:rect=Rect(x:crop.width-analysis.y-analysis.height,y:analysis.x,width:analysis.height,height:analysis.width)
            case 2:rect=Rect(x:crop.width-analysis.x-analysis.width,y:crop.height-analysis.y-analysis.height,width:analysis.width,height:analysis.height)
            case 3:rect=Rect(x:analysis.y,y:crop.height-analysis.x-analysis.width,width:analysis.height,height:analysis.width)
            default:return nil
            }
            return Rect(x:crop.x+rect.x,y:crop.y+rect.y,width:rect.width,height:rect.height)
        }
    }
    static func integer(_ value: Any?) -> Int? {
        guard let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,number.doubleValue.rounded()==number.doubleValue,
              number.doubleValue>=0,number.doubleValue<=Double(Int32.max) else {return nil}
        return number.intValue
    }
    private static func identity(_ value: Any?) -> Int64? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,
              n.doubleValue>=0,n.doubleValue<Double(Int64.max),n.doubleValue==Double(n.int64Value) else {return nil}
        return n.int64Value
    }
    private static func falseBoolean(_ value: Any?) -> Bool {
        guard let n=value as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else {return false}
        return !n.boolValue
    }
    static func rect(_ object: Any?) -> Rect? {
        guard let d=object as? [String:Any],Set(d.keys)==Set(["x","y","width","height"]),
              let x=integer(d["x"]),let y=integer(d["y"]),let w=integer(d["width"]),let h=integer(d["height"]) else {return nil}
        return Rect(x:x,y:y,width:w,height:h)
    }
    private static func hash(_ data: Data) -> String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
    private static func sha(_ value: String) -> Bool {
        value.utf8.count==64 && value.utf8.allSatisfy {(48...57).contains($0)||(97...102).contains($0)}
    }
    static func report(plan: Plan,envelope: String,session: String,frame: Int64,epoch: Int64,
                       observedMs: Int64,rawSHA: String,analysisSHA: String) -> [String:Any] {
        var result:[String:Any]=["schema":"trueplan.screen-read.analysis-projection.v1",
            "status":"HOLD","reason":"MISSING_OR_MISMATCHED_SOURCE","capture_session_id":session,
            "frame_id":frame,"epoch":epoch,"receipt_uptime_ms":observedMs,
            "raw_image_sha256":rawSHA,"analysis_image_sha256":analysisSHA,
            "raw_width":plan.rawWidth,"raw_height":plan.rawHeight,"pixel_crop":plan.crop.object,
            "quarter_turns_ccw":plan.quarterTurnsCCW,"analysis_width":plan.analysisWidth,"analysis_height":plan.analysisHeight,
            "coordinate_convention":"HALF_OPEN_PIXELS_TOP_LEFT","transform":"INTEGER_CROP_THEN_CCW_QUARTER_TURN",
            "pixel_equality_verified":false,"game_orientation_certified":false,"owner_certified":false,
            "mapped_rois":[[String:Any]](),"omitted_rois":[[String:Any]](),
            "current_state_eligible":false,"battle_advice_authorized":false,"battle_id":NSNull(),"turn":NSNull()]
        guard plan.valid,!session.isEmpty,session.utf8.count<=128,frame>0,epoch>0,observedMs>0,
              sha(rawSHA),sha(analysisSHA),envelope.utf8.count<=2_000_000,
              let wrapper=try? JSONSerialization.jsonObject(with:Data(envelope.utf8)) as? [String:Any],
              wrapper["schema"] as? String=="trueplan.mobile-envelope.v1",
              let payload=wrapper["payload_json"] as? String,wrapper["payload_sha256"] as? String==hash(Data(payload.utf8)),
              let packet=try? JSONSerialization.jsonObject(with:Data(payload.utf8)) as? [String:Any],
              packet["schema"] as? String=="trueplan.mobile-observation.v1",packet["battle_id"] as? String==session,
              identity(packet["frame_id"])==frame,identity(packet["epoch"])==epoch,
              identity(packet["observed_at_ms"])==observedMs,packet["image_sha256"] as? String==analysisSHA,
              falseBoolean(packet["production_enabled"]),
              let rows=packet["readings"] as? [[String:Any]],rows.count<=512 else {return result}
        var mapped=[[String:Any]](),omitted=[[String:Any]]()
        for (index,row) in rows.enumerated() where row["reason"] as? String=="FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND" {
            let reference="payload_json.readings[\(index)]"
            guard identity(row["source_frame_id"])==frame,
                  identity(row["source_epoch"])==epoch,row["source_image_sha256"] as? String==analysisSHA,
                  falseBoolean(row["roi_owner_certified"]),
                  row["roi_source"] as? String=="VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED",
                  let analysis=rect(row["roi_rect"]),let source=plan.sourceRect(analysis) else {
                omitted.append(["evidence_ref":reference,"reason":"ROI_MISSING_OR_UNBOUND"]);continue
            }
            mapped.append(["evidence_ref":reference,"analysis_rect":analysis.object,"raw_rect":source.object])
        }
        result["status"]="DECLARED_GEOMETRY_ONLY";result["reason"]="OCR_MEANING_AND_PER_FRAME_PIXEL_EQUALITY_UNCERTIFIED"
        result["mapped_rois"]=mapped;result["omitted_rois"]=omitted
        return result
    }
}
