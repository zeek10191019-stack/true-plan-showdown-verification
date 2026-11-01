import Foundation

/// R577: The same exact imported PNG must bind all offline Vision, layout and
/// Mega text evidence. Reports are diagnostic only; user must explicitly share.
/// Never grant live battle state or Mega/form/owner certification from this file.
enum R577OfflineEvidenceReport {
    static let schema = "trueplan.r577.offline-ocr-mega-diagnostic.v1"
    static let maximumReportBytes = 6_000_000
    static func encode(sourceSHA: String, width: Int, height: Int,
                       sourceBytes: Int, packetJSON: String,
                       snapshot: [String:Any], mega: [String:Any]) -> Data? {
        let bytes=Array(sourceSHA.utf8)
        guard bytes.count==64,bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              width>0,height>0,width<=8192,height<=8192,
              width*height<=36_000_000,(45...R576OfflinePNGImportGate.limitBytes).contains(sourceBytes),
              (1...2_000_000).contains(packetJSON.utf8.count),
              let packetBytes=packetJSON.data(using:.utf8),
              let parsed=(try? JSONSerialization.jsonObject(with:packetBytes)) as? [String:Any],
              parsed["image_sha256"] as? String==sourceSHA,
              (parsed["frame_id"] as? NSNumber)?.int64Value==1,
              (parsed["epoch"] as? NSNumber)?.int64Value==1,
              snapshot["image_sha256"] as? String==sourceSHA,
              snapshot["current_state_eligible"] as? Bool==false,
              snapshot["battle_advice_authorized"] as? Bool==false,
              mega["image_sha256"] as? String==sourceSHA,
              mega["mega_certified"] as? Bool==false,
              mega["visual_form_certified"] as? Bool==false else {return nil}
        let report:[String:Any]=[
          "schema":schema,"source_kind":"USER_IMPORTED_PNG_OFFLINE_ONLY",
          "image_sha256":sourceSHA,"image_width":width,"image_height":height,"png_bytes":sourceBytes,
          "capture_session_id":NSNull(),"real_game_accuracy_certified":false,
          "capture_time_calibrated":false,"owner_certified":false,"turn_certified":false,
          "mega_form_visual_certified":false,"current_state_eligible":false,
          "battle_advice_authorized":false,"user_opt_in_share_required":true,
          "source_png_in_report":false,"ground_truth_labels_present":false,
          "payload":parsed,"snapshot":snapshot,"mega_text_probe":mega]
        guard JSONSerialization.isValidJSONObject(report),
              let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.withoutEscapingSlashes]),
              data.count<=maximumReportBytes else {return nil}
        return data
    }
}
