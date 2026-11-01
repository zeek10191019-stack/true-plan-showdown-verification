from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/ChampionsOnDeviceApp.swift')
s=p.read_text('utf-8')
anchor='                    Section("画面の確認（過去フレーム・未認証）") {'
assert s.count(anchor)==1,'R656_APP_INSERTION_MISSING'
assert 'R656MegaVisionPanel()' not in s,'R656_ALREADY_INSERTED'
s=s.replace(anchor,
'''                    Section("R656｜メガ前後Vision研究（手動・未認証）") {
                        R656MegaVisionPanel()
                    }
'''+anchor,1)
p.write_text(s,encoding='utf-8')
print('R656_IOS_VISUAL_PANEL_WIRED')
