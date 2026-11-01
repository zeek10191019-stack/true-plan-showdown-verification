import Foundation

/// R569: Require all OCR alternatives assigned to one provisional field to
/// encode the same *literal value*. This does not identify a Pokémon/side/turn.
enum R569RoleConsensusFence {
    private static func compact(_ text:String)->String {
        R552StateValues.normalized(text)
            .replacingOccurrences(of:" ",with:"")
            .replacingOccurrences(of:"　",with:"")
            .replacingOccurrences(of:"\n",with:"")
            .replacingOccurrences(of:"\r",with:"")
    }
    private static func key(role:String,text:String)->String? {
        guard R566RoleTextFence.accepts(role:role,raw:text) else { return nil }
        var value=compact(text)
        switch role {
        case "own_hp","opponent_hp":
            if value.hasPrefix("HP") {value=String(value.dropFirst(2))}
            if value.hasSuffix("%") {
                let raw=String(value.dropLast())
                let parts=raw.split(separator:".",omittingEmptySubsequences:false)
                guard (1...2).contains(parts.count),
                      let whole=Int(parts[0]),whole<=100 else {return nil}
                let fractional=parts.count==2 ? String(parts[1]) : ""
                guard fractional.count<=2 else {return nil}
                let fraction=Int(fractional.padding(toLength:2,withPad:"0",startingAt:0)) ?? 0
                let basis=whole*100+fraction
                guard basis<=10000 else {return nil}
                return "P:\(basis)"
            }
            let parts=value.split(separator:"/")
            guard parts.count==2,let current=Int(parts[0]),let maximum=Int(parts[1]),
                  maximum>0,current<=maximum else {return nil}
            return "F:\(current)/\(maximum)"
        case "own_name","opponent_name","move_name":
            return value.isEmpty ? nil : "N:"+value
        default:return nil
        }
    }
    static func inspect(role:String,sites:[R553LayoutReading.Site])->Bool {
        guard role != "move_pp",!sites.isEmpty,sites.count<=32 else {return false}
        var expected:String?
        for site in sites {
            guard site.text.utf8.count<=256,
                  let value=key(role:role,text:site.text) else {return false}
            if let expected, expected != value {return false}
            expected=value
        }
        return expected != nil
    }
    /// Expose the literal value after consensus, without assigning an owner.
    static func literalValue(role:String,sites:[R553LayoutReading.Site])->Any? {
        guard inspect(role:role,sites:sites),let first=sites.first,
              let value=key(role:role,text:first.text) else {return nil}
        if value.hasPrefix("N:") {return String(value.dropFirst(2))}
        if value.hasPrefix("P:"),let basis=Int(value.dropFirst(2)) {return Double(basis)/100.0}
        if value.hasPrefix("F:") {
            let parts=value.dropFirst(2).split(separator:"/").compactMap {Int($0)}
            if parts.count==2 {return ["current":parts[0],"maximum":parts[1]]}
        }
        return nil
    }
}
