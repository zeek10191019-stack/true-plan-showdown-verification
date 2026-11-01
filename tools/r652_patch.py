#!/usr/bin/env python3
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/ChampionsOnDeviceApp.swift')
s=p.read_text()
def replace(a,b):
    global s
    assert s.count(a)==1, ('R652_MISSING_OR_DUPLICATE_ANCHOR',a[:90])
    s=s.replace(a,b)
replace('    @State private var showOfflinePNGPicker = false',
'''    @State private var showOfflinePNGPicker = false
    @State private var showMegaCatalogPicker = false
    @State private var megaCatalogStatus = "メガ参照JSON未取込"
'''.rstrip())
replace('                    Section("画面の確認（過去フレーム・未認証）") {',
'''                    Section("R652｜メガ姿の参照画像を端末に登録") {
                        Button("自分の参照JSONを選択（手動）") {
                            showMegaCatalogPicker = true
                        }
                        Text(megaCatalogStatus).font(.caption)
                        Text("本人が検証したChampions画像から作成したR595 JSONのみ。画像自体の自動取得や外部送信なし。姿・自他・メガ使用は未認証。最大512件／1ファイル。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Section("画面の確認（過去フレーム・未認証）") {''')
replace('            .onChange(of: capture.unifiedEvidenceURL) { _, next in',
'''            .fileImporter(isPresented:$showMegaCatalogPicker,
                allowedContentTypes:[.json], allowsMultipleSelection:false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        megaCatalogStatus = "ファイル未選択"
                        return
                    }
                    do {
                        let count = try R652MegaCatalogInstaller.importLocalFile(url)
                        megaCatalogStatus = "参照候補\\(count)件取込済み。実機認識は未認証"
                    } catch {
                        megaCatalogStatus = "取込拒否。以前の台帳を保持"
                    }
                case .failure:
                    megaCatalogStatus = "選択取消。以前の台帳を保持"
                }
            }
            .onChange(of: capture.unifiedEvidenceURL) { _, next in''')
p.write_text(s)
print('R652_UI_IMPORT_PATCH_APPLIED')
