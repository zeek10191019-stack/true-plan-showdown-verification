#!/usr/bin/env python3
from pathlib import Path
root=Path('app/ios/ChampionsOnDevice')
p=root/'CaptureCoordinator.swift'
s=p.read_text(encoding='utf-8')
needle='''                    R668PlainHUDReader.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
revised='''                    R668PlainHUDReader.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    // R669: proximity candidates, not proof of actor identity.
                    R669HUDAdjacentText.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(needle)==1,'R669_PARENT_CAPTURE_LAYOUT_MISMATCH'
assert 'R669HUDAdjacentText.enrich(' not in s,'R669_ALREADY_INTEGRATED'
assert s.count('R668PlainHUDReader.enrich(')==1
p.write_text(s.replace(needle,revised),encoding='utf-8')

q=root/'R668PlainHUDReader.swift'
a=q.read_text(encoding='utf-8')
anchor='''        return !excluded.contains(t)'''
patch='''        let nonSpeciesHUDWords=["やけど","まひ","ねむり","こおり","どく",
           "もうどく","こんらん","みがわり","ちょうはつ",
           "アンコール","かなしばり","あくび","すなあらし",
           "あめ","雨","ひざしがつよい","ゆき","雪",
           "リフレクター","ひかりのかべ","オーロラベール",
           "トリックルーム","グラスフィールド",
           "エレキフィールド","サイコフィールド",
           "ミストフィールド"]
        return !excluded.contains(t) && !nonSpeciesHUDWords.contains(t)'''
assert a.count(anchor)==1,'R669_R668_SPECIES_EXCLUSION_ANCHOR_MISSING'
assert 'nonSpeciesHUDWords' not in a,'R669_DUPLICATE_R668_PATCH'
q.write_text(a.replace(anchor,patch),encoding='utf-8')
print('R669_ADJACENT_READER_AND_R668_STATUS_NAME_FIX_INTEGRATED')
