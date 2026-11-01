"""Independent, read-only ZIP audit of staged research-only form evidence.

Reject path traversal, symlinks, malformed manifests, hash mismatches,
missing frames, and premature live certification. No network or game assets.
"""
import hashlib
import json
import sys
import zipfile
from pathlib import Path


def check_bundle(zip_path):
    p = Path(zip_path)
    try:
        with zipfile.ZipFile(p) as z:
            infos = z.infolist()
            if len(infos) < 3 or len(infos) > 2000:
                return False, 'ZIP_MEMBER_COUNT_INVALID'
            names = [i.filename for i in infos]
            if len(names) != len(set(names)):
                return False, 'ZIP_DUPLICATE_ENTRIES'
            for i in infos:
                parts = i.filename.split('/')
                if (i.is_dir() or i.filename.startswith('/') or '\\' in i.filename or
                    len(parts) > 12 or any(part in ('','.', '..') for part in parts)):
                    return False, 'ZIP_MEMBER_PATH_UNSAFE'
                mode=(i.external_attr >> 16) & 0o170000
                if mode == 0o120000:
                    return False, 'ZIP_SYMLINK_DENIED'
                if i.file_size > 12*1024*1024 or i.compress_size > 12*1024*1024:
                    return False, 'ZIP_OVERSIZED_MEMBER'
            if 'manifest.json' not in names or 'crop.png' not in names:
                return False, 'FRAME_OR_MANIFEST_MISSING'
            manifest=json.loads(z.read('manifest.json'))
            if manifest.get('original') is not True:
                return False, 'ORIGINAL_DATA_CORRUPT'
            ext=manifest.get('r598_form_evidence')
            if not isinstance(ext,dict):
                return False, 'FORM_EVIDENCE_MISSING'
            path=ext.get('path')
            if not isinstance(path,str) or not path.startswith('evidence/') or path not in names:
                return False, 'EVIDENCE_FILE_MISSING'
            evidence=z.read(path)
            if ext.get('sha256') != hashlib.sha256(evidence).hexdigest() or ext.get('bytes') != len(evidence):
                return False, 'EVIDENCE_DIGEST_MISMATCH'
            record=json.loads(evidence)
            if (record.get('certification') != 'NOT_CERTIFIED_FOR_LIVE_BATTLE' or
                record.get('result',{}).get('status') not in ('hold','candidate_unverified') or
                ext.get('certification') != record.get('certification') or
                ext.get('status') != record['result']['status']):
                return False, 'LIVE_CERTIFICATION_FORBIDDEN'
            if record.get('cropSHA256') != hashlib.sha256(z.read('crop.png')).hexdigest():
                return False, 'CROP_FRAME_HASH_MISMATCH'
            if record.get('captureSide') not in ('own','opponent'):
                return False, 'SIDE_UNVERIFIED'
            if record.get('frameID') != 21 or record.get('epoch') != 3:
                return False, 'FRAME_ID_UNEXPECTED'
            return True, 'R600_RESEARCH_ONLY_BUNDLE_VERIFIED'
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError, TypeError) as ex:
        return False, 'MALFORMED_ARCHIVE_OR_JSON'

if __name__=='__main__':
    ok,reason=check_bundle(sys.argv[1]);print(reason);sys.exit(0 if ok else 1)
