# R653 Mega Image Reference Import — 既存台帳の復元保証

## 固定ベース
R652 `48c394e7a2e61281c2df6afded35b3f6e912a5ca`（Apple CI合格）。

## R653修正
- iPhoneのR595参照JSON取込で、置換後の実バイト一致を確認。
- 不一致、書込失敗、参照カタログ読込不一致では旧台帳のバイトを復元。
- 初回取込で破損したファイルは除去。
- 復元そのものが失敗した際は `ROLLBACK_FAILED_CHECK_CATALOG` とし、旧ファイル保持を断言しない。
- UIは取込拒否時に現在の有効参照件数を表示するよう修正。
- 回帰試験では書込異常を故意に注入して拒否および復元を検証。

## 動作範囲・未了
- メガ81形態の候補台帳はR649〜651を維持。メガニャオニクスは性別画像を別外観クラスとして維持。
- 画像出典はPokeAPIのChampions画像メタデータを参照。元画像バイナリは今回も同梱・再配布しない。
- iPhone実機の認識成功、画面ROI校正、対象のOWN/OPP帰属、メガ使用の確定、全79項目の認証は未了。
- R650の参照生成ツールは実フレームに人間が正解ラベルを付けない限り教師参照0件。
- R595は1カタログ512件の制限を維持。複数シャードの取込や完全網羅は次工程。

## GitHub CI
`db.yml` は **mainへのアップロード時にpushで自動起動**、手動起動も可能。
固定親SHAを照合してR653修正、Swift独立テスト、R652回帰試験、iPhoneOSビルド、保存ブランチ作成を実施。
GitHub Actionsはプラン・残余枠・ランナー等の条件によって従量料金が発生し得る。実行前にGitHub課金状態を確認。

## 画像出典・利用に関する一次資料
- https://champions-news.pokemon-home.com/en/page/816.html
- https://github.com/PokeAPI/sprites/blob/master/README.md
- https://github.com/PokeAPI/sprites/blob/master/LICENCE.txt
