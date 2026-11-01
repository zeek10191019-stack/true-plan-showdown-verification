import Foundation

/// Research-only binding of an OCR reading to a verified image/ROI owner.
/// It cannot authorize a battle action. All non-verified inputs stay outside Battle State.
public enum R526Field: Hashable, Codable, CustomStringConvertible {
    case ownHP, opponentHPPercent, ownSpecies, opponentSpecies, weather
    case moveName(Int), movePP(Int), opponentMegaMarker

    public var description: String {
        switch self {
        case .ownHP: return "own_hp"
        case .opponentHPPercent: return "opponent_hp_percent"
        case .ownSpecies: return "own_species"
        case .opponentSpecies: return "opponent_species"
        case .weather: return "weather"
        case .moveName(let i): return "move_\(i)_name"
        case .movePP(let i): return "move_\(i)_pp"
        case .opponentMegaMarker: return "opponent_mega_marker"
        }
    }
}

public struct R526Frame: Equatable {
    public let battleID: String
    public let epoch: Int
    public let frameID: Int
    public let rawSHA256: String
    public let observedSHA256: String
    public let capturedAtMs: Int64
    public let nowMs: Int64
    public let isHistorical: Bool
    public let orientationCertified: Bool
    public let layoutCertified: Bool
    public let ownerModelCertified: Bool
    public init(battleID: String, epoch: Int, frameID: Int, rawSHA256: String,
                observedSHA256: String, capturedAtMs: Int64, nowMs: Int64,
                isHistorical: Bool, orientationCertified: Bool,
                layoutCertified: Bool, ownerModelCertified: Bool) {
        self.battleID=battleID; self.epoch=epoch; self.frameID=frameID
        self.rawSHA256=rawSHA256; self.observedSHA256=observedSHA256
        self.capturedAtMs=capturedAtMs; self.nowMs=nowMs
        self.isHistorical=isHistorical; self.orientationCertified=orientationCertified
        self.layoutCertified=layoutCertified; self.ownerModelCertified=ownerModelCertified
    }
}

/// Normalized coordinates in the *oriented image*, TOP-LEFT origin, never display points.
public struct R526ROI: Equatable {
    public let x: Double, y: Double, w: Double, h: Double
    public init(_ x: Double,_ y: Double,_ w: Double,_ h: Double) {
        self.x=x; self.y=y; self.w=w; self.h=h
    }
    public var valid: Bool {
        [x,y,w,h].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && w > 0 && h > 0
        && x+w <= 1.000001 && y+h <= 1.000001
    }
    public var midX: Double {x+w/2}
    public var midY: Double {y+h/2}
}
public struct R526OCRReading {
    public let battleID: String
    public let epoch: Int
    public let frameID: Int
    public let observedSHA256: String
    public let roi: R526ROI?
    public let text: String
    public let confidence: Double?
    public let field: R526Field
    public init(battleID: String, epoch: Int, frameID: Int,
                observedSHA256: String, roi: R526ROI?, text: String,
                confidence: Double?, field: R526Field) {
        self.battleID=battleID;self.epoch=epoch;self.frameID=frameID
        self.observedSHA256=observedSHA256;self.roi=roi;self.text=text
        self.confidence=confidence;self.field=field
    }
}
public enum R526Disposition: String { case researchBound, unverified, rejected, conflict }
public struct R526Result {
    public let field: R526Field
    public let disposition: R526Disposition
    public let text: String?
    public let reason: String
    public let decisionEligible: Bool = false
}

