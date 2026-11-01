# R655 | 全81メガ形態 — 教師画像ラベル矛盾検知

## 目的
R654は形態クラスごとの最良スコアを比較するが、手動ラベルの教師画像を信用する前に、同一の画像SHA・同じROI領域に「通常」「メガ」「X/Y/Z」等の異なるラベルを付けてしまう事故を除外する必要がある。

## 改修内容
- 同じ元画像のSHA-256かつ同じROIで異なる種族または形態ラベルを検出したらHOLD。
- 同じ元画像SHA/ROIに異なる16×12輝度特徴量を付与したらHOLD。
- 16×12の特徴量が完全一致するのに異なる形態とラベル付けされたらHOLD（異なる画像SHAでも）。
- メガと通常のラベルフラグ整合性、全81形態の登録済みspecies/variant、参照ID重複、手動レビュー、SHA形式、ROIの値域を検査。
- 同一形態の複数参照は維持。異なるROIの同じスクリーンショットは同じ個体と見なさない。
- 新しく `r655_reference_integrity` 証跡を1ボタンの履歴JSONへ追加。異常時はR654の比較結果も`HOLD_R655_REFERENCE_INTEGRITY`で停止。
- `owner_certified`、`mega_event_certified`、`mega_form_certified`、`battle_advice_authorized`は常にfalse。

## 検証
- Swift単体の異常系23件をローカル通過。
- 実在する81形態R649台帳とリンクするSwiftの実registry検証15件をローカル通過。
- 本番アプリiPhoneOS全体ビルドと回帰試験はR655のApple CI待ち。

## 制約・危険性
これは手動画像ラベルの整合性検査のみであり、画像が正しいポケモン・形態を写した証拠にはならない。R594の16×12輝度、左右仮ROIs、実画面・自他同定、性別・色違い、カメラ姿勢、アニメーションの校正は未完了。実機79項目は全て未認証のまま。

## 研究情報源
- https://github.com/PokeAPI/sprites/blob/master/README.md （Championsの前/後、色違いWebPなど）
- https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print （将来の端末内画像特徴量の評価手段。現在未実装）
- https://github.com/zeek10191019-stack/true-plan-showdown-verification/tree/research/r654-mega-class-safety-20261101 （R654保存正本）

画像著作権の許諾未確認データはZIPやGitHubへ無断添付しない。ユーザーが実機から収集した画像は本人レビュー後のみローカル参照候補へ使う。
