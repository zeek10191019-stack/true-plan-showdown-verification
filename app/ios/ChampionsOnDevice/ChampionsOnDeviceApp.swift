import SwiftUI
import UniformTypeIdentifiers

@available(iOS 27.0, *)
@main
struct ChampionsOnDeviceApp: App {
    @StateObject private var capture = CaptureCoordinator()
    @StateObject private var offlinePNG = R576OfflinePNGInspector()
    @State private var showOfflinePNGPicker = false
    @State private var showMegaCatalogPicker = false
    @State private var megaCatalogStatus = "メガ参照JSON未取込"
    @State private var unifiedShareItem: R535EvidenceShareItem?
    @State private var megaManualSide = "OWN"
    @State private var megaManualSpecies = ""
    @State private var megaManualForm = "UNKNOWN"
    @State private var megaManualVariant = ""
    @State private var megaManualBasis = "UNVERIFIED"


    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("iPhone端末内の画面認識") {
                        Button("画面取得を開始") { capture.startPicker() }.disabled(capture.running || capture.requestingPermission)
                        Button("取得を停止", role: .destructive) { capture.stop() }
                        Text(capture.status).font(.footnote)
                    }
                    Section("R576｜保存済みPNGを実画像で検証（画面共有なし）") {
                        Button("iPhone内のPNGファイルを選択") { showOfflinePNGPicker = true }
                        Text(offlinePNG.status).font(.caption)
                        if let image=offlinePNG.image {
                            Image(uiImage:image).resizable().scaledToFit()
                                .accessibilityLabel("選択済みの過去PNG。実戦現在画面ではありません")
                        }
                        Button("一括検証：画面・HP・技・PP・メガ文字・証拠JSON") {offlinePNG.inspectAll()}
                            .disabled(offlinePNG.image == nil || offlinePNG.busy)
                        if let report=offlinePNG.evidenceURL {
                            ShareLink(item:report) {
                                Text("一括証拠JSONを共有（明示操作のみ・PNG原本なし）")
                            }
                        }
                        if let paired=offlinePNG.pairedEvidenceURL {
                            ShareLink(item:paired) {
                                Text("R578｜元PNG・全OCR・メガ文字証拠をZIP一括共有")
                            }
                            Text("注意：このZIPにはゲーム画面の元画像が含まれます。個人情報・通知等が映っていないか、共有前に確認してください。自動送信はしません")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Button("同じVisionエンジンで画面・HP・技・PP等を解析") {offlinePNG.inspectText()}
                            .disabled(offlinePNG.image == nil || offlinePNG.busy)
                        Button("既存メガ4方向OCRで文字・演出候補を調査") {offlinePNG.inspectMegaEvidence()}
                            .disabled(offlinePNG.image == nil || offlinePNG.busy)
                        if offlinePNG.busy { Text("解析中").font(.caption) }
                        ForEach(Array(offlinePNG.lines.enumerated()),id: \.offset) { _,line in
                            Text(line).font(.caption)
                        }
                        ForEach(Array(offlinePNG.megaLines.enumerated()),id: \.offset) { _,line in
                            Text(line).font(.caption)
                        }
                        Button("取り込み画像と候補を消去",role:.destructive) {offlinePNG.clear()}
                            .disabled(offlinePNG.image == nil && offlinePNG.lines.isEmpty)
                        Text("ローカルで読取。画面共有履歴とは隔離。現在状態・自他・個体・メガ姿は未認証。自動送信・技推薦なし")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("R652｜メガ姿の参照画像を端末に登録") {
                        Button("自分の参照JSONを選択（手動）") {
                            showMegaCatalogPicker = true
                        }
                        Text(megaCatalogStatus).font(.caption)
                        Text("本人が検証したChampions画像から作成したR595 JSONのみ。画像自体の自動取得や外部送信なし。姿・自他・メガ使用は未認証。最大512件／1ファイル。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("R656｜メガ前後Vision研究（手動・未認証）") {
                        R656MegaVisionPanel()
                    }
                    Section("画面の確認（過去フレーム・未認証）") {
                        Text(capture.rawTimelineStatus).font(.caption)
                        if let preview = capture.diagnosticPreview {
                            Image(uiImage: preview).resizable().scaledToFit()
                                .accessibilityLabel("取得済みの診断用過去フレーム")
                        }
                        Text("表示は選択中の過去フレームです。現在の対戦状況や正しい認識を保証しません。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("メガ状態の目視メモ｜未認証・演出不要") {
                        Text("メガシンカの演出が映らない場合も記録できます。表示名とメガ状態は別管理。入力した内容は自動判定結果にはしません。")
                            .font(.caption).foregroundColor(.secondary)
                        Picker("対象", selection:$megaManualSide) {
                            Text("自分").tag("OWN")
                            Text("相手").tag("OPPONENT")
                        }
                        .pickerStyle(.segmented)
                        TextField("表示名（例：ギャラドス）", text:$megaManualSpecies)
                            .textInputAutocapitalization(.never)
                        Picker("現在の形態",selection:$megaManualForm) {
                            Text("不明").tag("UNKNOWN")
                            Text("通常").tag("BASE")
                            Text("メガ").tag("MEGA")
                        }
                        .pickerStyle(.segmented)
                        if megaManualForm == "MEGA" {
                            TextField("メガ形態名（任意：メガギャラドス等）",text:$megaManualVariant)
                        }
                        Picker("判断根拠",selection:$megaManualBasis) {
                            Text("未確認").tag("UNVERIFIED")
                            Text("ゲーム詳細画面で目視").tag("BATTLE_DETAIL_MANUAL")
                            Text("場の姿を目視").tag("ON_FIELD_VISUAL_MANUAL")
                        }
                        Button("選択中の過去フレームへ手動メモを記録") {
                            capture.recordSelectedFrameMega(
                                side:megaManualSide,species:megaManualSpecies,form:megaManualForm,
                                megaLabel:megaManualForm == "MEGA" ? megaManualVariant : "",
                                method:megaManualBasis)
                        }
                        .disabled(capture.rawTimelineCount == 0 || capture.battleEvidenceBusy)
                        Text(capture.megaManualStatus).font(.caption)
                        Text("異なる画像・個体には自動転記しません。メガ判定・技推薦の正式認証には使いません。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("選択画像の状況読取") {
                        Button("この画像の文字と状態候補を読む") { capture.inspectSelectedBattleState() }
                            .disabled(capture.rawTimelineCount == 0 || capture.battleEvidenceBusy || capture.battleReadBusy)
                        if capture.battleReadBusy { Text("画像を読み取っています").font(.caption) }
                        ForEach(Array(capture.screenReadStateLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption)
                        }
                        if capture.screenReadStateLines.isEmpty {
                            Text("画像を選んで読取を実行してください。現在の対戦状態・自分と相手の帰属は未認証です。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Section("証拠と診断を1回で保存") {
                        Button {
                            capture.prepareUnifiedEvidenceFile()
                        } label: {
                            Label("1回で全証拠をZIP出力", systemImage:"square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(capture.rawTimelineCount == 0 || capture.battleEvidenceBusy)
                        Text(capture.battleEvidenceStatus).font(.caption)
                        Text("R581：現在の全画面読取対象を1クリックで収集。全項目の可観測性目録を同梱し、未観測項目はUNKNOWN。最大8枚の背景画像と読取候補、メガ文字・手動メモを1個のZIPに集約。自他・メガ姿・ターンの真正性は未認証。自動送信・技推薦なし。実機試験は全項目の読取経路整備後。")
                            .font(.caption).foregroundColor(.secondary)
                        DisclosureGroup("画像なし：軽量診断のみ") {
                            R528OneTapDiagnosticsPanel()
                        }
                    }
                    DisclosureGroup("開発者向け詳細・ROI較正（通常は閉じる）") {
                    Text(capture.diagnosticUptimeDisclosure).font(.caption)
                    Section("画面取得の継続監査（映像・技名は保存しません）") {
                        Text(capture.continuityStatus).font(.footnote)
                        Text(capture.captureResolutionStatus).font(.footnote)
                        Button("受信状況を更新") { capture.refreshContinuityStatus() }
                        Button("数値ログJSONをコピー") { capture.copyLocalContinuityJSON() }
                        Text("アプリを離れて戻ったあと、非表示中に届いたフレーム数を検査します。iPhone実機の背景動作は未認証。")
                            .font(.footnote)
                    }
                    Section("R27.489｜実機キャプチャとOCR画像の寸法監査") {
                        Text(capture.researchSpatialDiagnostic).font(.footnote)
                        Text("表示画面やチャットのスクリーンショットを実機キャプチャと同一座標として扱いません。サイズ一致だけではROIを認証せず、実戦助言は無効です。")
                            .font(.footnote).foregroundColor(.red)
                    }
                    Section("R27.478｜全監査ログを1回でコピー") {
                        Text(capture.unifiedAuditStatus).font(.footnote)
                        Button("全監査ログをコピー") { capture.copyUnifiedAuditJSON() }
                        Text("PTS・受信・遅延・コールバック履歴を同時取得。以前のEpochは別枠保存。ゲーム状態や行動推薦には使いません。")
                            .font(.footnote).foregroundColor(.red)
                    }
                    Section("R27.476｜連続フレームPTS相対監査") {
                        Text(capture.sampleClockStatus).font(.footnote)
                        Button("PTS監査状況を更新") { capture.refreshSampleClockStatus() }
                        Button("PTS監査JSONをコピー") { capture.copySampleClockAuditJSON() }
                        Text("サンプルPTSと受信時刻は別の時計基準です。相対的な逆行・重複のみ監査し、実際の撮影時刻・ターン・行動推薦を認証しません。")
                            .font(.footnote).foregroundColor(.red)
                    }
                    Section("OCR処理遅延・数値監査") {
                        Text(capture.latencyStatus).font(.footnote)
                        Button("OCR処理時間を更新") { capture.refreshOCRLatencyStatus() }
                        Button("遅延数値ログJSONをコピー") { capture.copyLocalOCRLatencyJSON() }
                        Text("1500msを超えるOCR結果は推薦候補として使用しません。技名・映像はログに含めません。")
                            .font(.footnote)
                    }
                    Section("音声出力テスト（実戦助言ではありません）") {
                        Toggle("研究用の固定音声を許可", isOn: Binding(
                            get: { capture.researchVoiceEnabled },
                            set: { capture.setResearchVoiceEnabled($0) }
                        ))
                        Button("固定音声を1回テスト") { capture.testResearchVoice() }
                            .disabled(!capture.researchVoiceEnabled)
                        Text(capture.researchVoiceStatus).font(.footnote)
                        Text("音声は手動テストのみ。技・交代・選出の指示は出しません。")
                            .font(.footnote)
                    }
                    Section("R27.424｜取得解像度記録＋直接4技切り出しOCR（端末内のみ）") {
                        Text(capture.diagnosticStatus).font(.footnote)
                        Text(capture.diagnosticFilterStatus).font(.footnote)
                        Text(capture.rawTimelineStatus).font(.footnote)
                        Text(capture.orientationStatus).font(.footnote)
                        if capture.rawTimelineCount > 0 {
                            HStack {
                                Button("左に90°") { capture.rotateDiagnosticLeft() }
                                Spacer()
                                Text(capture.displayTurnLabel).font(.caption)
                                Spacer()
                                Button("右に90°") { capture.rotateDiagnosticRight() }
                            }
                            HStack {
                                Button("切出し切替") { capture.toggleDiagnosticCrop() }
                                Spacer()
                                Button("自動候補へ戻す") { capture.resetDiagnosticOrientation() }
                            }
                            Text("自動回転は画像形状からの仮説です。左右回転と切出しを手動で変更できます。Pokémon Championsの識別やOCR認証ではありません。")
                                .font(.footnote).foregroundColor(.red)
                        }
                        if capture.rawTimelineCount > 0 {
                            HStack {
                                Button("前の背景画像") { capture.selectRawTimeline(delta: -1) }
                                    .disabled(capture.rawTimelineIndex == 0)
                                Spacer()
                                Text("\(capture.rawTimelineIndex + 1)/\(capture.rawTimelineCount)")
                                    .font(.caption).monospacedDigit()
                                Spacer()
                                Button("次の背景画像") { capture.selectRawTimeline(delta: 1) }
                                    .disabled(capture.rawTimelineIndex + 1 >= capture.rawTimelineCount)
                            }
                            Text("背景履歴は取得出力サイズの画像です。元のゲーム画素と一致するかは未認証。表示だけの診断でありAIへの自動入力ではありません。")
                                .font(.footnote).foregroundColor(.red)
                        }
                        if let preview = capture.diagnosticPreview {
                            if capture.diagnosticIsUnfiltered {
                                Text("未選別の生フレーム：ゲーム認証・OCR・行動推薦には使用しません")
                                    .font(.footnote)
                                    .foregroundColor(.red)
                            }
                            ZStack {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                if capture.diagnosticIsUnfiltered && capture.calibrationVisible {
                                    GeometryReader { g in
                                        ForEach(0..<capture.calibrationOverlayROIs.count, id: \.self) { idx in
                                            let rect = capture.calibrationOverlayROIs[idx]
                                            Rectangle()
                                                .stroke(Color.orange,lineWidth:2)
                                                .frame(width:rect.width*g.size.width,
                                                       height:rect.height*g.size.height)
                                                .position(x:rect.midX*g.size.width,
                                                          y:rect.midY*g.size.height)
                                        }
                                    }
                                }

                                // Yellow outlines mark the original research ROI, not
                                // detected character bounding boxes or verified moves.
                                if !capture.diagnosticIsUnfiltered {
                                GeometryReader { geometry in
                                    ForEach(0..<4, id: \.self) { slot in
                                        let rois: [CGRect] = [
                                            CGRect(x: 0.744, y: 0.468, width: 0.145, height: 0.106),
                                            CGRect(x: 0.744, y: 0.350, width: 0.145, height: 0.104),
                                            CGRect(x: 0.744, y: 0.235, width: 0.145, height: 0.105),
                                            CGRect(x: 0.744, y: 0.119, width: 0.145, height: 0.109)
                                        ]
                                        let r = rois[slot]
                                        Rectangle()
                                            .stroke(Color.yellow, lineWidth: 2)
                                            .frame(width: r.width * geometry.size.width,
                                                   height: r.height * geometry.size.height)
                                            .position(x: (r.midX) * geometry.size.width,
                                                      y: (1 - r.midY) * geometry.size.height)
                                    }
                                }
                                }
                            }
                            .aspectRatio(capture.diagnosticIsUnfiltered ?
                                capture.diagnosticDisplayAspect :
                                capture.diagnosticDisplayAspect, contentMode: .fit)
                            if !capture.diagnosticIsUnfiltered {
                            ForEach(0..<4, id: \.self) { slot in
                                HStack {
                                    Text("推定技領域\(slot + 1)")
                                    Spacer()
                                    Text(capture.diagnosticCandidates[slot])
                                }
                            }
                            }
                        }
                        if capture.rawTimelineCount > 0 {
                            Toggle("4技の手動仮枠を表示（判定には不使用）", isOn: Binding(
                                get: { capture.calibrationVisible },
                                set: { capture.setCalibrationVisible($0) }))
                            if capture.calibrationVisible {
                                Text(capture.calibrationStatus).font(.footnote)
                                // Each range is bounded; invalid combinations fail closed.
                                VStack(alignment:.leading) {
                                    Text("左右位置 X")
                                    Slider(value:$capture.calibrationLayout.x,in:0...0.78,step:0.01)
                                    Text("上下位置 Y")
                                    Slider(value:$capture.calibrationLayout.top,in:0...0.75,step:0.01)
                                    Text("仮枠の幅")
                                    Slider(value:$capture.calibrationLayout.width,in:0.05...0.22,step:0.01)
                                    Text("仮枠の高さ")
                                    Slider(value:$capture.calibrationLayout.height,in:0.05...0.20,step:0.01)
                                    Text("枠間隔")
                                    Slider(value:$capture.calibrationLayout.gap,in:0...0.08,step:0.005)
                                }
                                .onChange(of:capture.calibrationLayout) { _,_ in
                                    capture.refreshCalibrationOverlay()
                                }
                                Text("初期枠は今回の実画面の技名欄を参考に配置。PP数字やタイプアイコンを含めないよう、オレンジ枠を技名だけに合わせてください。")
                                    .font(.footnote).foregroundColor(.secondary)
                                Button("仮枠を初期位置に戻す") {capture.resetCalibration()}
                                Button("かんたん診断：今表示している4技を読み取る") {
                                    capture.runGuidedResearchOCR()
                                }
                                .buttonStyle(.borderedProminent)
                                Text("操作：①ゲームで4技を表示→②共有中にアプリへ戻る→③下の背景履歴から技4枠のフレームを選ぶ→④画像の向きを『技名が横書きで読める向き』にする→⑤このボタンを押す。4枠がずれた場合だけ仮枠スライダーを調整し、従来の手動OCR診断を再実行。結果は研究用です。")
                                    .font(.footnote)
                                Button("選択フレームの4枠で手動OCR診断") {
                                    capture.runManualROIProbe()
                                }
                                Text(capture.manualOCRStatus).font(.footnote).foregroundColor(.red)
                                Text(capture.manualOCRPixelSummary).font(.caption)
                                Text(TP492BattleEffectOCRBridge.display(capture.battleWireJSON)).font(.caption).foregroundColor(.orange)
                                Text(TP493ObservationTimeline.display(capture.battleWireJSON)).font(.caption).foregroundColor(.orange)
                                Text("R27.521｜同一画像ROI重複監査／実戦助言なし")
                                Text("ROI位置のみ・OCR原文と画像は含まない／長押しでコピー")
                                    .font(.caption2).foregroundColor(.orange)
                                Text(capture.roiAuditPacket)
                                    .font(.system(.caption2,design:.monospaced))
                                    .textSelection(.enabled)
                                TP515ROIPositionMapView(packetJSON: capture.roiAuditPacket)
                                TP516ROIReadinessPanel(packetJSON: capture.roiAuditPacket)
                                TP519VisionEvidencePanel()
                                TP520VisionSessionPanel()
                                TP521VisionCollisionPanel()
                                    .font(.caption).foregroundColor(.orange)
                                Text(capture.autoResearchStatus).font(.caption).monospaced()
                                Text(capture.candidateFreshnessStatus).font(.caption).foregroundColor(.orange)
                                Text("天候・壁・メガ：安全な証拠台帳のみ準備／実画面連携は未認証").font(.caption).foregroundColor(.orange)

                                Text("R27.491｜共通観測カテゴリ：\(TPResearchEffectDomain.allCases.count)種／メガ判定・Battle State未認証／助言HOLD").font(.caption).foregroundColor(.red)
                                Text("R27.490｜PP専用領域（各4技枠の右34%）を別OCRで診断。画面上の11/12等と照合してください。結果はBattle Stateに反映しません。")
                                    .font(.caption)
                                ForEach(capture.researchPPDiagnostics, id: \.self) { value in
                                    Text(value).font(.caption).monospaced()
                                }

                                if capture.manualOCRThumbnails.count == 4 {
                                    Text("OCRが実際に使用した4枠の切り出し画像（表示は生画素、OCRは各3倍拡大）。PP混入・字の小ささを目視確認")
                                        .font(.footnote).foregroundColor(.red)
                                    ForEach(0..<4,id: \.self) { i in
                                        VStack(alignment:.leading) {
                                            Text("切り出し枠\(i+1)").font(.caption)
                                            Image(uiImage:capture.manualOCRThumbnails[i])
                                                .resizable().interpolation(.none)
                                                .scaledToFit()
                                                .frame(maxWidth:.infinity,alignment:.leading)
                                                .frame(height:66)
                                        }
                                    }
                                }
                                ForEach(0..<capture.manualOCRLines.count, id: \.self) { index in
                                    Text(capture.manualOCRLines[index]).font(.caption)
                                }
                                Text("正解4技を手入力して照合（端末内のみ）")
                                    .font(.footnote).foregroundColor(.secondary)
                                ForEach(0..<4, id: \.self) { index in
                                    TextField("正解技\(index+1)（画面を目視確認）",
                                              text: $capture.manualGroundTruth[index])
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                                .onChange(of: capture.manualGroundTruth) { _,_ in
                                    capture.clearAccuracyReview()
                                }
                                Button("手入力の正解4技と手動OCRを比較") {
                                    capture.runManualAccuracyReview()
                                }
                                Text(capture.accuracyReviewStatus).font(.footnote).foregroundColor(.red)
                                ForEach(capture.accuracyReviewLines, id: \.self) { v in
                                    Text(v).font(.caption)
                                }
                                ForEach(capture.calibrationMappedROIs, id:\.self) { v in
                                    Text(v).font(.caption).monospaced()
                                }
                                Text("元フレーム用ROIは監査表示です。手動Vision OCRは画面プレビューと同じ回転・切り出し状態で4枠を読み取ります。ゲーム認証・推薦・自動音声とは接続しません。")
                                    .font(.footnote).foregroundColor(.red)
                            }
                        }
                        Button("プレビューとOCR文字を消去", role: .destructive) {
                            capture.clearDiagnosticPreview()
                        }
                        Text("R27.423は回転済み画像の実画素から4枠を直接切り出し、OCRに渡した画像を画面で確認できます。未認証画像は技推薦へ一切接続しません。表示は1フレームの手入力一致率のみであり、実ゲームOCR精度の統計認証ではありません。検出した中央縦帯はタスク切替画面でもあり得ます。画像は端末メモリ内のみで停止・再取得・手動消去時に破棄。未選別画像の自動OCR・技推薦への流用は禁止。手動OCR診断はボタン押下時だけです。")
                            .font(.footnote)
                    }
                    Section("R27.430｜自分の技タイプ監査・色認識不要") {
                        Text("現画面の4技を手動OCRし、正解4/4と確認した後だけ診断します。現在有効な自分の特性を実際に確認した場合のみ選択。種族名からは推測しません。")
                            .font(.footnote)
                        Picker("自分の特性（有効を確認済み）",selection:$capture.confirmedOwnAbilityChoice) {
                            Text("未確認").tag("未確認")
                            Text("フェアリースキン有効").tag("フェアリースキン有効（実機確認）")
                            Text("スカイスキン有効").tag("スカイスキン有効（実機確認）")
                            Text("タイプ変換なし").tag("タイプ変換なし（実機確認）")
                        }
                        .onChange(of:capture.confirmedOwnAbilityChoice) { _,_ in
                            capture.refreshOwnMoveTypeAudit()
                        }
                        Text(capture.ownMoveTypeAuditStatus).font(.footnote).foregroundColor(.red)
                        ForEach(capture.ownMoveTypeAuditLines,id: \.self) { text in
                            Text(text).font(.caption)
                        }
                        Text("限定検証用技DBのみ。タイプ変動技・特性無効化・特性変更・不明技は保留。まだBattle AIの合法行動やダメージ計算へ接続しません。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Section("統一Battle State｜端末内候補・未認証") {
                        Button("表示中の画面を解析") { capture.inspectSelectedBattleState() }
                            .disabled(capture.diagnosticPreview == nil)
                        Text(capture.battleWireStatus).font(.footnote)
                        ForEach(capture.battleWireLines,id: \.self) { text in
                            Text(text).font(.caption)
                        }
                        Button("候補JSONをコピー") { capture.copyBattleStateCandidateJSON() }
                            .disabled(capture.battleWireJSON.isEmpty)
                        Button("実画像と候補を1ファイルに整理") { capture.prepareSelectedEvidenceFile() }
                            .disabled(capture.rawTimelineCount == 0 || capture.battleEvidenceBusy)
                        Text(capture.battleEvidenceStatus).font(.footnote)
                        if let exportFile = capture.battleEvidenceURL {
                            ShareLink(item: exportFile) {
                                Text("検証証跡JSONを共有（手動のみ）")
                            }
                        }
                        Text("共有ファイルは未回転の背景取得PNGと、候補があれば解析に使ったPNGを含みます。ゲーム外の画面や個人情報が映っていないか確認してください。ChatGPT等への自動送信はしません。")
                            .font(.footnote).foregroundColor(.secondary)
                        Text("数値・文字は未確定候補です。ターン、状態異常、能力ランク、ログの実画像認証は未完了。履歴の古さを維持し、推薦と音声へは接続しません。")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Section("2フレーム一致の研究結果") {
                        ForEach(0..<4, id: \.self) { slot in
                            HStack {
                                Text("技\(slot + 1)")
                                Spacer()
                                Text(capture.lastMoveCandidates[slot])
                            }
                        }
                    }
                    Section("安全性・認証状態") {
                        Text("Vision文字認識と手動音声テストのみ。相手の種族・盤面・合法行動・最善手・自動音声推薦は未実装です。記録した文字列は実戦での正答を保証しません。")
                        Text("LAN/クラウド/ChatGPTへの自動送信なし。追加課金APIなし。")
                    }.font(.footnote)
                    } // End developer diagnostics disclosure.
                }
                .navigationTitle("Champions On-Device")
            }
            .fileImporter(isPresented:$showOfflinePNGPicker,allowedContentTypes:[.png],allowsMultipleSelection:false) { result in
                switch result {
                case .success(let urls):
                    guard let url=urls.first else {offlinePNG.clear();return}
                    offlinePNG.importFile(.success(url))
                case .failure(let error):offlinePNG.importFile(.failure(error))
                }
            }
            .fileImporter(isPresented:$showMegaCatalogPicker,
                allowedContentTypes:[.json], allowsMultipleSelection:false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        megaCatalogStatus = "ファイル未選択"
                        return
                    }
                    do {
                        let count = try R652MegaCatalogInstaller.importLocalFile(url)
                        megaCatalogStatus = "参照候補\(count)件取込済み。実機認識は未認証"
                    } catch {
                        megaCatalogStatus = "取込拒否。現在の有効参照は\(R652MegaCatalogInstaller.localCount())件。異常時は再確認"
                    }
                case .failure:
                    megaCatalogStatus = "選択取消。以前の台帳を保持"
                }
            }
            .onChange(of: capture.unifiedEvidenceURL) { _, next in
                if let next { unifiedShareItem = R535EvidenceShareItem(url:next) }
            }
            .sheet(item: $unifiedShareItem) { item in
                VStack {
                    Text(capture.evidenceUptimeDisclosure).font(.callout).padding()
                    R535EvidenceShareView(url:item.url) { completed,failed in
                        capture.reportUnifiedShareOutcome(completed:completed,failed:failed)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                capture.didEnterBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                capture.willEnterForeground()
            }
        }
    }
}
