from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/ChampionsOnDeviceApp.swift')
s=p.read_text(encoding='utf-8')
anchor='''                    Section("R656｜メガ前後Vision研究（手動・未認証）") {
                        R656MegaVisionPanel()
                    }'''
assert s.count(anchor)==1, 'R658_APP_PANEL_ANCHOR_MISMATCH'
s=s.replace(anchor,anchor+'''
                    Section("R658｜メガ前後4画像の変化（未認証）") {
                        R658MegaTemporalPanel()
                    }''',1)
p.write_text(s,encoding='utf-8')
print('R658_PANEL_WIRED')
