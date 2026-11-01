import Foundation

/// Fail-closed semantic check for existing, historically scoped OCR position hints.
/// This gate cannot prove the Pokémon, the battle side, or a live state.
/// It only rejects an OCR string that cannot describe the proposed field kind.
enum R566RoleTextFence {
    private static func compact(_ raw: String) -> String {
        raw.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"　",with:"")
            .replacingOccurrences(of:"\n",with:"").replacingOccurrences(of:"\r",with:"")
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private static func matches(_ value: String, _ regex: String) -> Bool {
        value.range(of:regex,options:.regularExpression) != nil
    }
    private static func ratio(_ text: String, pp: Bool) -> Bool {
        var data=compact(text)
        if pp && data.hasPrefix("HP") {return false}
        if !pp && data.hasPrefix("PP") {return false}
        if data.hasPrefix("HP") || data.hasPrefix("PP") {data=String(data.dropFirst(2))}
        guard matches(data,pp ? #"^[0-9]{1,2}/[0-9]{1,2}$"# : #"^[0-9]{1,4}/[0-9]{1,4}$"#) else {return false}
        let pair=data.split(separator:"/").compactMap{Int($0)}
        guard pair.count==2,pair[1]>0,pair[0]<=pair[1] else {return false}
        return !pp || pair[1]<=64
    }
    private static func percentage(_ text:String) -> Bool {
        let t=compact(text)
        guard matches(t,#"^[0-9]{1,3}(\.[0-9]{1,2})?%$"#),let val=Double(t.dropLast()) else {return false}
        return (0...100).contains(val)
    }
    private static func japaneseLabel(_ text: String) -> Bool {
        let s=compact(text)
        return (2...24).contains(s.count) &&
            matches(s,#"^[ぁ-ゖァ-ヺー一-龯A-Za-z0-9・♀♂]+$"#) &&
            matches(s,#"[ぁ-ゖァ-ヺ一-龯]"#)
    }
    static func accepts(role: String, raw: String) -> Bool {
        switch role {
        case "own_hp":return ratio(raw,pp:false)
        case "opponent_hp":return percentage(raw) || ratio(raw,pp:false)
        case "own_name","opponent_name","move_name":return japaneseLabel(raw)
        case "move_pp":return ratio(raw,pp:true)
        default:return false
        }
    }
    static func inspect(role: String, site: R553LayoutReading.Site) -> Bool {
        // A valid source reference/rectangle/frame is checked by R565 upstream.
        guard site.reading>=0,site.reading<512,site.rank>=0,site.rank<32,
            site.text.utf8.count<=256 else {return false}
        return accepts(role:role,raw:site.text)
    }
}
