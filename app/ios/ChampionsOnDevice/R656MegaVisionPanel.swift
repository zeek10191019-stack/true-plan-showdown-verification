import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

@available(iOS 27.0, *)
final class R656MegaVisionModel: ObservableObject {
    @Published private(set) var beforeStatus = "メガ前PNG：未選択"
    @Published private(set) var afterStatus = "メガ後PNG：未選択"
    @Published private(set) var status = "未実行"
    @Published private(set) var reportURL: URL?
    @Published private(set) var busy = false
    private var beforePNG: Data?
    private var afterPNG: Data?
    private var epoch = UUID()
    private func removeReport() {
        if let url = reportURL { try? FileManager.default.removeItem(at:url) }
        reportURL = nil
    }
    func load(_ selection: Result<[URL], Error>, before: Bool) {
        precondition(Thread.isMainThread)
        epoch = UUID()
        removeReport()
        status = "参照変更。以前の比較結果は無効"
        busy = false // Invalidate in-flight callback as well as spinner.
        if before { beforePNG = nil } else { afterPNG = nil }
        let label: String
        do {
            guard case .success(let paths) = selection,
                  let url = paths.first else {
                throw R656MegaVisionPair.Failure("FILE_NOT_SELECTED")
            }
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            let attrs = try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard attrs.isRegularFile == true,
                  let n = attrs.fileSize,
                  (45...R576OfflinePNGImportGate.limitBytes).contains(n) else {
                throw R656MegaVisionPair.Failure("FILE_SIZE_REJECTED")
            }
            let data = try Data(contentsOf:url)
            guard case .accepted = R576OfflinePNGImportGate.validate(data) else {
                throw R656MegaVisionPair.Failure("PNG_IMPORT_REJECTED")
            }
            if before { beforePNG = data } else { afterPNG = data }
            label = "PNG登録済：\(data.count) bytes"
        } catch {
            label = "読込拒否。旧画像は無効：\(error.localizedDescription)"
        }
        if before { beforeStatus = label } else { afterStatus = label }
    }
    func invalidateControls() {
        precondition(Thread.isMainThread)
        epoch = UUID()
        busy = false
        removeReport()
        status = "形態・目視ラベル変更：旧比較結果を失効"
    }
    func run(formID: String, reviewed: Bool) {
        precondition(Thread.isMainThread)
        guard reviewed else {
            invalidateControls()
            status = "HOLD：2画像のラベル目視確認が未完了"
            return
        }
        guard !busy, let first = beforePNG, let second = afterPNG,
              R649MegaRegistryAudit.entries.contains(where:{$0.id == formID})
        else {status = "画像2枚または81形態IDが不正";return}
        let token = UUID()
        epoch = token
        removeReport()
        busy = true
        status = "2画像のVision特徴量を端末内で計算中"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var output: Data?
            var result = "比較失敗。証跡は未作成"
            do {
                let report = try R656MegaVisionPair.compare(
                    before:first, after:second, proposedMegaID:formID,
                    manuallyReviewed:reviewed)
                output = try JSONSerialization.data(
                    withJSONObject:report, options:[.sortedKeys])
                result = "比較終了。距離は候補のみ／メガ・自他は未認証"
            } catch {
                result = "比較保留：\(error)"
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.epoch == token else {return}
                self.busy = false
                if let output {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("r656-vision-\(token.uuidString).json")
                    do {
                        try output.write(to:url,options:.atomic)
                        self.reportURL = url
                    } catch { result = "証跡保存に失敗。比較は採用しません" }
                }
                self.status = result
            }
        }
    }
    func clear() {
        precondition(Thread.isMainThread)
        epoch = UUID()
        busy = false // A cancelled worker cannot keep the UI locked.
        beforePNG = nil
        afterPNG = nil
        removeReport()
        beforeStatus = "メガ前PNG：未選択"
        afterStatus = "メガ後PNG：未選択"
        status = "画像と結果を消去"
    }
}

@available(iOS 27.0, *)
struct R656MegaVisionPanel: View {
    @StateObject private var model = R656MegaVisionModel()
    @State private var beforePicker = false
    @State private var afterPicker = false
    @State private var targetID = "gyarados-mega"
    @State private var manualReview = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("R656｜メガ前後の2画像をVisionで比較（研究・端末内）")
                .font(.headline)
            Button("① メガ前のPNGを選択") {beforePicker = true}
                .fileImporter(isPresented:$beforePicker,
                    allowedContentTypes:[.png],allowsMultipleSelection:false) {
                    model.load($0,before:true)
                }
            Text(model.beforeStatus).font(.caption)
            Button("② メガ後のPNGを選択") {afterPicker = true}
                .fileImporter(isPresented:$afterPicker,
                    allowedContentTypes:[.png],allowsMultipleSelection:false) {
                    model.load($0,before:false)
                }
            Text(model.afterStatus).font(.caption)
            Picker("照合するメガ形態（手動指定）",selection:$targetID) {
                ForEach(R649MegaRegistryAudit.entries,id:\.id) { form in
                    Text(form.label).tag(form.id)
                }
            }
            Toggle("2画像の前後ラベルを自分で確認",isOn:$manualReview)
            .onChange(of:manualReview) { _,_ in
                model.invalidateControls()
            }
            .onChange(of:targetID) { _,_ in
                model.invalidateControls()
            }
            Button("③ Vision特徴量を比較してJSONを保存") {
                model.run(formID:targetID,reviewed:manualReview)
            }.disabled(model.busy || !manualReview)
            if let url = model.reportURL {
                ShareLink(item:url) {Text("比較証拠JSONを共有（画像なし）")}
            }
            Button("2画像と結果を削除",role:.destructive) {model.clear()}
            Text(model.status).font(.caption)
            Text("画像全体・左右の未較正領域・背景で特徴量距離を取得。" +
                 "差があってもメガ進化、自他、種族、ターンは確定しません。" +
                 "画像はアップロードせず、元画像もJSONに含めません。")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
