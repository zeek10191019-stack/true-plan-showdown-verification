# R659｜実取得フレームの1ボタンVision時系列検査

## 変更内容

従来のR658は4枚のPNGを手動で指定する必要があった。R659は、既存の「1回で全証拠をZIP出力」がすでに保持する最大8枚の実取得フレームから最新4枚だけを使用して、Apple Visionの画像特徴量を端末内で抽出する。

- フレームID・epoch・単調時刻・画像SHA-256を必ず紐付ける。
- 4枚が揃わない、世代・寸法・SHAが不一致、順序逆行、10秒を超えるフレーム間ギャップがあればHOLD。
- 左／右の仮説領域、背景の3領域×連続3区間＝9個の特徴量距離を記録。
- 画像データはこのJSONに重複格納しない。既存の「historical_visual_region_changes.json」にフィールド追加するのみで、ZIPエントリ数や既存の証拠インデックスを変更しない。
- メガ進化前・進化後、自分・相手を自動決め打ちしない。Vision距離からMega確定へ昇格しない。未認証のバトル行動推薦へ接続しない。
- 最大1,600msの処理予算を事前点検し、超えた場合はHOLD。Vision単発呼出しの実時間はプリエンプト不可能なので、予算を厳密に保証するものではない。
- 最新4枚のフレームが偶然メガ演出を含まない場合、メガ前後比較にはならない。

## 試験範囲

- Linux Swift: 証拠入力の22条件（構文、出典、同一epoch、重複SHA、時系列、サイズ、10秒ギャップ）
- macOS Apple CI: Vision APIで合成4フレームから9距離を実計算
- iPhoneOS build + 既存 `tools/run_macos_checks.py --source-guard-only`
- 実際のPokémon Champions実機フレームは未試験。認証率の分子には加算しない。

## 次の本命

実ゲーム映像からの視点／ROI校正と独立正解ラベルの収集。画像特徴量の距離値だけでは形態識別は成立せず、R649登録81形態の実姿学習・負例比較とメガイベント確証が必要。

公式API: https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest
