#!/usr/bin/env python3
"""Append provenance-bound signal count reporting; no battle facts."""
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
old='''                    R646FieldSignalReaders.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
new='''                    R646FieldSignalReaders.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")
                    // R664: candidate-signal counts are NOT game accuracy.
                    R664ReadoutScorecard.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
assert 'R664ReadoutScorecard.enrich(' not in s, 'R664_ALREADY_PRESENT'
assert s.count(old)==1, 'R664_ANCHOR_MISMATCH'
assert s.count('R581ReadabilityCoverage.make(')==1, 'R581_MISSING'
assert s.count('R646FieldSignalReaders.enrich(')==1, 'R646_MISSING'
s=s.replace(old,new)
assert s.count('R664ReadoutScorecard.enrich(')==1
p.write_text(s,encoding='utf-8')
print('R664_ONE_TAP_READOUT_SCORECARD_INTEGRATED')
