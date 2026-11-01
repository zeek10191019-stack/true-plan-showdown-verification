import Foundation
import SwiftUI
import UIKit

/// Actual R519/520/521 research snapshots in ONE action. Each has a distinct provenance scope.
/// No automatic remote upload and no Battle State writes.
@available(iOS 27.0, *)
struct R528OneTapDiagnosticsPanel: View {
    @State private var feedback = ""
    @State private var exportURL: URL?
    @State private var presentShare = false

    /// Snapshots are captured once per button press, never on a timer.
    private func makePacket() throws -> Data {
        let metrics = TP519VisionEvidenceMetrics.snapshot()
        let session = TP520VisionSessionFence.snapshot()
        let collision = TP521VisionCollisionFence.snapshot()
        let original=try R528DiagnosticCore.assemble(
            r519:metrics.redactedJSON,r520:session.redactedJSON,r521:collision.redactedJSON,
            epoch:session.epoch,frame:session.latestFrameID.flatMap(Int.init(exactly:)))
        return try TP532FirstPassDiagnostics.attach(to:original)
    }

    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:12) {
                Button {
                    do {
                        let data=try makePacket()
                        guard let text=String(data:data,encoding:.utf8) else {throw NSError(domain:"R528Export",code:2)}
                        UIPasteboard.general.string=text
                        feedback="4件の診断データを一括コピー済み（研究用）"
                    } catch { feedback="コピー失敗：\(error.localizedDescription)" }
                } label: {
                    Label("全部コピー",systemImage:"doc.on.doc").frame(maxWidth:.infinity)
                }.buttonStyle(.borderedProminent)
                Button {
                    do {
                        let data=try makePacket()
                        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("R528Export",isDirectory:true)
                        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
                        let file=dir.appendingPathComponent("champions_R528_\(UUID().uuidString.prefix(8)).json")
                        try data.write(to:file,options:.atomic)
                        exportURL=file
                        presentShare=true
                        feedback=""
                    } catch { feedback="ファイル作成失敗：\(error.localizedDescription)" }
                } label: {
                    Label("ファイル保存",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity)
                }.buttonStyle(.bordered)
            }
            if !feedback.isEmpty {Text(feedback).font(.caption).foregroundColor(.secondary)}
            Text("R519/520/521とR532初回OCR座標診断を収録。異なる時間範囲を混同しないため、同一フレーム認証は常にfalseです。OCR原文・画面画像・個人情報は含めません。")
                .font(.caption).foregroundColor(.secondary)
        }
        .sheet(isPresented:$presentShare) {
            if let exportURL {R528ShareSheet(url:exportURL)}
        }
    }
}

@available(iOS 27.0, *)
private struct R528ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context:Context) -> UIActivityViewController {
        UIActivityViewController(activityItems:[url],applicationActivities:nil)
    }
    func updateUIViewController(_ controller:UIActivityViewController,context:Context) {}
}
