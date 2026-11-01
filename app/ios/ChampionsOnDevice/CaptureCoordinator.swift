import Vision
import Foundation
import Combine
import AVFoundation
import CoreImage
import UIKit
import ScreenCaptureKit
import CoreMedia
import CryptoKit

// Research prototype for iOS 27+. Build/entitlement/authorization on-device are NOT verified.
@available(iOS 27.0, *)
final class CaptureCoordinator: NSObject, ObservableObject,
    SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    @Published var status = "端末内OCR研究版・技推薦は無効"
    @Published var running = false
    @Published var requestingPermission = false
    @Published var lastMoveCandidates = ["—", "—", "—", "—"]
    @Published var continuityStatus = "計測待ち・技推薦なし"
    // R27.410: visible only after a background-to-foreground transition.
    // Pixels stay local unless the user explicitly creates and shares evidence JSON.
    @Published var diagnosticPreview: UIImage?
    @Published var diagnosticCandidates = ["—", "—", "—", "—"]
    @Published var diagnosticStatus = "背景で取得したゲーム画面の診断待ち"
    @Published var diagnosticFrameID: Int64 = 0
    @Published var diagnosticFilterStatus = "画面切替候補の除外待ち"
    @Published var diagnosticIsUnfiltered = false
    @Published private(set) var rawTimelineIndex = 0
    @Published private(set) var rawTimelineCount = 0
    @Published private(set) var rawTimelineStatus = "背景履歴の診断待ち"
    @Published private(set) var orientationStatus = "画面方向の診断待ち"
    @Published private(set) var displayTurnLabel = "未判定"
    @Published private(set) var diagnosticDisplayAspect: CGFloat = 1108.0 / 512.0
    @Published private(set) var captureResolutionStatus = "取得解像度の確認待ち（OCR精度未認証）"
    private var captureResolutionPlan = CaptureResolutionPlan.fallback // sampleQueue only
    // Manual display-only ROI calibration; no live OCR or recommendations.
    @Published var calibrationLayout = MoveROICalibration.Layout.portraitLandscapeDiagnostics
    @Published var calibrationVisible = false
    @Published private(set) var calibrationStatus = "4技の仮枠較正待ち・OCR未接続"
    @Published private(set) var calibrationMappedROIs = [String]()
    @Published private(set) var calibrationOverlayROIs = [CGRect]()
    @Published private(set) var manualOCRStatus = "手動OCR未実行・正答率未認証"
    @Published private(set) var researchSpatialDiagnostic = "実機キャプチャの画像寸法・向きの確認待ち／スクリーンショット座標は不使用"
    @Published private(set) var manualOCRLines = [String](repeating:"—",count:4)
    @Published private(set) var manualOCRThumbnails = [UIImage]()
    @Published private(set) var manualOCRPixelSummary = "OCR入力の切り出し画像は未生成"
    @Published private(set) var researchPPDiagnostics = [String]()
    // Research type audit, never part of battle legality or an action recommendation.
    // Explicit own-ability evidence is required; choosing a different frame resets it.
    @Published var confirmedOwnAbilityChoice = "未確認"
    @Published private(set) var ownMoveTypeAuditStatus = "技名4件の厳密照合と現在の特性確認が必要"
    @Published private(set) var ownMoveTypeAuditLines = [String]()
    @Published var manualGroundTruth = [String](repeating: "", count: 4)
    @Published private(set) var accuracyReviewStatus = "正解4技の入力待ち・未認証"
    @Published private(set) var accuracyReviewLines = [String]()
    private var accuracyObserved = [String?]()
    private var accuracyFrameID: Int64? = nil
    private var accuracyRevision: Int64? = nil
    private var manualOCRGate = ManualOCRDiagnosticGate()
    private let manualOCRQueue = DispatchQueue(label: "champions.ondevice.manual-ocr", qos: .userInitiated)

    // Display-only orientation, explicitly separate from the OCR/decision path.
    private var rawOrientationProposals = [FrameOrientationGeometry.Proposal]()
    private var rawPreviewManualTurn: FrameOrientationGeometry.Turn?
    private var rawPreviewUseCrop = true
    // Main-thread only, never persisted/exported. Independent from OCR.
    private var rawTimelineImages = [UIImage]()
    private var rawTimelineFrameIDs = [Int64]()
    private var rawTimelineAgesMs = [Int64]()
    private var rawTimelineSourceEpochs = [Int64]()
    private var rawTimelineObservedMs = [Int64]()
    private var battleResearchSessionID = UUID().uuidString
    private var megaManualNotebook = R547MegaManualNotebook()
    @Published private(set) var megaManualStatus = "メガ状態：手動で確認した証拠なし（自動判定は未認証）"
    func recordSelectedFrameMega(side:String,species:String,form:String,
                                 megaLabel:String,method:String) {
        guard rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              rawTimelineSourceEpochs.indices.contains(rawTimelineIndex),
              rawTimelineObservedMs.indices.contains(rawTimelineIndex),
              let record = R547MegaManualRecord.make(
                sessionID:battleResearchSessionID,
                frameID:rawTimelineFrameIDs[rawTimelineIndex],
                epoch:rawTimelineSourceEpochs[rawTimelineIndex],
                side:side,species:species,form:form,megaLabel:megaLabel,method:method),
              megaManualNotebook.add(record) else {
            megaManualStatus = "記録不可：画像選択・種族名・状態・確認方法を点検してください"
            return
        }
        megaManualStatus = "手動メモを保存：\(record.side)・\(record.displayedSpecies)・\(record.claimedForm)／自動認証ではありません"
    }

    private var battleWireRevision: Int64 = 0
    @Published private(set) var battleWireStatus = "Battle State候補は未取得・実戦推薦は無効"
    @Published private(set) var battleWireLines = [String]()
    @Published private(set) var battleWireJSON = ""
    @Published private(set) var screenReadStateLines = [String]()
    @Published private(set) var screenReadStateJSON = ""
    @Published private(set) var battleReadBusy = false
    private var selectedOCRFailure: [String:Any]?
    private var selectedReadWork: R551EvidenceWork?
    @Published private(set) var autoResearchStatus = "背景画面の自動OCR待機／助言無効"
    @Published private(set) var candidateFreshnessStatus = "自動読取：新しい受信証拠待ち"
    @Published private(set) var evidenceUptimeDisclosure = "診断の共有・コピーは不具合調査のため任意に実行してください"
    var diagnosticUptimeDisclosure: String {
        "診断には端末稼働時間（現在 約\(Int64(ProcessInfo.processInfo.systemUptime))秒）が含まれます。共有・コピーは不具合調査のため必要な場合に操作してください。"
    }
    private let autoCandidateLease = R554CandidateLease(retireOnNewRequest:true)
    private let pairedCandidateLease = R554CandidateLease(retireOnNewRequest:true)
    private var liveReadWorkSlot=R562ReadWorkSlot() // sampleQueue; survives scope retirement
    private var inputHealth=R563InputHealthFence()
    private var lastReadClockDecision:R562ReadClockGate.Decision?
    private var lastReadClockEpoch:Int64?
    private var lastReadClockDeliveredMs:Int64?
    private var clockDisplayUpdateKey:String?
    private var pairedLeaseEpoch: Int64 = -1
    private var candidateExpiryTimer: Timer?
    @Published private(set) var roiAuditPacket = "R514｜診断JSON待機"
    private var autoResearchGate = TP494AutoSampleGate()
    private var autoResearchTimeline = TP493ObservationTimeline()
    private var autoAdmission = TP495ObservationAdmission()
    private var autoProvenanceRejects = 0
    private var actualCaptureProofRejects = 0
    private var actualPNGGeometryRejects = 0
    private var autoResearchSessionID = UUID().uuidString
    private var autoResearchSessionEpoch = -1

    private var battleAnalysisPNG: Data?
    private var battleAnalysisGeometry: R556AnalysisProjection.Plan?
    // A candidate must never be paired with a different selected/rotated frame.
    private var battleAnalysisFrameID: Int64?
    private var battleAnalysisEpoch: Int64?
    private var battleAnalysisObservedMs: Int64?
    private var evidenceExportGate = FrameEvidenceExportGate()
    private let evidenceExportQueue = DispatchQueue(label: "champions.ondevice.evidence", qos: .utility)
    private var evidenceWork: R551EvidenceWork? // MAIN ownership, worker cancellation is lock-protected
    private var memoryWarningObserver: NSObjectProtocol?
    @Published private(set) var battleEvidenceBusy = false
    @Published private(set) var battleEvidenceURL: URL?
    @Published private(set) var unifiedEvidenceURL: URL? // R535: one-tap, user-initiated share
    @Published private(set) var battleEvidenceStatus = "実画像証跡は未作成（共有は手動のみ）"

    @Published var latencyStatus = "遅延計測待ち・技推薦なし"
    @Published var researchVoiceEnabled = false
    @Published var researchVoiceStatus = "音声テストはOFF（技名・行動推薦は読み上げません）"
    private var voiceGate = ResearchVoiceGate()
    private let voiceAnnouncer = ResearchVoiceAnnouncer()

    private let sampleQueue = DispatchQueue(label: "champions.ondevice.capture", qos: .userInitiated)
    private let ocrQueue = DispatchQueue(label: "champions.ondevice.vision", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let recognizer = VisionLocalObserver()
    private var stream: SCStream?
    private var gate = FrameWindowGate()
    private var nextFrameID: Int64 = 0
    private var generation: Int64 = 0
    private var observationFence = ObservationFence()
    private var continuity = CaptureContinuityAudit()
    private let rawIngressAudit = ResearchRawFrameIngressAudit()
    private let sampleClockAudit = ResearchSampleClockAudit()
    // Access ONLY from sampleQueue. Prior epoch is kept separate; memory only.
    private var archivedUnifiedAuditJSON: String? = nil
    // Queue-isolated, ephemeral CAPTURE scope, not the Pokémon battle ID.
    private var captureAuditSessionTag = UUID().uuidString
    @Published private(set) var sampleClockStatus = "PTS監査：まだ実機ログなし（時計基準未認証）"
    @Published private(set) var unifiedAuditStatus = "統合監査：取得待ち・実戦助言HOLD"
    private var latencyAudit = OCRLatencyAudit()
    private var diagnosticMemory = DiagnosticFrameMemory()
    private var rawPreviewBuffer = BackgroundPreviewBuffer()
    private var rawFrameID: Int64 = 0
    // R582: automatic metadata-only capture audit; sampleQueue confinement.
    private var r582AutoCoverage = R582AutoCaptureCoverage()
    // Only accessed from sampleQueue; old streams must not feed a new session.
    private var activeStreamIdentity: ObjectIdentifier?
    private var active = false

    override init() {
        super.init()
        // Do not erase a completed export at next app launch. Files remain on-device.
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName:UIApplication.didReceiveMemoryWarningNotification,object:nil,queue:.main
        ) { [weak self] _ in
            self?.invalidateReceiptLeases(reason:"MEMORY_PRESSURE")
            self?.clearDiagnosticPreview()
            self?.refreshCandidateFreshness()
            self?.status = "メモリ不足のため保持画像と処理中の候補を解放しました"
        }
    }

    deinit {
        let expiryTimer=candidateExpiryTimer
        if Thread.isMainThread {expiryTimer?.invalidate()}
        else {DispatchQueue.main.async {expiryTimer?.invalidate()}}
        if let observer = memoryWarningObserver { NotificationCenter.default.removeObserver(observer) }
        evidenceWork?.cancel()
        selectedReadWork?.cancel()
    }

    private static var evidenceDirectory: URL {
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("ChampionsEvidence", isDirectory: true)
    }

    private func invalidateEvidenceExport() {
        precondition(Thread.isMainThread)
        evidenceWork?.cancel()
        evidenceWork = nil
        battleEvidenceBusy = false
        evidenceExportGate.invalidate()
        // Previously published files must remain readable by an open share extension.
        battleEvidenceURL = nil
        unifiedEvidenceURL = nil
        battleEvidenceStatus = "表示の証跡候補は失効（作成済みファイルは端末内に保持）"
    }

    func reportUnifiedShareOutcome(completed: Bool, failed: Bool) {
        precondition(Thread.isMainThread)
        // UIActivityViewController never proves the destination file exists.
        if failed { battleEvidenceStatus = "共有サービス側のエラー。端末内原本は保持しています" }
        else if completed { battleEvidenceStatus = "共有操作完了。保存先でファイルを確認してください（原本は端末内保持）" }
        else { battleEvidenceStatus = "共有キャンセル。端末内原本は保持しています" }
    }

    private func invalidateBattleCandidateForPreviewChange() {
        precondition(Thread.isMainThread)
        selectedReadWork?.cancel(); selectedReadWork = nil; battleReadBusy = false
        pendingUnifiedExport = nil
        battleEvidenceBusy = false
        invalidateEvidenceExport()
        battleWireRevision &+= 1
        battleWireJSON = ""
        battleWireLines = []
        screenReadStateJSON = ""; screenReadStateLines = []
        battleAnalysisPNG = nil; selectedOCRFailure = nil
        battleAnalysisGeometry = nil
        battleAnalysisFrameID = nil
        battleAnalysisEpoch = nil
        battleAnalysisObservedMs = nil
        battleWireStatus = "画像選択・回転・切出し変更につき候補失効。再解析してください"
    }

    // Called only by explicit in-app user interaction on the UI thread.
    func setResearchVoiceEnabled(_ enabled: Bool) {
        precondition(Thread.isMainThread)
        voiceAnnouncer.stopImmediately()
        voiceGate.setOptIn(enabled)
        researchVoiceEnabled = enabled
        researchVoiceStatus = enabled ? "音声テストON（手動操作のみ）" : "音声テストOFF"
    }

    func testResearchVoice() {
        precondition(Thread.isMainThread)
        let timestamp = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        let verdict = voiceGate.authorizeManualTest(for: voiceGate.epoch, nowMs: timestamp)
        guard verdict == .allowed else {
            researchVoiceStatus = "再生拒否: \(verdict.rawValue)"
            return
        }
        do {
            try voiceAnnouncer.speakApprovedManualTest()
            researchVoiceStatus = "固定の研究用音声を再生（行動推薦なし）"
        } catch {
            voiceAnnouncer.stopImmediately()
            researchVoiceStatus = "音声出力に失敗（行動推薦なし）"
        }
    }

    func startPicker() {
        // Do not mutate any battle or capture session ID on duplicate taps.
        guard !running && !requestingPermission else { return }
        invalidateReceiptLeases(reason:"CAPTURE_START",stop:true)
        candidateExpiryTimer?.invalidate()
        let expiryTimer=Timer(timeInterval:0.5,repeats:true) { [weak self] timer in
            guard let self else {timer.invalidate();return}
            self.refreshCandidateFreshness()
            if !self.running && !self.requestingPermission {timer.invalidate();self.candidateExpiryTimer=nil}
        }
        candidateExpiryTimer=expiryTimer
        RunLoop.main.add(expiryTimer,forMode:.common)
        battleResearchSessionID = UUID().uuidString
        megaManualNotebook.reset()
        megaManualStatus = "新しい取得を開始：旧フレームのメガ記録は引き継ぎません"
        battleWireRevision &+= 1
        battleWireJSON = ""; battleWireLines = []
        requestingPermission = true
        lastMoveCandidates = ["—", "—", "—", "—"]
        clearDiagnosticPreview()
        sampleQueue.sync {
            generation += 1
            // New capture = new scope. Old session history cannot be exported
            // as the new capture's pre-rotation evidence.
            archivedUnifiedAuditJSON = nil
            captureAuditSessionTag = UUID().uuidString
            latencyAudit.start(epoch: generation)
            diagnosticMemory.resetSession()
            rawPreviewBuffer.resetSession()
            r582AutoCoverage.reset()
            observationFence.start()
            gate = FrameWindowGate()
            nextFrameID = 0
            rawFrameID = 0
            inputHealth=R563InputHealthFence()
            activeStreamIdentity = nil
            captureResolutionPlan = .fallback
            active = true
        }
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        picker.isActive = true
        picker.present() // full display, explicit system UI, not "presentForCurrentApplication"
        DispatchQueue.main.async { self.status = "画面共有許可の待機中" }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter, for oldStream: SCStream?) {
        Task { @MainActor in
            guard self.requestingPermission || self.running else { return }
            var expectedGeneration = self.sampleQueue.sync { self.generation }
            do {
                if let current = self.stream {
                    self.invalidateReceiptLeases(reason:"SOURCE_STOPPED",stop:true)
                    self.stream = nil
                    self.sampleQueue.sync {
                        self.continuity.stopped(epoch: self.generation,
                            atMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
                        self.latencyAudit.stop(epoch: self.generation)
                        self.diagnosticMemory.clear()
                        self.rawPreviewBuffer.clear()
                        self.generation += 1
                        self.observationFence.start()
                        self.gate = FrameWindowGate()
                        self.rawFrameID = 0
                        self.activeStreamIdentity = nil
                    }
                    try? await current.stopCapture()
                }
                expectedGeneration = self.sampleQueue.sync { self.generation }
                guard self.sampleQueue.sync(execute: { self.active && self.generation == expectedGeneration }) else { return }
                let selected = CaptureResolutionPlan.resolve(
                    pointsWidth:Double(filter.contentRect.width),
                    pointsHeight:Double(filter.contentRect.height),
                    pointPixelScale:Double(filter.pointPixelScale))
                let config = SCStreamConfiguration()
                config.width = selected.width
                config.height = selected.height
                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
                self.stream = newStream
                self.sampleQueue.sync {
                    self.activeStreamIdentity = ObjectIdentifier(newStream)
                    self.inputHealth=R563InputHealthFence()
                    _ = self.rawIngressAudit.beginStream(epoch: expectedGeneration)
                    _ = self.sampleClockAudit.beginStream(epoch: expectedGeneration)
                    self.continuity.start(epoch: expectedGeneration,
                        atMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
                    self.latencyAudit.start(epoch: expectedGeneration)
                    self.rawFrameID = 0
                    self.captureResolutionPlan = selected
                    self.continuity.expectFrameSize(width:selected.width,height:selected.height)
                }
                self.captureResolutionStatus =
                    "取得設定\(selected.width)×\(selected.height)px ／" +
                    (selected.derivedFromFilter ? "選択画面の寸法×倍率から推定" : "寸法情報不正・旧設定へフォールバック") +
                    "／ゲーム原本解像度・OCR精度は未認証"
                try await newStream.startCapture()
                guard self.sampleQueue.sync(execute: { self.active && self.generation == expectedGeneration }) else {
                    try? await newStream.stopCapture()
                    if self.stream === newStream { self.stream = nil }
                    return
                }
                self.requestingPermission = false
                self.running = true
                self.status = "端末内OCR研究中・合法技の推薦はしません"
            } catch {
                // A late failure from an old picker must not stop a newer session.
                let matches = self.sampleQueue.sync { self.active && self.generation == expectedGeneration }
                guard matches else { return }
                self.sampleQueue.sync {
                    self.continuity.stopped(epoch: self.generation,
                        atMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
                    self.active = false; self.activeStreamIdentity = nil
                self.invalidateReceiptLeases(reason:"SOURCE_STOPPED",stop:true)
                    self.latencyAudit.stop(epoch: self.generation)
                    self.diagnosticMemory.clear()
                    self.rawPreviewBuffer.clear()
                    self.gate.halt(); self.observationFence.stop(); self.generation += 1
                }
                self.requestingPermission = false
                self.running = false
                self.lastMoveCandidates = ["—", "—", "—", "—"]
                self.status = "画面取得開始に失敗: \(error.localizedDescription)"
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor cancelledStream: SCStream?) {
        let callbackGeneration = sampleQueue.sync { generation }
        Task { @MainActor in
            guard self.requestingPermission || self.running,
                  self.sampleQueue.sync(execute: { self.generation == callbackGeneration }) else { return }
            if let cancelledStream, let current = self.stream, current !== cancelledStream { return }
            self.sampleQueue.sync {
                self.continuity.stopped(epoch:self.generation,
                    atMs:Int64(ProcessInfo.processInfo.systemUptime * 1000))
                self.active = false; self.activeStreamIdentity = nil
                self.invalidateReceiptLeases(reason:"SOURCE_STOPPED",stop:true)
                self.latencyAudit.stop(epoch:self.generation)
                self.diagnosticMemory.clear(); self.rawPreviewBuffer.clear()
                self.gate.halt(); self.observationFence.stop(); self.generation += 1
            }
            self.invalidateBattleCandidateForPreviewChange()
            self.requestingPermission = false; self.running = false
            self.lastMoveCandidates = ["—", "—", "—", "—"]
            self.status = "共有許可がキャンセルされました"
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        let callbackGeneration = sampleQueue.sync { generation }
        Task { @MainActor in
            // A delayed picker-start failure cannot terminate an already running stream.
            guard self.requestingPermission && !self.running,
                  self.sampleQueue.sync(execute: { self.generation == callbackGeneration }) else { return }
            self.sampleQueue.sync {
                self.continuity.stopped(epoch:self.generation,
                    atMs:Int64(ProcessInfo.processInfo.systemUptime * 1000))
                self.active = false; self.activeStreamIdentity = nil
                self.invalidateReceiptLeases(reason:"SOURCE_STOPPED",stop:true)
                self.latencyAudit.stop(epoch:self.generation)
                self.diagnosticMemory.clear(); self.rawPreviewBuffer.clear()
                self.gate.halt(); self.observationFence.stop(); self.generation += 1
            }
            self.invalidateBattleCandidateForPreviewChange()
            self.requestingPermission = false; self.running = false
            self.lastMoveCandidates = ["—", "—", "—", "—"]
            self.status = "共有ピッカーが失敗しました"
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // A retired stream must not invalidate a freshly started session.
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.invalidateBattleCandidateForPreviewChange()
            self.sampleQueue.sync {
                self.continuity.stopped(epoch: self.generation,
                    atMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
                self.active = false; self.activeStreamIdentity = nil
                self.invalidateReceiptLeases(reason:"SOURCE_STOPPED",stop:true)
                self.latencyAudit.stop(epoch: self.generation)
                self.diagnosticMemory.clear()
                self.rawPreviewBuffer.clear()
                self.gate.halt(); self.observationFence.stop(); self.generation += 1
            }
            self.requestingPermission = false
            self.running = false
            self.lastMoveCandidates = ["—", "—", "—", "—"]
            self.status = "共有停止・OCR結果破棄・推薦禁止"
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        // Audit ALL frames before backpressure drops, without retaining frame pixels.
        // A delayed foreign/audio callback cannot revoke a newer source's display.
        guard active,activeStreamIdentity == ObjectIdentifier(stream),outputType == .screen else {return}
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        rawFrameID += 1
        let valid=sample.isValid
        let buffer=valid ? sample.imageBuffer:nil
        let input=R563InputHealthFence.preflight(currentStream:true,screen:true,
            valid:valid,imageAvailable:buffer != nil)
        guard input == .ready,let buffer else {
            holdReadScopeForInput(input == .invalidSample ? .invalidSample:.missingImage,nowMs:nowMs)
            return
        }
        let verdict = continuity.observedFrame(epoch: generation, frameID: rawFrameID,
            atMs: nowMs, width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer))
        guard verdict == .accepted else {
            holdReadScopeForInput(.continuity,nowMs:nowMs);return
        }
        // Only callback delivery order is checked. Neither the actual capture age
        // nor game, move, battle or ownership identity is certified.
        let rawVerdict = rawIngressAudit.observe(epoch: generation, frameID: rawFrameID,
            deliveredMs: nowMs, width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            isBackground: continuity.backgrounded)
        guard rawVerdict == .acceptedDeliveryOnly else {
            holdReadScopeForInput(.ingress,nowMs:nowMs);return
        }
        inputHealth.accept()
        // PTS is a distinct clock domain; record relative changes only.
        // Invalid PTS does not disable manual image diagnostics, nor does a
        // valid PTS authorize any real battle state or recommendation.
        let mediaPTS = CMSampleBufferGetPresentationTimeStamp(sample)
        let presentationMs: Int64?
        if mediaPTS.isValid && !mediaPTS.isIndefinite {
            let seconds = CMTimeGetSeconds(mediaPTS)
            if seconds.isFinite && seconds >= 0 && seconds < 1.0e10 {
                presentationMs = Int64((seconds * 1000.0).rounded())
            } else { presentationMs = nil }
        } else { presentationMs = nil }
        let ptsVerdict = sampleClockAudit.record(epoch: generation, frameID: rawFrameID,
            deliveredMs: nowMs, presentationMs: presentationMs)
        let clockDecision=R562ReadClockGate.decide(verdict:ptsVerdict,epoch:generation,frame:rawFrameID,
            deliveredMs:nowMs,previousDeliveredMs:lastReadClockEpoch==generation ? lastReadClockDeliveredMs:nil)
        lastReadClockEpoch=generation;lastReadClockDeliveredMs=nowMs;lastReadClockDecision=clockDecision
        let allowsClockRead=clockDecision?.allowsAutomaticOCR ?? false
        _ = r582AutoCoverage.observe(epoch:generation,frame:rawFrameID,
            observedMs:nowMs,width:CVPixelBufferGetWidth(buffer),
            height:CVPixelBufferGetHeight(buffer),
            background:continuity.backgrounded,clockAccepted:allowsClockRead)
        if !allowsClockRead {invalidateReceiptLeases(reason:"CAPTURE_CLOCK_HELD")}
        if clockDecision?.requiresNewEpoch==true {retireReadScopeForClock(nowMs:nowMs)}
        guard active else {return}
        if !allowsClockRead {
            let key="\(generation):\(clockDecision?.reason ?? "INVALID_CONTEXT")"
            if clockDisplayUpdateKey != key {
                clockDisplayUpdateKey=key
                let scope=generation
                DispatchQueue.main.async { [weak self] in
                    guard let self,self.sampleQueue.sync(execute:{self.active && self.generation==scope}) else {return}
                    self.refreshCandidateFreshness()
                }
            }
        }
        // A throttled raw preview is independent of the paired OCR and visual gate.
        // Its sole purpose is to diagnose why the game screen was not displayed.
        // It never enters the action/recommendation path and remains memory-only.
        let bufferWidth=CVPixelBufferGetWidth(buffer)
        let bufferHeight=CVPixelBufferGetHeight(buffer)
        if rawPreviewBuffer.shouldSample(epoch: generation, atMs: nowMs,
                                         isBackground: continuity.backgrounded),
           let rawImage = context.createCGImage(CIImage(cvPixelBuffer: buffer),
                            from: CGRect(x: 0, y: 0, width: bufferWidth, height: bufferHeight)),
           let rawPNG = UIImage(cgImage: rawImage).pngData() {
            let buffered = rawPreviewBuffer.offer(epoch: generation, frameID: rawFrameID,
                                        png: rawPNG, observedMs: nowMs,
                                        isBackground: continuity.backgrounded)
            if buffered {
                let digest = SHA256.hash(data:rawPNG).map { String(format:"%02x",$0) }.joined()
                _ = r582AutoCoverage.markRetained(epoch:generation,frame:rawFrameID,pngSHA:digest)
            }
            let ep=Int(generation), frame=rawFrameID
            if allowsClockRead,liveReadWorkSlot.isAvailable,
               autoResearchGate.offer(epoch:ep,frame:frame,observedMs:nowMs,
                    width:bufferWidth,height:bufferHeight,
                    background:continuity.backgrounded) {
                if autoResearchSessionEpoch != ep {
                    autoResearchSessionEpoch=ep
                    autoResearchSessionID=UUID().uuidString
                    _=autoCandidateLease.begin(session:autoResearchSessionID,epoch:Int64(ep))
                    autoResearchTimeline.reset(battle:autoResearchSessionID,
                        sourceEpoch:ep)
                    autoAdmission.reset()
                }
                guard let workTicket=liveReadWorkSlot.begin() else {return}
                let sessionID=autoResearchSessionID
                let leaseTicket=autoCandidateLease.issue(frame:frame,observedMs:nowMs)
                if leaseTicket != nil {
                    let scope=generation
                    DispatchQueue.main.async { [weak self] in
                        guard let self,self.sampleQueue.sync(execute:{self.active && self.generation==scope}) else {return}
                        self.refreshCandidateFreshness()
                    }
                }
                ocrQueue.async { [weak self] in
                    guard let self else{return}
                    let begin=Int64(ProcessInfo.processInfo.systemUptime*1000)
                    var wire:String?=nil
                    var actualPNGSHA:String?=nil
                    var actualPNGDimensions:TP510PNGGeometryProof.Dimensions?=nil
                    var firstPassROI: (kept:Int,rejected:Int,reason:String)?=nil
                    do {
                        guard let src=UIImage(data:rawPNG)?.cgImage else {
                            throw ResearchBattleVision.Failure.invalidImage
                        }
                        let turn:UIImage.Orientation=src.width<src.height ? .left : .up
                        let oriented=UIImage(cgImage:src,scale:1,orientation:turn)
                        let physical=try Self.physicallyOrientedAnalysisImage(oriented)
                        guard let png=physical.pngData(),
                              png.count<=FrameEvidenceExportGate.maximumPNGBytes else {
                            throw ResearchBattleVision.Failure.invalidImage
                        }
                        actualPNGSHA=TP509CaptureAttestation.sha256Hex(png)
                        actualPNGDimensions=TP510PNGGeometryProof.actualDimensions(png)
                        wire=try ResearchBattleVision.inspect(png:png,
                            battleID:sessionID,epoch:ep,frame:Int(frame),
                            turn:nil,observedMs:nowMs,mode:.automaticFirstPass).0
                        // R530: geometry comes from the original full-frame Vision
                        // request, not a second 85ms-limited duplicate OCR pass.
                        // The collision fence can only reject research geometry.
                        if let baseline=wire, let hash=actualPNGSHA,
                           let dimensions=actualPNGDimensions {
                            let roi=TP521VisionCollisionFence.audit(
                                wire:baseline,verifiedPNGHash:hash,battleID:sessionID,
                                epoch:ep,frameID:frame,imageWidth:dimensions.width,
                                imageHeight:dimensions.height)
                            wire=roi.wire
                            firstPassROI=(kept:roi.kept,rejected:roi.rejected,reason:roi.reason)
                        }
                    } catch {wire=nil}
                    let end=Int64(ProcessInfo.processInfo.systemUptime*1000)
                    self.sampleQueue.async { [weak self] in
                        guard let self else{return}
                        _=self.liveReadWorkSlot.finish(workTicket)
                        let state=self.autoResearchGate.finish(epoch:ep,frame:frame,
                            observedMs:nowMs,startedMs:begin,completedMs:end,
                            succeeded:wire != nil)
                        guard self.active,self.generation==Int64(ep),
                              self.autoResearchSessionID==sessionID,
                              state != "OLD_OR_INCONSISTENT_OCR" else{return}
                        TP532FirstPassDiagnostics.record(
                            battleID:sessionID,epoch:ep,frameID:frame,retained:firstPassROI?.kept ?? 0,
                            rejected:firstPassROI?.rejected ?? 0,
                            elapsedMs:Int(max(0,end-begin)),
                            result:firstPassROI?.reason ?? "NO_OCR_RESULT")
                        let imageProof = TP509CaptureAttestation.verify(
                            wire,actualPNGHash:actualPNGSHA,
                            battleID:sessionID,epoch:ep,frameID:frame)
                        if imageProof != .verified { self.actualCaptureProofRejects += 1 }
                        let geometrySidecar=TP512CaptureGeometrySidecar.prepare(
                            wire,actual:actualPNGDimensions,
                            battleID:sessionID,epoch:ep,frameID:frame,
                            pngDigestVerified:imageProof == .verified)
                        let geometryProof=TP510PNGGeometryProof.verify(
                            geometrySidecar.wireForGeometry,actual:actualPNGDimensions,
                            battleID:sessionID,epoch:ep,frameID:frame,
                            pngDigestVerified:imageProof == .verified)
                        if geometryProof != .verifiedGeometry { self.actualPNGGeometryRejects += 1 }
                        let roiPixelAudit=TP511ROIFrameEvidence.inspect(
                            wire,actual:actualPNGDimensions,
                            battleID:sessionID,epoch:ep,frameID:frame,
                            pngDigestVerified:imageProof == .verified)
                        let ownerClaimAudit=TP513ROIClaimConsistency.audit(
                            wire,actual:actualPNGDimensions,
                            battleID:sessionID,epoch:ep,frameID:frame,
                            pngVerified:imageProof == .verified,
                            geometryVerified:geometryProof == .verifiedGeometry)
                        let roiPacket=TP514ROIAuditExport.create(
                            wire,audit:ownerClaimAudit,actual:actualPNGDimensions,
                            battleID:sessionID,epoch:ep,frameID:frame,
                            pngVerified:imageProof == .verified)
                        let provenance = TP496WireProvenance.check(
                            wire,battle:sessionID,epoch:ep,
                            frame:frame,observedMs:nowMs)
                        let provenanceOK = provenance == .matched
                        if !provenanceOK { self.autoProvenanceRejects += 1 }
                        let admitted = self.autoAdmission.admit(
                            result:state,epoch:ep,frame:frame,
                            observedMs:nowMs,completedMs:end,
                            matchingSession:self.autoResearchSessionID==sessionID
                                && provenanceOK && imageProof == .verified && geometryProof == .verifiedGeometry)
                        if let leaseTicket {
                            _=self.autoCandidateLease.finish(leaseTicket,imageSHA:actualPNGSHA,admitted:admitted)
                        }
                        let diagnostic = TP498OCRDiagnostic.inspect(wire, admitted: admitted)
                        let consensus = TP499OCRConsensus.shared.observe(wire, admitted: admitted)
                        let fieldEvidence = TP500EffectFrameGate.shared.observe(wire, admitted: admitted)
                        let visibleEffectText = TP501VisualOCRProbe.shared.observe(wire, admitted: admitted)
                        let visualReconciliation = TP502EffectReconciler.shared.inspect(wire, admitted: admitted)
                        let spatialEvidence = TP503ROIEvidenceAudit.shared.inspect(wire, admitted: admitted)
                        let readiness = TP504EvidenceReadiness.shared.inspect(wire, admitted: admitted)
                        let pixelCoordinates = TP505PixelCoordinateFence.shared.inspect(wire, admitted: admitted)
                        let previewGeometry = TP506PreviewGeometryFence.shared.inspect(wire, admitted: admitted)
                        let roiAnchorAssociation = TP507ROIAnchorAssociation.shared.inspect(wire, admitted: admitted, preview: previewGeometry)
                        let frameEvidence = TP508FrameEvidenceBridge.shared.inspect(wire, admitted: admitted, anchor: roiAnchorAssociation, verifiedActualCapture: imageProof == .verified)
                        let v:TP493FrameAudit? = admitted ? wire.map {
                            self.autoResearchTimeline.observe($0)
                        } : nil
                        let admissionLabel = admitted ?
                            "FRESH_RESEARCH_ONLY" : "REJECTED_FROM_TIMELINE"

                        let desc=v.map {
                            "Frame\($0.frameID ?? -1)・候補\($0.effectHints)" +
                            "・確定イベント\($0.certifiedEvents)（\($0.reason)）"
                        } ?? "OCR未完了・時系列棄却・未確定"
                        let line=self.autoResearchGate.concise + "／" + desc + "／" + state + "／" + admissionLabel + "／" + self.autoAdmission.concise + "／" + provenance.rawValue + "／証拠不整合\(self.autoProvenanceRejects)" + "／" + diagnostic.concise + "／" + consensus.concise + "／" + fieldEvidence.concise + "／" + visibleEffectText.concise + "／" + visualReconciliation.concise + "／" + spatialEvidence.concise + "／" + readiness.concise + "／" + pixelCoordinates.concise + "／" + previewGeometry.concise + "／" + roiAnchorAssociation.concise + "／" + frameEvidence.concise + "／" + imageProof.rawValue + "／画像証明拒否\(self.actualCaptureProofRejects)" + "／" + geometryProof.rawValue + "／寸法証明拒否\(self.actualPNGGeometryRejects)" + "／" + geometrySidecar.concise + "／" + ownerClaimAudit.concise + "／" + roiPixelAudit.concise
                        DispatchQueue.main.async { [weak self] in
                            guard let self,
                                  self.sampleQueue.sync(execute: {
                                      self.active && self.generation==Int64(ep) &&
                                      self.autoResearchSessionID==sessionID
                                  }) else {return}
                            if let leaseTicket,self.autoCandidateLease.canPublish(leaseTicket) {
                                self.autoResearchStatus=line
                                self.roiAuditPacket=roiPacket.json
                            }
                            self.refreshCandidateFreshness()
                        }
                    }
                }
            }
        }
        // The original paired research OCR has fixed 1108x512 ROIs. On a
        // newly negotiated geometry it MUST NOT consume scaled source pixels,
        // mislabel them as game observations, or consume the 1500ms budget.
        // High-fidelity images are only inspected by explicit manual OCR.
        guard allowsClockRead,captureResolutionPlan.legacyGeometry else { return }
        // Never process unbounded frames when a previous OCR pair is in flight.
        guard liveReadWorkSlot.isAvailable,!gate.halted, !gate.inFlight,
              let image = context.createCGImage(CIImage(cvPixelBuffer: buffer),
                  from: CGRect(x: 0, y: 0, width: 1108, height: 512)),
              let png = UIImage(cgImage: image).pngData() else { return }
        nextFrameID += 1
        let packet = FramePacket(frameID: nextFrameID, png: png,
            monotonicMs: nowMs,
            wallClockMs: Int64(Date().timeIntervalSince1970 * 1000))
        guard case .pair(let first, let second) = gate.offer(packet) else { return }
        guard let workTicket=liveReadWorkSlot.begin() else {return}
        let sampleGeneration = generation
        if pairedLeaseEpoch != sampleGeneration {
            pairedLeaseEpoch=sampleGeneration
            _=pairedCandidateLease.begin(session:captureAuditSessionTag,epoch:sampleGeneration)
        }
        let pairedTicket=pairedCandidateLease.issue(frame:second.frameID,observedMs:second.monotonicMs)
        if pairedTicket != nil {
            let scope=generation
            DispatchQueue.main.async { [weak self] in
                guard let self,self.sampleQueue.sync(execute:{self.active && self.generation==scope}) else {return}
                self.refreshCandidateFreshness()
            }
        }
        ocrQueue.async { [weak self] in
            guard let self else { return }
            let ocrStartedMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
            let firstVisual = FrameVisualSampler.inspect(first.png)
            let secondVisual = FrameVisualSampler.inspect(second.png)
            let pairedVisual = FrameVisualGate.paired(firstVisual, secondVisual)
            let result = self.recognizer.readPair(first: first.png, second: second.png,
                firstID: first.frameID, secondID: second.frameID,
                firstMs: first.monotonicMs, secondMs: second.monotonicMs)
            self.sampleQueue.async {
                _=self.liveReadWorkSlot.finish(workTicket)
                guard self.active, !self.gate.halted,
                      sampleGeneration == self.generation else { return }
                self.gate.completePair()
                let currentMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
                // Measure only frame ages and OCR duration; never persist pixel or move data.
                let latencyVerdict = self.latencyAudit.observe(epoch: sampleGeneration,
                    frameMs: second.monotonicMs, ocrStartedMs: ocrStartedMs,
                    completedMs: currentMs)
                guard latencyVerdict == .measured else {
                    if let pairedTicket {_=self.pairedCandidateLease.finish(pairedTicket,imageSHA:nil,admitted:false)}
                    DispatchQueue.main.async {
                        guard self.sampleQueue.sync(execute:{self.active && self.generation==sampleGeneration && self.liveReadWorkSlot.isLatest(workTicket)}) else {return}
                        self.lastMoveCandidates = ["—", "—", "—", "—"]
                        self.status = "OCR遅延ゲート停止（\(latencyVerdict.rawValue)）・推薦禁止"
                    }
                    return
                }
                let verdict = self.observationFence.inspect(
                    epoch: sampleGeneration, latestFrameMs: second.monotonicMs, nowMs: currentMs)
                guard verdict == .accept else {
                    if let pairedTicket {_=self.pairedCandidateLease.finish(pairedTicket,imageSHA:nil,admitted:false)}
                    DispatchQueue.main.async {
                        guard self.sampleQueue.sync(execute:{self.active && self.generation==sampleGeneration && self.liveReadWorkSlot.isLatest(workTicket)}) else {return}
                        self.lastMoveCandidates = ["—", "—", "—", "—"]
                        self.status = "古いOCR結果を破棄（\(verdict.rawValue)）・推薦禁止"
                    }
                    return
                }
                let strings = result.consensusMoves.map { $0 ?? "—" }
                // Keep at most one recent *background* frame paired with these very
                // OCR strings. A foreground frame is never mistaken for game evidence.
                let frameStageVerdict = self.diagnosticMemory.stage(epoch: sampleGeneration,
                    frameID: second.frameID, png: second.png, candidates: strings,
                    observedMs: second.monotonicMs, processedMs: currentMs,
                    isBackground: self.continuity.backgrounded,
                    screenVerdict: pairedVisual)
                if let pairedTicket {
                    _=self.pairedCandidateLease.finish(pairedTicket,
                        imageSHA:TP509CaptureAttestation.sha256Hex(second.png),
                        admitted:pairedVisual == .candidateUnverified &&
                            (frameStageVerdict == .accepted || frameStageVerdict == .foreground))
                }
                DispatchQueue.main.async {
                    guard let pairedTicket,self.pairedCandidateLease.canPublish(pairedTicket) else {
                        self.refreshCandidateFreshness();return
                    }
                    // The UI queue may have been delayed after publication was authorized.
                    let stillFresh = self.sampleQueue.sync {
                        self.observationFence.inspect(
                            epoch: sampleGeneration,
                            latestFrameMs: second.monotonicMs,
                            nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000)) == .accept
                    }
                    guard stillFresh else {
                        self.lastMoveCandidates = ["—", "—", "—", "—"]
                        self.status = "OCR結果期限切れ・推薦禁止"
                        return
                    }
                    guard pairedVisual == .candidateUnverified,
                          frameStageVerdict == .accepted || frameStageVerdict == .foreground else {
                        self.lastMoveCandidates = ["—", "—", "—", "—"]
                        self.status = "非ゲーム画面の疑い・OCR表示を停止（\(pairedVisual.rawValue)）"
                        return
                    }
                    self.lastMoveCandidates = strings
                    self.refreshCandidateFreshness()
                    self.status = "未認証画面の研究候補: \(strings.filter { $0 != "—" }.count)/4技一致。行動推薦は無効"
                }
            }
        }
    }

    private func invalidateReceiptLeases(reason: String,stop: Bool=false) {
        autoCandidateLease.invalidate(reason:reason,stop:stop)
        pairedCandidateLease.invalidate(reason:reason,stop:stop)
    }

    // sampleQueue only. Keep one running live worker until its own completion;
    // its old lease/epoch will reject publication after this boundary.
    private func retireReadScopeForClock(nowMs:Int64,phase:String="presentation_clock_retirement") {
        archivedUnifiedAuditJSON=unifiedAuditSnapshot(nowMs:nowMs,phase:phase) ?? archivedUnifiedAuditJSON
        guard generation<Int64.max else {
            active=false;gate.halt();observationFence.stop()
            invalidateReceiptLeases(reason:"CAPTURE_CLOCK_HELD",stop:true);return
        }
        let old=generation
        latencyAudit.stop(epoch:old);generation+=1;latencyAudit.start(epoch:generation)
        continuity.rotateEpochKeepingCounts(from:old,to:generation)
        _=rawIngressAudit.rotateForClockDiscontinuity(from:old,to:generation)
        _=sampleClockAudit.rotateForClockDiscontinuity(from:old,to:generation)
        observationFence.start();gate=FrameWindowGate()
        rawPreviewBuffer.clear();diagnosticMemory.clear()
    }

    private func holdReadScopeForInput(_ reason:R563InputHealthFence.Rejection,nowMs:Int64) {
        // A sustained bad input must not rotate epochs or enqueue UI updates at frame rate.
        guard inputHealth.reject(reason) else {return}
        invalidateReceiptLeases(reason:"CAPTURE_INPUT_HELD")
        retireReadScopeForClock(nowMs:nowMs,phase:"current_input_retirement")
        let scope=generation
        DispatchQueue.main.async { [weak self] in
            guard let self,self.sampleQueue.sync(execute:{self.active && self.generation==scope}) else {return}
            self.refreshCandidateFreshness()
        }
    }

    private func readClockDiagnosticPacket() -> [String:Any] {
        var clock:Any=NSNull()
        if let decision=lastReadClockDecision,decision.epoch==generation {clock=decision.object}
        return ["scope":"CAPTURE_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_CLOCK_PROOF",
                "clock_decision":clock,"live_work_slot":liveReadWorkSlot.object]
    }

    private func refreshCandidateFreshness() {
        precondition(Thread.isMainThread)
        let full=autoCandidateLease.snapshot(),paired=pairedCandidateLease.snapshot()
        candidateFreshnessStatus="全画面："+R554CandidateLease.display(full)+"\n技候補："+R554CandidateLease.display(paired)
        candidateFreshnessStatus += "\n"+sampleQueue.sync {
            let clock=lastReadClockDecision.flatMap {$0.epoch==generation ? $0.display:nil} ?? "自動読取の映像時刻を確認しています"
            return inputHealth.display+"\n"+clock
        }
        if paired["view_status"] as? String != "FRESH_RECEIPT_ONLY" {lastMoveCandidates=["—","—","—","—"]}
        if full["view_status"] as? String != "FRESH_RECEIPT_ONLY" {
            autoResearchStatus="直近の自動読取候補は未取得または失効。現在状態は未確認です"
            roiAuditPacket="R514｜直近の自動診断は未取得または失効"
        }
    }

    // Lifecycle events are delivered by SwiftUI on the main thread. Measurement and
    // OCR-generation mutations remain confined to the serial sampleQueue.
    func refreshSampleClockStatus() {
        precondition(Thread.isMainThread)
        let s = sampleClockAudit.summary()
        sampleClockStatus = "PTS相対監査：" + String(s.relativeAccepted) + "件 / 保留" +
            String(s.relativeHeld) + "件。最終=" + s.lastVerdict +
            "／絶対フレーム鮮度・ゲーム状態は未認証"
    }
    func copySampleClockAuditJSON() {
        precondition(Thread.isMainThread)
        UIPasteboard.general.string = sampleClockAudit.json()
        refreshSampleClockStatus()
    }
    func didEnterBackground() {
        precondition(Thread.isMainThread)
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        invalidateReceiptLeases(reason:"APP_BACKGROUND")
        refreshCandidateFreshness()
        sampleQueue.sync {
            guard continuity.active else { return }
            continuity.didEnterBackground(epoch: generation, atMs: nowMs)
        }
    }

    func willEnterForeground() {
        precondition(Thread.isMainThread)
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        var completedBackgroundSample: DiagnosticFrameMemory.Snapshot?
        var rawTimeline = [BackgroundPreviewBuffer.Snapshot]()
        var rawSavedCount = 0
        var stagedScreens = 0
        var rejectedScreens = 0
        sampleQueue.sync {
            guard continuity.active else { diagnosticMemory.clear(); return }
            completedBackgroundSample = diagnosticMemory.takeAndClear(expectedEpoch: generation, nowMs: nowMs)
            rawTimeline = rawPreviewBuffer.takeTimelineAndClear(epoch: generation, nowMs: nowMs)
            rawSavedCount = rawPreviewBuffer.savedCount
            stagedScreens = diagnosticMemory.stagedScreens
            rejectedScreens = diagnosticMemory.rejectedScreens
            continuity.willEnterForeground(epoch: generation, atMs: nowMs)
            archivedUnifiedAuditJSON = unifiedAuditSnapshot(nowMs: nowMs,
                phase: "before_foreground_epoch_rotation") ?? archivedUnifiedAuditJSON
            invalidateReceiptLeases(reason:"APP_FOREGROUND")
            let oldEpoch = generation
            latencyAudit.stop(epoch: generation)
            generation &+= 1 // discard recognition in-flight before the UI resumes
            latencyAudit.start(epoch: generation)
            continuity.rotateEpochKeepingCounts(from: oldEpoch, to: generation)
            _ = rawIngressAudit.rotateAfterForeground(from: oldEpoch, to: generation)
            _ = sampleClockAudit.rotateAfterForeground(from: oldEpoch, to: generation)
            observationFence.start()
            gate = FrameWindowGate()
        }
        clearManualOCRDiagnostic(clearGroundTruth: true)
        lastMoveCandidates = ["—", "—", "—", "—"]
        autoResearchStatus = sampleQueue.sync { autoResearchGate.concise } + "／直前の背景キャプチャ集計"
        refreshCandidateFreshness()
        rawTimelineImages.removeAll(keepingCapacity: false)
        rawTimelineFrameIDs.removeAll(keepingCapacity: false)
        rawTimelineAgesMs.removeAll(keepingCapacity: false)
        rawTimelineSourceEpochs.removeAll(keepingCapacity: false)
        rawTimelineObservedMs.removeAll(keepingCapacity: false)
        rawOrientationProposals.removeAll(keepingCapacity: false)
        rawPreviewManualTurn = nil
        rawPreviewUseCrop = true
        for item in rawTimeline {
            guard let image = UIImage(data: item.png),
                  let cg=image.cgImage,
                  CaptureResolutionPlan.permitted(width:cg.width,height:cg.height) else { continue }
            rawTimelineImages.append(image)
            rawOrientationProposals.append(FrameOrientationSampler.inspect(image))
            rawTimelineFrameIDs.append(item.frameID)
            rawTimelineAgesMs.append(nowMs - item.observedMs)
            rawTimelineSourceEpochs.append(item.epoch)
            rawTimelineObservedMs.append(item.observedMs)
        }
        rawTimelineCount = rawTimelineImages.count
        rawTimelineIndex = 0
        rawTimelineStatus = rawTimelineCount == 0
            ? "背景履歴なし（共有先・フレーム受信状況を確認）"
            : "背景履歴\(rawTimelineCount)枚。前後ボタンで画面切替より前の映像を確認できます。すべて未認証"
        if !rawTimelineImages.isEmpty {
            // Always show the oldest background image first. This diagnostic
            // does not authorize game recognition or recommendation.
            updateDisplayOnlyRawPreview(at: 0)
            diagnosticIsUnfiltered = true
            diagnosticCandidates = ["—", "—", "—", "—"]
            diagnosticFrameID = rawTimelineFrameIDs[0]
            diagnosticStatus = "未選別の背景履歴画像（frame \(rawTimelineFrameIDs[0])）。ゲーム判定なし・行動推薦禁止"
        } else if let sample = completedBackgroundSample,
                  let preview = UIImage(data: sample.png),
                  preview.cgImage != nil {
            diagnosticPreview = preview
            diagnosticIsUnfiltered = false
            diagnosticCandidates = sample.fourMoveCandidates
            diagnosticFrameID = sample.frameID
            diagnosticStatus = "画面形状を審査した背景候補／frame \(sample.frameID)／OCR処理 \(sample.processingMs)ms。ゲーム画面との一致は未認証"
        } else {
            diagnosticPreview = nil
            diagnosticIsUnfiltered = false
            diagnosticCandidates = ["—", "—", "—", "—"]
            diagnosticFrameID = 0
            diagnosticStatus = "背景映像を保持できませんでした。画面共有対象・配信状態の確認が必要"
        }
        diagnosticFilterStatus = "OCR連動採用\(stagedScreens)組／選別除外\(rejectedScreens)組／背景生画像保存\(rawSavedCount)枚（すべて未認証）"
        status = "復帰後は新規フレームから再判定。行動推薦なし"
        refreshContinuityStatus()
    }

    // UI-only raw timeline; never modifies the OCR observation, gate or recommendation.
    func selectRawTimeline(delta: Int) {
        precondition(Thread.isMainThread)
        guard !rawTimelineImages.isEmpty else { return }
        let next = rawTimelineIndex + delta
        guard next >= 0, next < rawTimelineImages.count else { return }
        clearManualOCRDiagnostic(clearGroundTruth: true)
        rawTimelineIndex = next
        updateDisplayOnlyRawPreview(at: next)
        diagnosticIsUnfiltered = true
        diagnosticCandidates = ["—", "—", "—", "—"]
        diagnosticFrameID = rawTimelineFrameIDs[next]
        diagnosticStatus = "未選別・背景履歴 \(next+1)/\(rawTimelineCount)／frame \(rawTimelineFrameIDs[next])／復帰時点の経過 \(rawTimelineAgesMs[next])ms。OCR・推薦への使用禁止"
    }

    // All transformation and selection are on the main/UI thread and do not
    // change a source frame, an OCR result, or a recommendation gate.
    private func updateDisplayOnlyRawPreview(at index:Int) {
        guard rawTimelineImages.indices.contains(index),
              rawOrientationProposals.indices.contains(index) else {return}
        // Covers frame selection AND rotation/crop buttons; reject stale async OCR.
        invalidateBattleCandidateForPreviewChange()
        let src=rawTimelineImages[index], proposed=rawOrientationProposals[index]
        let turn=rawPreviewManualTurn ?? proposed.suggestedTurn
        let crop=rawPreviewUseCrop ? proposed.crop : FrameOrientationGeometry.full
        clearManualOCRDiagnostic()
        let rendered=FrameOrientationSampler.rendered(src,crop:crop,turn:turn)
        diagnosticPreview=rendered ?? src
        let appliedTurn:FrameOrientationGeometry.Turn = rendered == nil ? .none : turn
        if let actual=diagnosticPreview?.cgImage {
            diagnosticDisplayAspect = (appliedTurn == .left || appliedTurn == .right)
                ? CGFloat(actual.height)/CGFloat(actual.width) : CGFloat(actual.width)/CGFloat(actual.height)
        }
        let symbols=["0°","左90°","180°","右90°"]
        displayTurnLabel=symbols[appliedTurn.rawValue]
        orientationStatus=proposed.status + "／実際の表示=" + displayTurnLabel +
            (rawPreviewManualTurn == nil ? "（自動候補）" : "（手動）") +
            (rendered == nil ? "／切出し失敗・元画像を表示" : (rawPreviewUseCrop ? "／縦帯切出し候補" : "／全画像")) +
            "。表示と明示的OCRの入力変換のみ。ゲームの向き・自他は未認証"
        refreshCalibrationOverlay()
    }
    func rotateDiagnosticLeft() {
        precondition(Thread.isMainThread)
        guard rawTimelineImages.indices.contains(rawTimelineIndex) else{return}
        let current=rawPreviewManualTurn ?? rawOrientationProposals[rawTimelineIndex].suggestedTurn
        rawPreviewManualTurn=current.rotatedLeft()
        updateDisplayOnlyRawPreview(at:rawTimelineIndex)
    }
    func rotateDiagnosticRight() {
        precondition(Thread.isMainThread)
        guard rawTimelineImages.indices.contains(rawTimelineIndex) else{return}
        let current=rawPreviewManualTurn ?? rawOrientationProposals[rawTimelineIndex].suggestedTurn
        rawPreviewManualTurn=current.rotatedRight()
        updateDisplayOnlyRawPreview(at:rawTimelineIndex)
    }
    func toggleDiagnosticCrop() {
        precondition(Thread.isMainThread)
        guard rawTimelineImages.indices.contains(rawTimelineIndex) else{return}
        rawPreviewUseCrop.toggle()
        updateDisplayOnlyRawPreview(at:rawTimelineIndex)
    }
    func resetDiagnosticOrientation() {
        precondition(Thread.isMainThread)
        guard rawTimelineImages.indices.contains(rawTimelineIndex) else{return}
        rawPreviewManualTurn=nil;rawPreviewUseCrop=true
        updateDisplayOnlyRawPreview(at:rawTimelineIndex)
    }

    // Main thread. Sliders can adjust a hypothetical four-move geometry without
    // recognizing a battle screen, validating text, or authorizing a recommendation.
    func setCalibrationVisible(_ value:Bool) {
        precondition(Thread.isMainThread)
        calibrationVisible = value && rawTimelineImages.indices.contains(rawTimelineIndex)
        refreshCalibrationOverlay()
    }
    func resetCalibration() {
        precondition(Thread.isMainThread)
        clearManualOCRDiagnostic()
        calibrationLayout = .portraitLandscapeDiagnostics
        refreshCalibrationOverlay()
    }
    func refreshCalibrationOverlay() {
        precondition(Thread.isMainThread)
        clearManualOCRDiagnostic()
        calibrationMappedROIs = []
        calibrationOverlayROIs = []
        guard rawTimelineImages.indices.contains(rawTimelineIndex),
              rawOrientationProposals.indices.contains(rawTimelineIndex),
              let nativeImage=rawTimelineImages[rawTimelineIndex].cgImage else {
            calibrationStatus = "背景履歴なし・較正停止"
            return
        }
        let proposal=rawOrientationProposals[rawTimelineIndex]
        let turn=rawPreviewManualTurn ?? proposal.suggestedTurn
        let crop=rawPreviewUseCrop ? proposal.crop : FrameOrientationGeometry.full
        guard CaptureResolutionPlan.permitted(width:nativeImage.width,height:nativeImage.height),
              let mappings=MoveROICalibration.map(layout:calibrationLayout,crop:crop,turn:turn) else {
            calibrationStatus="仮枠が画像領域外・較正停止"
            return
        }
        calibrationOverlayROIs=mappings.map { m in
            CGRect(x:m.display.x,y:m.display.y,width:m.display.width,height:m.display.height)
        }
        calibrationMappedROIs=mappings.enumerated().map { (i,m) in
            let r=m.visionBottomLeft
            return String(format:"参考：旧元フレーム座標%d（R27.423 OCRでは不使用） x=%.3f y=%.3f w=%.3f h=%.3f",
                          i+1,r.x,r.y,r.width,r.height)
        }
        calibrationStatus="frame \(rawTimelineFrameIDs[rawTimelineIndex])・\(displayTurnLabel)・表示と同じ向きで4技領域を手動Vision診断／未認証／技推薦禁止"
    }

    // Explicit UI tap required. This is a local, diagnostic-only Vision probe:
    // it NEVER enters live OCR, the battle state, or audio recommendations.
    // R27.490: One tap for the existing four-slot research OCR. This MUST NOT
    // alter image rotation, infer slots from chat screenshots or admit Battle State.
    func runGuidedResearchOCR() {
        precondition(Thread.isMainThread)
        calibrationVisible = true
        refreshCalibrationOverlay()
        runManualROIProbe()
    }


    // R27.490: Optional, narrow PP-only Vision pass over the SAME already-cropped
    // move-row image. Avoid re-running OCR on the entire source/game capture.
    // The 0.66 x threshold is a research hypothesis; display it in the UI and
    // leave any uncertain result unadmitted. Never infer PP from move name.
    private static func focusedPPRescan(_ image: UIImage) -> String {
        guard let cg=image.cgImage, cg.width>=120,cg.height>=35 else {
            return "専用PP領域なし・未認証"
        }
        let left = Int(Double(cg.width)*0.66)
        let rect=CGRect(x:CGFloat(left),y:0,width:CGFloat(cg.width-left),height:CGFloat(cg.height))
        guard let small=cg.cropping(to:rect) else {return "PP切出し失敗・未認証"}
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.008
        let handler=VNImageRequestHandler(cgImage:small,options:[:])
        do {try handler.perform([request])} catch {return "専用PP Vision失敗・未認証"}
        let found=(request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let candidates=found.flatMap { $0.topCandidates(3).map { $0.string } }
        let upper=found.first?.topCandidates(1).first?.string
        let lower=found.dropFirst().first?.topCandidates(1).first?.string
        return ResearchSpatialROIGate.PPLexicalDiagnostic.report(
            directStrings:candidates,upper:upper,lower:lower)
    }

    func runManualROIProbe() {
        precondition(Thread.isMainThread)
        clearManualOCRDiagnostic()
        guard rawTimelineImages.indices.contains(rawTimelineIndex), calibrationVisible,
              rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              rawOrientationProposals.indices.contains(rawTimelineIndex),
              let nativeImage = rawTimelineImages[rawTimelineIndex].cgImage else {
            manualOCRStatus = "履歴と4枠を選んでから実行してください"
            return
        }
        let frame = rawTimelineFrameIDs[rawTimelineIndex]
        let proposal = rawOrientationProposals[rawTimelineIndex]
        let turn = rawPreviewManualTurn ?? proposal.suggestedTurn
        let crop = rawPreviewUseCrop ? proposal.crop : FrameOrientationGeometry.full
        guard CaptureResolutionPlan.permitted(width:nativeImage.width,height:nativeImage.height),
              let maps = MoveROICalibration.map(layout:calibrationLayout,crop:crop,turn:turn),
              let token=manualOCRGate.request(frameID:frame,roiCount:maps.count) else {
            manualOCRStatus = "領域外・画像不正・手動OCR停止"
            return
        }
        // R27.423: flatten the preview orientation into pixels and directly crop
        // 4 displayed-region patches; older inverse-ROI values are audit-only.
        guard let plan=ManualOCRDisplayGeometry.prepare(
                sourceWidth:nativeImage.width,sourceHeight:nativeImage.height,
                crop:crop,turn:turn,layout:calibrationLayout) else {
            manualOCRStatus = "補正画像の領域が不正・手動OCR停止"
            return
        }
        let fixedLayout=calibrationLayout // immutable snapshot, bound to token
        researchPPDiagnostics = []
        manualOCRStatus = "frame \(frame) を手動Vision処理中（判定・推薦なし）"
        manualOCRQueue.async { [weak self] in
            let values = ManualROIOCRProbe.inspect(image:nativeImage,plan:plan,layout:fixedLayout)
            let ppDiagnostics = values.map { Self.focusedPPRescan($0.crop) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.manualOCRGate.validCompletion(
                    revision:token,frameID:frame,count:values.count),
                    self.rawTimelineImages.indices.contains(self.rawTimelineIndex),
                    self.rawTimelineFrameIDs[self.rawTimelineIndex] == frame else { return }
                self.manualOCRThumbnails = values.map { $0.crop }
                self.researchPPDiagnostics = ppDiagnostics.enumerated().map { "枠\($0.offset+1)：\($0.element)" }
                let rotatedSize = ManualOCRDirectPixelGeometry.orientedDimensions(
                    crop:plan.pixelCrop,turn:plan.turn)
                let dimensions = "取得\(nativeImage.width)×\(nativeImage.height)px → " +
                    "切出し\(plan.pixelCrop.width)×\(plan.pixelCrop.height)px → " +
                    "回転\(rotatedSize?.width ?? 0)×\(rotatedSize?.height ?? 0)px"
                let patches = values.enumerated().map { i,v in
                    "枠\(i+1)：\(v.width)×\(v.height)px"
                }.joined(separator:"／")
                self.manualOCRPixelSummary =
                    "frame \(frame)・\(dimensions)・\(patches)。各枠は技名+PPを1回のOCRで診断（不完全な枠のみ再解析）。拡大による新規画素情報なし。"
                // Compare exactly the best displayed name, not a PP substring.
                self.accuracyObserved = values.map {
                    $0.recognized ?? $0.processedRecognized
                }
                self.accuracyFrameID = frame
                self.accuracyRevision = token
                self.clearAccuracyReview()
                self.manualOCRLines = values.enumerated().map { i,v in
                    let raw=v.recognized.map { name in
                        String(format:"%@ (%.2f)",name,v.confidence ?? 0)
                    } ?? "未検出"
                    let enhanced=v.processedRecognized.map { name in
                        String(format:"%@ (%.2f)",name,v.processedConfidence ?? 0)
                    } ?? "未検出"
                    let firstPP: String
                    if let cur=v.rawCurrentPP,let max=v.rawMaximumPP {
                        firstPP="\(cur)/\(max)"
                    } else { firstPP="未検出" }
                    let fallbackPP: String
                    if let cur=v.enhancedCurrentPP,let max=v.enhancedMaximumPP {
                        fallbackPP="\(cur)/\(max)"
                    } else { fallbackPP="未検出" }
                    let targetedPP: String
                    if let cur=v.targetedCurrentPP,let max=v.targetedMaximumPP {
                        targetedPP="\(cur)/\(max)"
                    } else { targetedPP="未検出" }
                    return "枠\(i+1)：技=\(raw)／PP=\(firstPP)｜補正再検=\(enhanced)／補正PP=\(fallbackPP)｜PP専用再検=\(targetedPP)（手動診断・未認証）"
                }
                self.manualOCRStatus = "手動OCR診断完了・frame \(frame)・ゲーム画面/技名正答率未認証・推薦禁止"
            }
        }
    }

    // A ground-truth comparison is explicitly user-initiated, for the EXACT SAME
    // selected frame/rotation/ROI and OCR revision. Never changes a battle gate.
    func runManualAccuracyReview() {
        precondition(Thread.isMainThread)
        clearAccuracyReview()
        guard rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              let frame = accuracyFrameID, let revision = accuracyRevision,
              frame == rawTimelineFrameIDs[rawTimelineIndex],
              manualOCRGate.validCompletion(revision: revision, frameID: frame, count: accuracyObserved.count),
              let report = ManualOCRAccuracyAudit.score(reference: manualGroundTruth, observed: accuracyObserved)
        else {
            accuracyReviewStatus = "比較拒否：現在フレームの手動OCRと正解4技を揃えてください"
            return
        }
        let labels = ["一致", "不一致", "未検出"]
        accuracyReviewLines = report.outcomes.enumerated().map { i, result in
            let index = result == .match ? 0 : (result == .mismatch ? 1 : 2)
            if result == .match {return "枠\(i+1)：一致"}
            // A visually identical string may contain a hidden character.
            // Show both normalized values and Unicode scalars LOCALLY so the
            // mismatch can be traced without silently weakening exact matching.
            let reference = ManualOCRAccuracyAudit.normalize(manualGroundTruth[i]) ?? "<invalid>"
            let observed = accuracyObserved[i].flatMap {
                ManualOCRAccuracyAudit.normalize($0)
            } ?? "<missing>"
            let scalars=observed.unicodeScalars.map {
                String(format:"%04X",$0.value)
            }.joined(separator:" ")
            return "枠\(i+1)：\(labels[index])／正解=【\(reference)】／OCR=【\(observed)】／OCR文字コード=\(scalars)"
        }
        accuracyReviewStatus = "入力された4技との完全一致 \(report.correct)/4（\(Int(report.accuracy * 100))%）／未検出\(report.missing)／不一致\(report.mismatched)。1画面のみ・認識精度未認証・行動推薦禁止"
        refreshOwnMoveTypeAudit()
    }

    func clearAccuracyReview() {
        precondition(Thread.isMainThread)
        accuracyReviewStatus = "正解4技との比較待ち・未認証"
        accuracyReviewLines = []
        ownMoveTypeAuditLines = []
        ownMoveTypeAuditStatus = "同一フレームの技名4/4照合と有効特性の確認待ち"
    }

    // No persistent or automatic type inference. READ-ONLY display on a manually
    // verified same-frame OCR; never connected to legal actions or the coach.
    func refreshOwnMoveTypeAudit() {
        precondition(Thread.isMainThread)
        ownMoveTypeAuditLines = []
        ownMoveTypeAuditStatus = "同一フレームの技名4/4照合と有効特性の確認待ち"
        guard rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              let frame=accuracyFrameID,let revision=accuracyRevision,
              frame==rawTimelineFrameIDs[rawTimelineIndex],
              manualOCRGate.validCompletion(revision:revision,frameID:frame,count:accuracyObserved.count),
              let report=ManualOCRAccuracyAudit.score(
                  reference:manualGroundTruth,observed:accuracyObserved),report.perfect
        else { return }
        guard let evidence=R27430OwnTypeAudit.AbilityEvidence(
                    rawValue:confirmedOwnAbilityChoice),evidence != .unknown else {
            ownMoveTypeAuditStatus="技名4/4確認。自分の現在有効な特性は未確認（色判定は使用しません）"
            return
        }
        ownMoveTypeAuditLines=(0..<4).map { i in
            let name=accuracyObserved[i] ?? ""
            let r=R27430OwnTypeAudit.resolve(exactlyVerifiedMove:name,
                evidence:evidence,exactSameFrameVerified:true,
                abilityEffectStateVerified:true)
            guard let actual=r.effectiveType,let multiplier=r.typeBoost else {
                return "枠\(i+1)：\(name)／タイプ保留：\(r.status)"
            }
            let extra=multiplier>1.0 ? "／スキン威力×1.2（攻撃技のみ）" : ""
            return "枠\(i+1)：\(name) → \(actual)\(extra)【研究用・\(r.status)】"
        }
        ownMoveTypeAuditStatus="R27.430限定DB＋手動確認特性。色認識不使用。実戦推薦は禁止・正式DB未接続"
    }

    private func clearManualOCRDiagnostic(clearGroundTruth: Bool = false) {
        precondition(Thread.isMainThread)
        selectedReadWork?.cancel(); selectedReadWork = nil; battleReadBusy = false
        invalidateEvidenceExport()
        battleAnalysisPNG = nil; selectedOCRFailure = nil
        battleAnalysisGeometry = nil
        battleWireRevision &+= 1
        battleWireJSON = ""; battleWireLines = []
        battleWireStatus = "選択画面・向きの変更により以前の候補は失効"
        screenReadStateJSON = ""; screenReadStateLines = []

        precondition(Thread.isMainThread)
        manualOCRGate.invalidate()
        pendingUnifiedExport = nil
        manualOCRStatus = "手動OCR未実行・正答率未認証"
        manualOCRLines = [String](repeating:"—",count:4)
        manualOCRThumbnails = []
        manualOCRPixelSummary = "OCR入力の切り出し画像は未生成"
        accuracyObserved = []
        accuracyFrameID = nil
        accuracyRevision = nil
        clearAccuracyReview()
        confirmedOwnAbilityChoice = "未確認"
        if clearGroundTruth { manualGroundTruth = [String](repeating: "", count: 4) }
    }

    // Explicit button only. This does not re-label historical pixels as live evidence.
    func inspectSelectedBattleState() {
        precondition(Thread.isMainThread)
        guard !battleReadBusy else { return }
        invalidateEvidenceExport()
        battleAnalysisPNG = nil; selectedOCRFailure = nil
        battleAnalysisGeometry = nil
        battleAnalysisFrameID = nil
        battleAnalysisEpoch = nil
        battleAnalysisObservedMs = nil
        battleWireRevision &+= 1
        let revision = battleWireRevision
        battleWireJSON = ""; battleWireLines = []
        screenReadStateJSON = ""; screenReadStateLines = []
        guard rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              rawTimelineSourceEpochs.indices.contains(rawTimelineIndex),
              rawTimelineObservedMs.indices.contains(rawTimelineIndex),
              rawTimelineImages.indices.contains(rawTimelineIndex),
              rawOrientationProposals.indices.contains(rawTimelineIndex),
              let rawImage=rawTimelineImages[rawTimelineIndex].cgImage,
              let image = diagnosticPreview else {
            battleWireStatus = "背景履歴の表示を選択してください"; return
        }
        let frame = rawTimelineFrameIDs[rawTimelineIndex]
        let sourceEpoch = rawTimelineSourceEpochs[rawTimelineIndex]
        let observedMs = rawTimelineObservedMs[rawTimelineIndex]
        let sessionID = battleResearchSessionID
        let proposal=rawOrientationProposals[rawTimelineIndex]
        let chosenCrop=rawPreviewUseCrop ? proposal.crop : FrameOrientationGeometry.full
        let chosenTurn=rawPreviewManualTurn ?? proposal.suggestedTurn
        let requestedPixels=ManualOCRDisplayGeometry.pixelCrop(width:rawImage.width,height:rawImage.height,crop:chosenCrop)
        let expectedOrientation:UIImage.Orientation
        switch chosenTurn {
        case .none:expectedOrientation = .up
        case .left:expectedOrientation = .left
        case .half:expectedOrientation = .down
        case .right:expectedOrientation = .right
        }
        let renderingSucceeded=requestedPixels.map {
            image.cgImage?.width==$0.width && image.cgImage?.height==$0.height && image.imageOrientation==expectedOrientation
        } ?? false
        guard renderingSucceeded || (image.cgImage?.width==rawImage.width && image.cgImage?.height==rawImage.height && image.imageOrientation == .up) else {
            battleWireStatus="表示画像と変換の記録が不一致・解析を保留";return
        }
        let pixels=renderingSucceeded ? requestedPixels : ManualOCRDisplayGeometry.PixelCrop(x:0,y:0,width:rawImage.width,height:rawImage.height)
        guard let pixels else {battleWireStatus="切り抜きの座標記録を生成できません";return}
        let geometry=R556AnalysisProjection.Plan(rawWidth:rawImage.width,rawHeight:rawImage.height,
            crop:.init(x:pixels.x,y:pixels.y,width:pixels.width,height:pixels.height),
            quarterTurnsCCW:renderingSucceeded ? chosenTurn.rawValue : 0)
        let readWork = R551EvidenceWork()
        selectedReadWork = readWork
        battleReadBusy = true
        battleWireStatus = "選択した表示画像を端末内Visionで解析中"
        manualOCRQueue.async { [weak self] in
            var attemptedPNG: Data?
            do {
                try readWork.check()
                // No battle turn is visible/authenticated by this profile: preserve nil.
                let transformed=try R556PixelTransform.apply(rawImage,plan:geometry,work:readWork)
                let physicalImage=UIImage(cgImage:transformed,scale:1,orientation:.up)
                // R27.489: separate native SCStream pixel coordinates from the
                // rotated OCR buffer and SwiftUI preview. A user screenshot has
                // no authority to calibrate a raw-capture ROI.
                let spatialStatus: String = geometry.valid
                    ? "元バッファ\(geometry.rawWidth)×\(geometry.rawHeight)／整数切抜き原点(\(geometry.crop.x),\(geometry.crop.y))・\(geometry.crop.width)×\(geometry.crop.height)／左回転\(geometry.quarterTurnsCCW*90)°→OCR \(geometry.analysisWidth)×\(geometry.analysisHeight)。変換記録のみ・ゲームの向き/自他/現在値は未認証"
                    : "画像変換の寸法が不整合・ROI較正HOLD"
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.battleWireRevision == revision,self.battleResearchSessionID==sessionID,
                          self.rawTimelineFrameIDs.indices.contains(self.rawTimelineIndex),
                          self.rawTimelineSourceEpochs.indices.contains(self.rawTimelineIndex),
                          self.rawTimelineFrameIDs[self.rawTimelineIndex] == frame,
                          self.rawTimelineSourceEpochs[self.rawTimelineIndex] == sourceEpoch else { return }
                    self.researchSpatialDiagnostic = spatialStatus
                }

                guard let png = physicalImage.pngData(), png.count <= FrameEvidenceExportGate.maximumPNGBytes else {
                    throw ResearchBattleVision.Failure.invalidImage
                }
                attemptedPNG=png
                let result = try ResearchBattleVision.inspect(png:png,battleID:sessionID,
                    epoch:Int(sourceEpoch),frame:Int(frame),turn:nil,observedMs:observedMs,
                    mode:.manualDetailed,work:readWork)
                try readWork.check()
                let state = R551ScreenReadState.make(envelope:result.0,captureSessionID:sessionID,
                    frame:frame,epoch:sourceEpoch,observedMs:observedMs,
                    imageSHA:SHA256.hash(data:png).map { String(format:"%02x",$0) }.joined(),
                    width:physicalImage.cgImage?.width ?? 0,height:physicalImage.cgImage?.height ?? 0)
                let stateData = try JSONSerialization.data(withJSONObject:state,options:[.sortedKeys,.withoutEscapingSlashes])
                let stateJSON = String(data:stateData,encoding:.utf8) ?? ""
                let stateLines = ["元画像\(geometry.rawWidth)×\(geometry.rawHeight)／整数切抜き\(geometry.crop.width)×\(geometry.crop.height)／左回転\(geometry.quarterTurnsCCW*90)°の変換記録。ゲームの向き・自他は未認証"] + R551ScreenReadState.displayLines(state)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.battleWireRevision == revision,
                          self.selectedReadWork === readWork, !readWork.isCancelled,
                          self.rawTimelineFrameIDs.indices.contains(self.rawTimelineIndex),
                          self.rawTimelineSourceEpochs.indices.contains(self.rawTimelineIndex),
                          self.rawTimelineObservedMs.indices.contains(self.rawTimelineIndex),
                          self.rawTimelineFrameIDs[self.rawTimelineIndex] == frame,
                          self.rawTimelineSourceEpochs[self.rawTimelineIndex] == sourceEpoch,
                          self.rawTimelineObservedMs[self.rawTimelineIndex] == observedMs else { return }
                    let autoExport = self.pendingUnifiedExport.map {
                        $0.epoch == sourceEpoch && $0.frame == frame && $0.observed == observedMs
                    } ?? false
                    self.pendingUnifiedExport = nil
                    self.battleEvidenceBusy = false
                    self.selectedReadWork = nil; self.battleReadBusy = false
                    // Retire stale candidate export URL, not a completed on-disk file.
                    self.invalidateEvidenceExport()
                    self.battleAnalysisPNG = png
                    self.selectedOCRFailure = nil
                    self.battleAnalysisGeometry = geometry
                    self.battleAnalysisFrameID = frame
                    self.battleAnalysisEpoch = sourceEpoch
                    self.battleAnalysisObservedMs = observedMs
                    self.battleWireJSON = result.0; self.battleWireLines = result.1
                    self.screenReadStateJSON = stateJSON; self.screenReadStateLines = stateLines
                    self.battleWireStatus = "取得値は候補のみ。ターン不明・背景履歴のため実戦入力はHOLD"
                    if autoExport { self.prepareSelectedEvidenceFile(includeDiagnostics:true) }
                }
            } catch {
                let failedPNG=attemptedPNG
                let failure=R559OCRFailure.report(error,session:sessionID,frame:frame,epoch:sourceEpoch,
                    observedMs:observedMs,png:failedPNG,width:geometry.analysisWidth,height:geometry.analysisHeight)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.battleWireRevision == revision,
                          self.selectedReadWork === readWork else { return }
                    self.selectedReadWork = nil; self.battleReadBusy = false
                    self.selectedOCRFailure = failure
                    self.battleAnalysisPNG = failedPNG
                    self.battleWireStatus = "文字認識に失敗しました。画像と診断を保存して再試行できます"
                    if let pending = self.pendingUnifiedExport,
                       self.rawTimelineFrameIDs.indices.contains(self.rawTimelineIndex),
                       self.rawTimelineSourceEpochs.indices.contains(self.rawTimelineIndex),
                       self.rawTimelineObservedMs.indices.contains(self.rawTimelineIndex),
                       self.rawTimelineFrameIDs[self.rawTimelineIndex] == pending.frame,
                       self.rawTimelineSourceEpochs[self.rawTimelineIndex] == pending.epoch,
                       self.rawTimelineObservedMs[self.rawTimelineIndex] == pending.observed {
                        self.pendingUnifiedExport = nil
                        self.battleEvidenceBusy = false
                        self.prepareSelectedEvidenceFile(includeDiagnostics:true)
                    } else {
                        self.pendingUnifiedExport = nil
                        self.battleEvidenceBusy = false
                    }
                }
            }
        }
    }

    // UIImage.cgImage does not apply imageOrientation. Flatten the same visible
    // crop/turn into physical .up pixels, with a bounded allocation, before OCR.
    private static func physicallyOrientedAnalysisImage(_ image:UIImage) throws -> UIImage {
        guard let source=image.cgImage,
              FrameEvidenceExportGate.permitted(width:source.width,height:source.height)
        else { throw ResearchBattleVision.Failure.invalidImage }
        let swap:Bool
        switch image.imageOrientation {
        case .left,.leftMirrored,.right,.rightMirrored: swap=true
        case .up,.upMirrored,.down,.downMirrored: swap=false
        @unknown default: throw ResearchBattleVision.Failure.invalidImage
        }
        let width=swap ? source.height : source.width
        let height=swap ? source.width : source.height
        let size=CGSize(width:CGFloat(width),height:CGFloat(height))
        let format=UIGraphicsImageRendererFormat()
        format.scale=1;format.opaque=true
        let oriented=UIImage(cgImage:source,scale:1,orientation:image.imageOrientation)
        let physical=UIGraphicsImageRenderer(size:size,format:format).image { _ in
            oriented.draw(in:CGRect(origin:.zero,size:size))
        }
        guard let cg=physical.cgImage, cg.width==width, cg.height==height,
              physical.imageOrientation == .up else { throw ResearchBattleVision.Failure.invalidImage }
        return physical
    }

    // R27.441 explicit local export; PNG/JSON encoding never runs on the UI thread.
    // Exact analysis bytes accompany candidates. Raw-to-analysis semantics remain unverified.
    func prepareSelectedEvidenceFile() {
        prepareSelectedEvidenceFile(includeDiagnostics: false)
    }

    /// Research-only one-tap source packet. Never uploads automatically.
    /// Refresh selected-frame OCR first, when possible, so one tap is sufficient.
    private var pendingUnifiedExport: (epoch: Int64, frame: Int64, observed: Int64)?
    func prepareUnifiedEvidenceFile() {
        precondition(Thread.isMainThread)
        guard !battleEvidenceBusy,
              rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              rawTimelineSourceEpochs.indices.contains(rawTimelineIndex),
              rawTimelineObservedMs.indices.contains(rawTimelineIndex),
              diagnosticPreview != nil else {
            battleEvidenceStatus = "選択した背景画像がありません"; return
        }
        let frame = rawTimelineFrameIDs[rawTimelineIndex]
        let epoch = rawTimelineSourceEpochs[rawTimelineIndex]
        let observed = rawTimelineObservedMs[rawTimelineIndex]
        if !battleWireJSON.isEmpty && FrameEvidenceExportGate.sameSource(
            candidateFrame:battleAnalysisFrameID, candidateEpoch:battleAnalysisEpoch,
            candidateObservedMs:battleAnalysisObservedMs, rawFrame:frame,
            rawEpoch:epoch, rawObservedMs:observed) {
            prepareSelectedEvidenceFile(includeDiagnostics:true)
            return
        }
        // Separate analysis and export queues. No repeated capture or stale-frame reuse.
        inspectSelectedBattleState()
        pendingUnifiedExport = (epoch,frame,observed)
        battleEvidenceBusy = true
        battleEvidenceStatus = "選択画像をVisionで解析中。完了後に証拠ファイルを作成します"
    }

    private func prepareSelectedEvidenceFile(includeDiagnostics: Bool) {
        precondition(Thread.isMainThread)
        guard !battleEvidenceBusy else { return }
        invalidateEvidenceExport()
        guard rawTimelineImages.indices.contains(rawTimelineIndex),
              rawTimelineFrameIDs.indices.contains(rawTimelineIndex),
              rawTimelineSourceEpochs.indices.contains(rawTimelineIndex),
              rawTimelineObservedMs.indices.contains(rawTimelineIndex),
              let cg = rawTimelineImages[rawTimelineIndex].cgImage else {
            battleEvidenceStatus = "元画像またはフレーム証跡なし・作成を拒否"; return
        }
        let frame = rawTimelineFrameIDs[rawTimelineIndex]
        let epoch = rawTimelineSourceEpochs[rawTimelineIndex]
        let observedMs = rawTimelineObservedMs[rawTimelineIndex]
        let captureSessionID = battleResearchSessionID
        let reportUptimeMs=Int64(ProcessInfo.processInfo.systemUptime*1000)
        let freshnessPacket = ["automatic_full_frame":autoCandidateLease.snapshot(),"paired_move_candidates":pairedCandidateLease.snapshot()]
        let (readClockPacket,inputHealthPacket)=sampleQueue.sync {(readClockDiagnosticPacket(),inputHealth.object)}
        let r582CapturePacket = sampleQueue.sync { r582AutoCoverage.snapshot(epoch:epoch) }
        let appVersion = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "UNKNOWN"
        let appBuild = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "UNKNOWN"
        let candidateRevision = battleWireRevision
        guard let token = evidenceExportGate.request(epoch:epoch,frame:frame,observedMs:observedMs,
                candidateRevision:candidateRevision,width:cg.width,height:cg.height) else {
            battleEvidenceStatus = "画像上限または出典不正・作成を拒否"; return
        }
        let manualMegaEntries = megaManualNotebook.selected(sessionID:battleResearchSessionID,epoch:epoch,frameID:frame)
        // R548: collect the actual retained timeline, not a synthesized history.
        // These are display-only captures, not validated Battle AI observations.
        let retainedTimeline: [(frame:Int64,epoch:Int64,observed:Int64,image:CGImage,manual:[[String:Any]])] =
            includeDiagnostics ? rawTimelineImages.enumerated().compactMap { (i, image) in
                guard let cg=image.cgImage,
                      rawTimelineFrameIDs.indices.contains(i),
                      rawTimelineSourceEpochs.indices.contains(i),
                      rawTimelineObservedMs.indices.contains(i) else {return nil}
                let id=rawTimelineFrameIDs[i],ep=rawTimelineSourceEpochs[i]
                guard ep==epoch else {return nil}
                return (frame:id,epoch:ep,observed:rawTimelineObservedMs[i],image:cg,
                        manual:megaManualNotebook.selected(sessionID:battleResearchSessionID,
                            epoch:ep,frameID:id))
            } : []
        let originalCandidate = battleWireJSON
        // Never attach OCR from another image. For the one-tap packet, retain the
        // selected raw frame but omit the mismatched candidate explicitly.
        let matchingCandidate = originalCandidate.isEmpty || FrameEvidenceExportGate.sameSource(
            candidateFrame:battleAnalysisFrameID, candidateEpoch:battleAnalysisEpoch,
            candidateObservedMs:battleAnalysisObservedMs, rawFrame:frame,
            rawEpoch:epoch, rawObservedMs:observedMs)
        if !matchingCandidate && !includeDiagnostics {
            evidenceExportGate.invalidate()
            battleEvidenceStatus = "候補と背景画像の出典不一致・再解析してください"
            return
        }
        let candidate = matchingCandidate ? originalCandidate : ""
        let exclusionReason = matchingCandidate ? "NONE" : "DIFFERENT_FRAME_CANDIDATE_OMITTED"
        let failedOCR=selectedOCRFailure.flatMap {failure -> [String:Any]? in
            guard failure["capture_session_id"] as? String==captureSessionID,
                  failure["frame_id"] as? Int64==frame,failure["epoch"] as? Int64==epoch,
                  failure["receipt_uptime_ms"] as? Int64==observedMs else {return nil}
            return failure
        }
        let analysisPNG = candidate.isEmpty && failedOCR == nil ? nil : battleAnalysisPNG
        let analysisGeometry = candidate.isEmpty ? nil : battleAnalysisGeometry
        // Each telemetry source has its own window; it is NEVER frame-certified.
        var diagnosticPacket: Data?
        if includeDiagnostics {
            do {
                let vision = TP519VisionEvidenceMetrics.snapshot()
                let session = TP520VisionSessionFence.snapshot()
                let collision = TP521VisionCollisionFence.snapshot()
                let baseline = try R528DiagnosticCore.assemble(
                    r519:vision.redactedJSON, r520:session.redactedJSON,
                    r521:collision.redactedJSON,
                    epoch:session.epoch,frame:session.latestFrameID.flatMap(Int.init(exactly:)))
                diagnosticPacket = try TP532FirstPassDiagnostics.attach(to:baseline)
            } catch {
                // The export inventory records missing diagnostics.
                diagnosticPacket = nil
            }
        }
        let exportWork = R551EvidenceWork()
        evidenceWork = exportWork
        battleEvidenceBusy = true
        battleEvidenceStatus = "画像証跡を端末内で整理中"
        evidenceExportQueue.async { [weak self] in
            autoreleasepool {
                var savedURL: URL?
                var exportCandidate = candidate
                var exportExclusionReason = exclusionReason
                var failureReason = "UNKNOWN_EXPORT_FAILURE"
                var diagnosticIncludedInPacket = false
                do {
                    try exportWork.check()
                    let rawPNG = UIImage(cgImage:cg).pngData()
                    guard let png=rawPNG else {
                        failureReason = "RAW_PNG_ENCODE_FAILED"
                        throw ResearchBattleVision.Failure.invalidImage
                    }
                    var exportAnalysisPNG = analysisPNG
                    if !candidate.isEmpty {
                        let disposition = FrameEvidenceExportGate.candidateDisposition(
                            rawBytes:png.count, analysisBytes:analysisPNG?.count,
                            candidatePresent:true)
                        if disposition == "ANALYSIS_IMAGE_OMITTED_SIZE_OR_MISSING" {
                            exportCandidate = ""
                            exportAnalysisPNG = nil
                            exportExclusionReason = disposition
                        }
                    }
                    if let diagnostic = FrameEvidenceExportGate.rejectReason(
                        rawBytes:png.count,
                        analysisBytes:exportAnalysisPNG?.count,
                        candidatePresent:!exportCandidate.isEmpty) {
                        failureReason = diagnostic
                        throw ResearchBattleVision.Failure.invalidImage
                    }
                    var analysis: Any = NSNull()
                    if let bytes = exportAnalysisPNG {
                        guard let image = UIImage(data:bytes)?.cgImage,
                              FrameEvidenceExportGate.permitted(width:image.width,height:image.height) else {
                            failureReason = "ANALYSIS_IMAGE_INVALID"
                            throw ResearchBattleVision.Failure.invalidImage
                        }
                        analysis = ["width":image.width,"height":image.height,"png_bytes":bytes.count,
                            "png_sha256":SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),
                            "image_png_base64":bytes.base64EncodedString()] as [String:Any]
                    }
                    var bundle: [String: Any] = [
                        "schema":"trueplan.r27441.manual-frame-evidence.v2",
                        "source":"ondevice_background_unrotated_buffer",
                        "frame_id":frame,"epoch":epoch,"observed_ms_monotonic":observedMs,
                        "image_width":cg.width,"image_height":cg.height,"png_bytes":png.count,
                        "png_sha256":SHA256.hash(data:png).map { String(format:"%02x",$0) }.joined(),
                        "image_png_base64":png.base64EncodedString(),"analysis_image":analysis,
                        "research_candidate_envelope":exportCandidate.isEmpty ? NSNull() : exportCandidate as Any,
                        "candidate_image_may_be_rotated_or_cropped":true,
                        "verified_game_screen":false,"observed_turn":NSNull(),
                        "production_enabled":false,"battle_advice_authorized":false
                    ]
                    if exportCandidate.isEmpty,let failure=failedOCR {bundle["r559_ocr_failure"]=failure}
                    if !exportCandidate.isEmpty,let plan=analysisGeometry,let bytes=exportAnalysisPNG,
                       plan.rawWidth==cg.width,plan.rawHeight==cg.height,
                       let actual=UIImage(data:bytes)?.cgImage,
                       actual.width==plan.analysisWidth,actual.height==plan.analysisHeight {
                        bundle["analysis_projection"]=R556AnalysisProjection.report(plan:plan,envelope:exportCandidate,
                            session:captureSessionID,frame:frame,epoch:epoch,observedMs:observedMs,
                            rawSHA:bundle["png_sha256"] as? String ?? "",
                            analysisSHA:SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined())
                    } else {bundle["analysis_projection_omission"]="NO_MATCHING_DECLARED_TRANSFORM"}
                    if includeDiagnostics {
                        bundle["r547_manual_mega_evidence"] = R547MegaManualExport.envelope(
                            records:manualMegaEntries,frame:frame,epoch:epoch,
                            imageHash:bundle["png_sha256"] as? String ?? "")
                    }
                    if includeDiagnostics {
                        // A rejected or absent diagnostics sidecar cannot erase the raw frame.
                        // The manifest below reports exactly which source was omitted.
                        bundle = R535UnifiedEvidenceGate.mergeOrOmit(
                            bundle, diagnostics:diagnosticPacket, expectedFrame:frame,
                            expectedEpoch:epoch, candidateExclusionReason:exportExclusionReason)
                    }
                    if includeDiagnostics {
                        bundle = try R537EvidenceManifest.attach(bundle,frame:frame,epoch:epoch,
                            candidateExcluded:exportExclusionReason != "NONE")
                    }
                    if includeDiagnostics {
                        // Spatial coverage is measurable; own/opp field ownership is NOT.
                        bundle["r543_spatial_coverage"] = R543SpatialCoverageAudit.inspect(
                            bundle,frame:frame,epoch:epoch)
                    }
                    if includeDiagnostics {
                        // Screen-side, turn, HP-vs-PP and Mega remain uncertified.
                        bundle["r544_unattributed_observations"] = R544ObservationInventory.inspect(
                            bundle,frame:frame,epoch:epoch)
                        bundle["r545_device_trial_readiness"] = R545EvidenceReadiness.inspect(
                            bundle,frame:frame,epoch:epoch)
                        // Meta-only research: distinguish on-screen Mega text from certified evolution.
                        bundle["r546_mega_evidence_audit"] = R546MegaEvidenceAudit.inspect(
                            bundle,frame:frame,epoch:epoch)
                    }
                    bundle["capture_session_id"] = captureSessionID
                    bundle["diagnostic_privacy"]=["system_uptime_ms_at_prepare":reportUptimeMs,
                        "sharing":"USER_INITIATED_BUG_REPORT_ONLY","may_contain_images_and_OCR":true]
                    if includeDiagnostics {
                        bundle["r554_candidate_leases"]=freshnessPacket
                        bundle["r562_read_clock_diagnostics"]=readClockPacket
                        bundle["r563_input_health"]=inputHealthPacket
                    }
                    bundle["battle_id"] = NSNull() // capture scope is not a verified game battle ID
                    bundle["capture_timestamp_basis"] = "HOST_UPTIME_RECEIPT_UNCALIBRATED_TO_SAMPLE_PTS"
                    if !exportCandidate.isEmpty,let analysis = analysis as? [String:Any],let digest=analysis["png_sha256"] as? String,
                       let width=analysis["width"] as? Int,let height=analysis["height"] as? Int {
                        bundle["screen_read_state"] = R551ScreenReadState.make(
                            envelope:exportCandidate,captureSessionID:captureSessionID,
                            frame:frame,epoch:epoch,observedMs:observedMs,imageSHA:digest,width:width,height:height)
                    } else {
                        bundle["screen_read_state"] = NSNull()
                    }
                    // R581: inventory every readable domain in the existing one-button ZIP.
                    // Missing or unverified items are explicitly UNKNOWN, never filled.
                    bundle["r581_full_read_coverage"] = R581ReadabilityCoverage.make(
                        sourceSHA:bundle["png_sha256"] as? String ?? "",
                        sourceKind:"LIVE_RETAINED_FRAME",
                        snapshot:bundle["screen_read_state"] as? [String:Any],
                        mega:bundle["r546_mega_evidence_audit"] as? [String:Any],
                        projection:bundle["analysis_projection"] as? [String:Any])
                    // R634: route all 79 canonical fields to actual evidence sources.
                    // Only capture receipt metadata can be promoted at this stage.
                    R634FieldEvidenceRouting.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R635LayoutToFields.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R636TypedHUDEvidence.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R637GeometryDiagnostics.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R638SourceBindingAudit.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R639OrientationHypotheses.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R640FieldGapAudit.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R641RotatedHUDCandidates.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R642MappedFrameProof.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R643SplitPPProof.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R644MoveSlotCoupler.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R645DualHPEvidence.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R646FieldSignalReaders.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    diagnosticIncludedInPacket = bundle["metrics"] is [String:Any]
                    let data = try JSONSerialization.data(withJSONObject:bundle,
                        options:[.sortedKeys,.withoutEscapingSlashes])
                    guard data.count <= FrameEvidenceExportGate.maximumJSONBytes else {
                        failureReason = "JSON_SIZE_LIMIT"
                        throw ResearchBattleVision.Failure.invalidJSON
                    }
                    try exportWork.check()
                    failureReason = "FILE_WRITE_OR_PROTECTION_FAILURE"
                    try FileManager.default.createDirectory(at:Self.evidenceDirectory,
                        withIntermediateDirectories:true,attributes:nil)
                    var folder = Self.evidenceDirectory
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try folder.setResourceValues(values)
                    let destination = Self.evidenceDirectory.appendingPathComponent(
                        "R537_EVIDENCE_\(epoch)_\(frame)_\(UUID().uuidString.prefix(8)).json")
                    try data.write(to:destination,options:[.atomic,.completeFileProtectionUnlessOpen])
                    // Readback both validates the bytes and guarantees the inventory is parsable.
                    let readback = try Data(contentsOf:destination,options:[.mappedIfSafe])
                    guard readback.count == data.count,
                          SHA256.hash(data:readback) == SHA256.hash(data:data),
                          (!includeDiagnostics ||
                           (R542EvidenceIntegrityGate.verify(readback,frame:frame,epoch:epoch) == .pass
                            && R543SpatialCoverageAudit.verifyAttached(readback,frame:frame,epoch:epoch)
                            && R544ObservationInventory.verifyAttached(readback,frame:frame,epoch:epoch)
                            && R545EvidenceReadiness.verifyAttached(readback,frame:frame,epoch:epoch)
                            && R546MegaEvidenceAudit.verifyAttached(readback,frame:frame,epoch:epoch)
                            && R547MegaManualExport.verify(
                                (try? JSONSerialization.jsonObject(with:readback) as? [String:Any]) ?? [:],
                                frame:frame,epoch:epoch))) else {
                        try? FileManager.default.removeItem(at:destination)
                        failureReason = "FILE_READBACK_INTEGRITY_FAILURE"
                        throw ResearchBattleVision.Failure.invalidJSON
                    }
                    // A single user action shares ONE ZIP containing the verified JSON
                    // plus every still-retained background frame. Uncaptured animation
                    // cannot be reconstructed and never becomes a certified Mega event.
                    if includeDiagnostics {
                        let zipURL=Self.evidenceDirectory.appendingPathComponent(
                            "R548_ONE_TAP_\(epoch)_\(frame)_\(UUID().uuidString.prefix(8)).zip")
                        var entries=[R548ResearchArchive.Entry(name:"selected_evidence.json",bytes:readback)]
                        var snapshots=[[String:Any]]()
                        // R584: only historical OCR event mentions; never live battle state.
                        var retainedTextIndexes=[[String:Any]]()
                        var omitted=[String]()
                        var ocrCache=[String:[String:Any]]()
                        var visualHUDFrames=[[String:Any]]()
                        var colorHUDFrames=[[String:Any]]()
                        // R593: bounded raw-pixel signatures for historical visual change.
                        var visualSceneSamples=[[String:Any]]()
                        // R594: separate, uncalibrated actor appearance descriptors.
                        var actorAppearanceSamples=[[String:Any]]()
                        let ocrDeadline = ProcessInfo.processInfo.systemUptime + 6.0
                        for sample in retainedTimeline.prefix(8) {
                            try exportWork.check()
                            guard let bytes=UIImage(cgImage:sample.image).pngData(),
                                  bytes.count<=BackgroundPreviewBuffer.maximumPNGBytes else {
                                omitted.append("FRAME_\(sample.frame)_PNG_ENCODE_OR_LIMIT")
                                continue
                            }
                            let name="frames/frame_\(sample.epoch)_\(sample.frame).png"
                            let digest=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                            let cached = ocrCache[digest]
                            let remainingMs = max(0,Int((ocrDeadline-ProcessInfo.processInfo.systemUptime)*1000))
                            let observation = cached ?? R548MegaSceneProbe.inspect(
                                bytes,budgetMs:min(1800,remainingMs),work:exportWork)
                            ocrCache[digest] = observation
                            // R589/R590: one bounded RGBA conversion reused by both
                            // pixel scanners. Both are historical, uncalibrated evidence.
                            let w=sample.image.width,h=sample.image.height
                            var pixelHUD:[String:Any]=[
                                "schema":R589PixelHUDProbe.schema,"status":"HOLD_PIXEL_BUFFER_NOT_AVAILABLE",
                                "image_sha256":digest,"frame_id":sample.frame,"epoch":sample.epoch,
                                "current_state_eligible":false,"owner_certified":false]
                            var colorHUD:[String:Any]=[
                                "schema":R590ColorHUDCorroboration.schema,
                                "status":"HOLD_PIXEL_BUFFER_NOT_AVAILABLE",
                                "candidate_count":0,"color_run_candidates":[[String:Any]](),
                                "image_sha256":digest,"frame_id":sample.frame,
                                "epoch":sample.epoch,"observed_ms_monotonic":sample.observed,
                                "owner_certified":false,"current_state_eligible":false]
                            var visualScene=R593VisualChangeEvidence.unavailable(
                                epoch:sample.epoch,frame:sample.frame,
                                observedMs:sample.observed,imageSHA:digest,
                                reason:"RGBA_RENDER_UNAVAILABLE")
                            var appearance=R594ActorAppearance.unavailable(
                                epoch:sample.epoch,frame:sample.frame,ms:sample.observed,
                                sha:digest,reason:"RGBA_RENDER_UNAVAILABLE")
                            if w>=128,h>=128,w<=R589PixelHUDProbe.maxDimension,
                               h<=R589PixelHUDProbe.maxDimension,
                               w*4<=R589PixelHUDProbe.maxPixelBytes/h {
                                var rgba=[UInt8](repeating:0,count:w*h*4)
                                let produced=rgba.withUnsafeMutableBytes { buffer -> Bool in
                                    guard let ctx=CGContext(data:buffer.baseAddress,width:w,height:h,
                                        bitsPerComponent:8,bytesPerRow:w*4,
                                        space:CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
                                    else {return false}
                                    ctx.draw(sample.image,in:CGRect(x:0,y:0,width:w,height:h))
                                    return true
                                }
                                if produced {
                                    visualScene=R593VisualChangeEvidence.capture(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        observedMs:sample.observed,imageSHA:digest)
                                    appearance=R594ActorAppearance.capture(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        ms:sample.observed,sha:digest)
                                    pixelHUD=R589PixelHUDProbe.inspect(pixels:rgba,width:w,height:h,
                                        rowBytes:w*4,epoch:sample.epoch,frame:sample.frame,
                                        observedMs:sample.observed,imageSHA:digest)
                                    colorHUD=R590ColorHUDCorroboration.inspect(
                                        pixels:rgba,width:w,height:h,rowBytes:w*4,
                                        epoch:sample.epoch,frame:sample.frame,
                                        observedMs:sample.observed,imageSHA:digest)
                                }
                            }
                            visualSceneSamples.append(visualScene)
                            actorAppearanceSamples.append(appearance)
                            colorHUDFrames.append(colorHUD)
                            visualHUDFrames.append(pixelHUD)
                            entries.append(.init(name:name,bytes:bytes))
                            // Reuse OCR evidence already collected for this frame;
                            // do NOT run extra Vision requests during one-tap export.
                            let textIndex=R583FrameReadabilityIndex.make(
                                frame:sample.frame,epoch:sample.epoch,
                                observedMs:sample.observed,imageSHA:digest,ocr:observation)
                            let indexName="frames/frame_\(sample.epoch)_\(sample.frame)_readability.json"
                            let indexData=try JSONSerialization.data(withJSONObject:textIndex,
                                options:[.sortedKeys,.withoutEscapingSlashes])
                            entries.append(.init(name:indexName,bytes:indexData))
                            retainedTextIndexes.append(textIndex)
                            snapshots.append([
                                "file":name,"readability_index_file":indexName,
                                "readability_index_schema":R583FrameReadabilityIndex.schema,
                                "text_candidate_fields":textIndex["fields_with_candidate_text"] ?? 0,
                                "frame_id":sample.frame,"epoch":sample.epoch,
                                "observed_ms_monotonic":sample.observed,"png_sha256":digest,
                                "png_bytes":bytes.count,"width":sample.image.width,
                                "height":sample.image.height,
                                "mega_scene_ocr_hints":observation,
                                "ocr_reused_for_identical_pixels":cached != nil,
                                "manual_mega_notes":sample.manual,
                                "own_opponent_certified":false,
                                "mega_form_visual_certified":false
                            ])
                        }
                        var manifest=R548CaptureManifest.make(selectedFrame:frame,
                            selectedEpoch:epoch,frames:snapshots,omissions:omitted)
                        manifest["capture_session_id"] = captureSessionID
                        manifest["r582_automatic_delivery_coverage"] = r582CapturePacket
                        // R584: include a bounded chronological OCR-mention timeline.
                        // It is tied to these exact retained frames and contains no
                        // inferred turn number, owner, or Mega visual confirmation.
                        let eventMentions=R584BattleTextEventTimeline.make(indexes:retainedTextIndexes)
                        let eventMentionsData=try JSONSerialization.data(withJSONObject:eventMentions,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_text_event_mentions.json",bytes:eventMentionsData))
                        // R585: screen-space OCR boxes for downstream ROI calibration.
                        // No orientation/side/identity confirmation from this archive.
                        let spatial=R585SpatialOCRProjection.make(indexes:retainedTextIndexes)
                        let spatialData=try JSONSerialization.data(withJSONObject:spatial,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_spatial_ocr_candidates.json",bytes:spatialData))
                        // R586: lexical HUD numbers intersected with candidate geometry.
                        // Every own/opponent/PP label is a HYPOTHESIS, never battle state.
                        let hud=R586HUDSpatialCandidates.make(spatial:spatial)
                        let hudData=try JSONSerialization.data(withJSONObject:hud,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_hud_region_hypotheses.json",bytes:hudData))
                        manifest["r584_historical_text_event_mentions_file"] = "historical_text_event_mentions.json"
                        manifest["r584_historical_mention_count"] = eventMentions["mention_count"] ?? 0
                        manifest["r584_events_or_owners_certified"] = false
                        manifest["r585_spatial_ocr_file"] = "historical_spatial_ocr_candidates.json"
                        manifest["r585_spatial_candidate_count"] = spatial["candidate_count"] ?? 0
                        manifest["r585_orientation_or_owner_certified"] = false
                        manifest["r586_hud_hypotheses_file"] = "historical_hud_region_hypotheses.json"
                        manifest["r586_hud_hypotheses_count"] = hud["matched_candidates"] ?? 0
                        manifest["r586_hud_role_or_orientation_certified"] = false
                        // R587: cross-bind HUD numeric anchors to exactly retained PNGs.
                        // This is historical evidence; do not promote to live state.
                        let frameAssociations=R587HUDFrameAssociation.make(
                            hud:hud,snapshots:snapshots)
                        let frameAssociationsData=try JSONSerialization.data(
                            withJSONObject:frameAssociations,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_hud_frame_associations.json",
                                             bytes:frameAssociationsData))
                        manifest["r587_frame_associations_file"] = "historical_hud_frame_associations.json"
                        manifest["r587_frame_association_count"] = frameAssociations["frame_count"] ?? 0
                        manifest["r587_orientation_or_owner_certified"] = false
                        // R590: correlate historical three-color HUD pixels to the
                        // exact retained frame's OCR fractions/percentages. Never
                        // promote region labels to authenticated owner or HP.
                        let colorCrosscheck=R590ColorHUDCorroboration.correlate(
                            pixelFrames:colorHUDFrames,associations:frameAssociations)
                        let colorCrosscheckData=try JSONSerialization.data(
                            withJSONObject:colorCrosscheck,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_hud_color_crosscheck.json",
                                             bytes:colorCrosscheckData))
                        manifest["r590_hud_color_crosscheck_file"] = "historical_hud_color_crosscheck.json"
                        manifest["r590_ocr_pixel_hp_or_owner_certified"] = false
                        // R592: stricter than same-frame coincidence; require geometric
                        // proximity between the pixel-run rectangle and the OCR box.
                        // Neither image orientation nor player ownership is certified.
                        let spatialPixel=R592HUDSpatialPixelAlignment.make(
                            pixelFrames:colorHUDFrames,associations:frameAssociations)
                        let spatialPixelData=try JSONSerialization.data(
                            withJSONObject:spatialPixel,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_hud_spatial_pixel_alignment.json",
                                             bytes:spatialPixelData))
                        manifest["r592_hud_spatial_pixel_file"] = "historical_hud_spatial_pixel_alignment.json"
                        manifest["r592_spatial_pixel_frame_count"] = spatialPixel["frame_count"] ?? 0
                        manifest["r592_owner_hp_orientation_certified"] = false
                        // R588: rotation-of-OCR consensus hypotheses, NOT screen orientation.
                        let rotationEvidence=R588OrientationEvidence.make(associations:frameAssociations)
                        let rotationEvidenceData=try JSONSerialization.data(
                            withJSONObject:rotationEvidence,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_ocr_rotation_consensus.json",
                                             bytes:rotationEvidenceData))
                        manifest["r588_ocr_rotation_consensus_file"] = "historical_ocr_rotation_consensus.json"
                        manifest["r588_ocr_rotation_candidate_count"] = rotationEvidence["candidate_count"] ?? 0
                        manifest["r588_display_rotation_or_owner_certified"] = false
                        // R589 visual green bar runs are historical pixel evidence,
                        // NOT confirmed HP, ownership, color state or game orientation.
                        let pixelReport:[String:Any]=[
                            "schema":"trueplan.r589.historical-hud-pixel-bundle.v1",
                            "frame_count":visualHUDFrames.count,"frames":visualHUDFrames,
                            "owner_certified":false,"hp_certified":false,
                            "current_state_eligible":false,"automatic_upload":false]
                        let pixelData=try JSONSerialization.data(withJSONObject:pixelReport,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_hud_pixel_runs.json",bytes:pixelData))
                        manifest["r589_hud_pixel_runs_file"]="historical_hud_pixel_runs.json"
                        manifest["r589_pixel_frame_count"]=visualHUDFrames.count
                        manifest["r589_owner_hp_or_mega_certified"]=false
                        // R593: compare actual rendered pixels across saved frames.
                        // These changes may be sprite animation, camera motion or FX;
                        // never assert a switch, Mega evolution, owner or species.
                        var visualChanges=R593VisualChangeEvidence.timeline(visualSceneSamples)
                        // Keep the archive entry count unchanged: attach the new
                        // appearance audit to the existing historical visual JSON.
                        visualChanges["r594_actor_appearance"] =
                            R594ActorAppearance.timeline(actorAppearanceSamples)
                        // R595: optional on-device reviewed form references. An
                        // absent catalog explicitly returns HOLD; never guesses Mega.
                        let localRefURL=FileManager.default.urls(
                            for:.applicationSupportDirectory,in:.userDomainMask
                        ).first?.appendingPathComponent("R595FormReferenceCatalog.json")
                        visualChanges["r595_form_reference_candidates"] =
                            R595FormReferenceMatcher.audit(actorAppearanceSamples,
                                references:R595FormReferenceMatcher.loadLocalCatalog(at:localRefURL))
                        let visualChangesData=try JSONSerialization.data(
                            withJSONObject:visualChanges,options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"historical_visual_region_changes.json",
                                             bytes:visualChangesData))
                        manifest["r593_visual_region_changes_file"] = "historical_visual_region_changes.json"
                        manifest["r593_visual_pair_count"] = visualChanges["pair_count"] ?? 0
                        manifest["r593_switch_or_mega_confirmed"] = false
                        manifest["r594_appearance_audit_embedded"] = true
                        manifest["r594_species_or_mega_certified"] = false
                        manifest["r595_optional_reference_matcher_embedded"] = true
                        manifest["r595_form_identity_certified"] = false
                        manifest["battle_id"] = NSNull()
                        manifest["rotation_ocr_budget_ms"] = 6000
                        manifest["rotation_ocr_complete"] = snapshots.allSatisfy {
                            (($0["mega_scene_ocr_hints"] as? [String:Any])?["rotations_completed"] as? [Int])?.count == 4
                        } && !snapshots.isEmpty
                        let manifestData=try JSONSerialization.data(withJSONObject:manifest,
                            options:[.sortedKeys,.withoutEscapingSlashes])
                        entries.append(.init(name:"capture_manifest.json",bytes:manifestData))
                        do {
                            try exportWork.check()
                            entries = try R551EvidenceIntegrity.appendingIndex(entries,
                                captureSessionID:captureSessionID,frame:frame,epoch:epoch,
                                appVersion:appVersion,appBuild:appBuild)
                            let r602Entries = R602OneTapFormArchive.beforeZip(entries)
                            let r603Entries = R603FormReadiness.beforeZip(r602Entries)
                            let r604Entries = R604HistoricalFeatureArchive.beforeZip(
                                r603Entries, samples: actorAppearanceSamples
                            )
                            let r605Entries = R605ExactFrameBinding.beforeZip(r604Entries)
                            let r607Entries = R607FrameProvenanceAudit.beforeZip(r605Entries)
                            let r608Entries = R608FramePixelEvidence.beforeZip(r607Entries)
                            let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)
                            let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)
                            let r611Entries = R611TemporalHUDReview.beforeZip(r610Entries)
                            let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)
                            guard r612Entries.count == r610Entries.count + 2 else {
                                throw NSError(domain:"R612_EVIDENCE_CAPACITY_EXHAUSTED",code:612)
                            }
                            let r613Entries = R613R616IntegratedReadiness.beforeZip(r612Entries)
                            guard r613Entries.count == r612Entries.count + 1 else {
                                throw NSError(domain:"R616_ARCHIVE_READINESS_CAPACITY_EXHAUSTED",code:616)
                            }
                            let r617Entries = R617R620RotationReadout.beforeZip(r613Entries)
                            guard r617Entries.count == r613Entries.count + 1 else {
                                throw NSError(domain:"R620_ROTATION_ARCHIVE_CAPACITY_EXHAUSTED",code:620)
                            }
                            let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)
                            guard r621Entries.count == r617Entries.count &&
                                  R621R624VisualCandidates.containsReport(r621Entries) else {
                                throw NSError(domain:"R624_VISUAL_EMBEDDED_REPORT_MISSING",code:624)
                            }
                            let r625Entries = R625R628PixelHUDAndSprite.beforeZip(r621Entries)
                            guard r625Entries.count == r621Entries.count &&
                                  R625R628PixelHUDAndSprite.containsReport(r625Entries) else {
                                throw NSError(domain:"R628_PIXEL_ARCHIVE_HOLD",code:628)
                            }
                            _ = try R548ResearchArchive.write(
                                r625Entries, to: zipURL, work: exportWork
                            )
                            // The original verified JSON remains in Application Support.
                            savedURL=zipURL
                        } catch {
                            // Fail transparent: a selected-frame JSON is better than no evidence.
                            failureReason="ZIP_FAILED_SELECTED_JSON_ONLY"
                            savedURL=destination
                        }
                    } else {
                        savedURL=destination
                    }
                } catch {
                    // Diagnostics contain only a fixed category; never leak paths or image contents.
                }
                let exportFailure = failureReason
                let resultURL = savedURL
                let includedCandidate = !exportCandidate.isEmpty
                let includedMetrics = savedURL != nil && diagnosticIncludedInPacket
                let outcomeReason = exportExclusionReason
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        if let url=resultURL { try? FileManager.default.removeItem(at:url) }; return
                    }
                    // A retired completion must never unlock or replace a newer operation.
                    guard self.evidenceWork === exportWork, !exportWork.isCancelled else {
                        if let url=resultURL { try? FileManager.default.removeItem(at:url) }; return
                    }
                    guard self.rawTimelineFrameIDs.indices.contains(self.rawTimelineIndex),
                          self.rawTimelineSourceEpochs.indices.contains(self.rawTimelineIndex),
                          self.evidenceExportGate.accepts(token,
                            epoch:self.rawTimelineSourceEpochs[self.rawTimelineIndex],
                            frame:self.rawTimelineFrameIDs[self.rawTimelineIndex],
                            candidateRevision:self.battleWireRevision) else {
                        if let url=resultURL { try? FileManager.default.removeItem(at:url) }; return
                    }
                    self.battleEvidenceBusy = false
                    self.evidenceWork = nil
                    self.evidenceExportGate.finish(token)
                    guard let url=resultURL else {
                        self.battleEvidenceStatus = "証跡作成失敗 [\(exportFailure)]・共有不可"; return
                    }
                    self.battleEvidenceURL = url
                    self.evidenceUptimeDisclosure="この診断には端末稼働時間 約\(reportUptimeMs/1000)秒と画像・取得できたOCR文字が含まれます。不具合調査用の提出先を選び、必要な場合に共有してください。"
                    if includeDiagnostics { self.unifiedEvidenceURL = url }
                    let metricsLabel = includedMetrics ? "診断あり" : "診断欠落（目録に記録）"
                    let ocrLabel = includedCandidate ? "同一フレームOCRあり" : "OCR省略 [\(outcomeReason)]"
                    let archiveLabel = url.pathExtension.lowercased() == "zip"
                        ? "保持済み背景フレームと診断をZIPに集約（メガ自動認証なし）"
                        : "選択フレームJSONのみ（全フレームZIP未生成）"
                    self.battleEvidenceStatus = "\(archiveLabel)／\(ocrLabel)／\(metricsLabel)／保存先未確認"
                    // Do not delete while a user is navigating the Files share sheet.
                }
            }
        }
    }

    func copyBattleStateCandidateJSON() {
        precondition(Thread.isMainThread)
        guard !battleWireJSON.isEmpty else { return }
        UIPasteboard.general.string = battleWireJSON // explicit user tap; no image bytes
    }

    // Must run on sampleQueue: continuity/latency/generation are queue-isolated.
    // Other modules protect their own snapshots. Section epochs are explicitly
    // verified and never silently substituted across an epoch transition.
    private func unifiedAuditSnapshot(nowMs: Int64, phase: String,
                                      prior: String? = nil,
                                      battleWire: String? = nil) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let continuityData = try? encoder.encode(continuity.snapshot(nowMs: nowMs)),
              let latencyData = try? encoder.encode(latencyAudit.snapshot()),
              let ptsData = try? encoder.encode(sampleClockAudit.summary()),
              let continuityText = String(data: continuityData, encoding: .utf8),
              let latencyText = String(data: latencyData, encoding: .utf8),
              let ptsText = String(data: ptsData, encoding: .utf8) else { return nil }
        let ingress = rawIngressAudit.snapshot()
        let rawObject: [String: Any] = [
            "r563_input_health":inputHealth.object,
            "r562_read_clock_diagnostics":readClockDiagnosticPacket(),
            "candidate_receipt_leases":["automatic_full_frame":autoCandidateLease.snapshot(),"paired_move_candidates":pairedCandidateLease.snapshot()],
            "active_epoch": (ingress.activeEpoch.map { NSNumber(value: $0) } as Any?) ?? NSNull(),
            "last_delivered_frame_id": (ingress.lastDelivered.map { NSNumber(value: $0.frameID) } as Any?) ?? NSNull(),
            "last_delivered_uptime_ms": (ingress.lastDelivered.map { NSNumber(value: $0.deliveredMs) } as Any?) ?? NSNull(),
            "stream_begins": ingress.streamBegins,
            "epoch_rotations": ingress.epochRotations,
            "presented_frames": ingress.presentedFrames,
            "delivery_accepted": ingress.deliveryAccepted,
            "delivery_rejected": ingress.deliveryRejected,
            "invalid_transitions": ingress.invalidTransitions,
            "eligible_for_battle_state": false
        ]
        guard let rawBytes = try? JSONSerialization.data(withJSONObject: rawObject, options: [.sortedKeys]),
              let rawText = String(data: rawBytes, encoding: .utf8) else { return nil }
        return ResearchUnifiedTelemetryBundle.build(
            epoch: generation, uptimeMs: nowMs, phase: phase,
            continuityJSON: continuityText, latencyJSON: latencyText,
            ptsJSON: ptsText, ingressJSON: rawText,
            previousEpochJSON: prior,
            captureSessionTag: captureAuditSessionTag,
            observationJSON: battleWire)
    }

    func copyUnifiedAuditJSON() {
        precondition(Thread.isMainThread)
        // Snapshot the published wire on MAIN; do not read MainActor UI state
        // on the capture queue, or reuse it for archival epoch rotations.
        let currentWire = battleWireJSON
        let result = sampleQueue.sync {
            unifiedAuditSnapshot(nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000),
                                 phase: "manual_one_tap",
                                 prior: archivedUnifiedAuditJSON,
                                 battleWire: currentWire)
        }
        guard let result else {
            unifiedAuditStatus = "統合監査：証跡が不完全・コピー停止（HOLD）"
            return
        }
        UIPasteboard.general.string = result
        unifiedAuditStatus = "統合監査JSONを1回でコピー済み（研究用・Battle State未認証）"
    }

    func refreshContinuityStatus() {
        precondition(Thread.isMainThread)
        let report = sampleQueue.sync {
            continuity.snapshot(nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
        }
        continuityStatus = "受信\(report.deliveredFrames)枚／非表示中\(report.backgroundFrames)枚／最長断絶\(report.longestFrameGapMs)ms／不一致寸法\(report.unexpectedShapeRejects)件。\(report.status)"
    }

    func refreshOCRLatencyStatus() {
        precondition(Thread.isMainThread)
        let report = sampleQueue.sync { latencyAudit.snapshot() }
        let p95 = report.p95FrameAgeMsLast32.map(String.init) ?? "未測定"
        latencyStatus = "処理済み\(report.measuredPairs)組／期限内\(report.withinBudgetPairs)組／1500ms超\(report.overBudgetPairs)組／p95(直近32組)\(p95)ms。実機動作未認証"
    }

    func copyLocalOCRLatencyJSON() {
        precondition(Thread.isMainThread)
        let report = sampleQueue.sync { latencyAudit.snapshot() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let bytes = try? encoder.encode(report),
              let json = String(data: bytes, encoding: .utf8) else {
            latencyStatus = "数値ログ生成失敗・技推薦なし"
            return
        }
        UIPasteboard.general.string = json // explicit button, no OCR text or video
        refreshOCRLatencyStatus()
    }

    func copyLocalContinuityJSON() {
        precondition(Thread.isMainThread)
        let report = sampleQueue.sync {
            continuity.snapshot(nowMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8) else {
            continuityStatus = "数値ログの生成に失敗。画面は保存しません"
            return
        }
        UIPasteboard.general.string = json  // explicit user tap only; no frames or OCR strings.
        refreshContinuityStatus()
    }

    // User explicitly removes all identifiable pixels / OCR words from volatile UI.
    func clearDiagnosticPreview() {
        precondition(Thread.isMainThread)
        clearManualOCRDiagnostic(clearGroundTruth: true)
        sampleQueue.sync { diagnosticMemory.clear(); rawPreviewBuffer.clear() }
        rawTimelineImages.removeAll(keepingCapacity: false)
        rawTimelineFrameIDs.removeAll(keepingCapacity: false)
        rawTimelineAgesMs.removeAll(keepingCapacity: false)
        rawTimelineSourceEpochs.removeAll(keepingCapacity: false)
        rawTimelineObservedMs.removeAll(keepingCapacity: false)
        rawOrientationProposals.removeAll(keepingCapacity: false)
        rawPreviewManualTurn=nil
        rawPreviewUseCrop=true
        calibrationLayout = .portraitLandscapeDiagnostics
        calibrationVisible = false
        calibrationStatus = "4技の仮枠較正待ち・OCR未接続"
        calibrationMappedROIs = []
        calibrationOverlayROIs = []
        orientationStatus="画面方向の診断待ち"
        displayTurnLabel="未判定"
        diagnosticDisplayAspect = 1108.0 / 512.0
        captureResolutionStatus = "取得解像度の確認待ち（OCR精度未認証）"
        rawTimelineIndex = 0
        rawTimelineCount = 0
        rawTimelineStatus = "背景履歴を消去済み"
        diagnosticPreview = nil
        diagnosticIsUnfiltered = false
        diagnosticCandidates = ["—", "—", "—", "—"]
        diagnosticFrameID = 0
        diagnosticStatus = "診断プレビュー消去済み（次の背景画面を待機）"
        diagnosticFilterStatus = "画面切替候補の除外待ち"
    }

    func stop() {
        invalidateReceiptLeases(reason:"SOURCE_STOPPED",stop:true)
        candidateExpiryTimer?.invalidate();candidateExpiryTimer=nil
        refreshCandidateFreshness()
        // Silence audio synchronously before invalidating the observation stream.
        voiceAnnouncer.stopImmediately()
        voiceGate.resetSession()
        sampleQueue.sync {
            let beforeStopMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
            archivedUnifiedAuditJSON = unifiedAuditSnapshot(nowMs: beforeStopMs,
                phase: "before_capture_stop") ?? archivedUnifiedAuditJSON
            continuity.stopped(epoch: generation,
                atMs: Int64(ProcessInfo.processInfo.systemUptime * 1000))
            active = false; activeStreamIdentity = nil
            latencyAudit.stop(epoch: generation)
            diagnosticMemory.clear()
            rawPreviewBuffer.clear()
            generation += 1; gate.halt(); observationFence.stop()
            autoResearchGate.reset()
            autoAdmission.reset()
        }
        SCContentSharingPicker.shared.remove(self)
        requestingPermission = false
        running = false
        lastMoveCandidates = ["—", "—", "—", "—"]
        clearDiagnosticPreview()
        status = "利用者が停止しました。OCR結果破棄・推薦禁止"
        refreshContinuityStatus()
        refreshOCRLatencyStatus()
        let previous = stream
        stream = nil
        Task { @MainActor in
            if let previous { try? await previous.stopCapture() }
        }
    }
}
