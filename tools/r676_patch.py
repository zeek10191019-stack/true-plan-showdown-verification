from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
a='''                    R669HUDAdjacentText.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(a)==1, f'R669 anchor count {s.count(a)}'
assert 'R676FieldOverlayOCR.enrich(&bundle,' not in s
s=s.replace(a,a+'''
                    // R676: source-bound OCR of displayed field effects.
                    // On-screen label is NOT proof of activation or turn age.
                    R676FieldOverlayOCR.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")''')
p.write_text(s)
print('R676_FIELD_EFFECT_OCR_SELECTED_EVIDENCE_INTEGRATED')
