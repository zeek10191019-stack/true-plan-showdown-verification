"""Insert exactly one verified R605 post-R604 hook in original one-button seam."""
import re
from pathlib import Path
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
PAT=re.compile(r'(?m)^(?P<i>[ \t]*)let r604Entries = R604HistoricalFeatureArchive\.beforeZip\(\n'
 r'(?P=i)    r603Entries, samples: actorAppearanceSamples\n'
 r'(?P=i)\)\n'
 r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
 r'(?P=i)    r604Entries, to: zipURL, work: exportWork\n'
 r'(?P=i)\)[ \t]*$')
def patch(root):
 p=Path(root)/TARGET;src=p.read_text();hits=list(PAT.finditer(src))
 if len(hits)!=1 or 'R605ExactFrameBinding.beforeZip(' in src:
  raise ValueError('R605_PRODUCTION_SEAM_CHANGED_OR_DUPLICATED')
 m=hits[0];i=m.group('i');s=(i+'let r604Entries = R604HistoricalFeatureArchive.beforeZip(\n'
   +i+'    r603Entries, samples: actorAppearanceSamples\n'+i+')\n'
   +i+'let r605Entries = R605ExactFrameBinding.beforeZip(r604Entries)\n'
   +i+'_ = try R548ResearchArchive.write(\n'+i+'    r605Entries, to: zipURL, work: exportWork\n'+i+')')
 p.write_text(src[:m.start()]+s+src[m.end():]);return p
if __name__=='__main__':print(patch('.'))
