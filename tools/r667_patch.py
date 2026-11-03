from pathlib import Path
p=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
s=p.read_text(encoding='utf-8')
a='''                    R666TypedOCRCandidates.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
b='''                    R666TypedOCRCandidates.enrich(&bundle,
                        sourceKind:"LIVE_RETAINED_FRAME")
                    // R667 text extraction, NOT owner or Mega form evidence.
                    R667ExpandedOCRFields.enrich(&bundle)
                    R647MegaSignalBoundary.enrich(&bundle, sourceKind:"LIVE_RETAINED_FRAME")'''
assert s.count(a)==1, 'R667_BASE_MISMATCH'
assert 'R667ExpandedOCRFields.enrich(' not in s,'R667_DUPLICATE'
p.write_text(s.replace(a,b),encoding='utf-8')
print('R667_EXPANDED_TEXT_READER_INTEGRATED')
