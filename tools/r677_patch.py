from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text()
anchor='''                    R676FieldOverlayOCR.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(anchor)==1, 'R676 selected evidence not found'
assert 'R677TurnTimerOCR.enrich(&bundle,' not in s
s=s.replace(anchor, anchor+'''
                    // R677: displayed header turn and clock OCR, not battle truth.
                    R677TurnTimerOCR.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")''')
p.write_text(s)
print('R677_TURN_TIMER_SELECTED_EVIDENCE_INTEGRATED')
