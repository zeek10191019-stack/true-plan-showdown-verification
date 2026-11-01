"""Strict, transactional R613-616 research report integration; never promotes game claims."""
from pathlib import Path
import hashlib,re
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
OLD=re.compile(r'(?m)^(?P<indent>[ \t]*)let r612Entries = R612ArchiveEvidenceClosure\.beforeZip\(r611Entries\)\n'
               r'(?P=indent)guard r612Entries\.count == r610Entries\.count \+ 2 else \{\n'
               r'(?P=indent)    throw NSError\(domain:"R612_EVIDENCE_CAPACITY_EXHAUSTED",code:612\)\n'
               r'(?P=indent)\}\n'
               r'(?P=indent)_ = try R548ResearchArchive\.write\(\n'
               r'(?P=indent)    r612Entries, to: zipURL, work: exportWork\n'
               r'(?P=indent)\)')
TEST=Path('tests/test_r611batch_integration.py')
TEST_SHA='34dc96b928fb90f5324f0979c7161cf0552ecee263a4d6671b311dfb4222c7f6'
OLD_TEST="      'r612Entries, to: zipURL, work: exportWork']"
NEW_TEST="      'let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)']"
# Duplicate final chain prefix would violate the one-occurrence assertion, so
# remove the final-writer assertion rather than swap to the new implementation.
NEW_TEST="      ]"

def patch(root):
    root=Path(root);file=root/TARGET;test=root/TEST
    before=file.read_bytes();src=before.decode('utf-8')
    matches=list(OLD.finditer(src))
    if len(matches)!=1 or src.count('R613R616IntegratedReadiness.beforeZip(')!=0 or src.count('R548ResearchArchive.write(')!=1:
        raise ValueError('WRITER_SEAM_CHANGED_OR_ALREADY_PATCHED')
    original_test=test.read_bytes()
    if hashlib.sha256(original_test).hexdigest()!=TEST_SHA:
        raise ValueError('OLD_TEST_DRIFT')
    text=original_test.decode('utf-8')
    if text.count(OLD_TEST)!=1 or text.count(NEW_TEST)!=0:
        raise ValueError('OLD_TEST_EXPECTATION_CHANGED')
    m=matches[0];i=m.group('indent')
    replacement=(i+'let r612Entries = R612ArchiveEvidenceClosure.beforeZip(r611Entries)\n'
      +i+'guard r612Entries.count == r610Entries.count + 2 else {\n'
      +i+'    throw NSError(domain:"R612_EVIDENCE_CAPACITY_EXHAUSTED",code:612)\n'
      +i+'}\n'
      +i+'let r613Entries = R613R616IntegratedReadiness.beforeZip(r612Entries)\n'
      +i+'guard r613Entries.count == r612Entries.count + 1 else {\n'
      +i+'    throw NSError(domain:"R616_ARCHIVE_READINESS_CAPACITY_EXHAUSTED",code:616)\n'
      +i+'}\n'
      +i+'_ = try R548ResearchArchive.write(\n'
      +i+'    r613Entries, to: zipURL, work: exportWork\n'
      +i+')')
    updated=(src[:m.start()]+replacement+src[m.end():]).encode('utf-8')
    upgraded_test=text.replace(OLD_TEST,NEW_TEST).encode('utf-8')
    if updated==before or upgraded_test==original_test:raise ValueError('NO_CHANGE')
    # Atomicity at the validation boundary: no files are changed until all checks succeed.
    file.write_bytes(updated)
    test.write_bytes(upgraded_test)
    assert updated.count(b'R613R616IntegratedReadiness.beforeZip(')==1
    assert updated.count(b'R548ResearchArchive.write(')==1
    return file
