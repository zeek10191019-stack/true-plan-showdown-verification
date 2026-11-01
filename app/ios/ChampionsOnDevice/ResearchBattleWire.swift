import Foundation

// Shared transport version. All device OCR is provisional; nil turn is unknown.
enum ResearchJSON: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: ResearchJSON]), array([ResearchJSON]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: ResearchJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([ResearchJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

struct ResearchTextAlternative: Codable, Equatable {
    let rank: Int
    let raw_text: String
    let confidence: Double
}

struct ResearchOCROmission: Codable {
    let observation_index: Int
    let reason: String
}

struct ResearchOCRVisionInput: Codable {
    let schema: String
    let handler: String
    let normalization: String
    let width: Int
    let height: Int
    let bytes_per_row: Int
    let allocation_bytes: Int
    let visible_pixel_bytes: Int
    let visible_pixel_sha256: String
    let source_pixel_equality_certified: Bool
}

struct ResearchOCRErrorCode: Codable {
    let domain: String
    let code: Int
}
struct ResearchOCRExecutionAttempt: Codable {
    let mode: String
    let outcome: String
    let configuration_accepted: Bool
    let request_performed: Bool
    let supported_stage_count: Int
    let main_stage_present: Bool
    let cpu_assigned_stage_count: Int
    let software_context_requested: Bool
    let error_codes: [ResearchOCRErrorCode]
}
struct ResearchOCRExecutionAudit: Codable {
    let schema: String
    let policy_id: String
    let status: String
    let attempt_count: Int
    let attempts: [ResearchOCRExecutionAttempt]
    let same_input_reused: Bool
    let configuration_only: Bool
    let compute_execution_attested: Bool
    let ocr_accuracy_certified: Bool
    let owner_certified: Bool
    let current_state_eligible: Bool
    let battle_advice_authorized: Bool
}

/// Request diagnostics are self-reported, never a signature or accuracy grade.
struct ResearchOCRRequestAudit: Codable {
    let schema: String
    let engine_version: String
    let scope: String
    let input_binding: String
    let execution_attestation: String
    let capture_session_id: String
    let frame_id: Int64
    let epoch: Int64
    let receipt_uptime_ms: Int64
    let timestamp_basis: String
    let image_sha256: String
    let image_width: Int
    let image_height: Int
    let requested_mode: String
    let effective_recognition_level: String
    let requested_languages: [String]
    let effective_supported_languages: [String]
    let fast_language_check: String
    let fast_supported_languages: [String]
    let request_revision: Int
    let uses_language_correction: Bool
    let maximum_regions: Int
    let maximum_candidates_per_region: Int
    let raw_region_count: Int
    let examined_region_count: Int
    let emitted_region_count: Int
    let truncated_region_count: Int
    let omitted_observations: [ResearchOCROmission]
    let unbound_roi_count: Int
    let ocr_accuracy_certified: Bool
    let device_certified: Bool
    let owner_certified: Bool
    let current_state_eligible: Bool
    let battle_advice_authorized: Bool
    var vision_input: ResearchOCRVisionInput? = nil
    var execution_audit: ResearchOCRExecutionAudit? = nil
}

struct ResearchReading: Codable, Equatable {
    let key: String?
    let value: ResearchJSON
    let raw_text: String
    let confidence: Double?
    let reason: String
    // Pixel geometry from the original Vision request; never a certified owner.
    var roi_rect: [String:Int]? = nil
    var source_epoch: Int? = nil
    var source_frame_id: Int64? = nil
    var source_image_sha256: String? = nil
    var roi_source: String? = nil
    var roi_owner_certified: Bool? = nil
    var ocr_alternatives: [ResearchTextAlternative]? = nil
    var ocr_observation_index: Int? = nil
    // Encode nil explicitly: unknown fields must survive language boundaries.
    enum CodingKeys: String, CodingKey {
        case key, value, raw_text, confidence, reason
        case roi_rect, source_epoch, source_frame_id, source_image_sha256, roi_source, roi_owner_certified
        case ocr_alternatives
        case ocr_observation_index
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let key { try c.encode(key, forKey: .key) } else { try c.encodeNil(forKey: .key) }
        try c.encode(value, forKey: .value); try c.encode(raw_text, forKey: .raw_text)
        if let confidence { try c.encode(confidence, forKey: .confidence) } else { try c.encodeNil(forKey: .confidence) }
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(roi_rect, forKey: .roi_rect)
        try c.encodeIfPresent(source_epoch, forKey: .source_epoch)
        try c.encodeIfPresent(source_frame_id, forKey: .source_frame_id)
        try c.encodeIfPresent(source_image_sha256, forKey: .source_image_sha256)
        try c.encodeIfPresent(roi_source, forKey: .roi_source)
        try c.encodeIfPresent(roi_owner_certified, forKey: .roi_owner_certified)
        try c.encodeIfPresent(ocr_alternatives, forKey: .ocr_alternatives)
        try c.encodeIfPresent(ocr_observation_index, forKey: .ocr_observation_index)
    }
}

struct ResearchBattlePacket: Codable {
    var schema = "trueplan.mobile-observation.v1"
    let battle_id: String
    let epoch: Int
    let frame_id: Int
    let turn: Int?
    let observed_at_ms: Int64
    let received_at_ms: Int64
    let image_sha256: String
    let source_ref: String
    let screen_kind: String
    let readings: [ResearchReading]
    var production_enabled = false
    var ocr_engine_version: String? = nil
    var ocr_request_audit: ResearchOCRRequestAudit? = nil
    enum CodingKeys: String, CodingKey {
        case schema, battle_id, epoch, frame_id, turn, observed_at_ms, received_at_ms
        case image_sha256, source_ref, screen_kind, readings, production_enabled
        case ocr_engine_version, ocr_request_audit
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema);try c.encode(battle_id, forKey: .battle_id)
        try c.encode(epoch, forKey: .epoch);try c.encode(frame_id, forKey: .frame_id)
        if let turn { try c.encode(turn, forKey: .turn) } else { try c.encodeNil(forKey: .turn) }
        try c.encode(observed_at_ms, forKey: .observed_at_ms);try c.encode(received_at_ms, forKey: .received_at_ms)
        try c.encode(image_sha256, forKey: .image_sha256);try c.encode(source_ref, forKey: .source_ref)
        try c.encode(screen_kind, forKey: .screen_kind);try c.encode(readings, forKey: .readings)
        try c.encode(false, forKey: .production_enabled)
        try c.encodeIfPresent(ocr_engine_version, forKey: .ocr_engine_version)
        try c.encodeIfPresent(ocr_request_audit, forKey: .ocr_request_audit)
    }
}

enum ResearchLiteralParser {
    static let productionEnabled = false
    static func hp(_ raw: String, side: String) -> [ResearchReading] {
        guard side == "own" || side == "opp" else { return [] }
        let t = raw.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
        if let range = t.range(of: #"^\d{1,4}/\d{1,4}$"#, options: .regularExpression) {
            let parts = t[range].split(separator: "/").compactMap { Int($0) }
            guard parts.count == 2, parts[1] > 0, parts[0] <= parts[1] else { return [] }
            return [ResearchReading(key: side + ".hp", value: .number(Double(parts[0])), raw_text: raw, confidence: nil, reason: "LITERAL_HP_CANDIDATE"),
                    ResearchReading(key: side + ".max_hp", value: .number(Double(parts[1])), raw_text: raw, confidence: nil, reason: "LITERAL_MAX_HP_CANDIDATE")]
        }
        if t.range(of: #"^\d{1,3}(\.\d{1,2})?%$"#, options: .regularExpression) != nil,
           let p = Double(t.dropLast()), p >= 0, p <= 100 {
            return [ResearchReading(key: side + ".hp_percent", value: .number(p), raw_text: raw, confidence: nil, reason: "LITERAL_PERCENT_NOT_ABSOLUTE_HP")]
        }
        return []
    }
    static func status(_ raw: String, side: String?) -> ResearchReading {
        let labels = ["やけど":"burn", "まひ":"paralysis", "ねむり":"sleep", "こおり":"freeze", "もうどく":"bad_poison"]
        guard let side, ["own","opp"].contains(side), let value = labels[raw.trimmingCharacters(in:.whitespacesAndNewlines)] else {
            return ResearchReading(key:nil,value:.null,raw_text:raw,confidence:nil,reason:"STATUS_OR_OWNER_UNBOUND; POISON_SEVERITY_NOT_GUESSED")
        }
        return ResearchReading(key:side+".status",value:.string(value),raw_text:raw,confidence:nil,reason:"STATUS_CANDIDATE_ONLY")
    }
    static func boost(_ raw: String, side: String?) -> ResearchReading {
        let labels = ["こうげき":"atk","ぼうぎょ":"def","とくこう":"spa","とくぼう":"spd","すばやさ":"spe","命中":"accuracy","回避":"evasion"]
        let parts = raw.precomposedStringWithCompatibilityMapping.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let side, ["own","opp"].contains(side), parts.count == 2, let stat = labels[parts[0]],
              parts[1] == "0" || parts[1].hasPrefix("+") || parts[1].hasPrefix("-"),
              let stage = Int(parts[1]), (-6...6).contains(stage) else {
            return ResearchReading(key:nil,value:.null,raw_text:raw,confidence:nil,reason:"ABSOLUTE_BOOST_OR_OWNER_UNBOUND")
        }
        return ResearchReading(key:side+".boost."+stat,value:.number(Double(stage)),raw_text:raw,confidence:nil,reason:"ABSOLUTE_BOOST_CANDIDATE_ONLY")
    }
}
