import Foundation

/// Research-only diagnostic exchange format. This never confers recognition or advice certification.
public enum DiagnosticsPacket {
    public static let schema = "R522_ONE_TAP_DIAGNOSTICS_V1"
    public static let sourceNames = ["r519_vision", "r520_roi_session", "r521_roi_collision"]
    private static let forbiddenKeys: Set<String> = [
        "image_png_base64", "image_bytes", "image_base64", "image_data",
        "raw_text", "ocr_text", "ocr_raw", "payload_json", "screenshot_base64",
        "token", "api_key", "authorization", "access_token", "password"
    ]

    /// Returns one compact, redacted JSON report with all three diagnostics.
    /// Inputs must be JSON objects. Malformed/missing data is explicitly marked; never synthesized.
    public static func assemble(
        visionJSON: String?, sessionJSON: String?, collisionJSON: String?,
        build: String = "R27.522", frameID: Int? = nil, epoch: Int? = nil,
        generatedAt: Date = Date()
    ) throws -> Data {
        let inputs = [visionJSON, sessionJSON, collisionJSON]
        var sources: [String: Any] = [:]
        var missing: [String] = []
        var invalid: [String] = []
        var redactedPaths: [String] = []

        for (i, name) in sourceNames.enumerated() {
            guard let raw = inputs[i], !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                missing.append(name)
                continue
            }
            guard let bytes = raw.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: bytes),
                  let object = parsed as? [String: Any] else {
                invalid.append(name)
                continue
            }
            sources[name] = clean(object, path: name, redacted: &redactedPaths)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var packet: [String: Any] = [
            "schema": schema,
            "app_build": build,
            "generated_at": formatter.string(from: generatedAt),
            "scope": "APP_LIFETIME_RESEARCH_ONLY",
            "decision_eligible": false,
            "recognition_certified": false,
            "battle_advice_authorized": false,
            "image_bytes_included": false,
            "ocr_raw_text_included": false,
            "source_count": sources.count,
            "sources": sources,
            "missing_sources": missing,
            "invalid_sources": invalid,
            "redacted_paths": redactedPaths.sorted()
        ]
        if let frameID { packet["frame_id"] = frameID }
        if let epoch { packet["epoch"] = epoch }
        return try JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys])
    }

    private static func clean(_ value: Any, path: String, redacted: inout [String]) -> Any {
        if let dict = value as? [String: Any] {
            var output: [String: Any] = [:]
            for (k, v) in dict {
                if forbiddenKeys.contains(k.lowercased()) || k.lowercased().contains("base64") {
                    redacted.append("\(path).\(k)")
                } else {
                    output[k] = clean(v, path: "\(path).\(k)", redacted: &redacted)
                }
            }
            return output
        }
        if let arr = value as? [Any] {
            return arr.enumerated().map { i, v in
                clean(v, path: "\(path)[\(i)]", redacted: &redacted)
            }
        }
        return value
    }
}
import Foundation

/// R523: provenance-aware store for the three *research-only* diagnostic snapshots.
/// It is deliberately independent of Battle State, recommendations and screen capture.
