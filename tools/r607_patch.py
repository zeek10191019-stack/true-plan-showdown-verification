"""Only replace the verified pre-ZIP seam after R605; reject drift."""
from pathlib import Path
import re
TARGET=Path('app/ios/ChampionsOnDevice/CaptureCoordinator.swift')
PAT=re.compile(
 r'(?m)^(?P<i>[ \t]*)let r605Entries = R605ExactFrameBinding\.beforeZip\(r604Entries\)\n'
 r'(?P=i)_ = try R548ResearchArchive\.write\(\n'
 r'(?P=i)    r605Entries, to: zipURL, work: exportWork\n'
 r'(?P=i)\)[ \t]*$'
)
def patch(root):
    p=Path(root)/TARGET
    s=p.read_text(encoding='utf-8')
    m=list(PAT.finditer(s))
    if len(m)!=1 or 'R607FrameProvenanceAudit.beforeZip(' in s:
        raise ValueError('R607_PRODUCTION_SOURCE_SEAM_MISMATCH_OR_DUPLICATE')
    x=m[0]; i=x.group('i')
    new=(i+'let r605Entries = R605ExactFrameBinding.beforeZip(r604Entries)\n'
       +i+'let r607Entries = R607FrameProvenanceAudit.beforeZip(r605Entries)\n'
       +i+'_ = try R548ResearchArchive.write(\n'
       +i+'    r607Entries, to: zipURL, work: exportWork\n'
       +i+')')
    result=s[:x.start()]+new+s[x.end():]
    assert result.count('R607FrameProvenanceAudit.beforeZip(')==1
    p.write_text(result,encoding='utf-8')
    return p
