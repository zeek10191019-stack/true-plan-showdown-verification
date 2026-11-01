import Foundation
import CoreFoundation

/// Bounded alternatives from one Vision observation, not independent readings.
enum R553OCRAlternatives {
    struct Variant {
        let text: String
        let confidence: Double?
        let rank: Int
        func reference(reading: Int) -> String {
            let root = "payload_json.readings[\(reading)]"
            return rank == 0 ? root : root + ".ocr_alternatives[\(rank)]"
        }
    }
    static func confidence(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, (0...1).contains(n.doubleValue) else {return nil}
        return n.doubleValue
    }
    static func expand(_ row: [String:Any]) -> [Variant]? {
        guard let raw = row["raw_text"] as? String, !raw.isEmpty, raw.count <= 256 else {return nil}
        let primary = Variant(text:raw,confidence:confidence(row["confidence"]),rank:0)
        guard let object = row["ocr_alternatives"] else {return [primary]}
        guard let rows = object as? [[String:Any]], (1...3).contains(rows.count) else {return nil}
        var result = [Variant]()
        for (index, item) in rows.enumerated() {
            guard let rank = item["rank"] as? NSNumber, CFGetTypeID(rank) != CFBooleanGetTypeID(),
                  rank.doubleValue == Double(index),
                  let text = item["raw_text"] as? String, !text.isEmpty, text.count <= 256,
                  let score = confidence(item["confidence"]),
                  index != 0 || (text == raw && primary.confidence == score) else {return nil}
            if let previous=result.last?.confidence, previous<score {return nil}
            result.append(Variant(text:text,confidence:score,rank:index))
        }
        return result
    }
}
