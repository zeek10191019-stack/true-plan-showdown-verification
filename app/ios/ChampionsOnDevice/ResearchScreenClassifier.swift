import Foundation

// Structural text candidates only. Conflicting screen signals remain unknown.
enum ResearchScreenClassifier {
    static func classify(_ tokens: [String]) -> String {
        let normalized = tokens.map { $0.precomposedStringWithCompatibilityMapping }
        let exact = Set(normalized.map { $0.filter { !$0.isWhitespace }.uppercased() })
        // A label may share an OCR box with its timer. Prose and substrings
        // such as COMMANDER must not become a command-screen anchor.
        let hasCommand = exact.contains {
            $0.range(of:#"^COMMAND(?::?[0-9]{1,3})?$"#,options:.regularExpression) != nil
        }
        let hasExplainButton = exact.contains("技の説明")
        let hasMoveCategory = exact.contains("技分類")
        let detailCount = ["威力", "命中", "効果範囲"].filter { keyword in
            exact.contains(keyword)
        }.count
        var kinds = [String]()
        if hasCommand && hasExplainButton && (hasMoveCategory || detailCount >= 1) {
            kinds.append("move_selection_with_move_details_overlay_candidate")
        } else if hasCommand && hasExplainButton {
            kinds.append("move_selection_candidate")
        } else if hasCommand && !exact.isDisjoint(with:["たたかう","こうたい","ポケモン","にげる"]) {
            kinds.append("normal_command_candidate")
        }
        if !exact.isDisjoint(with:["選出","選出順","出すポケモンを選んでください"]) &&
           !exact.isDisjoint(with:["決定","完了","あと3匹","あと2匹"]) {
            kinds.append("party_selection_candidate")
        }
        if !exact.isDisjoint(with:["相手のパーティ","対戦相手のポケモン"]) &&
           !exact.isDisjoint(with:["パーティ確認","見せ合い","選出時間"]) {
            kinds.append("party_preview_candidate")
        }
        if !exact.isDisjoint(with:["交代先を選んでください","交代するポケモンを選んでください"]) &&
           !exact.isDisjoint(with:["もどる","キャンセル","決定"]) {
            kinds.append("switch_selection_candidate")
        }
        if !exact.isDisjoint(with:["YOUWIN","YOULOSE","対戦終了","勝利","敗北"]) {
            kinds.append("battle_end_candidate")
        }
        if kinds.isEmpty && !exact.isDisjoint(with:["メガシンカ","メガ進化"]) {
            kinds.append("animation_or_battle_message_candidate")
        }
        return kinds.count == 1 ? kinds[0] : "unknown"
    }
}
