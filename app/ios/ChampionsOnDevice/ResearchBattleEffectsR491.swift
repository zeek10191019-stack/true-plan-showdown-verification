import Foundation

enum TPResearchEffectDomain: String, CaseIterable, Codable {
    case species, form, megaActivation, megaUsage
    case hp, pp, majorStatus, volatileStatus, statStages, ability, heldItem
    case weather, terrain, trickRoom, gravity, magicRoom, wonderRoom
    case reflect, lightScreen, auroraVeil, tailwind, safeguard, mist
    case stealthRock, spikes, toxicSpikes, stickyWeb
    case leechSeed, substitute, protect, encore, taunt, disable, yawn, perishSong
    case confusion, trapping, wish, healingWish
    case turnBoundary, uiScreen, battleEnd
}
enum TPResearchEffectOwner: String, Codable { case own, opponent, field, unknown }
enum TPResearchEffectOrigin: String, Codable {
    case ocrBattleMessage, ocrStatusIcon, ocrMoveMenu, uiIconClassifier
    case formImageClassifier, animationClassifier, temporalTracker, manualGroundTruth
}
enum TPResearchEffectLifecycle: String, Codable { case observed, started, ended }
enum TPResearchEffectJudgement: String, Codable {
    case candidate, multiSourceCorroborated, conflict, stale, unknown
}
struct TPResearchEffectKey: Hashable, Codable {
    let owner: TPResearchEffectOwner
    let domain: TPResearchEffectDomain
    let slot: String? // requires independent verified party/active identity
}
struct TPResearchEffectEvidence: Codable {
    let battleID: String
    let epoch: Int
    let frameID: Int
    let monotonicMS: Int64
    let turn: Int? // nil if no independently validated turn
    let ownerVerified: Bool
    let roiVerified: Bool
    let key: TPResearchEffectKey
    let candidateValue: String // research string, never an action recommendation
    var lifecycle: TPResearchEffectLifecycle = .observed
    let origin: TPResearchEffectOrigin
    let confidence: Double?
    let modelVersion: String? // required for an ML-derived evidence channel
}
struct TPResearchEffectSnapshot: Codable {
    let schema: String
    let key: TPResearchEffectKey
    let candidateValue: String?
    let judgement: TPResearchEffectJudgement
    let evidenceCount: Int
    let independentOrigins: Int
    let turnKnown: Bool
    let admissionAllowed: Bool
    let reason: String
}

struct TPResearchBattleEffectLedger {
    private(set) var battleID: String?
    private(set) var epoch: Int?
    private(set) var lastFrameID: Int = -1
    private(set) var lastMonotonicMS: Int64 = -1
    private var evidence: [TPResearchEffectKey: [TPResearchEffectEvidence]] = [:]
    private(set) var rejected: [String] = []
    static let admissionAllowed = false // until separately certified engine-wide
    static let schema = "trueplan.research-battle-effects.v1"

