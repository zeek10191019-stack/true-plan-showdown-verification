import Foundation
import CryptoKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Research-only operator supplied 4 PNGs. No live game-state writes.
@available(iOS 27.0, *)
final class R658MegaTemporalModel: ObservableObject {
    @Published private(set) var labels = [String](repeating:"PNG未選択",count:4)
    @Published private(set) var status = "未実行"
    @Published private(set) var reportURL:URL?
    @Published private(set) var busy = false
    private var inputs:[Data?] = [nil,nil,nil,nil]
    private var epoch=UUID()
    private func invalidate() {
        epoch=UUID()
        busy=false
        if let url=reportURL {try? FileManager.default.removeItem(at:url)}
        reportURL=nil
        status="画像または設定が変更されました。旧結果は失効"
    }
    func settingsChanged() {
        precondition(Thread.isMainThread)
        invalidate()
    }
    func importPNG(_ result:Result<[URL],Error>, slot:Int) {
        precondition(Thread.isMainThread)
        guard (0..<4).contains(slot) else {return}
        invalidate()
        inputs[slot]=nil
        do {
            guard case .success(let urls)=result,let url=urls.first else {
                throw R656MegaVisionPair.Failure("FILE_NOT_SELECTED")
            }
            let allowed=url.startAccessingSecurityScopedResource()
            defer {if allowed {url.stopAccessingSecurityScopedResource()}}
            let info=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard info.isRegularFile == true, let bytes=info.fileSize,
                  (45...R576OfflinePNGImportGate.limitBytes).contains(bytes) else {
                throw R656MegaVisionPair.Failure("FILE_SIZE_REJECTED")
            }
            let data=try Data(contentsOf:url)
            guard case .accepted=R576OfflinePNGImportGate.validate(data) else {
                throw R656MegaVisionPair.Failure("PNG_INVALID")
            }
            inputs[slot]=data
            labels[slot]="PNG登録済（\(data.count) bytes）"
        } catch {
            labels[slot]="読込拒否：\(error.localizedDescription)"
        }
    }
    func clear() {
        precondition(Thread.isMainThread)
        invalidate()
        inputs=[nil,nil,nil,nil]
        labels=[String](repeating:"PNG未選択",count:4)
        status="4画像と比較証拠を削除しました"
    }
    func run(formID:String, reviewed:Bool) {
        precondition(Thread.isMainThread)
        guard !busy, reviewed,
              R649MegaRegistryAudit.entries.contains(where:{$0.id==formID}),
              inputs.count==4,inputs.allSatisfy({$0 != nil}) else {
            invalidate()
            status="HOLD：4画像・目視ラベル・形態IDが不足"
            return
        }
        let images=inputs.compactMap{$0}
        let keys=images.map {bytes in
            SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
        }
        guard Set(keys).count==4 else {
            invalidate()
            status="HOLD：同一PNGの重複で独立4フレーム不足"
            return
        }
        invalidate()
        let token=UUID();epoch=token
        busy=true
        status="4画像の前後差と同一形態内差を解析中"
        DispatchQueue.global(qos:.userInitiated).async {[weak self] in
            var result="比較失敗。診断証拠は生成されません"
            var encoded:Data?
            do {
                let p:[(Int,Int)] = [(0,1),(2,3),(0,2),(1,3)]
                var reports=[[String:Any]]()
                for (a,b) in p {
                    let entry=try R656MegaVisionPair.compare(
                        before:images[a],after:images[b],
                        proposedMegaID:formID,manuallyReviewed:true)
                    reports.append(entry)
                }
                let audit=R658MegaTemporalGate.audit(reports)
                encoded=try JSONSerialization.data(
                    withJSONObject:audit,options:[.sortedKeys])
                result=(audit["status"] as? String) ?? "HOLD_UNKNOWN"
            } catch {
                result="HOLD：Vision画像比較エラー（\(error)）"
            }
            DispatchQueue.main.async {[weak self] in
                guard let self,self.epoch==token else {return}
                self.busy=false
                if let encoded {
                    let target=FileManager.default.temporaryDirectory
                        .appendingPathComponent("r658-\(token.uuidString).json")
                    do {
                        try encoded.write(to:target,options:.atomic)
                        self.reportURL=target
                    } catch {
                        result="HOLD：JSON保存失敗"
                    }
                }
                self.status=result
            }
        }
    }
}

@available(iOS 27.0, *)
struct R658MegaTemporalPanel:View {
    @StateObject private var model=R658MegaTemporalModel()
    @State private var pickers=[false,false,false,false]
    @State private var formID="gyarados-mega"
    @State private var reviewed=false
    private let labels=["進化前1","進化前2","進化後1","進化後2"]
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("R658｜メガ前後4フレームVision比較（研究用）")
                .font(.headline)
            ForEach(0..<4,id:\.self) {i in
                Button("\(labels[i]) PNGを選択") {pickers[i]=true}
                .fileImporter(isPresented:Binding(
                    get:{pickers[i]},set:{pickers[i]=$0}),
                    allowedContentTypes:[.png],
                    allowsMultipleSelection:false) {selection in
                        model.importPNG(selection,slot:i)
                }
                Text(model.labels[i]).font(.caption)
            }
            Picker("照合対象（手動指定）",selection:$formID) {
                ForEach(R649MegaRegistryAudit.entries,id:\.id) {form in
                    Text(form.label).tag(form.id)
                }
            }.onChange(of:formID) {_,_ in model.settingsChanged()}
            Toggle("4枚の前後ラベルを目視確認",isOn:$reviewed)
                .onChange(of:reviewed) {_,_ in model.settingsChanged()}
            Button("4枚のVision差分と背景変化を検証") {
                model.run(formID:formID,reviewed:reviewed)
            }.disabled(model.busy || !reviewed)
            if let url=model.reportURL {
                ShareLink(item:url) {Text("4フレーム診断JSONを共有（元画像なし）")}
            }
            Button("4画像と結果を消去",role:.destructive) {model.clear()}
            Text(model.status).font(.caption)
            Text("前後それぞれ2枚の揺れを計測。背景移動や両側同時変化は保留。変化だけではメガ・所有者・種族を認証しません。画像の自動送信なし。")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
