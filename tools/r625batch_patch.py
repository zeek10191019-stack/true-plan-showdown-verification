"""R625-R628 atomic production ZIP writer integration with version-pinned tests."""
from pathlib import Path
import re,hashlib
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
SOURCE_TEST=Path('tests/test_r621batch_source.py')
PATCH_TEST=Path('tests/test_r621batch_patch.py')
# R624.1 verified source of the regression fixture at parent BK replay.
EXPECTED_621_FIX_SHA='a654e5d56ec8dd84d73b20ad4cb70e1a3a443171e2ebba24598db0fa1d7fe7ee'
# R621 legacy test source is the byte-identical content embedded by BJ.
EXPECTED_621_SOURCE_SHA='8d7f3ee9e12bc5de041479de93110746a2d163b1524eccff52ece7649ddbad9f'

WRITE=re.compile(r'(?m)^(?P<i>[ \t]*)_ = try R548ResearchArchive\.write\(\n(?P=i)    r621Entries, to: zipURL, work: exportWork\n(?P=i)\)')

def _updated_patch_fixture(src:str)->str:
    # Reuse R624.1 regression's own inversion logic, but reconstruct the prior
    # production writer before running that historical patch fixture.
    anchor='''    # R621 is nested in CaptureCoordinator, not at four-space indentation.\n'''
    if src.count(anchor)!=1:
        raise ValueError('R6241_FIXTURE_ANCHOR_DRIFT')
    insertion='''    # R625 is the terminal writer now; restore the R621 writer in a test-only
    # temp copy before R621's original inverse-patch fixture runs.
    import re
    step=r'(?m)^(?P<i>[ \\t]*)let r625Entries = R625R628PixelHUDAndSprite\\.beforeZip\\(r621Entries\\)$'
    steps=list(re.finditer(step,data))
    assert len(steps)==1,'R625_WRITER_MARKER_NOT_UNIQUE'
    j=steps[0].group('i')
    start=steps[0].start()
    tail=(j+'let r625Entries = R625R628PixelHUDAndSprite.beforeZip(r621Entries)\\n'\n          +j+'guard r625Entries.count == r621Entries.count &&\\n'
          +j+'      R625R628PixelHUDAndSprite.containsReport(r625Entries) else {\\n'
          +j+'    throw NSError(domain:"R628_PIXEL_ARCHIVE_HOLD",code:628)\\n'
          +j+'}\\n'
          +j+'_ = try R548ResearchArchive.write(\\n'
          +j+'    r625Entries, to: zipURL, work: exportWork\\n'
          +j+')')
    assert data[start:start+len(tail)]==tail,'R625_TERMINAL_WRITER_DRIFT'
    old=(j+'_ = try R548ResearchArchive.write(\\n'
         +j+'    r621Entries, to: zipURL, work: exportWork\\n'
         +j+')')
    data=data[:start]+old+data[start+len(tail):]
'''
    return src.replace(anchor,insertion+anchor)

def patch(root):
    root=Path(root)
    c=root/TARGET;t=root/SOURCE_TEST;p=root/PATCH_TEST
    old=c.read_text();test=t.read_text();fixture=p.read_text()
    if hashlib.sha256(fixture.encode()).hexdigest()!=EXPECTED_621_FIX_SHA:
        raise ValueError('R6241_FIXTURE_SHA_DRIFT')
    if hashlib.sha256(test.encode()).hexdigest()!=EXPECTED_621_SOURCE_SHA:
        raise ValueError('R621_SOURCE_TEST_SHA_DRIFT')
    if old.count('R625R628PixelHUDAndSprite.beforeZip(')!=0:
        raise ValueError('R625_WRITER_ALREADY_PATCHED')
    found=list(WRITE.finditer(old))
    if len(found)!=1 or old.count('R621R624VisualCandidates.beforeZip(')!=1:
        raise ValueError('R6241_PRODUCTION_WRITER_SEAM_DRIFT')
    needle="self.assertIn('r621Entries, to: zipURL, work: exportWork',s)"
    new_need="self.assertIn('let r621Entries = R621R624VisualCandidates.beforeZip(r617Entries)',s)"
    if test.count(needle)!=1 or test.count(new_need)!=0:
        raise ValueError('R621_LEGACY_TEST_ANCHOR_DRIFT')
    # No mutation occurs before every exact precondition is checked.
    m=found[0];i=m.group('i')
    replacement='\n'.join([
        i+'let r625Entries = R625R628PixelHUDAndSprite.beforeZip(r621Entries)',
        i+'guard r625Entries.count == r621Entries.count &&',
        i+'      R625R628PixelHUDAndSprite.containsReport(r625Entries) else {',
        i+'    throw NSError(domain:"R628_PIXEL_ARCHIVE_HOLD",code:628)',
        i+'}',
        i+'_ = try R548ResearchArchive.write(',
        i+'    r625Entries, to: zipURL, work: exportWork',
        i+')'])
    dst=old[:m.start()]+replacement+old[m.end():]
    new_test=test.replace(needle,new_need)
    new_fixture=_updated_patch_fixture(fixture)
    assert dst.count('R548ResearchArchive.write(')==1
    assert dst.count('R625R628PixelHUDAndSprite.beforeZip(')==1
    assert new_fixture.count('R625_TERMINAL_WRITER_DRIFT')==1
    c.write_text(dst);t.write_text(new_test);p.write_text(new_fixture)
    return c
