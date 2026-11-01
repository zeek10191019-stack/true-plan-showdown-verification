"""R600 read-only Swift source investigation. Reports *candidate* call sites, never patches.

Run after exact SHA-pinned R599 replay. No fabricated production integration.
"""
from __future__ import annotations
import hashlib
import json
import re
import sys
from pathlib import Path

KEY = re.compile(r"collect|export|archive|manifest|diagnostic|capture|zip|one.?button|share|snapshot|png|feature|appearance",re.I)
DECL = re.compile(r"\b(?:func|init|class|struct|enum|extension)\s+([A-Za-z_][A-Za-z0-9_]*)")
CALL = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(")
EXCLUDE = {"if","while","guard","switch","for","catch","return","print","assert","super","Task"}


def trace(base: str | Path) -> dict:
    root=Path(base)/"app/ios/ChampionsOnDevice"
    files=sorted(root.glob('*.swift'))
    result={"schema":"trueplan.r600.swift_source_trace.v1", "swift_file_count":len(files),
       "r595_source_present":False,"r595_source_sha256":None,
       "r595_feature_contract":"HOLD_NEEDS_NUMERIC_GOLDEN_VECTOR",
       "one_button_production_invocation":"NOT_PROVEN",
       "candidate_declarations":[], "callsites":[], "source_tree_sha256":None}
    if not files:return result
    h=hashlib.sha256()
    names=set()
    rows=[]
    for f in files:
        data=f.read_bytes()
        h.update(f.name.encode()+b'\0'+hashlib.sha256(data).digest())
        if f.name.startswith("R59") or f.name.startswith("R600"):continue
        for num,line in enumerate(data.decode('utf8').splitlines(),1):
            d=DECL.search(line)
            if d and KEY.search(d.group(1)):
                names.add(d.group(1))
                rows.append((f.name,num,line.strip()[:240],d.group(1)))
    result["source_tree_sha256"]=h.hexdigest()
    result["candidate_declarations"]=[{"file":f,"line":line,"declaration":txt,"symbol":symbol}
       for f,line,txt,symbol in rows[:150]]
    for f in files:
        if f.name.startswith("R59") or f.name.startswith("R600"):continue
        for num,line in enumerate(f.read_text('utf8').splitlines(),1):
            if any(re.search(r'\b'+re.escape(s)+r'\s*\(',line) for s in names):
                if DECL.search(line):continue
                if KEY.search(line) or len(names)<25:
                    result["callsites"].append({"file":f.name,"line":num,"text":line.strip()[:220]})
            if len(result["callsites"])>=150:break
    src=root/'R595FormReferenceMatcher.swift'
    if src.is_file():
        content=src.read_text('utf8')
        result['r595_source_present']=True
        result['r595_source_sha256']=hashlib.sha256(content.encode()).hexdigest()
        result['r595_feature_related_lines']=[{"line":i,"text":x.strip()[:220]}
          for i,x in enumerate(content.splitlines(),1) if re.search(r'16|12|vector|feature|pixel|grayscale|luminance|normalize|resize|scale|RGB|ROI',x,re.I)][:75]
    # More information is useful, but not evidence of a live UI callsite.
    return result

if __name__=='__main__':
    print(json.dumps(trace(sys.argv[1] if len(sys.argv)>1 else '.'),ensure_ascii=False,indent=2))
