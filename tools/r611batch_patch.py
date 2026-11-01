"""Exact, transactional extension of the R610 one-button archive seam.
Also upgrades predecessor source tests to assert stage linkage, not writer finality.
"""
from pathlib import Path
import re, hashlib
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
OLD_SEAM=re.compile(
  r'(?m)^(?P<i>[ \t]*)let r610Entries = R610CrossEvidenceCandidate\.beforeZip\(r609Entries\)\n'
  r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
  r'(?P=i)    r610Entries, to: zipURL, work: exportWork\n'
  r'(?P=i)\)[ \t]*$')
TESTS = {
  'tests/test_r609_source.py': (
    '2ff81ad2288216e3f581a1d9aefab22972440ce4bdf024d795e3ec5bca5109e0',
    "self.assertIn('r609Entries, to: zipURL, work: exportWork',self.coordinator)",
    "self.assertIn('let r609Entries = R609VisionTextSpatialEvidence.beforeZip(r608Entries)',self.coordinator)"),
  'tests/test_r610_source.py': (
    'daaa9a17d81df6edaaebb9ac863f5d80462421688e3ef29fd682d67b6ef9af0d',
    "self.assertIn('r610Entries, to: zipURL, work: exportWork',self.target)",
    "self.assertIn('let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)',self.target)")
}
def patch(root):
    root=Path(root)
    target=root/TARGET
    original=target.read_bytes()
    content=original.decode('utf-8')
    matches=list(OLD_SEAM.finditer(content))
    if len(matches)!=1 or 'R611TemporalHUDReview.beforeZip(' in content or 'R612ArchiveEvidenceClosure.beforeZip(' in content:
        raise ValueError('R611_BATCH_WRITER_SEAM_MISSING_OR_DUPLICATED')
    match=matches[0]
    i=match.group('i')
    new=(i+'let r610Entries = R610CrossEvidenceCandidate.beforeZip(r609Entries)\n'
         +i+'let r611Entries = R611TemporalHUDReview.beforeZip(r610Entries)\n'
         +i+'let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)\n'
         +i+'guard r612Entries.count == r610Entries.count + 2 else {\n'
         +i+'    throw NSError(domain:"R612_EVIDENCE_CAPACITY_EXHAUSTED",code:612)\n'
         +i+'}\n'
         +i+'_ = try R548ResearchArchive.write(\n'
         +i+'    r612Entries, to: zipURL, work: exportWork\n'
         +i+')')
    updated=(content[:match.start()]+new+content[match.end():]).encode()
    all_edits={target:updated}
    for name,(digest,old,new) in TESTS.items():
        file=root/name
        before=file.read_bytes()
        if hashlib.sha256(before).hexdigest()!=digest:
            raise ValueError('PREDECESSOR_TEST_SOURCE_CHANGED:'+name)
        t=before.decode('utf-8')
        if t.count(old)!=1 or t.count(new)!=0:
            raise ValueError('OLD_SOURCE_TEST_ANCHOR_MISMATCH:'+name)
        all_edits[file]=t.replace(old,new).encode('utf-8')
    for f,blob in all_edits.items():
        if f.read_bytes()==blob:raise ValueError('NOOP_EDIT')
    # All preconditions have been checked; write only after validation.
    for f,blob in all_edits.items(): f.write_bytes(blob)
    assert updated.count(b'R611TemporalHUDReview.beforeZip(')==1
    assert updated.count(b'R612ArchiveEvidenceClosure.beforeZip(')==1
    return target
