import Foundation

/// Audit-only combined export of actual R519/R520/R521 snapshots.
/// Different scope counters are NEVER treated as a single frame or a single battle.
public enum R528DiagnosticCore {
    public static func assemble(r519:String,r520:String,r521:String,
                                epoch:Int?,frame:Int?) throws -> Data {
        let base=try DiagnosticsPacket.assemble(visionJSON:r519,sessionJSON:r520,
               collisionJSON:r521,build:"R27.528",frameID:frame,epoch:epoch)
        guard var envelope=try JSONSerialization.jsonObject(with:base) as? [String:Any] else {
            throw NSError(domain:"R528Export",code:1)
        }
        envelope["schema"]="R528_ACTUAL_APP_THREE_SOURCE_DIAGNOSTICS_V1"
        envelope["source_scopes"]=[
            "r519_vision":"APP_LIFETIME",
            "r520_roi_session":"LATEST_CAPTURE_SESSION",
            "r521_roi_collision":"APP_LIFETIME"]
        envelope["all_sources_same_frame_certified"]=false
        envelope["owner_certified"]=false
        envelope["image_orientation_certified"]=false
        envelope["battle_advice_authorized"]=false
        envelope["notes"]="Capture-session values and app-lifetime counters are NOT one synchronous frame."
        return try JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys])
    }
}
