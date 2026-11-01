import Foundation

/// R567: checks evidence group semantics after R565 proves source references and ROI.
/// The legacy layout parser permits slash-separated PP OCR: `14` followed by `/16`.
/// Rejects incompatible or ambiguous fragments without inferring owner or game state.
enum R567EvidenceGroupFence {
    private static func compact(_ raw:String)->String {
        R552StateValues.normalized(raw).replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"　",with:"")
            .replacingOccurrences(of:"\n",with:"").replacingOccurrences(of:"\r",with:"")
            .trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private static func fullPP(_ raw:String)->(Int,Int)? {
        var value=compact(raw)
        guard !value.hasPrefix("HP") else {return nil}
        if value.hasPrefix("PP") {value=String(value.dropFirst(2))}
        guard value.range(of:#"^[0-9]{1,2}/[0-9]{1,2}$"#, options:.regularExpression) != nil else {return nil}
        let parts=value.split(separator:"/").compactMap{Int($0)}
        guard parts.count==2,parts[1]>0,parts[1]<=64,parts[0]<=parts[1] else {return nil}
        return (parts[0],parts[1])
    }
    private static func roiValid(_ site:R553LayoutReading.Site)->Bool {
        guard site.reading>=0,site.reading<512,site.rank>=0,site.rank<32,
              site.text.utf8.count<=256,let x=site.roi["x"],let y=site.roi["y"],
              let w=site.roi["width"],let h=site.roi["height"],
              x>=0,y>=0,w>0,h>0 else {return false}
        return true
    }
    static func inspect(role:String,sites:[R553LayoutReading.Site])->Bool {
        guard !sites.isEmpty,sites.count<=32,sites.allSatisfy({roiValid($0)}) else {return false}
        guard role=="move_pp" else {
            return sites.allSatisfy{R566RoleTextFence.inspect(role:role,site:$0)}
        }
        return ppValue(sites:sites) != nil
    }
    /// Literal PP only. Alternatives belong to observations, not independent votes.
    /// The same two observations may each have up to three agreeing alternatives.
    static func ppValue(sites:[R553LayoutReading.Site])->[String:Int]? {
        guard !sites.isEmpty,sites.count<=6,sites.allSatisfy({roiValid($0)}) else {return nil}
        let observations=Dictionary(grouping:sites,by:{$0.reading})
        guard observations.count<=2 else {return nil}
        for group in observations.values {
            let ranks=group.map(\.rank)
            guard ranks.count<=3,Set(ranks)==Set(0..<ranks.count),
                  let roi=group.first?.roi,group.allSatisfy({$0.roi==roi}) else {return nil}
        }
        // Complete readings and their alternatives must agree exactly.
        let full=sites.compactMap{fullPP($0.text)}
        if full.count==sites.count {
            // Full PP alternatives must refer to one Vision observation.
            // Two independently observed labels with the same digits are
            // insufficient evidence for a single move's PP slot.
            guard let first=full.first,observations.count==1,
                  full.allSatisfy({$0.0==first.0 && $0.1==first.1}) else {return nil}
            return ["current":first.0,"maximum":first.1]
        }
        guard observations.count==2,full.isEmpty else {return nil}
        let number=sites.filter {compact($0.text).range(of:#"^[0-9]{1,2}$"#,options:.regularExpression) != nil}
        let denominator=sites.filter {compact($0.text).range(of:#"^/[0-9]{1,2}$"#,options:.regularExpression) != nil}
        guard number.count+denominator.count==sites.count,
              Set(number.map(\.reading)).count==1,Set(denominator.map(\.reading)).count==1,
              let n=number.first,let d=denominator.first,n.reading != d.reading,
              let nr=n.roi["y"],let dr=d.roi["y"],nr<dr,
              let nx=n.roi["x"],let dx=d.roi["x"],
              let nw=n.roi["width"],let dw=d.roi["width"],
              let nh=n.roi["height"],let dh=d.roi["height"],
              let numerator=Int(compact(n.text)),let maxPP=Int(compact(d.text).dropFirst()),
              maxPP>0,maxPP<=64,numerator<=maxPP,
              number.allSatisfy({Int(compact($0.text))==numerator}),
              denominator.allSatisfy({Int(compact($0.text).dropFirst())==maxPP}) else {return nil}
        // Keep fragments locally aligned and adjacent. Use subtraction, not abs(Int64),
        // and avoid overflow by bounding the search image coordinates first.
        guard nx<=4096,dx<=4096,nr<=4096,dr<=4096,nw<=4096,dw<=4096,
              nh<=4096,dh<=4096 else {return nil}
        guard nr+nh<=dr,abs(nx-dx)<=2*max(nw,dw),dr-nr<=4*max(nh,dh) else {return nil}
        return ["current":numerator,"maximum":maxPP]
    }
}
