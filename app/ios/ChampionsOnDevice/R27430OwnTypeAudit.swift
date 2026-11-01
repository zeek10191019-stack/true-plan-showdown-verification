import Foundation

// R27.430: read-only own move type diagnostic.
// Does NOT use screen color, guess an ability from species, authorize an action,
// or replace the Current-Season Frozen Canonical DB. Catalog is a LIMITED audit subset.
enum R27430OwnTypeAudit {
    enum AbilityEvidence: String, CaseIterable {
        case unknown = "未確認"
        case pixilate = "フェアリースキン有効（実機確認）"
        case aerilate = "スカイスキン有効（実機確認）"
        case noConversion = "タイプ変換なし（実機確認）"
    }
    enum Category { case physical, special, status }
    struct MoveFact {
        let name: String
        let baseType: String
        let category: Category
    }
    struct Resolution {
        let effectiveType: String?
        let typeBoost: Double?
        let status: String
        var resolved: Bool { effectiveType != nil && typeBoost != nil }
    }
    // Research subset only; exact name OCR must first be matched to a confirmed
    // user-entered move name from the SAME frame. Unknown moves never default.
    private static let fixedFacts: [String: MoveFact] = {
        let rows: [(String, String, Category)] = [
            ("つるぎのまい", "ノーマル", .status),
            ("かげうち", "ゴースト", .physical),
            ("じゃれつく", "フェアリー", .physical),
            ("ウッドハンマー", "くさ", .physical),
            ("ハイパーボイス", "ノーマル", .special),
            ("みきり", "かくとう", .status),
            ("あくび", "ノーマル", .status),
            ("ねがいごと", "ノーマル", .status),
            ("すてみタックル", "ノーマル", .physical),
            ("ムーンフォース", "フェアリー", .special)
        ]
        return Dictionary(uniqueKeysWithValues: rows.map {
            ($0.0, MoveFact(name: $0.0, baseType: $0.1, category: $0.2))
        })
    }()
    private static let conditionalMoves: Set<String> = [
        "ウェザーボール", "だいちのはどう", "さばきのつぶて",
        "マルチアタック", "テクノバスター", "めざめるダンス",
        "テラバースト", "しぜんのめぐみ"
    ]
    static func resolve(exactlyVerifiedMove: String,
                        evidence: AbilityEvidence,
                        exactSameFrameVerified: Bool,
                        abilityEffectStateVerified: Bool) -> Resolution {
        guard exactSameFrameVerified else {
            return Resolution(effectiveType:nil,typeBoost:nil,status:"未認証：技名と同一フレームの正解照合が必要")
        }
        let name = exactlyVerifiedMove.trimmingCharacters(in:.whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
        guard !conditionalMoves.contains(name) else {
            return Resolution(effectiveType:nil,typeBoost:nil,status:"保留：状況依存の技タイプ。別の仕様検証が必要")
        }
        guard let fact=fixedFacts[name] else {
            return Resolution(effectiveType:nil,typeBoost:nil,status:"保留：凍結DB未接続・この技の検証済みデータなし")
        }
        guard evidence != .unknown, abilityEffectStateVerified else {
            return Resolution(effectiveType:nil,typeBoost:nil,status:"未認証：現在の特性・特性効果の有効状態が不明")
        }
        let converted = fact.baseType == "ノーマル" && evidence != .noConversion
        let finalType: String
        switch evidence {
        case .pixilate: finalType=converted ? "フェアリー" : fact.baseType
        case .aerilate: finalType=converted ? "ひこう" : fact.baseType
        case .noConversion: finalType=fact.baseType
        case .unknown:
            return Resolution(effectiveType:nil,typeBoost:nil,status:"未認証：特性不明")
        }
        // A status move may change type, but its power does not get a 1.2 multiplier.
        let boost = converted && fact.category != .status ? 1.2 : 1.0
        return Resolution(effectiveType:finalType,typeBoost:boost,
            status: converted ? "限定DB照合・スキンによる変換" : "限定DB照合・基本タイプを維持")
    }
    static let certifiedFullDatabase = false
    static let allowedInBattleRecommendations = false
}
