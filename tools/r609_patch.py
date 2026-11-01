"""Apply exactly one R609 wrapper at the proven R608 ZIP seam; abort on drift."""
from pathlib import Path
import re
TARGET = Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
PATTERN = re.compile(
 r'(?m)^(?P<i>[ \t]*)let r608Entries = R608FramePixelEvidence\.beforeZip\(r607Entries\)\n'
 r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
 r'(?P=i)    r608Entries, to: zipURL, work: exportWork\n'
 r'(?P=i)\)[ \t]*$'
)
def patch(root):
    path = Path(root) / TARGET
    original = path.read_bytes()
    content = original.decode('utf-8')
    matches = list(PATTERN.finditer(content))
    if len(matches) != 1 or 'R609VisionTextSpatialEvidence.beforeZip(' in content:
        raise ValueError('R609_EXACT_ZIP_SEAM_NOT_FOUND_OR_DUPLICATED')
    hit = matches[0]
    i = hit.group('i')
    replacement = (
       i + 'let r608Entries = R608FramePixelEvidence.beforeZip(r607Entries)\n'
       + i + 'let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)\n'
       + i + '_ = try R548ResearchArchive.write(\n'
       + i + '    r609Entries, to: zipURL, work: exportWork\n'
       + i + ')'
    )
    updated = content[:hit.start()] + replacement + content[hit.end():]
    assert updated.count('R609VisionTextSpatialEvidence.beforeZip(') == 1
    path.write_bytes(updated.encode('utf-8'))
    return path
