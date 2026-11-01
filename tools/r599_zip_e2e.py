"""Cross-language archive integrity check for the R599 staged Swift fixture.

The before/after directories come from actual R599 Swift attachment execution.
Uses R598's independent, read-only original-entry-preservation audit.
"""
import io
import json
import sys
import zipfile
from pathlib import Path
from r598_zip_audit import audit


def zip_bytes(folder):
    folder = Path(folder)
    assert (folder / 'manifest.json').is_file(), 'ZIP_E2E_MANIFEST_MISSING'
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
        for p in sorted(folder.rglob('*')):
            if p.is_file():
                zf.write(p, p.relative_to(folder).as_posix())
    return buf.getvalue()


def run(root):
    root = Path(root)
    before, after = zip_bytes(root / 'before'), zip_bytes(root / 'after')
    result = audit(before, after)
    assert result['candidate_status'] == 'hold'
    assert result['live_recognition_certified'] is False
    return result


if __name__ == '__main__':
    print(json.dumps(run(sys.argv[1]), sort_keys=True))