public enum R526ObservationIngress {
    private static func isHexSHA(_ s:String) -> Bool {
        s.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func zone(_ f:R526Field, _ r:R526ROI) -> Bool {
        // Coarse layout constraints are an extra reject fence, NOT an ownership classifier.
        // Layout is defined for the user's 2796×1290 move-selection screen only.
        switch f {
        case .ownHP, .ownSpecies:
            return r.midX >= 0.07 && r.midX <= 0.42 && r.midY >= 0.75 && r.midY <= 0.99
        case .opponentHPPercent, .opponentSpecies, .opponentMegaMarker:
            return r.midX >= 0.70 && r.midX <= 0.98 && r.midY >= 0.00 && r.midY <= 0.23
        case .weather:
            return r.midX >= 0.12 && r.midX <= 0.36 && r.midY >= 0.00 && r.midY <= 0.14
        case .moveName(let index), .movePP(let index):
            guard (1...4).contains(index), r.midX >= 0.69 && r.midX <= 0.98 else {return false}
            let centers: [Double] = [0.478,0.598,0.717,0.838]
            return abs(r.midY - centers[index-1]) < 0.065
        }
    }
    private static func textValid(_ f:R526Field, _ input:String) -> Bool {
        let v=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !v.isEmpty && v.utf8.count <= 180 else { return false }
        switch f {
        case .ownHP:
            let parts=v.split(separator:"/",omittingEmptySubsequences:false)
            guard parts.count==2, let a=Int(parts[0]),let b=Int(parts[1]) else{return false}
            return a>=0 && b>0 && b<=999 && a<=b
        case .opponentHPPercent:
            guard v.hasSuffix("%"), let p=Int(v.dropLast()) else{return false}
            return (0...100).contains(p)
        case .movePP:
            let parts=v.split(separator:"/",omittingEmptySubsequences:false)
            guard parts.count==2,let a=Int(parts[0]),let b=Int(parts[1]) else{return false}
            return a>=0 && a<=b && b>0 && b<=99
        case .opponentMegaMarker:
            // OCR of a species name or the sandstorm cannot prove a mega form.
            return false
        default: return true
        }
    }
    public static func route(_ readings:[R526OCRReading], frame:R526Frame,
                             maxAgeMs:Int64=1500) -> [R526Result] {
        var raw: [R526Result] = []
        let validFrame = !frame.battleID.isEmpty && frame.epoch>=0 && frame.frameID>=0
            && isHexSHA(frame.rawSHA256) && isHexSHA(frame.observedSHA256)
            && frame.nowMs >= frame.capturedAtMs
            && frame.nowMs-frame.capturedAtMs <= maxAgeMs && !frame.isHistorical
        for o in readings {
            func put(_ status:R526Disposition,_ reason:String,_ text:String?=nil) {
                raw.append(R526Result(field:o.field,disposition:status,text:text,reason:reason))
            }
            guard validFrame else {put(.rejected,"INVALID_STALE_OR_HISTORICAL_FRAME");continue}
            guard o.battleID==frame.battleID && o.epoch==frame.epoch && o.frameID==frame.frameID &&
                o.observedSHA256==frame.observedSHA256 else {
                put(.rejected,"PROVENANCE_MISMATCH");continue
            }
            guard let roi=o.roi, roi.valid else {put(.unverified,"MISSING_OR_INVALID_OCR_BOUNDING_BOX");continue}
            guard frame.orientationCertified && frame.layoutCertified && frame.ownerModelCertified else {
                put(.unverified,"ORIENTATION_LAYOUT_OR_OWNER_UNCERTIFIED");continue
            }
            guard zone(o.field,roi) else {put(.rejected,"FIELD_OUTSIDE_EXPECTED_ZONE");continue}
            guard let c=o.confidence,c.isFinite,c>=0.95 && c<=1 else {
                put(.unverified,"OCR_CONFIDENCE_UNVERIFIED");continue
            }
            guard textValid(o.field,o.text) else {put(.unverified,"SEMANTIC_VALUE_UNVERIFIED");continue}
            put(.researchBound,"ROI_BOUND_RESEARCH_NOT_BATTLE_CERTIFIED",o.text.trimmingCharacters(in:.whitespacesAndNewlines))
        }
        // Contradictory candidate values for the same field/frame must not silently overwrite.
        let grouped=Dictionary(grouping:raw.indices.filter{raw[$0].disposition == .researchBound},
                              by:{raw[$0].field})
        for (_,indices) in grouped {
            if Set(indices.compactMap{raw[$0].text}).count > 1 {
                for i in indices {raw[i]=R526Result(field:raw[i].field,disposition:.conflict,
                                                   text:nil,reason:"CONFLICTING_SAME_FRAME_READINGS")}
            }
        }
        return raw
    }
}
