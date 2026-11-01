import Foundation

/// Validation before invoking the SAME R558 Vision reader as live capture.
/// Offline images NEVER establish current battle state or automatic Mega identity.
enum R576OfflinePNGImportGate {
    enum Verdict: Equatable { case accepted(width:Int,height:Int); case rejected }
    static let limitBytes=12_000_000
    static func validate(_ data:Data)->Verdict {
        guard (45...limitBytes).contains(data.count) else {return .rejected}
        let a=[UInt8](data.prefix(33))
        guard Array(a[0..<8]) == [137,80,78,71,13,10,26,10],
              Array(a[8..<12]) == [0,0,0,13],Array(a[12..<16])==Array("IHDR".utf8),
              Array(data.suffix(12)) == [0,0,0,0,73,69,78,68,174,66,96,130] else {return .rejected}
        func num(_ i:Int)->Int {a[i..<i+4].reduce(0){($0<<8)|Int($1)}}
        let w=num(16),h=num(20)
        guard w>0,h>0,w<=8192,h<=8192,Double(w)*Double(h)<=36_000_000 else {return .rejected}
        return .accepted(width:w,height:h)
    }
    static func proof(width:Int,height:Int,sha:String,byteCount:Int)->[String:Any] {
        ["schema":"trueplan.r576.offline-exact-png-import.v1",
         "source_kind":"OFFLINE_EXACT_PNG", "image_sha256":sha,
         "image_width":width,"image_height":height,"png_bytes":byteCount,
         "current_state_eligible":false,"owner_certified":false,
         "identity_certified":false,"mega_form_visual_certified":false,
         "battle_advice_authorized":false,"game_accuracy_certified":false,
         "capture_time_calibrated":false,"source":"USER_SELECTED_LOCAL_FILE_NO_AUTOMATIC_UPLOAD"]
    }
}
