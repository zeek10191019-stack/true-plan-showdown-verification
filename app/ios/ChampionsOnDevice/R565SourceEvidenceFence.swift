import Foundation
import CoreFoundation

/// Verifies that each provisional position hint came from an actual Vision OCR
/// candidate in the same image, ROI and capture epoch. No hint is promoted to
/// an identified Pokémon or current battle state, even after this gate passes.
enum R565SourceEvidenceFence {
    private static func falseBoolean(_ value:Any?)->Bool {
        guard let n=value as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else {return false}
        return !n.boolValue
    }
    private static func sameRect(_ first: [String:Int64], _ second: [String:Int64]) -> Bool {
        ["x","y","width","height"].allSatisfy { first[$0] == second[$0] }
    }
    static func report(base: [String:Any], sites: [R553LayoutReading.Site],
                       session: String, frame: Int64, epoch: Int64, imageSHA: String) -> [String:Any] {
        var result=base
        result["schema"]="trueplan.screen-read.source-bound-hints.v2"
        result["source_evidence_checked"]=false
        result["role_text_checked"]=false
        result["evidence_group_checked"]=false
        result["semantic_consensus_checked"]=false
        result["literal_values_checked"]=false
        result["identity_certified"]=false
        result["owner_certified"]=false
        result["current_state_eligible"]=false
        result["battle_advice_authorized"]=false
        result["iPhone_accuracy_certified"]=false
        func reject(_ reason: String) -> [String:Any] {
            result["status"]=reason
            result["hints"]=[[String:Any]]()
            result["source_evidence_checked"]=false
            result["role_text_checked"]=false
            result["evidence_group_checked"]=false
            result["semantic_consensus_checked"]=false
            result["literal_values_checked"]=false
            return result
        }
        guard base["status"] as? String == "PROVISIONAL_POSITION_HINTS_NO_OWNER_CERTIFICATION" else {
            return reject(base["status"] as? String ?? "HOLD_R564_BASE_INVALID")
        }
        guard base["capture_session_id"] as? String == session,
              base["frame_id"] as? Int64 == frame,
              base["epoch"] as? Int64 == epoch,
              base["image_sha256"] as? String == imageSHA,
              falseBoolean(base["owner_certified"]),
              falseBoolean(base["current_state_eligible"]),
              let hints=base["hints"] as? [[String:Any]],hints.count<=12 else {
            return reject("HOLD_R565_WRONG_FRAME_OR_BASE")
        }
        guard !hints.isEmpty else {return reject("HOLD_R565_NO_POSITION_HINTS")}
        guard sites.count<=2048 else {return reject("HOLD_R565_TOO_MANY_SITES")}
        var references=[String:R553LayoutReading.Site]()
        for site in sites {
            guard site.reading>=0,site.reading<512,site.rank>=0,site.rank<32,
                  R568ObservationReferenceFence.canonical(site),
                  site.roi["width",default:0]>0,site.roi["height",default:0]>0 else {
                return reject("HOLD_R565_MALFORMED_SOURCE_SITE")
            }
            guard references[site.reference] == nil else {
                return reject("HOLD_R565_SOURCE_REFERENCE_DUPLICATED")
            }
            references[site.reference]=site
        }
        var consumed=Set<String>()
        var consumedObservations=[Int:Int]()
        var valuedHints=[[String:Any]]()
        for (hintIndex,hint) in hints.enumerated() {
            guard hint["verification"] as? String == "POSITION_ONLY_UNVERIFIED",
                  falseBoolean(hint["current_state_eligible"]),
                  hint["knowledge_state"] as? String == "INFERRED",
                  hint["role_hint"] as? String != nil,
                  let role=hint["role_hint"] as? String,
                  let evidence=hint["evidence_refs"] as? [String],!evidence.isEmpty,evidence.count<=32,
                  let rois=hint["rois"] as? [[String:Int64]],rois.count==evidence.count else {
                return reject("HOLD_R565_HINT_STRUCTURE_INVALID")
            }
            var group=[R553LayoutReading.Site]()
            for (reference,roi) in zip(evidence,rois) {
                guard let source=references[reference],sameRect(source.roi,roi) else {
                    return reject("HOLD_R565_SOURCE_EVIDENCE_ROI_MISMATCH")
                }
                guard !consumed.contains(reference) else {
                    return reject("HOLD_R565_ROLE_REFERENCE_COLLISION")
                }
                guard let reading=R568ObservationReferenceFence.reading(source) else {
                    return reject("HOLD_R568_SOURCE_REFERENCE_IDENTITY")
                }
                // Distinct OCR alternatives from the same observation may be
                // compared within one hint, but must never label different roles.
                if let previous=consumedObservations[reading],previous != hintIndex {
                    return reject("HOLD_R568_OBSERVATION_REUSED_ACROSS_HINTS")
                }
                consumedObservations[reading]=hintIndex
                group.append(source)
                consumed.insert(reference)
            }
            if role == "move_pp" {
                guard R567EvidenceGroupFence.inspect(role:role,sites:group) else {
                    return reject("HOLD_R567_ROLE_EVIDENCE_GROUP_INVALID")
                }
            } else {
                guard group.allSatisfy({R566RoleTextFence.inspect(role:role,site:$0)}) else {
                    return reject("HOLD_R566_ROLE_TEXT_MISMATCH")
                }
                guard R569RoleConsensusFence.inspect(role:role,sites:group) else {
                    return reject("HOLD_R569_AMBIGUOUS_ROLE_VALUE")
                }
            }
            let value:Any? = role == "move_pp" ? R567EvidenceGroupFence.ppValue(sites:group) :
                R569RoleConsensusFence.literalValue(role:role,sites:group)
            guard let literal=value else {return reject("HOLD_R571_LITERAL_VALUE_UNAVAILABLE")}
            var valued=hint
            valued["literal_value"]=literal
            valued["raw_texts"]=group.map(\.text)
            valued["source_confidences"]=group.map {$0.confidence.map {$0 as Any} ?? NSNull()}
            valued["value_basis"]="OCR_LITERAL_CONSENSUS_ONLY"
            valued["side"]="UNKNOWN_OWNER"
            valued["owner_certified"]=false
            valued["identity_certified"]=false
            valued["validity"]="HISTORICAL_FRAME_ONLY"
            valuedHints.append(valued)
        }
        result["hints"]=valuedHints
        result["source_evidence_checked"]=true
        result["role_text_checked"]=true
        result["evidence_group_checked"]=true
        result["semantic_consensus_checked"]=true
        result["literal_values_checked"]=true
        result["source_evidence_count"]=consumed.count
        result["status"]="PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION"
        return result
    }
    static func displayLines(_ report: [String:Any]) -> [String] {
        guard report["status"] as? String == "PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION" else {
            return ["画面位置とOCR証拠の対応は保留。自分・相手を確定しません"]
        }
        let hints=report["hints"] as? [[String:Any]] ?? []
        var lines=["OCR出典と文字の値が一致：候補\(hints.count)件（自他・個体・現在値は未認証）"]
        for hint in hints.prefix(12) {
            guard let role=hint["role_hint"] as? String,let value=hint["literal_value"] else {continue}
            let slot=(hint["slot"] as? Int).map {"技枠\($0+1)"} ?? ""
            let label=["own_hp":"自分側位置のHP候補","opponent_hp":"相手側位置のHP候補",
                "own_name":"自分側位置の名前候補","opponent_name":"相手側位置の名前候補",
                "move_name":slot+"の技名候補","move_pp":slot+"のPP候補"][role] ?? "文字候補"
            if let fraction=value as? [String:Int],let current=fraction["current"],let maximum=fraction["maximum"] {
                lines.append("\(label)：\(current)/\(maximum)")
            } else if role=="opponent_hp",let percent=value as? NSNumber {
                lines.append("\(label)：\(percent)%")
            } else {lines.append("\(label)：\(value)")}
        }
        return lines
    }
}
