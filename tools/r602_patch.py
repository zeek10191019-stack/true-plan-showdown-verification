"""R602: inject exactly one guarded call at the R601-proven production ZIP write."""
import re
from pathlib import Path

TARGET = Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
WRITE = re.compile(
    r'(?m)^(?P<indent>[ \t]*)_\s*=\s*try\s+'
    r'R548ResearchArchive\.write\(entries,\s*to:\s*zipURL,\s*'
    r'work:\s*exportWork\)[ \t]*$'
)


def patch(root):
    target = Path(root) / TARGET
    before = target.read_text(encoding='utf-8')
    matches = list(WRITE.finditer(before))
    if len(matches) != 1 or 'R602OneTapFormArchive.beforeZip(' in before:
        raise ValueError('PRODUCTION_ONE_BUTTON_SEAM_UNVERIFIED_OR_DUPLICATE')
    m = matches[0]
    indent = m.group('indent')
    replacement = (
        indent + 'let r602Entries = R602OneTapFormArchive.beforeZip(entries)\n'
        + indent + '_ = try R548ResearchArchive.write(\n'
        + indent + '    r602Entries, to: zipURL, work: exportWork\n'
        + indent + ')'
    )
    after = before[:m.start()] + replacement + before[m.end():]
    target.write_text(after, encoding='utf-8')
    assert len(list(WRITE.finditer(after))) == 0
    assert after.count('R602OneTapFormArchive.beforeZip(') == 1
    return target

if __name__ == '__main__':
    print('R602_PRODUCTION_PATCH', patch('.'))
