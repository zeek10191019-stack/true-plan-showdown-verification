import Foundation
import CoreFoundation

// R27.478 -- one-button, research-only diagnostic. No pixels, OCR literals,
// moves, Pokémon names, Apple IDs, device identifiers or audio are persisted.
// The output retains source-specific epochs; it MUST NOT merge observations
// across epochs or certify a battle, turn, owner, clock mapping, or advice.
enum ResearchUnifiedTelemetryBundle {
    static let productionEnabled = false
    static let schema = "trueplan.unified-capture-audit.v1"

    private static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              data.count > 1, data.count <= 500_000,
              let value = try? JSONSerialization.jsonObject(with: data),
              let dictionary = value as? [String: Any] else { return nil }
        return dictionary
    }
    private static func int64(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let magnitude = number.doubleValue
        guard magnitude.isFinite,
              magnitude >= Double(Int64.min),
              magnitude < 9223372036854775808.0,
              magnitude.rounded(.towardZero) == magnitude else { return nil }
        return number.int64Value
    }
    private static func sectionEpoch(_ name: String, _ obj: [String: Any]) -> Int64? {
        switch name {
        case "continuity": return int64(obj["currentEpoch"])
        case "latency": return int64(obj["epoch"])
        case "pts": return int64(obj["activeEpoch"])
        case "ingress": return int64(obj["active_epoch"])
        default: return nil
        }
    }
    // R27.481: diagnostic triage is explicitly historical/provisional.
    // It reads NUMERIC telemetry only. It cannot authenticate an image, ROI,
    // Pokémon owner, frame timestamp, turn, battle ID, or recommendation.
    // Missing/invalid counters remain unknown, never silently zero.
    static func diagnosticTriage(continuity: [String: Any],
                                 latency: [String: Any],
                                 sourceEpochsConsistent: Bool) -> [String: Any] {
        func counter(_ obj: [String: Any], _ key: String) -> Int64? {
            guard let n = int64(obj[key]), n >= 0 else { return nil }
            return n
        }
        let tracked: [(String, [String: Any], String)] = [
            ("unexpected_shape_rejects", continuity, "unexpectedShapeRejects"),
            ("historical_long_frame_gaps", continuity, "longFrameGaps"),
            ("max_historical_frame_gap_ms", continuity, "longestFrameGapMs"),
            ("out_of_order_rejects", continuity, "outOfOrderRejects"),
            ("wrong_epoch_rejects", continuity, "wrongEpochRejects"),
            ("continuity_clock_rejects", continuity, "invalidClockRejects"),
            ("latency_over_budget_pairs", latency, "overBudgetPairs"),
            ("latency_epoch_rejects", latency, "staleEpochRejects"),
            ("latency_clock_rejects", latency, "invalidClockRejects")
        ]
        var measured: [String: Any] = [:]
        var unknown: [String] = []
        for (label, obj, key) in tracked {
            if let n = counter(obj, key) { measured[label] = n }
            else { measured[label] = NSNull(); unknown.append(label) }
        }
        let latestAge = counter(continuity, "lastAcceptedFrameAgeMs")
        measured["last_accepted_frame_age_ms"] = latestAge.map { NSNumber(value: $0) } ?? NSNull()
        if latestAge == nil { unknown.append("last_accepted_frame_age_ms") }
        var flags = [String]()
        if !sourceEpochsConsistent { flags.append("SOURCE_EPOCH_MISMATCH") }
        if let n = counter(continuity, "unexpectedShapeRejects"), n > 0 {
            flags.append("HISTORICAL_UNEXPECTED_FRAME_DIMENSIONS")
        }
        if let n = counter(continuity, "longFrameGaps"), n > 0 {
            flags.append("HISTORICAL_FRAME_DELIVERY_GAPS")
        }
        if let n = latestAge, n >= 1500 {
            flags.append("LATEST_DELIVERED_FRAME_AGE_EXCEEDS_1500MS")
        }
        for (key, reason) in [
            ("outOfOrderRejects", "HISTORICAL_OUT_OF_ORDER_FRAMES"),
            ("wrongEpochRejects", "HISTORICAL_WRONG_EPOCH_FRAMES"),
            ("invalidClockRejects", "HISTORICAL_INVALID_CONTINUITY_CLOCK")
        ] {
            if let n = counter(continuity, key), n > 0 { flags.append(reason) }
        }
        if let n = counter(latency, "overBudgetPairs"), n > 0 {
            flags.append("HISTORICAL_OCR_LATENCY_OVER_BUDGET")
        }
        if let n = counter(latency, "staleEpochRejects"), n > 0 {
            flags.append("HISTORICAL_OCR_STALE_EPOCH")
        }
        if let n = counter(latency, "invalidClockRejects"), n > 0 {
            flags.append("HISTORICAL_OCR_INVALID_CLOCK")
        }
        if !unknown.isEmpty { flags.append("UNKNOWN_OR_INVALID_MONITOR_COUNTERS") }
        // Never infer per-frame failure from a historical aggregate counter.
        return [
            "schema": "trueplan.capture-diagnostic-triage.v1",
            "numeric_counters": measured,
            "unknown_counters": unknown.sorted(),
            "diagnostic_flags": flags,
            "historical_counters_not_current_frame_proof": true,
            "owner_and_turn_bound": false,
            "clock_domain_calibrated": false,
            "advice_allowed": false,
            "verdict": "RESEARCH_TELEMETRY_ONLY_HOLD"
        ]
    }

    // A bounded, redacted fail-closed result. No observation contents escape.
    private static func contradictoryObservation(reason: String) -> [String: Any] {
        return ["schema": "trueplan.observation-association.v1",
                "status": "CONTRADICTORY_OBSERVATION_ENVELOPE_HOLD",
                "reason_codes": [reason], "observation_present": true,
                "battle_owner_verified": false, "turn_verified": false,
                "clock_domain_calibrated": false, "advice_allowed": false]
    }

    // R27.482. Research-only linkage of the latest UI observation to ingress
    // metadata. We do not expose raw OCR text, names, moves or health values
    // in numeric telemetry. The connection is NOT a Battle State admission.
    static func observationAssociation(observationJSON: String?,
                                       epoch: Int64,
                                       ingress: [String: Any]) -> [String: Any] {
        var reasons = [String]()
        guard let raw = observationJSON, !raw.isEmpty else {
            return ["schema": "trueplan.observation-association.v1",
                    "status": "NO_BATTLE_OBSERVATION_HOLD",
                    "observation_present": false,
                    "battle_owner_verified": false,
                    "turn_verified": false,
                    "clock_domain_calibrated": false,
                    "advice_allowed": false,
                    "reason_codes": ["NO_OBSERVATION"]]
        }
        var input = object(raw)
        // R27.484. A transport wrapper cannot override or contradict its
        // nested observation. A payload_json field of the wrong type or
        // invalid JSON is never allowed to fall back to the outer object.
        if let outer = input, outer.keys.contains("payload_json") {
            guard let nestedText = outer["payload_json"] as? String,
                  let nested = object(nestedText),
                  !nested.keys.contains("payload_json") else {
                return contradictoryObservation(reason: "INVALID_NESTED_PAYLOAD")
            }
            for name in ["battle_id", "epoch", "frame_id", "production_enabled"] {
                guard let outerValue = outer[name] else { continue }
                guard let innerValue = nested[name] else {
                    return contradictoryObservation(reason: "MISSING_NESTED_MIRRORED_FIELD")
                }
                let equal: Bool
                switch name {
                case "epoch", "frame_id":
                    let a = int64(outerValue), b = int64(innerValue)
                    equal = a != nil && a == b
                case "production_enabled":
                    let a = outerValue as? Bool, b = innerValue as? Bool
                    equal = a != nil && a == b
                default:
                    let a = outerValue as? String, b = innerValue as? String
                    equal = a != nil && a == b
                }
                guard equal else {
                    return contradictoryObservation(reason: "ENVELOPE_FIELD_CONFLICT")
                }
            }
            // R27.485: duplicated observation evidence must agree with the
            // nested payload. Reject time, geometry, and OCR array conflicts,
            // not only the four identity fields. Never echo the conflicted
            // values into the clipboard diagnostic.
            let evidenceFields = [
                "observed_at_ms", "received_at_ms", "image_sha256",
                "turn", "screen_kind", "readings", "move_candidates",
                "hp_readings", "owner", "pokemon", "moves", "pp", "hp"
            ]
            for name in evidenceFields {
                guard let outerValue = outer[name] else { continue }
                guard let nestedValue = nested[name] else {
                    return contradictoryObservation(reason: "MISSING_NESTED_MIRRORED_FIELD")
                }
                // Use canonical JSON for structured arrays/maps; string
                // comparison and int64 parsing alone are insufficient.
                let a = try? JSONSerialization.data(
                    withJSONObject: ["value": outerValue], options: [.sortedKeys])
                let b = try? JSONSerialization.data(
                    withJSONObject: ["value": nestedValue], options: [.sortedKeys])
                guard a != nil, a == b else {
                    return contradictoryObservation(reason: "ENVELOPE_EVIDENCE_CONFLICT")
                }
            }
            input = nested
        }
        guard let obj = input else {
            return ["schema": "trueplan.observation-association.v1",
                    "status": "INVALID_BATTLE_OBSERVATION_HOLD",
                    "observation_present": true,
                    "battle_owner_verified": false,
                    "turn_verified": false,
                    "clock_domain_calibrated": false,
                    "advice_allowed": false,
                    "reason_codes": ["INVALID_OBSERVATION_JSON"]]
        }
        let hasBattle = (obj["battle_id"] as? String).flatMap(UUID.init(uuidString:)) != nil
        let obEpoch = int64(obj["epoch"])
        let obFrame = int64(obj["frame_id"])
        let ingressFrame = int64(ingress["last_delivered_frame_id"])
        let matchesEpoch = obEpoch == epoch && epoch > 0
        let matchesFrame = obFrame != nil && ingressFrame != nil &&
            obFrame! > 0 && obFrame == ingressFrame
        if !hasBattle { reasons.append("MISSING_VERIFIED_BATTLE_ID") }
        if !matchesEpoch { reasons.append("OBSERVATION_EPOCH_MISMATCH_OR_UNKNOWN") }
        if !matchesFrame { reasons.append("FRAME_ID_NOT_LATEST_DELIVERED") }
        if (obj["production_enabled"] as? Bool) != false {
            reasons.append("OBSERVATION_PRODUCTION_FLAG_NOT_FALSE")
        }
        // We may count keyed readings, but may NEVER accept a key as proof
        // of owner, geometry, health, move, PP, or freshness. In particular,
        // key=nil in the supplied Frame334 JSON is not a battle state.
        let readings = obj["readings"] as? [[String: Any]]
        let keyed = readings?.filter { record in
            guard let k = record["key"] as? String else { return false }
            return !k.isEmpty && k.count <= 80
        }.count ?? 0
        if keyed == 0 { reasons.append("NO_KEYED_ROI_READINGS") }
        reasons.append("OWNER_AND_TURN_NOT_CERTIFIED")
        reasons.append("PTS_TO_UPTIME_NOT_CALIBRATED")
        // Never echo observation raw_text into clipboard telemetry.
        return ["schema": "trueplan.observation-association.v1",
                "status": "OBSERVATION_PROVENANCE_RESEARCH_ONLY_HOLD",
                "observation_present": true,
                "battle_id_format_valid": hasBattle,
                "same_epoch": matchesEpoch,
                "same_latest_ingress_frame_id": matchesFrame,
                "readings_count": readings?.count ?? 0,
                "keyed_readings_count": keyed,
                "roi_binding_blockers": roiBindingBlockers(readings),
                "hp_pp_syntax_diagnostic": hpPPSyntaxDiagnostic(readings),
                "unassigned_numeric_candidates": unassignedNumericCandidates(readings),
                "unbound_roi_collision_audit": unboundROICollisionAudit(readings),
                "battle_owner_verified": false,
                "turn_verified": false,
                "clock_domain_calibrated": false,
                "advice_allowed": false,
                "reason_codes": reasons]
    }


    // R27.486: Conservative HP / PP OCR lexical assessment. This is a research
    // diagnostic, never evidence of ROI ownership, turn, freshness or battle state.
    // No raw OCR characters or inferred numerators/denominators are exported.
    static func hpPPSyntaxDiagnostic(_ readings: [[String: Any]]?) -> [String: Any] {
        guard let readings = readings, readings.count <= 256 else {
            return ["schema": "trueplan.hp-pp-lexical.v1",
                    "status": "MISSING_OR_EXCESSIVE_READINGS_HOLD",
                    "reading_count": NSNull(), "advice_allowed": false]
        }
        var hpFraction = 0, hpPercent = 0, ppFraction = 0
        var malformed = 0, unrecognizedKey = 0, duplicates = 0
        var seen = Set<String>()
        // This is a lexical whitelist only, NOT proof that the ROI belongs to
        // the named Pokémon. Index is 0-based and limited to four move slots.
        func keyKind(_ key: String) -> String? {
            if key == "own.hp" || key == "opp.hp" { return "hp" }
            for i in 0..<4 where key == "own.move.\(i).pp" { return "pp" }
            return nil
        }
        func strictInt(_ text: Substring, maximum: Int) -> Int? {
            guard !text.isEmpty, text.count <= 4,
                  text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let value = Int(text), value <= maximum else { return nil }
            return value
        }
        for item in readings {
            guard let key = item["key"] as? String, let kind = keyKind(key) else {
                unrecognizedKey += 1; continue
            }
            if !seen.insert(key).inserted { duplicates += 1; continue }
            guard let raw = item["raw_text"] as? String,
                  raw.utf8.count <= 16,
                  raw.utf8.allSatisfy({ $0 < 128 }) else {
                malformed += 1; continue
            }
            if raw.hasSuffix("%") && kind == "hp" {
                let p = raw.dropLast()
                if strictInt(p, maximum: 100) != nil { hpPercent += 1 }
                else { malformed += 1 }
                continue
            }
            let tokens = raw.split(separator: "/", omittingEmptySubsequences: false)
            guard tokens.count == 2 else { malformed += 1; continue }
            let limit = kind == "hp" ? 2048 : 64
            guard let current = strictInt(tokens[0], maximum: limit),
                  let maximum = strictInt(tokens[1], maximum: limit),
                  maximum > 0, current <= maximum else {
                malformed += 1; continue
            }
            if kind == "hp" { hpFraction += 1 } else { ppFraction += 1 }
        }
        // Even syntactically valid readings are NOT certified game values.
        return ["schema": "trueplan.hp-pp-lexical.v1",
                "status": "OCR_SYNTAX_RESEARCH_ONLY_HOLD",
                "reading_count": readings.count,
                "hp_fraction_syntax_count": hpFraction,
                "hp_percent_syntax_count": hpPercent,
                "pp_fraction_syntax_count": ppFraction,
                "malformed_recognized_key_count": malformed,
                "unknown_or_unkeyed_count": unrecognizedKey,
                "duplicate_key_count": duplicates,
                "roi_owner_verified": false,
                "turn_verified": false,
                "clock_domain_calibrated": false,
                "battle_state_admission_allowed": false,
                "advice_allowed": false]
    }

    // R27.488: Analyze only *unbound* OCR evidence. A repeated numeric string
    // must never be treated as an ownership or move-slot proof. The result
    // deliberately contains counts, not raw OCR, ROI names, or values.
    static func unboundROICollisionAudit(_ readings: [[String: Any]]?) -> [String: Any] {
        let hold = "ROI_OWNER_AND_SLOT_NOT_CERTIFIED_HOLD"
        guard let readings = readings, readings.count <= 256 else {
            return ["schema": "trueplan.unbound-roi-collision.v1", "status": hold,
                    "input_missing_or_oversized": true, "unbound_readings": NSNull(),
                    "numeric_collisions": NSNull(), "battle_state_admission_allowed": false,
                    "real_time_advice_enabled": false]
        }
        var unbound = 0, missingReason = 0, ownClaim = 0, oppClaim = 0
        var splitHP = 0, otherClaim = 0, numericCandidate = 0
        var ownerOrSlotUnknown = 0
        var numericFrequency: [String: Int] = [:]
        for item in readings {
            if let key = item["key"] as? String, !key.isEmpty { continue }
            unbound += 1
            let reason = item["reason"] as? String ?? ""
            if reason.isEmpty { missingReason += 1 }
            else if reason == "UNVERIFIED_ROI_OWNER_OWN" { ownClaim += 1 }
            else if reason == "UNVERIFIED_ROI_OWNER_OPP" { oppClaim += 1 }
            else if reason == "UNVERIFIED_SPLIT_HP_LAYOUT_OWN_NOT_BATTLE_STATE" { splitHP += 1 }
            else { otherClaim += 1 }
            // The OCR string is used only for *within-this-export* collision
            // detection. It is never returned nor attached to a battle state.
            guard let value = item["raw_text"] as? String,
                  value.utf8.count <= 16, value.utf8.allSatisfy({ $0 < 128 }) else {
                ownerOrSlotUnknown += 1
                continue
            }
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let isPct = text.hasSuffix("%") && text.dropLast().utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
                && !text.dropLast().isEmpty && Int(text.dropLast()) != nil && Int(text.dropLast())! <= 100
            let p = text.split(separator: "/", omittingEmptySubsequences: false)
            let isFraction = p.count == 2 && p.allSatisfy({ !$0.isEmpty && $0.count <= 4 && $0.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) })
                && Int(p[0]) != nil && Int(p[1]) != nil && Int(p[1])! > 0 && Int(p[0])! <= Int(p[1])! && Int(p[1])! <= 2048
            if isPct || isFraction {
                numericCandidate += 1
                numericFrequency[text, default: 0] += 1
            } else { ownerOrSlotUnknown += 1 }
        }
        let collisionGroups = numericFrequency.values.filter({ $0 > 1 }).count
        let collisionItems = numericFrequency.values.filter({ $0 > 1 }).reduce(0, +)
        return ["schema": "trueplan.unbound-roi-collision.v1", "status": hold,
                "unbound_readings": unbound, "missing_reason": missingReason,
                "own_roi_unverified": ownClaim, "opp_roi_unverified": oppClaim,
                "split_hp_layout_unverified": splitHP, "other_unverified": otherClaim,
                "numeric_candidates": numericCandidate,
                "ambiguous_or_non_numeric": ownerOrSlotUnknown,
                "numeric_collisions": collisionGroups,
                "collision_affected_observations": collisionItems,
                "owner_or_move_slot_proven": false,
                "battle_state_admission_allowed": false,
                "real_time_advice_enabled": false]
    }

    // R27.487: track plausible OCR numerics that do NOT have proven ROI keys.
    // A fraction is inherently ambiguous: it might be HP, PP, or UI text.
    // These counts are research-only and omit all raw values and OCR strings.
    static func unassignedNumericCandidates(_ readings: [[String: Any]]?) -> [String: Any] {
        let hold = "UNKEYED_OCR_CANDIDATES_RESEARCH_ONLY_HOLD"
        guard let readings = readings, readings.count <= 256 else {
            return ["schema": "trueplan.unassigned-numerics.v1", "status": hold,
                    "readings_count": NSNull(), "missing_or_excessive": true,
                    "battle_state_admission_allowed": false, "advice_allowed": false]
        }
        func digits(_ s: Substring) -> Int? {
            guard !s.isEmpty, s.count <= 4,
                  s.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let n = Int(s), n <= 2048 else { return nil }
            return n
        }
        var fraction = 0, percent = 0, rejected = 0
        var unkeyed = 0, missingRaw = 0
        for reading in readings {
            if let key = reading["key"] as? String, !key.isEmpty { continue }
            unkeyed += 1
            guard let raw = reading["raw_text"] as? String,
                  raw.utf8.count <= 16,
                  raw.utf8.allSatisfy({ $0 < 128 }) else {
                missingRaw += 1
                continue
            }
            if raw.hasSuffix("%") {
                if let n = digits(raw.dropLast()), n <= 100 { percent += 1 }
                else { rejected += 1 }
                continue
            }
            let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2,
               let current = digits(parts[0]), let maximum = digits(parts[1]),
               maximum > 0, current <= maximum {
                fraction += 1
            } else {
                rejected += 1
            }
        }
        return ["schema": "trueplan.unassigned-numerics.v1", "status": hold,
                "readings_count": readings.count,
                "unkeyed_readings_count": unkeyed,
                "plausible_unassigned_fraction_count": fraction,
                "plausible_unassigned_percent_count": percent,
                "malformed_unassigned_count": rejected,
                "unreadable_or_non_text_unassigned_count": missingRaw,
                "owner_verified": false, "slot_verified": false, "turn_verified": false,
                "numeric_candidate_is_not_certified_hp_or_pp": true,
                "raw_text_exported": false,
                "battle_state_admission_allowed": false, "advice_allowed": false]
    }

    // R27.483: classify the precise observation-to-state blockers using only
    // bounded counters. Diagnostic categories are whitelisted so accidental
    // OCR strings or untrusted reason labels never enter clipboard telemetry.
    static func roiBindingBlockers(_ readings: [[String: Any]]?) -> [String: Any] {
        guard let readings = readings, readings.count <= 256 else {
            return ["schema": "trueplan.roi-binding-blockers.v1",
                    "status": "MISSING_OR_EXCESSIVE_READINGS_HOLD",
                    "readings_count": NSNull(),
                    "advice_allowed": false,
                    "blockers": ["READINGS_MISSING_OR_TOO_MANY"]]
        }
        var unkeyed = 0
        var own = 0
        var opp = 0
        var splitHP = 0
        var other = 0
        var duplicates = 0
        var seen = Set<String>()
        for reading in readings {
            if let key = reading["key"] as? String,
               !key.isEmpty, key.count <= 80 {
                if !seen.insert(key).inserted { duplicates += 1 }
            } else { unkeyed += 1 }
            let reason = reading["reason"] as? String ?? ""
            if reason == "UNVERIFIED_ROI_OWNER_OWN" { own += 1 }
            else if reason == "UNVERIFIED_ROI_OWNER_OPP" { opp += 1 }
            else if reason.hasPrefix("UNVERIFIED_SPLIT_HP_LAYOUT_") {
                // Prefix only; NEVER export the untrusted trailing characters.
                splitHP += 1
            } else { other += 1 }
        }
        var blockers: [String] = ["OWNER_NOT_PROVEN", "TURN_NOT_PROVEN",
                                  "FRAME_FRESHNESS_NOT_PROVEN"]
        if unkeyed > 0 { blockers.append("UNKEYED_READINGS_PRESENT") }
        if own + opp > 0 { blockers.append("ROI_OWNER_UNVERIFIED") }
        if splitHP > 0 { blockers.append("HP_LAYOUT_UNVERIFIED") }
        if duplicates > 0 { blockers.append("DUPLICATE_READING_KEYS") }
        if readings.isEmpty { blockers.append("NO_READINGS") }
        return ["schema": "trueplan.roi-binding-blockers.v1",
                "status": "RESEARCH_ONLY_BINDING_BLOCKERS_HOLD",
                "readings_count": readings.count,
                "unkeyed_readings_count": unkeyed,
                "unverified_own_roi_count": own,
                "unverified_opponent_roi_count": opp,
                "unverified_split_hp_count": splitHP,
                "duplicate_key_count": duplicates,
                "other_or_unrecognized_reason_count": other,
                "raw_text_exported": false,
                "advice_allowed": false,
                "blockers": blockers]
    }

    // Call on the SAME serial capture queue that protects continuity and
    // latency. Independent monitors have separate locks and clock domains.
    // A mismatch is visible in the resulting JSON and always HOLD.
    static func build(epoch: Int64, uptimeMs: Int64, phase: String,
                      continuityJSON: String, latencyJSON: String,
                      ptsJSON: String, ingressJSON: String,
                      previousEpochJSON: String? = nil,
                      captureSessionTag: String? = nil,
                      observationJSON: String? = nil) -> String? {
        guard epoch > 0, uptimeMs > 0, phase.count > 0 && phase.count <= 60,
              let continuity = object(continuityJSON),
              let latency = object(latencyJSON),
              let pts = object(ptsJSON),
              let ingress = object(ingressJSON) else { return nil }
        let sections: [String: [String: Any]] = [
            "continuity": continuity, "latency": latency,
            "pts": pts, "ingress": ingress
        ]
        var evidence: [String: Any] = [:]
        var allSame = true
        for key in ["continuity", "latency", "pts", "ingress"] {
            let seen = sectionEpoch(key, sections[key]!)
            let ok = seen == epoch
            evidence[key] = [
                "source_epoch": seen.map { NSNumber(value: $0) } ?? NSNull(),
                "same_as_envelope": ok
            ] as [String: Any]
            if !ok { allSame = false }
        }
        var envelope: [String: Any] = [
            "schema": schema, "phase": phase, "current_epoch": epoch,
            "snapshot_uptime_ms": uptimeMs, "sections": sections,
            "epoch_provenance": evidence,
            "capture_diagnostic_triage": diagnosticTriage(
                continuity: continuity, latency: latency,
                sourceEpochsConsistent: allSame),
            "observation_association": observationAssociation(
                observationJSON: observationJSON, epoch: epoch, ingress: ingress),
            "all_source_epochs_consistent": allSame,
            "clock_domain_calibrated": false,
            "battle_state_certified": false,
            "real_time_advice_enabled": false,
            "production_enabled": false,
            "verdict": allSame
              ? "SAME_EPOCH_TELEMETRY_ONLY_HOLD"
              : "SOURCE_EPOCH_MISMATCH_OR_UNKNOWN_HOLD",
            "limitations": "Transport, OCR and PTS measurements are research evidence only. No cross-clock frame-age proof, no owner/turn/battle certification or live advice."
        ]
        // A capture-session tag is ephemeral and is NOT a battle ID.
        // If a prior snapshot claims a different tag, discard it (fail closed).
        // Old unscoped callers remain research-only for regression compatibility.
        if let tag = captureSessionTag {
            guard UUID(uuidString: tag) != nil else { return nil }
            envelope["capture_session_tag"] = tag
        }
        if let prior = previousEpochJSON, let obj = object(prior) {
            // A previous audit is EVIDENCE, never a promotion to battle state.
            // The tag alone cannot prove chronology: enforce session, schema,
            // epoch, and same-monotonic-clock ordering independently.
            let sameScope = captureSessionTag == nil ||
                (obj["capture_session_tag"] as? String) == captureSessionTag
            let oldEpoch = int64(obj["current_epoch"])
            let oldUptime = int64(obj["snapshot_uptime_ms"])
            let chronologyOK = oldEpoch != nil && oldEpoch! > 0 && oldEpoch! < epoch &&
                oldUptime != nil && oldUptime! > 0 && oldUptime! <= uptimeMs
            let sameSchema = (obj["schema"] as? String) == schema
            let safeFlags = (obj["production_enabled"] as? Bool) == false &&
                (obj["real_time_advice_enabled"] as? Bool) == false &&
                (obj["battle_state_certified"] as? Bool) == false
            if sameScope && chronologyOK && sameSchema && safeFlags {
                // An archived sample must not recursively embed the whole
                // historical chain: flat, bounded per-epoch evidence only.
                var flat = obj
                flat.removeValue(forKey: "previous_epoch_snapshot")
                flat.removeValue(forKey: "previous_snapshot_is_distinct")
                flat.removeValue(forKey: "previous_snapshot_rejected_cross_session")
                flat.removeValue(forKey: "previous_snapshot_rejected_reason")
                envelope["previous_epoch_snapshot"] = flat
                envelope["previous_snapshot_is_distinct"] = true
                envelope["previous_epoch_ancestry_pruned"] = true
            } else {
                envelope["previous_snapshot_rejected_reason"] = !sameScope
                    ? "CROSS_CAPTURE_SESSION_HOLD"
                    : (!sameSchema || !safeFlags
                        ? "INVALID_PREVIOUS_EVIDENCE_HOLD"
                        : "NON_MONOTONIC_EPOCH_OR_UPTIME_HOLD")
                if !sameScope {
                    envelope["previous_snapshot_rejected_cross_session"] = true
                }
            }
        }
        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(
                 withJSONObject: envelope, options: [.sortedKeys, .prettyPrinted]),
              data.count < 2_000_000 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
