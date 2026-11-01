"""R604 fail-closed source audit of R594/R595 feature producer & one-tap path.
Only source signatures, anchor summaries and internal SHA-256, not source bodies.
"""
from pathlib import Path
import hashlib,json,re,sys
ROOT=Path('app/ios/ChampionsOnDevice')
TARGETS=['R594ActorAppearance.swift','R595FormReferenceMatcher.swift',
         'CaptureCoordinator.swift','R602OneTapFormArchive.swift','R603FormReadiness.swift']
TERMS=re.compile(r'(?i)feature|raster|luma|crop|actor|frame|pixel|roi|export|appearance|archive')
FUN=re.compile(r'\b(?:func|static\s+func|private\s+func|struct|enum)\s+([a-zA-Z_]\w*)')

def audit(root=ROOT):
    result={'schema':'trueplan.r604.feature_source.v1',
            'producer_callsite_certified':False,
            'numeric_parity_certified':False,
            'runtime_frame_crop_wired':False,'files':[]}
    for name in TARGETS:
        path=Path(root)/name
        if not path.is_file():raise ValueError('SOURCE_FILE_MISSING:'+name)
        data=path.read_bytes();lines=data.decode('utf-8').splitlines()
        symbols=[]
        for i,line in enumerate(lines,1):
            match=FUN.search(line)
            if match and (TERMS.search(line) or name in TARGETS[3:]):
                symbols.append({'symbol':match.group(1),'line':i})
        if name=='CaptureCoordinator.swift':
            one=[i for i,line in enumerate(lines,1)
                 if 'R604FrameFeatureEvidence.stage' in line]
            legacy=[i for i,line in enumerate(lines,1)
                    if 'R603FormReadiness.beforeZip' in line]
            result['existing_one_tap_hook_count']=len(legacy)
            result['r604_producer_hook_count']=len(one)
        result['files'].append({'file':name,'bytes':len(data),
                'sha256':hashlib.sha256(data).hexdigest(),
                'functions':symbols[:65]})
    assert result['existing_one_tap_hook_count']==1,'R603_HOOK_MISSING_OR_DUPLICATED'
    # The API exists, but until the caller provides a provably fresh crop and
    # R595 features bound to the same epoch/frame no production-ready claim.
    result['status']='HOLD_REAL_FRAME_FEATURE_CALLER_NOT_PROVEN'
    return result

if __name__=='__main__':
    out=audit()
    Path('r604_source_trace.json').write_text(json.dumps(out,indent=2))
    print('R604_SOURCE_CONTRACT',json.dumps(out,separators=(',',':'))[:10500])
