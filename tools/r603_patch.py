"""R603: deterministic integration after R602 hook, exact and single seam."""
import re
from pathlib import Path

TARGET = Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
PATTERN = re.compile(
    r'(?m)^(?P<indent>[ \t]*)let r602Entries = '
    r'R602OneTapFormArchive\.beforeZip\(entries\)\n'
    r'(?P=indent)_ = try R548ResearchArchive\.write\(\n'
    r'(?P=indent)    r602Entries, to: zipURL, work: exportWork\n'
    r'(?P=indent)\)\s*$'
)


def patch(root):
    target = Path(root) / TARGET
    before = target.read_text(encoding='utf-8')
    matches = list(PATTERN.finditer(before))
    if len(matches) != 1 or 'R603FormReadiness.beforeZip(' in before:
        raise ValueError('R603_R602_PRODUCTION_SEAM_MISSING_OR_DUPLICATED')
    match = matches[0]
    indent = match.group('indent')
    repl = (
        indent + 'let r602Entries = R602OneTapFormArchive.beforeZip(entries)\n'
        + indent + 'let r603Entries = R603FormReadiness.beforeZip(r602Entries)\n'
        + indent + '_ = try R548ResearchArchive.write(\n'
        + indent + '    r603Entries, to: zipURL, work: exportWork\n'
        + indent + ')'
    )
    result = before[:match.start()] + repl + before[match.end():]
    target.write_text(result, encoding='utf-8')
    assert result.count('R603FormReadiness.beforeZip(') == 1
    assert result.count('R602OneTapFormArchive.beforeZip(') == 1
    return target

if __name__ == '__main__':
    print('R603_PRODUCTION_SEAM', patch('.'))
