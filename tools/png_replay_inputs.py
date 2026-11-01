"""Prepare label-free exact-PNG inputs for the shared Swift reader. Offline only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from screen_read_corpus import safe_path,read_json
from screen_read_metrics import token
from verify_screen_evidence import _png,integer,is_sha

SCHEMA='trueplan.screen-read.png-replay-inputs.v1'
MAX_IMAGES=64

def need(ok,reason):
    if not ok:raise ValueError('PNG_REPLAY_INPUT_'+reason)

def prepare_inputs(root,rows):
    root=Path(root);need(isinstance(rows,list) and 1<=len(rows)<=MAX_IMAGES,'COUNT')
    result=[];ids=set();digests=set();paths=set()
    for row in rows:
        fields={'sample_id','path','sha256','bytes','width','height'}
        need(isinstance(row,dict) and set(row)==fields,'FIELDS')
        ident,name=row['sample_id'],row['path']
        need(token(ident) and ident not in ids,'IDENTITY')
        need(isinstance(name,str) and re.fullmatch(r'[A-Za-z0-9_./-]{1,120}\.png',name) is not None and name.casefold() not in paths,'PATH')
        path=safe_path(root,name)
        need(integer(row['bytes'],1) and row['bytes']<=12_000_000 and path.stat().st_size==row['bytes'],'BYTE_COUNT')
        data=path.read_bytes();digest=hashlib.sha256(data).hexdigest()
        need(is_sha(row['sha256']) and digest==row['sha256'] and digest not in digests,'SHA_OR_DUPLICATE_IMAGE')
        _png(data,row['width'],row['height'])
        ids.add(ident);digests.add(digest);paths.add(name.casefold());result.append(dict(row))
    return dict(schema=SCHEMA,samples=result)

def validate_inputs(root,document):
    need(isinstance(document,dict) and set(document)=={'schema','samples'} and document.get('schema')==SCHEMA,'DOCUMENT')
    return prepare_inputs(root,document['samples'])

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--corpus-audit',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    audit=read_json(args.corpus_audit)
    need(audit.get('schema')=='trueplan.screen-read.corpus-audit.v1' and isinstance(audit.get('frames'),list),'CORPUS_AUDIT')
    rows=[{k:frame[k] for k in ('sample_id','path','sha256','bytes','width','height')} for frame in audit['frames']]
    result=prepare_inputs(args.root,rows)
    with args.output.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2);f.write('\n')
    print('LABEL_FREE_PNG_REPLAY_INPUTS_READY',len(rows),'images; NO_OCR_EXECUTED')

if __name__=='__main__':main()
