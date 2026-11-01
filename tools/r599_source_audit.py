"""R599: source visibility report after R598 SHA-pinned replay.

Static cross-references only; do not infer that a method is called by a button.
No automatic, heuristic source code mutation. Avoid emitting private screenshots.
"""
import hashlib
import json
import re
from pathlib import Path

RELEVANT = re.compile(r"zip|archive|export|diagnostic|collect|snapshot|png|manifest|tap|button", re.I)
METHOD = re.compile(r"\b(?:func|class|struct|enum|extension)\s+([A-Za-z_][A-Za-z0-9_]*)")


def audit(root):
    root = Path(root)
    source = root / 'app/ios/ChampionsOnDevice'
    r595 = source / 'R595FormReferenceMatcher.swift'
    if not r595.is_file():
        return {'r595_present': False, 'production_hook': 'HOLD_PARENT_R595_MISSING', 'ready': False}
    files = sorted(source.glob('*.swift'))
    inventory = []
    for f in files:
        # Exclude the new research-only bridge files as proof of a UI seam.
        if re.match(r'R59[5-9]', f.name):
            continue
        lines = f.read_text(encoding='utf-8').splitlines()
        hits = [(i, x.strip()[:180]) for i, x in enumerate(lines, 1)
                if RELEVANT.search(x) and ('func ' in x or 'struct ' in x or 'class ' in x)]
        if hits:
            inventory.append({'file': f.name, 'sha256': hashlib.sha256(f.read_bytes()).hexdigest(),
                              'candidate_declarations': [{'line': i, 'text': x} for i, x in hits[:12]]})
    r595_text = r595.read_text(encoding='utf-8')
    actor = source / 'R594ActorAppearance.swift'
    return {'schema': 'trueplan.r599.source_audit.v1',
            'r595_present': True, 'r595_sha256': hashlib.sha256(r595.read_bytes()).hexdigest(),
            'r595_declared_symbols': sorted(set(METHOD.findall(r595_text))),
            'r594_present': actor.is_file(),
            'r594_sha256': hashlib.sha256(actor.read_bytes()).hexdigest() if actor.is_file() else None,
            'candidate_production_files': inventory[:30],
            'new_r599_binding_adapter_present': (source / 'R599BoundOneButton.swift').exists(),
            'one_button_production_invocation_verified': False,
            'r595_pixel_feature_equivalence_verified': False,
            'real_game_reference_images_admitted': 0,
            'production_hook': 'HOLD_NEEDS_EXACT_COLLECTOR_CALLSITE_AND_PIXEL_VECTOR_REPLAY',
            'ready': False}


if __name__ == '__main__':
    import sys
    print(json.dumps(audit(sys.argv[1] if len(sys.argv)>1 else '.'), ensure_ascii=False, indent=2))
