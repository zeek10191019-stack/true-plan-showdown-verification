"""Static R595 source/one-button collector inventory after pinned replay.

Inventory is deliberately non-certifying: seeing an extractor in source does
not prove its 16x12 samples and normalization match R596's stored vectors.
"""
import hashlib
import json
import re
from pathlib import Path

FUNC = re.compile(r'\b(?:func|struct|class|enum)\s+([A-Za-z_][A-Za-z_0-9]*)')
KEYWORDS = re.compile(r'zip|export|collector|collect|snapshot|onebutton|one_button|png|archive|manifest', re.I)


def probe(root):
    root = Path(root)
    target = root / 'app/ios/ChampionsOnDevice/R595FormReferenceMatcher.swift'
    if not target.is_file():
        return {'r595_source_present': False, 'extractor_compatibility': 'HOLD_SOURCE_NOT_FOUND',
                'one_button_hook_confirmed': False, 'production_ready': False}
    text = target.read_text(encoding='utf-8')
    symbols = FUNC.findall(text)
    swift = root / 'app/ios/ChampionsOnDevice'
    candidate_files = []
    for file in swift.glob('*.swift'):
        if KEYWORDS.search(file.name) and file.name != target.name:
            candidate_files.append(file.name)
    return {
        'r595_source_present': True,
        'r595_source_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
        'r595_symbols': sorted(set(symbols))[:80],
        'possible_collector_files': sorted(candidate_files)[:80],
        'extractor_compatibility': 'HOLD_NO_PIXEL_NORMALIZATION_EQUIVALENCE_PROOF',
        'one_button_hook_confirmed': False,
        'production_ready': False,
        'next_required_proof': 'R595_PIXEL_CROP_AND_NUMERIC_VECTOR_REPLAY_WITH_INDEPENDENT_REAL_PNG'
    }


if __name__ == '__main__':
    import sys
    print(json.dumps(probe(sys.argv[1] if len(sys.argv)>1 else '.'), indent=2))
