import Foundation

/// A research-only, human-labelled Mega observation attached to ONE selected image.
/// No appearance classifier, roster identity, action recommendation or auto-certification.
/// A displayed species name is separate from the form label and the proposed Mega state.
struct R547MegaManualRecord: Equatable {
    let sessionID: String
    let frameID: Int64
    let epoch: Int64
    let side: String
    let displayedSpecies: String
    let claimedForm: String
    let megaFormLabel: String
    let confirmationMethod: String

    static func make(sessionID: String, frameID: Int64, epoch: Int64,
                     side: String, species: String, form: String,
                     megaLabel: String, method: String) -> Self? {
        let cleanSpecies = species.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMega = megaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty, frameID > 0, epoch > 0,
              ["OWN", "OPPONENT"].contains(side),
              ["UNKNOWN", "BASE", "MEGA"].contains(form),
              ["BATTLE_DETAIL_MANUAL", "ON_FIELD_VISUAL_MANUAL", "UNVERIFIED"].contains(method),
              !cleanSpecies.isEmpty, cleanSpecies.count <= 48,
              cleanMega.count <= 64,
              !cleanSpecies.contains("\n"), !cleanMega.contains("\n"),
              // Avoid claiming a Mega form while reporting a base/unknown state.
              (form == "MEGA" || cleanMega.isEmpty) else { return nil }
        return Self(sessionID: sessionID,frameID:frameID,epoch:epoch,
                    side:side,displayedSpecies:cleanSpecies,claimedForm:form,
                    megaFormLabel:cleanMega,confirmationMethod:method)
    }
    var json: [String:Any] {
        ["source_frame_id":frameID, "source_epoch":epoch, "side_manual":side,
         "displayed_species_name":displayedSpecies, "manual_form_claim":claimedForm,
         "mega_form_label_manual":megaFormLabel, "confirmation_method":confirmationMethod,
         "input_origin":"USER_MANUAL_NOT_CAPTURE_CLASSIFIER",
         "own_opponent_auto_certified":false,
         "mega_state_auto_certified":false,
         "name_change_required":false,
         "transformation_animation_required":false,
         "battle_advice_authorized":false]
    }
}

final class R547MegaManualNotebook {
    private var entries: [R547MegaManualRecord] = []
    func reset() { entries.removeAll() }
    @discardableResult
    func add(_ record: R547MegaManualRecord) -> Bool {
        guard entries.count < 80 else { return false }
        // Replace a correction on the SAME frame/side, not another battle or another side.
        entries.removeAll { $0.sessionID == record.sessionID &&
            $0.epoch == record.epoch && $0.frameID == record.frameID && $0.side == record.side }
        entries.append(record)
        return true
    }
    func selected(sessionID:String,epoch:Int64,frameID:Int64) -> [[String:Any]] {
        entries.filter { $0.sessionID == sessionID && $0.epoch == epoch && $0.frameID == frameID }
            .sorted { $0.side < $1.side }.map(\.json)
    }
}

enum R547MegaManualExport {
    static let schema = "trueplan.r547.manual-mega-form-evidence.v1"
    static func envelope(records:[[String:Any]], frame:Int64, epoch:Int64,
                         imageHash:String) -> [String:Any] {
        ["schema":schema,"source_frame_id":frame,"source_epoch":epoch,
         "source_image_sha256":imageHash,
         "entries":records,"entry_count":records.count,
         "mega_state_auto_certified":false,"name_change_required":false,
         "transformation_animation_required":false,
         "manual_labels_are_ground_truth":false,
         "r525_ledger_auto_updated":false,
         "battle_advice_authorized":false,
         "readiness":"MANUAL_LABELS_ONLY_NOT_CERTIFIED"]
    }
    static func verify(_ root:[String:Any],frame:Int64,epoch:Int64)->Bool {
        guard let block=root["r547_manual_mega_evidence"] as? [String:Any],
              block["schema"] as? String == schema,
              block["source_frame_id"] as? Int64 == frame,
              block["source_epoch"] as? Int64 == epoch,
              block["source_image_sha256"] as? String == root["png_sha256"] as? String,
              let entries=block["entries"] as? [[String:Any]], entries.count<=2,
              block["entry_count"] as? Int == entries.count,
              block["mega_state_auto_certified"] as? Bool == false,
              block["battle_advice_authorized"] as? Bool == false,
              block["r525_ledger_auto_updated"] as? Bool == false,
              block["name_change_required"] as? Bool == false,
              block["transformation_animation_required"] as? Bool == false else { return false }
        var sides=Set<String>()
        for e in entries {
            guard let side=e["side_manual"] as? String, sides.insert(side).inserted,
                  let species=e["displayed_species_name"] as? String,
                  let form=e["manual_form_claim"] as? String,
                  let label=e["mega_form_label_manual"] as? String,
                  let method=e["confirmation_method"] as? String,
                  R547MegaManualRecord.make(sessionID:"verified-export",frameID:frame,
                      epoch:epoch,side:side,species:species,form:form,
                      megaLabel:label,method:method) != nil,
                  e["source_frame_id"] as? Int64 == frame,
                  e["source_epoch"] as? Int64 == epoch,
                  e["mega_state_auto_certified"] as? Bool == false,
                  e["battle_advice_authorized"] as? Bool == false else { return false }
        }
        return true
    }
}
