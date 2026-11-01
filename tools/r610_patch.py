"""Strictly wrap the verified R609 one-button ZIP seam; no fallback edit."""
from pathlib import Path
import re
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
SEAM=re.compile(
    r'(?m)^(?P<i>[ \t]*)let r609Entries = R609VisionTextSpatialEvidence\.beforeZip\(r608Entries\)\n'
    r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
    r'(?P=i)    r609Entries, to: zipURL, work: exportWork\n'
    r'(?P=i)\)[ \t]*$'
)
def patch(root):
    path=Path(root)/TARGET
    original=path.read_bytes()
    text=original.decode('utf-8')
    matches=list(SEAM.finditer(text))
    if len(matches)!=1 or 'R610CrossEvidenceCandidate.beforeZip(' in text:
        raise ValueError('R610_EXACT_R609_SEAM_MISSING_OR_DUPLICATED')
    match=matches[0]
    i=match.group('i')
    replace=(
        i+'let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)\n'
        +i+'let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)\n'
        +i+'_ = try R548ResearchArchive.write(\n'
        +i+'    r610Entries, to: zipURL, work: exportWork\n'
        +i+')'
    )
    updated=text[:match.start()]+replace+text[match.end():]
    if updated.count('R610CrossEvidenceCandidate.beforeZip(')!=1:
        raise ValueError('R610_UNEXPECTED_PATCH_COUNT')
    path.write_bytes(updated.encode('utf-8'))
    return path
