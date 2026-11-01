import Foundation

/// A research-only evidence ledger. It does not perform visual recognition or issue moves.
struct TP497FieldEvidenceLedger {
    enum Field: String, CaseIterable {
        case weather, terrain, trickRoom
        case reflectOwn, reflectOpp, lightScreenOwn, lightScreenOpp
        case statusOwn, statusOpp, megaOwn, megaOpp
        var isMega: Bool { self == .megaOwn || self == .megaOpp }
    }
    enum Source { case hint, visibleUI, corroboratedEvent }
    enum Verdict: String {
        case unknown = "UNKNOWN"
        case hint = "HINT_UNCERTIFIED"
        case seenAtTurn = "SEEN_AT_OBSERVED_TURN"
        case boundedActive = "ACTIVE_WITH_EXPLICIT_DURATION"
        case boundedExpired = "EXPIRED_BY_EXPLICIT_DURATION"
        case uncertain = "STALE_OR_UNRESOLVED"
        case megaSeen = "MEGA_WAS_WITNESSED_NOT_ACTIVE_ASSERTION"
    }
    struct Entry {
        let value: String
        let turn: Int
        let frame: Int64
        let source: Source
        let turnsKnown: Int?
    }
    private(set) var battleID = ""
    private(set) var epoch = -1
    private(set) var lastFrame: Int64 = -1
    private(set) var lastTurn: Int = -1
    private(set) var accepted = 0
    private(set) var rejected = 0
    private(set) var entries: [Field: Entry] = [:]
    mutating func reset(battle: String, epoch: Int) {
        battleID = battle; self.epoch = epoch
        lastFrame = -1; lastTurn = -1; entries = [:]
    }
    /// Absolute turn comes from the observed battle UI, never invented by this ledger.
    @discardableResult mutating func record(battle: String, epoch: Int, frame: Int64,
                   field: Field, value: String, turn: Int, source: Source,
                   explicitlyCertifiedTurns: Int? = nil) -> Bool {
        guard !battle.isEmpty, battle == battleID, epoch == self.epoch,
              frame >= lastFrame, frame > 0, turn >= lastTurn, turn >= 0, !value.isEmpty,
              value.utf8.count <= 80, !value.contains("\n"),
              (explicitlyCertifiedTurns == nil || (explicitlyCertifiedTurns! > 0 && explicitlyCertifiedTurns! <= 16)),
              (!field.isMega || explicitlyCertifiedTurns == nil),
              (source != .hint || explicitlyCertifiedTurns == nil),
              (entries[field].map { frame > $0.frame && turn >= $0.turn } ?? true) else {
            rejected += 1; return false
        }
        let duration = source == .hint ? nil : explicitlyCertifiedTurns
        entries[field] = Entry(value:value,turn:turn,frame:frame,source:source,turnsKnown:duration)
        lastFrame=frame; lastTurn=turn; accepted += 1
        return true
    }
    func verdict(field: Field, nowTurn: Int?, battle: String, epoch: Int) -> Verdict {
        guard battle == battleID, epoch == self.epoch,
              let entry = entries[field] else { return .unknown }
        guard entry.source != .hint else { return .hint }
        if field.isMega { return .megaSeen }
        guard let nowTurn, nowTurn >= entry.turn else { return .uncertain }
        if nowTurn == entry.turn { return .seenAtTurn }
        guard let duration = entry.turnsKnown else { return .uncertain }
        return nowTurn - entry.turn < duration ? .boundedActive : .boundedExpired
    }
}
