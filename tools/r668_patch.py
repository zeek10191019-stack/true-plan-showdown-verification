#!/usr/bin/env python3
from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
a='''                    // R667 text extraction, NOT owner or Mega form evidence.
                    R667ExpandedOCRFields.enrich(&bundle)
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
b='''                    // R667 text extraction, NOT owner or Mega form evidence.
                    R667ExpandedOCRFields.enrich(&bundle)
                    // R668: direct plain-label HUD OCR with geometric anchors.
                    // Position is not player ownership, form or live state.
                    R668PlainHUDReader.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(a)==1,'R668_PARENT_LAYOUT_MISMATCH'
assert 'R668PlainHUDReader.enrich(' not in s,'R668_DUPLICATE'
assert s.count('R667ExpandedOCRFields.enrich(')==1
p.write_text(s.replace(a,b),encoding='utf-8')
print('R668_PLAIN_HUD_OCR_INTEGRATED')
