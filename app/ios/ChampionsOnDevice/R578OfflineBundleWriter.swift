import Foundation
import CryptoKit

/// Three-file STORE ZIP; no background upload, no automatic disclosure.
/// original.png can contain on-screen personal information: explicit user share only.
enum R578OfflineBundleWriter {
    enum Failure: Error { case inconsistentSource, inconsistentManifest }
    static func write(png:Data,diagnostic:Data,sourceSHA:String,to destination:URL) throws -> Int {
        guard R578OfflineBundlePolicy.accepts(png,diagnostic,sourceSHA:sourceSHA) else {
            throw Failure.inconsistentSource
        }
        func digest(_ data:Data)->String {SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()}
        guard digest(png)==sourceSHA else {throw Failure.inconsistentSource}
        let entries:[R548ResearchArchive.Entry]=[
            .init(name:"original.png",bytes:png),
            .init(name:"diagnostic.json",bytes:diagnostic)
        ]
        let manifest:[String:Any]=[
            "schema":R578OfflineBundlePolicy.schema,
            "source_kind":"USER_IMPORTED_PNG_OFFLINE_ONLY",
            "image_sha256":sourceSHA,
            "entries":entries.map {["path":$0.name,"bytes":$0.bytes.count,
                                   "sha256":digest($0.bytes),
                                   "crc32":UInt64(R548ResearchArchive.crc32($0.bytes))] as [String:Any]},
            "capture_session_id":NSNull(),"turn":NSNull(),
            "current_state_eligible":false,"owner_certified":false,
            "mega_visual_certified":false,"game_accuracy_certified":false,
            "battle_advice_authorized":false,
            "user_explicit_share_required":true,
            "bundle_contains_original_png":true,
            "integrity_scope":"LOCAL_BYTE_CONSISTENCY_ONLY_NOT_AUTHENTICITY"
        ]
        guard JSONSerialization.isValidJSONObject(manifest) else {throw Failure.inconsistentManifest}
        let index=try JSONSerialization.data(withJSONObject:manifest,options:[.sortedKeys,.withoutEscapingSlashes])
        return try R548ResearchArchive.write(entries + [.init(name:"manifest.json",bytes:index)],to:destination)
    }
}
