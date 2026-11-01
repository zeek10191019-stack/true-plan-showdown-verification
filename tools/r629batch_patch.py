"""Atomic exact-anchor R629 annotation patch; production writer is unchanged."""
from pathlib import Path
import hashlib
TARGET=Path('app/ios/ChampionsOnDevice/R625R628PixelHUDAndSprite.swift')
ORIGINAL_SHA='83f6cc37815ede7066ced44b3db326f7c572ba22557c4516882d1969142e1370'
ANCHOR='        prior[embeddedKey]=report\n        guard let data=try? JSONSerialization.data(withJSONObject:prior,options:[.sortedKeys]),'
REPLACEMENT='        prior[embeddedKey]=report\n        R629R632SlotEvidence.enrich(&prior)\n        guard let data=try? JSONSerialization.data(withJSONObject:prior,options:[.sortedKeys]),'

def patch(root):
    path=Path(root)/TARGET
    content=path.read_bytes()
    if hashlib.sha256(content).hexdigest()!=ORIGINAL_SHA:raise ValueError('R625_SOURCE_SHA_DRIFT')
    old=content.decode('utf-8')
    if old.count(ANCHOR)!=1 or old.count(REPLACEMENT)!=0:raise ValueError('ANNOTATION_SEAM_DRIFT')
    new=old.replace(ANCHOR,REPLACEMENT,1)
    assert new.count('R629R632SlotEvidence.enrich(&prior)')==1
    path.write_text(new)
    return path
