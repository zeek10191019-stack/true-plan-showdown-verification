import Foundation
import Combine
import UIKit
import CryptoKit

/// Independently imported historical PNG. Not part of any capture-session timeline.
@available(iOS 27.0, *)
final class R576OfflinePNGInspector: ObservableObject {
    @Published private(set) var status="PNG未選択。画面共有の取得とは独立しています"
    @Published private(set) var image:UIImage?
    @Published private(set) var lines=[String]()
    @Published private(set) var megaLines=[String]()
    @Published private(set) var busy=false
    @Published private(set) var sourceSHA=""
    @Published private(set) var evidenceURL:URL?
    @Published private(set) var pairedEvidenceURL:URL?
    private var currentPNG:Data?
    private var version=UUID().uuidString
    private func clearEvidenceFile() {
        if let url=evidenceURL {try? FileManager.default.removeItem(at:url)}
        if let url=pairedEvidenceURL {try? FileManager.default.removeItem(at:url)}
        evidenceURL=nil;pairedEvidenceURL=nil
    }
    private let worker=DispatchQueue(label:"trueplan.r576.offline-import",qos:.userInitiated)
    func importFile(_ result:Result<URL,Error>) {
        precondition(Thread.isMainThread)
        version=UUID().uuidString
        busy=false;currentPNG=nil;image=nil;lines=[];megaLines=[];sourceSHA="";clearEvidenceFile()
        switch result {
        case .failure:status="ファイル選択が取消または失敗。旧結果は使用しません"
        case .success(let url):
            let access=url.startAccessingSecurityScopedResource()
            defer {if access {url.stopAccessingSecurityScopedResource()}}
            do {
                let properties=try url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                guard properties.isRegularFile == true,
                      let fileSize=properties.fileSize,
                      (45...R576OfflinePNGImportGate.limitBytes).contains(fileSize) else {
                    status="PNG容量またはファイル形式が不正。読込を拒否しました";return
                }
                let data=try Data(contentsOf:url)
                guard case .accepted(let w,let h)=R576OfflinePNGImportGate.validate(data),
                      let image=UIImage(data:data),image.size.width>0,image.size.height>0 else {
                    status="PNG形式・サイズが不正。旧結果は破棄済み";return
                }
                let sha=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
                self.currentPNG=data;self.image=image;self.sourceSHA=sha
                status="オフラインPNG選択済：\(w)×\(h)・SHA \(sha.prefix(12))。実戦の現在値ではありません"
            } catch {status="PNG読込失敗。旧結果は破棄済み"}
        }
    }
    /// One deliberate action runs the unmodified shared full-frame reader and
    /// the retained 4-rotation Mega text probe on the *same* source PNG.
    /// The output is evidence for independent ground-truth scoring, not a live state.
    func inspectAll() {
        precondition(Thread.isMainThread)
        guard !busy,let png=currentPNG else {return}
        let key=version
        clearEvidenceFile()
        busy=true;lines=[];megaLines=[]
        status="OCR・メガ4方向を一括検証中。自他・姿・現在値は未認証"
        worker.async {[weak self] in
            do {
                let decoded=try R558FullFrameOCR.decodePNG(png)
                let stamp=max(1,Int64(ProcessInfo.processInfo.systemUptime*1000))
                let batch=try R558FullFrameOCR.inspect(decoded:decoded,session:"offline-"+key,
                    frame:1,epoch:1,observedMs:stamp)
                let tokens=batch.tokens.filter{$0.rect != nil}
                let kind=R557ScreenEvidence.decide(primary:tokens.map(\.text),
                    allVariants:tokens.flatMap{$0.alternatives.map(\.raw_text)}).kind
                var packet=ResearchBattlePacket(battle_id:"offline-"+key,epoch:1,frame_id:1,
                    turn:nil,observed_at_ms:stamp,received_at_ms:stamp,
                    image_sha256:decoded.sha256,source_ref:"user-imported-exact-png-not-live",
                    screen_kind:kind,readings:batch.readings)
                packet.ocr_engine_version=R558FullFrameOCR.engineVersion
                packet.ocr_request_audit=batch.audit
                let coder=JSONEncoder();coder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
                let payload=try coder.encode(packet)
                let hash=SHA256.hash(data:payload).map{String(format:"%02x",$0)}.joined()
                let envelope=try JSONSerialization.data(withJSONObject:["schema":"trueplan.mobile-envelope.v1",
                    "payload_json":String(decoding:payload,as:UTF8.self),"payload_sha256":hash],options:[.sortedKeys])
                let snapshot=R551ScreenReadState.make(envelope:String(decoding:envelope,as:UTF8.self),
                    captureSessionID:"offline-"+key,frame:1,epoch:1,observedMs:stamp,
                    imageSHA:decoded.sha256,width:decoded.image.width,height:decoded.image.height)
                let mega=R548MegaSceneProbe.inspect(png,budgetMs:1800)
                // Preserve the R577 envelope contract while adding an all-fields
                // one-button readability inventory for every imported source PNG.
                let diagnostic:Data? = {
                    guard let base=R577OfflineEvidenceReport.encode(sourceSHA:decoded.sha256,
                        width:decoded.image.width,height:decoded.image.height,
                        sourceBytes:png.count,packetJSON:String(decoding:payload,as:UTF8.self),
                        snapshot:snapshot,mega:mega),
                        var document=(try? JSONSerialization.jsonObject(with:base)) as? [String:Any] else {return nil}
                    document["r581_full_read_coverage"] = R581ReadabilityCoverage.make(
                        sourceSHA:decoded.sha256,sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY",
                        snapshot:snapshot,mega:mega)
                    // Offline PNG must never be represented as current live battle.
                    R634FieldEvidenceRouting.enrich(&document, sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY")
                    R635LayoutToFields.enrich(&document, sourceKind:"USER_IMPORTED_PNG_OFFLINE_ONLY")
                    guard let data=try? JSONSerialization.data(withJSONObject:document,
                        options:[.sortedKeys,.withoutEscapingSlashes]),
                        data.count <= R577OfflineEvidenceReport.maximumReportBytes else {return nil}
                    return data
                }()
                let saved:URL? = {
                    guard let data=diagnostic else {return nil}
                    let url=FileManager.default.temporaryDirectory
                        .appendingPathComponent("r577-offline-"+key+".json")
                    do {try data.write(to:url,options:.atomic);return url}
                    catch {return nil}
                }()
                let bundle:URL? = {
                    guard let data=diagnostic else {return nil}
                    let url=FileManager.default.temporaryDirectory
                        .appendingPathComponent("r578-bundle-"+key+".zip")
                    do {
                        _ = try R578OfflineBundleWriter.write(png:png,diagnostic:data,
                            sourceSHA:decoded.sha256,to:url)
                        return url
                    } catch {try? FileManager.default.removeItem(at:url);return nil}
                }()
                DispatchQueue.main.async {[weak self] in
                    guard let self,self.version==key else {
                        if let saved {try? FileManager.default.removeItem(at:saved)}
                        if let bundle {try? FileManager.default.removeItem(at:bundle)}
                        return
                    }
                    self.busy=false;self.evidenceURL=saved;self.pairedEvidenceURL=bundle
                    self.lines=["同一PNGから全Vision候補を取得（履歴のみ・現在値ではない）"] + R551ScreenReadState.displayLines(snapshot)
                    let hints=mega["text_hints"] as? [String] ?? []
                    self.megaLines=["メガOCR：\(mega["state"] as? String ?? "UNKNOWN")",
                        "文字候補：\(hints.isEmpty ? "なし" : hints.joined(separator:", "))",
                        "姿・対象個体の自動確定：未認証"]
                    self.status=saved == nil ?
                        "認識候補を表示。JSONの完全性検査に通らず証跡は作成しません" :
                        (bundle == nil ? "一括解析完了。PNG証跡ZIPの検証は不合格です" :
                         "一括解析完了。元PNG＋解析JSONのZIPは明示操作まで端末内のみ")
                }
            } catch {
                DispatchQueue.main.async {[weak self] in
                    guard let self,self.version==key else {return}
                    self.busy=false;self.lines=[];self.megaLines=[]
                    self.status="一括解析失敗。結果と証跡は採用しません"
                }
            }
        }
    }
    func inspectText() {
        precondition(Thread.isMainThread)
        guard !busy,let png=currentPNG else {return}
        let key=version
        busy=true;lines=[];megaLines=[]
        status="選択PNGのOCR中。自他・個体・メガは未確定"
        worker.async {[weak self] in
            do {
                let decoded=try R558FullFrameOCR.decodePNG(png)
                let stamp=max(1,Int64(ProcessInfo.processInfo.systemUptime*1000))
                let batch=try R558FullFrameOCR.inspect(decoded:decoded,session:"offline-"+key,frame:1,epoch:1,observedMs:stamp)
                let tokens=batch.tokens.filter{$0.rect != nil}
                let kind=R557ScreenEvidence.decide(primary:tokens.map(\.text),
                    allVariants:tokens.flatMap{$0.alternatives.map(\.raw_text)}).kind
                var packet=ResearchBattlePacket(battle_id:"offline-"+key,epoch:1,frame_id:1,
                    turn:nil,observed_at_ms:stamp,received_at_ms:stamp,
                    image_sha256:decoded.sha256,source_ref:"user-imported-exact-png-not-live",
                    screen_kind:kind,readings:batch.readings)
                packet.ocr_engine_version=R558FullFrameOCR.engineVersion
                packet.ocr_request_audit=batch.audit
                let coder=JSONEncoder();coder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
                let payload=try coder.encode(packet)
                let hash=SHA256.hash(data:payload).map{String(format:"%02x",$0)}.joined()
                let envelope=try JSONSerialization.data(withJSONObject:["schema":"trueplan.mobile-envelope.v1",
                    "payload_json":String(decoding:payload,as:UTF8.self),"payload_sha256":hash],options:[.sortedKeys])
                let state=R551ScreenReadState.make(envelope:String(decoding:envelope,as:UTF8.self),
                    captureSessionID:"offline-"+key,frame:1,epoch:1,observedMs:stamp,
                    imageSHA:decoded.sha256,width:decoded.image.width,height:decoded.image.height)
                let display=R551ScreenReadState.displayLines(state)
                let proof=R576OfflinePNGImportGate.proof(width:decoded.image.width,
                    height:decoded.image.height,sha:decoded.sha256,byteCount:png.count)
                guard proof["current_state_eligible"] as? Bool == false else {return}
                DispatchQueue.main.async {[weak self] in
                    guard let self,self.version==key else {return}
                    self.busy=false;self.lines=["R576：実PNG／同一Vision OCR／履歴のみ・自他未認証"]+display
                    self.status="OCR完了（候補のみ）。現在の対戦状態への転用は禁止"
                }
            } catch {
                DispatchQueue.main.async {[weak self] in
                    guard let self,self.version==key else {return}
                    self.busy=false;self.lines=[];self.status="OCR失敗：値を採用しません。別のPNGを確認してください"
                }
            }
        }
    }
    func inspectMegaEvidence() {
        precondition(Thread.isMainThread)
        guard !busy,let png=currentPNG else {return}
        let key=version
        busy=true;megaLines=[]
        worker.async {[weak self] in
            let result=R548MegaSceneProbe.inspect(png,budgetMs:1800)
            let hints=result["text_hints"] as? [String] ?? []
            let status=result["state"] as? String ?? "UNKNOWN"
            DispatchQueue.main.async {[weak self] in
                guard let self,self.version==key else{return}
                self.busy=false
                self.megaLines=["R548既存コードによる4方向OCR証拠：\(status)",
                    "メガ関連文字候補：\(hints.isEmpty ? "なし・不明" : hints.joined(separator:", "))",
                    "姿・発動・対象個体の自動認証：なし"]
            }
        }
    }
    func clear() {
        precondition(Thread.isMainThread)
        version=UUID().uuidString
        currentPNG=nil;image=nil;lines=[];megaLines=[];sourceSHA="";busy=false;clearEvidenceFile()
        status="取り込み画像と候補を破棄しました"
    }
}
