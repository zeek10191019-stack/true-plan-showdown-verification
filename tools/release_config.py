"""Derive candidate identity from the bundled source, never from a prior CI pass."""
from pathlib import Path
import hashlib
import plistlib

def release_config(root):
    root = Path(root)
    source = root/'app/ios/ChampionsOnDevice'
    info_path = source/'Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    revision = 'R'+info['CFBundleVersion']
    files = sorted(source.glob('*.swift'))
    tree = hashlib.sha256(''.join(p.name+hashlib.sha256(p.read_bytes()).hexdigest() for p in files).encode()).hexdigest()
    return {'revision':revision,'slug':revision.lower(),'app_version':info['CFBundleShortVersionString'],
            'source_count':len(files),'source_tree_sha256':tree,
            'info_plist_sha256':hashlib.sha256(info_path.read_bytes()).hexdigest()}
