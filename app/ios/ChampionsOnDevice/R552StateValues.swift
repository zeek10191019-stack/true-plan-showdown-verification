import Foundation
import CoreFoundation

/// Literal values from one historical OCR frame. Nothing here binds a side or a turn.
enum R552StateValues {
    static let timedDomains: Set<String> = ["weather", "terrain", "room", "screen_or_side_effect", "visible_volatile"]
    private static let statNames = ["こうげき":"atk", "ぼうぎょ":"def", "とくこう":"spa",
        "とくぼう":"spd", "すばやさ":"spe", "命中":"accuracy", "回避":"evasion"]
    private static let statuses = ["やけど":"burn", "まひ":"paralysis", "ねむり":"sleep",
        "こおり":"freeze", "どく":"poison", "もうどく":"poison"]

    static func normalized(_ raw: String) -> String {
        raw.precomposedStringWithCompatibilityMapping.replacingOccurrences(of:"−", with:"-")
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private static func groups(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern:pattern),
              let match = regex.firstMatch(in:text, range:NSRange(text.startIndex..., in:text)) else {return nil}
        return (1..<match.numberOfRanges).map {
            guard let range = Range(match.range(at:$0), in:text) else {return ""}
            return String(text[range])
        }
    }
    static func absoluteBoost(_ raw: String) -> [String:Any]? {
        guard let parts = groups(normalized(raw), #"^(こうげき|ぼうぎょ|とくこう|とくぼう|すばやさ|命中|回避)(?:\s+|:\s*)([+-]?[0-6])$"#),
              let stat = statNames[parts[0]], let stage = Int(parts[1]), (-6...6).contains(stage) else {return nil}
        return ["stat":stat, "stage":stage, "semantics":"ABSOLUTE_DISPLAY_CANDIDATE"]
    }
    static func visibleLabel(_ raw: String, domain: String) -> [String:Any]? {
        let text = normalized(raw)
        let prefixes = domain == "visible_ability_label" ? ["特性:", "とくせい:"] : ["持ち物:", "もちもの:"]
        guard let prefix = prefixes.first(where:{text.hasPrefix($0)}) else {return nil}
        let label = String(text.dropFirst(prefix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !label.isEmpty, label.count <= 128 else {return nil}
        return ["label":label, "visibility":"TEXT_LABEL_ONLY"]
    }
    static func literal(_ raw: String, domain: String) -> Any {
        let text = normalized(raw)
        if domain == "absolute_boost", let boost = absoluteBoost(text) {return boost}
        if domain == "visible_ability_label" || domain == "visible_item_label",
           let label = visibleLabel(text, domain:domain) {return label}
        let compact = text.replacingOccurrences(of:" ", with:"")
        if timedDomains.contains(domain) {
            if let parts = groups(compact, #"^(.+?):?(あと|残り)?([0-9]{1,2})ターン$"#), let count = Int(parts[2]) {
                let label = parts[0].hasSuffix(":") ? String(parts[0].dropLast()) : parts[0]
                // A total duration or a message mentioning turns is never a remaining counter.
                var remaining: Any = NSNull()
                if !parts[1].isEmpty {remaining = count}
                return ["label":label, "remaining_turns":remaining,
                    "duration_semantics":parts[1].isEmpty ? "UNKNOWN" : "EXPLICIT_REMAINING_CANDIDATE"]
            }
            return ["label":compact, "remaining_turns":NSNull(), "duration_semantics":"UNKNOWN"]
        }
        if domain == "major_status", let kind = statuses[compact] {
            let severity: Any = kind == "poison" ? (compact == "もうどく" ? "BAD_POISON_TEXT_CANDIDATE" : "UNKNOWN") : NSNull()
            return ["kind":kind, "poison_severity":severity, "scope":"TEXT_LABEL_ONLY"]
        }
        return text
    }
    private static func integer(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
              n.doubleValue >= 0, n.doubleValue < Double(Int64.max), n.doubleValue == Double(n.int64Value) else {return nil}
        return n.int64Value
    }
    private static func canonical(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject:[value], options:[.sortedKeys, .withoutEscapingSlashes]) else {return nil}
        return String(data:data, encoding:.utf8)
    }
    private static func components(_ candidate: [String:Any]) -> [(String, Any)] {
        guard let domain = candidate["domain"] as? String else {return []}
        let value = candidate["value"]
        if domain == "hp_percent", let number = value as? NSNumber {return [("value", number.doubleValue)]}
        if ["hp", "pp", "hp_or_pp"].contains(domain), let value = value {return [("value", value)]}
        guard let object = value as? [String:Any] else {return []}
        if domain == "absolute_boost", let stat = object["stat"] as? String, let stage = object["stage"] {
            return [("stage:" + stat, stage)]
        }
        if domain == "major_status", let kind = object["kind"] as? String {return [("kind", kind)]}
        if domain == "visible_ability_label" || domain == "visible_item_label", let label = object["label"] as? String {
            return [("label", label)]
        }
        if timedDomains.contains(domain), let label = object["label"] as? String {
            var result: [(String,Any)] = ["weather", "terrain"].contains(domain) ? [("label", label)] : []
            if let count = integer(object["remaining_turns"]) {result.append(("remaining_turns:" + label, count))}
            return result
        }
        return []
    }
    /// Compare interpretations only at exactly the same bound ROI. No overlap heuristic,
    /// cross-frame accumulation, unknown-vs-known disagreement, or inferred owner.
    static func conflicts(_ candidates: [[String:Any]]) -> [[String:Any]] {
        struct Group {
            var indices: [Int]
            var values: Set<String>
            var record: [String:Any]
        }
        var groups = [String:Group]()
        for (index, candidate) in candidates.enumerated() {
            guard let session = candidate["capture_session_id"] as? String, !session.isEmpty,
                  let frame = integer(candidate["frame_id"]), frame > 0,
                  let epoch = integer(candidate["epoch"]), epoch > 0,
                  let image = candidate["image_sha256"] as? String, image.utf8.count == 64,
                  let roi = candidate["roi"] as? [String:Any],
                  let x = integer(roi["x"]), let y = integer(roi["y"]),
                  let w = integer(roi["width"]), w > 0, let h = integer(roi["height"]), h > 0,
                  candidate["roi_coordinate_space"] as? String == "ANALYSIS_PIXELS_TOP_LEFT",
                  let domain = candidate["domain"] as? String,
                  candidate["side"] as? String == "UNKNOWN_OWNER" else {continue}
            for (semanticKey, value) in components(candidate) {
                guard let key = canonical([session, frame, epoch, image, x, y, w, h, domain, semanticKey]),
                      let comparable = canonical(value) else {continue}
                if var group = groups[key] {
                    group.indices.append(index); group.values.insert(comparable); groups[key] = group
                } else {
                    groups[key] = Group(indices:[index], values:[comparable], record:[
                        "domain":domain, "semantic_key":semanticKey, "capture_session_id":session,
                        "frame_id":frame, "epoch":epoch, "image_sha256":image, "roi":roi,
                        "knowledge_state":"CONFLICT", "scope":"OCR_INTERPRETATION_ONLY",
                        "reason":"DIFFERENT_VALUES_SAME_BOUND_FRAME_AND_ROI",
                        "side":"UNKNOWN_OWNER", "current_state_eligible":false])
                }
            }
        }
        return groups.values.filter {$0.values.count > 1}.sorted {
            let a = $0.indices.first ?? 0, b = $1.indices.first ?? 0
            return a == b ? ($0.record["semantic_key"] as? String ?? "") < ($1.record["semantic_key"] as? String ?? "") : a < b
        }.map { group in
            var record = group.record
            record["candidate_indices"] = group.indices
            record["evidence_refs"] = group.indices.compactMap { candidates[$0]["evidence_ref"] as? String }
            return record
        }
    }
}
