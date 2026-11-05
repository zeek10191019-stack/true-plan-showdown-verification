from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
a='''                    R677TurnTimerOCR.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(a)==1, 'R677 selected evidence absent'
assert 'R678MoveTypeOCR.enrich(&bundle,' not in s
s=s.replace(a,a+'''
                    R678MoveTypeOCR.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")''')
p.write_text(s)
r=Path('app/ios/ChampionsOnDevice/R668PlainHUDReader.swift')
s=r.read_text()
label='''        let t=s.trimmingCharacters(in:.whitespacesAndNewlines)'''
assert s.count(label)==1
s=s.replace(label,label+'''
        if t == "10まんボルト" { return true }''')
a='''        return !excluded.contains(t) && !nonSpeciesHUDWords.contains(t)'''
assert s.count(a)==1
s=s.replace(a,'''        let typeLabels=["ノーマル","ほのお","みず","でんき",
            "くさ","こおり","かくとう","どく","じめん",
            "ひこう","エスパー","むし","いわ","ゴースト",
            "ドラゴン","あく","はがね","フェアリー"]
        return !excluded.contains(t) && !nonSpeciesHUDWords.contains(t)
            && !typeLabels.contains(t)''')
r.write_text(s)
print('R678_MOVE_TYPE_OCR_AND_R668_TYPE_FILTER_INTEGRATED')