    mutating func startBattle(_ id: String, epoch: Int) {
        battleID = id
        self.epoch = epoch
        lastFrameID = -1
        lastMonotonicMS = -1
        evidence = [:]
        rejected = []
    }
    mutating func rotateEpoch(_ next: Int) {
        guard let current = epoch, next > current else { return }
        epoch = next
        evidence = [:]
        lastFrameID = -1
        lastMonotonicMS = -1
    }
    @discardableResult mutating func observe(_ e: TPResearchEffectEvidence) -> Bool {
        guard !e.battleID.isEmpty, e.battleID == battleID else {
            rejected.append("BATTLE_ID_MISMATCH"); return false
        }
        guard e.epoch == epoch else {
            rejected.append("EPOCH_MISMATCH"); return false
        }
        guard e.frameID >= 0, e.frameID >= lastFrameID,
              e.monotonicMS >= 0, e.monotonicMS >= lastMonotonicMS else {
            rejected.append("FRAME_OR_MONOTONIC_ORDER"); return false
        }
        guard !e.candidateValue.isEmpty,
              e.candidateValue.count < 128 else {
            rejected.append("INVALID_VALUE"); return false
        }
        guard e.confidence == nil || (e.confidence!.isFinite && (0...1).contains(e.confidence!)) else {
            rejected.append("INVALID_CONFIDENCE"); return false
        }
        if [.formImageClassifier, .animationClassifier, .uiIconClassifier].contains(e.origin) {
            guard let modelVersion = e.modelVersion, !modelVersion.isEmpty else {
                rejected.append("MODEL_VERSION_REQUIRED"); return false
            }
        }
        if e.origin == .ocrMoveMenu && e.key.domain != .uiScreen && e.key.domain != .pp {
            rejected.append("MOVE_MENU_IS_NOT_EFFECT_EVENT"); return false
        }
        lastFrameID = e.frameID
        lastMonotonicMS = e.monotonicMS
        evidence[e.key, default: []].append(e)
        return true
    }
    func snapshot(_ key: TPResearchEffectKey) -> TPResearchEffectSnapshot {
        let fullHistory = evidence[key] ?? []
        guard !fullHistory.isEmpty else {
            return TPResearchEffectSnapshot(schema: Self.schema, key:key,candidateValue:nil,
                judgement:.unknown,evidenceCount:0,independentOrigins:0,turnKnown:false,
                admissionAllowed:false,reason:"NO_OBSERVATION")
        }
        let newestTurn = fullHistory.last?.turn
        let sameTurn = fullHistory.filter { $0.turn == newestTurn }
        let finalLifecycle = sameTurn.last?.lifecycle ?? .observed
        let list = sameTurn.filter { $0.lifecycle == finalLifecycle }
        let values = Set(list.map(\.candidateValue))
        let origins = Set(list.map(\.origin))
        let turnKnown = newestTurn != nil && list.allSatisfy {$0.turn == newestTurn}
        let ownerVerified = list.allSatisfy { $0.ownerVerified && $0.roiVerified }
        let isML = list.contains { [.formImageClassifier,.animationClassifier,.uiIconClassifier].contains($0.origin) }
        let isManualOnly = origins == Set([.manualGroundTruth])
        let conflict = values.count > 1
        let sufficient = origins.count >= 2 && ownerVerified && turnKnown && !isManualOnly && isML
        let judgement: TPResearchEffectJudgement = conflict ? .conflict : (sufficient ? .multiSourceCorroborated : .candidate)
        let reason = conflict ? "CONFLICTING_VALUES" : (sufficient ? "DIAGNOSTIC_MULTISOURCE_ONLY" : "INSUFFICIENT_INDEPENDENT_EVIDENCE")
        return TPResearchEffectSnapshot(schema:Self.schema,key:key,candidateValue:conflict ? nil : list.last?.candidateValue,
            judgement:judgement,evidenceCount:list.count,independentOrigins:origins.count,
            turnKnown:turnKnown,admissionAllowed:false,reason:reason)
    }
    func summary() -> [String:Int] {
        var result = [String:Int]()
        for d in TPResearchEffectDomain.allCases {result[d.rawValue] = 0}
        for (k,v) in evidence where !v.isEmpty {result[k.domain.rawValue,default:0] += 1}
        return result
    }
}

enum TPResearchEffectChannels {
    static let uiText: Set<TPResearchEffectDomain> = [.species,.form,.hp,.pp,.majorStatus,.statStages,.heldItem,.ability,.weather,.terrain,.trickRoom,.reflect,.lightScreen,.auroraVeil,.stealthRock,.spikes,.toxicSpikes,.stickyWeb,.tailwind,.substitute,.yawn,.encore,.taunt]
    static let visualState: Set<TPResearchEffectDomain> = [.species,.form,.megaActivation,.majorStatus,.statStages,.weather,.terrain,.reflect,.lightScreen,.auroraVeil,.trickRoom,.stealthRock,.spikes,.toxicSpikes,.stickyWeb]
    static let eventTimeline: Set<TPResearchEffectDomain> = Set(TPResearchEffectDomain.allCases)
    static func label(_ domain: TPResearchEffectDomain) -> String {
        switch domain {
        case .megaActivation: return "メガシンカ開始イベント"
        case .megaUsage: return "メガ使用履歴"
        case .weather: return "天候"
        case .terrain: return "フィールド"
        case .trickRoom: return "トリックルーム"
        case .reflect: return "リフレクター"
        case .lightScreen: return "ひかりのかべ"
        case .auroraVeil: return "オーロラベール"
        case .majorStatus: return "状態異常"
        case .statStages: return "能力ランク"
        case .form: return "通常形態・メガ形態"
        default: return domain.rawValue
        }
    }
}
