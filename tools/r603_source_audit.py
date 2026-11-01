"""Scan reconstructed, hash-pinned iOS source. Only print bounded code identifiers.
No claim of feature parity, no PNG or personal battle data exported.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path('app/ios/ChampionsOnDevice')
TARGETS = (
    'R594ActorAppearance.swift',
    'R595FormReferenceMatcher.swift',
    'CaptureCoordinator.swift',
    'R603FormReadiness.swift',
)


def inspect(root=ROOT):
    out = {'schema': 'trueplan.r603.source_audit.v1',
           'feature_parity_certified': False,
           'actual_frame_producer_wired': False,
           'source': [], 'relevant_callsite_hits': [],
           'feature_flow_lines': []}
    for name in TARGETS:
        path = Path(root) / name
        if not path.is_file():
            raise RuntimeError('MISSING_PINNED_SOURCE:' + name)
        data = path.read_bytes()
        rows = data.decode('utf-8').splitlines()
        symbols = []
        for n, line in enumerate(rows, 1):
            if re.match(r'^\s*(?:(?:private|static|fileprivate|public|internal|final)\s+)*'
                        r'(?:func|struct|enum|class|let|var)\s+[A-Za-z_]', line):
                if re.search(r'feature|luminance|raster|appearance|crop|extract|'
                             r'orientation|owner|pixel|frame|form', line, re.I):
                    symbols.append({'line': n, 'signature': line.strip()[:165]})
        out['source'].append({'file': name, 'bytes': len(data),
                              'sha256': hashlib.sha256(data).hexdigest(),
                              'symbols': symbols[:90]})
        if name in ('R594ActorAppearance.swift', 'R595FormReferenceMatcher.swift'):
            terms = (r'(?i)feature|luminance|raster|normalize|downsample|'
                     r'stride|pixel|width|height|16|12|192|extract|grid|'
                     r'for .* in|row|column|Float|Double')
            selected = set()
            for i, line in enumerate(rows):
                if re.search(terms, line):
                    selected.update(range(max(0, i - 1), min(len(rows), i + 2)))
            for i in sorted(selected)[:95]:
                line = rows[i].strip()
                if not re.search(r'(?i)secret|token\s*=|password|api[_-]?key', line):
                    out['feature_flow_lines'].append({
                        'file': name, 'line': i + 1, 'text': line[:150]})
        if name == 'CaptureCoordinator.swift':
            for n, line in enumerate(rows, 1):
                if re.search(r'R594|R595|R602|R603|R548ResearchArchive\.write|'
                             r'pixelBuffer|CGImage|crop\.png', line):
                    out['relevant_callsite_hits'].append({
                        'line': n, 'text': line.strip()[:165]})
    return out

if __name__ == '__main__':
    print('R603_SOURCE_TRACE', json.dumps(inspect(), ensure_ascii=False,
                                          separators=(',', ':'))[:22000])
