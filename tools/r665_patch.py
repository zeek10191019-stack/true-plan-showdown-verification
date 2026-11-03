#!/usr/bin/env python3
"""Install one-tap evidence audit in the existing, verified pipeline."""
from pathlib import Path
path=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=path.read_text(encoding='utf-8')
old='''                    R664ReadoutScorecard.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
new='''                    R664ReadoutScorecard.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    // R665: source trace only, never gameplay truth.
                    R665EvidenceTraceAudit.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
assert 'R665EvidenceTraceAudit.enrich(' not in s,'R665_ALREADY_PRESENT'
assert s.count(old)==1,'R665_UNEXPECTED_CAPTURE_ANCHOR'
assert s.count('R581ReadabilityCoverage.make(')==1,'R581_MISSING'
assert s.count('R646FieldSignalReaders.enrich(')==1,'R646_MISSING'
assert s.count('R664ReadoutScorecard.enrich(')==1,'R664_MISSING'
s=s.replace(old,new)
assert s.count('R665EvidenceTraceAudit.enrich(')==1
path.write_text(s,encoding='utf-8')
print('R665_ONE_TAP_EVIDENCE_TRACE_INTEGRATED')
