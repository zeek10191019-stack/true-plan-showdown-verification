"""Read-only inspection of true collector UI and 16x12 feature implementation.
No production modification, no synthetic success label.
"""
import hashlib
import json
import re
from pathlib import Path

UI = re.compile(r'Button\s*\(|@IBAction|onTapGesture|accessibilityIdentifier|one.?button', re.I)
EXPORT = re.compile(r'zip|export|archive|bundle|manifest|diagnostic|collect', re.I)
FEATURE = re.compile(r'16\s*\*\s*12|16\s*,\s*12|feature|grayscale|pixel|luminance|resize|crop|image', re.I)
FUNC = re.compile(r'\bfunc\s+(\w+)\s*\(')


def audit(root):
    root = Path(root) / 'app/ios/ChampionsOnDevice'
    sources = sorted(root.glob('*.swift'))
    digest = hashlib.sha256()
    results = {'schema': 'trueplan.r601.production_seam.v1',
               'swift_files': len(sources), 'tree_sha256': None,
               'ui_candidates': [], 'archive_candidates': [],
               'callsite_edges': [], 'r595_feature_lines': [],
               'production_wired': False, 'numerical_parity_certified': False,
               'reason': 'REQUIRES_VERIFIED_PRODUCTION_CALLSITE_AND_GOLDEN_VECTORS'}
    functions = {}
    for source in sources:
        data = source.read_bytes()
        digest.update(source.name.encode() + b'\x00' + hashlib.sha256(data).digest())
        lines = data.decode('utf8').splitlines()
        if source.name == 'R595FormReferenceMatcher.swift':
            results['r595_sha256'] = hashlib.sha256(data).hexdigest()
            results['r595_feature_lines'] = [
                {'line': i, 'text': line.strip()[:180]}
                for i, line in enumerate(lines, 1) if FEATURE.search(line)
            ][:85]
        if re.match(r'R59[6-9]|R600|R601', source.name):
            continue
        for i, line in enumerate(lines, 1):
            fn = FUNC.search(line)
            if fn:
                functions.setdefault(fn.group(1), []).append((source.name, i))
            if UI.search(line):
                results['ui_candidates'].append({'file': source.name, 'line': i, 'text': line.strip()[:180]})
            if EXPORT.search(line) and (fn or 'Zip' in line or '.zip' in line or 'write(' in line):
                results['archive_candidates'].append({'file': source.name, 'line': i, 'text': line.strip()[:180]})
    # Report calls between likely collector functions. Name matching is not a wiring proof.
    targets = {name for name in functions if EXPORT.search(name)}
    for source in sources:
        if re.match(r'R59[6-9]|R600|R601', source.name):
            continue
        for i, line in enumerate(source.read_text('utf8').splitlines(), 1):
            for symbol in sorted(targets):
                if re.search(r'\b' + re.escape(symbol) + r'\s*\(', line) and not FUNC.search(line):
                    results['callsite_edges'].append({'source': source.name, 'line': i,
                                                       'symbol': symbol, 'text': line.strip()[:160]})
                    break
    for key in ('ui_candidates', 'archive_candidates', 'callsite_edges'):
        results[key] = results[key][:140]
    results['tree_sha256'] = digest.hexdigest()
    return results


if __name__ == '__main__':
    print(json.dumps(audit('.'), ensure_ascii=False, indent=2))
