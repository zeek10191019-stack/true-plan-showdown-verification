"""Patch only the verified R607 before-ZIP call; never fork production collection."""
from pathlib import Path
import re
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
PAT=re.compile(
 r'(?m)^(?P<i>[ \t]*)let r607Entries = R607FrameProvenanceAudit\.beforeZip\(r605Entries\)\n'
 r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
 r'(?P=i)    r607Entries, to: zipURL, work: exportWork\n'
 r'(?P=i)\)[ \t]*$'
)
def patch(root):
    p=Path(root)/TARGET
    original=p.read_text(encoding='utf-8')
    found=list(PAT.finditer(original))
    if len(found)!=1 or 'R608FramePixelEvidence.beforeZip(' in original:
        raise ValueError('R608_PRODUCTION_SEAM_DRIFT_OR_DUPLICATE')
    hit=found[0];i=hit.group('i')
    value=(i+'let r607Entries = R607FrameProvenanceAudit.beforeZip(r605Entries)\n'
          +i+'let r608Entries = R608FramePixelEvidence.beforeZip(r607Entries)\n'
          +i+'_ = try R548ResearchArchive.write(\n'
          +i+'    r608Entries, to: zipURL, work: exportWork\n'
          +i+')')
    output=original[:hit.start()]+value+original[hit.end():]
    assert output.count('R608FramePixelEvidence.beforeZip(')==1
    p.write_text(output,encoding='utf-8')
    return p
