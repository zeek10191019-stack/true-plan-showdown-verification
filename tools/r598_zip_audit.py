"""Read-only audit for R598 one-button diagnostic ZIP integrity.

No feature extraction, no classifier training, no certification. Accepts an
original bundle ZIP and one with an R598 sidecar; proves original ZIP members
were not dropped/changed and the new manifest's sidecar SHA matches.
"""
import hashlib
import io
import json
import posixpath
import stat
import zipfile
from pathlib import PurePosixPath

MAX_TOTAL_UNCOMPRESSED = 2 * 1024 ** 3
MANIFEST_NAME = 'manifest.json'


def digest_stream(zf, name):
    h = hashlib.sha256()
    with zf.open(name) as f:
        while True:
            b = f.read(1024 * 1024)
            if not b:
                return h.hexdigest()
            h.update(b)


def _validate(zf):
    infos = zf.infolist()
    names = [x.filename for x in infos]
    if len(names) != len(set(names)):
        raise ValueError('DUPLICATED_ZIP_ENTRY')
    if sum(x.file_size for x in infos) > MAX_TOTAL_UNCOMPRESSED:
        raise ValueError('ZIP_UNCOMPRESSED_SIZE_UNSAFE')
    for item in infos:
        name = item.filename
        components = PurePosixPath(name).parts
        if not name or name.startswith('/') or '\\' in name or '\x00' in name or '..' in components:
            raise ValueError('UNSAFE_ZIP_ENTRY')
        if posixpath.normpath(name) != name.rstrip('/'):
            raise ValueError('UNSAFE_ZIP_ENTRY')
        if stat.S_IFMT(item.external_attr >> 16) == stat.S_IFLNK:
            raise ValueError('ZIP_SYMLINK_UNSAFE')
    return set(names)


def _manifest(zf, name):
    try:
        value = json.loads(zf.read(name))
    except (KeyError, ValueError, UnicodeDecodeError) as e:
        raise ValueError('MANIFEST_UNREADABLE') from e
    if not isinstance(value, dict):
        raise ValueError('MANIFEST_NOT_OBJECT')
    return value


def audit(before, after, manifest_name=MANIFEST_NAME):
    """Return evidence metadata; raise ValueError on any proof failure."""
    if manifest_name not in ('manifest.json', 'capture_manifest.json'):
        raise ValueError('UNRECOGNIZED_MANIFEST')
    with zipfile.ZipFile(io.BytesIO(before)) as a, zipfile.ZipFile(io.BytesIO(after)) as b:
        original = _validate(a)
        updated = _validate(b)
        if manifest_name not in original or manifest_name not in updated:
            raise ValueError('MANIFEST_MISSING')
        if not original.issubset(updated):
            raise ValueError('ORIGINAL_MEMBER_DROPPED')
        for name in original - {manifest_name}:
            if digest_stream(a, name) != digest_stream(b, name):
                raise ValueError('ORIGINAL_MEMBER_MUTATED:' + name)
        prior = _manifest(a, manifest_name)
        current = _manifest(b, manifest_name)
        if 'r598_form_evidence' in prior:
            raise ValueError('R598_BASELINE_ALREADY_PRESENT')
        copy = dict(current)
        sidecar = copy.pop('r598_form_evidence', None)
        if copy != prior:
            raise ValueError('ORIGINAL_MANIFEST_FIELDS_CHANGED')
        if not isinstance(sidecar, dict):
            raise ValueError('R598_EXTENSION_MISSING')
        if sidecar.get('schema') != 'trueplan.r598.sidecar.v1':
            raise ValueError('R598_SCHEMA_INVALID')
        path = sidecar.get('path')
        if not isinstance(path, str) or not path.startswith('evidence/r598_form_') or not path.endswith('.json'):
            raise ValueError('R598_SIDECAR_PATH_INVALID')
        if path in original or path not in updated:
            raise ValueError('R598_SIDECAR_MISSING_OR_COLLISION')
        if updated - original != {path}:
            raise ValueError('UNEXPECTED_ADDED_MEMBERS')
        blob = b.read(path)
        if sidecar.get('sha256') != hashlib.sha256(blob).hexdigest() or sidecar.get('bytes') != len(blob):
            raise ValueError('R598_SIDECAR_HASH_MISMATCH')
        try:
            detail = json.loads(blob)
        except (ValueError, UnicodeDecodeError) as e:
            raise ValueError('R598_SIDECAR_BAD_JSON') from e
        if detail.get('schema') != 'trueplan.r597.form_evidence.v1':
            raise ValueError('R597_EVIDENCE_SCHEMA_INVALID')
        if detail.get('certification') != 'NOT_CERTIFIED_FOR_LIVE_BATTLE':
            raise ValueError('PRODUCTION_CERTIFICATION_BYPASS')
        status = detail.get('result', {}).get('status')
        if status not in ('hold', 'candidate_unverified') or sidecar.get('status') != status:
            raise ValueError('CLASSIFICATION_STATUS_UNSAFE')
        return {'result': 'PASS', 'preserved_original_entries': len(original),
                'new_sidecar': path, 'sidecar_sha256': sidecar['sha256'],
                'candidate_status': status, 'live_recognition_certified': False}


if __name__ == '__main__':
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('before')
    p.add_argument('after')
    p.add_argument('--manifest-name', default=MANIFEST_NAME)
    args = p.parse_args()
    with open(args.before, 'rb') as f:
        before_data = f.read()
    with open(args.after, 'rb') as f:
        after_data = f.read()
    print(json.dumps(audit(before_data, after_data, args.manifest_name), indent=2))
