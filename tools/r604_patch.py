"""Fail-closed modification to the exact R603 one-tap writer seam."""
from pathlib import Path
import re
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
PAT=re.compile(r'(?m)^(?P<i>[ \t]*)let r602Entries = R602OneTapFormArchive\.beforeZip\(entries\)\n'
               r'(?P=i)let r603Entries = R603FormReadiness\.beforeZip\(r602Entries\)\n'
               r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
               r'(?P=i)    r603Entries, to: zipURL, work: exportWork\n'
               r'(?P=i)\)[ \t]*$')

def patch(root):
 p=Path(root)/TARGET;s=p.read_text();matches=list(PAT.finditer(s))
 if len(matches)!=1 or 'R604HistoricalFeatureArchive.beforeZip' in s:
  raise ValueError('R604_SOURCE_SEAM_NOT_EXACT_OR_DUPLICATE')
 if 'var actorAppearanceSamples=[[String:Any]]()' not in s:
  raise ValueError('R594_CAPTURE_SOURCE_NOT_PRESENT')
 m=matches[0];i=m.group('i')
 replacement=(i+'let r602Entries = R602OneTapFormArchive.beforeZip(entries)\n'
              +i+'let r603Entries = R603FormReadiness.beforeZip(r602Entries)\n'
              +i+'let r604Entries = R604HistoricalFeatureArchive.beforeZip(\n'
              +i+'    r603Entries, samples: actorAppearanceSamples\n'
              +i+')\n'
              +i+'_ = try R548ResearchArchive.write(\n'
              +i+'    r604Entries, to: zipURL, work: exportWork\n'+i+')')
 p.write_text(s[:m.start()]+replacement+s[m.end():]);return p
if __name__=='__main__':print(patch('.'))
