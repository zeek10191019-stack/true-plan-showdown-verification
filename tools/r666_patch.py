#!/usr/bin/env python3
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
a='''                    R665EvidenceTraceAudit.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
b='''                    R665EvidenceTraceAudit.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    // R666: typed OCR candidates, never certified game state.
                    R666TypedOCRCandidates.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(a)==1, 'R666_PARENT_LAYOUT_UNEXPECTED'
assert 'R666TypedOCRCandidates.enrich(' not in s,'R666_DUPLICATE'
assert s.count('R665EvidenceTraceAudit.enrich(')==1
assert s.count('R646FieldSignalReaders.enrich(')==1
p.write_text(s.replace(a,b),encoding='utf-8')
print('R666_TYPED_READER_INTEGRATED')
