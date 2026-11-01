"""Verify existing development images and convert provisional labels for scoring.

No OCR, model, network, inferred owner/identity, or holdout certification. Explicit
recording groups are required; filename similarity alone is not independence.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import tempfile
from screen_read_metrics import DATA_SCHEMA, validate_dataset, token, sha
from verify_screen_evidence import _png, parse_json

MAX_IMAGE_BYTES=12_000_000

def need(condition,reason):
    if not condition:raise ValueError('CORPUS_'+reason)

def integer(value,minimum,maximum):return type(value) is int and minimum<=value<=maximum

def safe_path(root,name):
    need(isinstance(name,str) and 0<len(name)<=256,'PATH')
    relative=PurePosixPath(name)
    need(not relative.is_absolute() and '..' not in relative.parts and '\\' not in name and name==relative.as_posix(),'PATH')
    path=root/name
    need(not path.is_symlink() and path.resolve().is_relative_to(root.resolve()) and path.is_file(),'PATH_ESCAPE_OR_MISSING')
    return path

def read_json(path):
    need(0<path.stat().st_size<=2_000_000,'JSON_SIZE')
    return parse_json(path.read_bytes())

def import_legacy(root,recording_groups):
    root=Path(root)
    labels_path=root/'R551_VISUAL_GROUND_TRUTH.json';manifest_path=root/'FIXTURE_MANIFEST.json'
    labels=read_json(labels_path);manifest=read_json(manifest_path)
    need(isinstance(labels,dict) and labels.get('current_app_accuracy_certified') is False,'NO_LEGACY_APP_CERTIFICATION')
    frames=labels.get('frames');fixtures=manifest.get('fixtures')
    need(isinstance(frames,list) and 1<=len(frames)<=64 and isinstance(fixtures,list) and len(frames)==len(fixtures),'FRAME_COUNT')
    need(isinstance(recording_groups,dict),'EXPLICIT_RECORDING_GROUPS')
    entries={}
    for entry in fixtures:
        need(isinstance(entry,dict) and isinstance(entry.get('path'),str),'MANIFEST_ROW')
        name='fixtures/'+entry['path'];need(name not in entries,'DUPLICATE_MANIFEST')
        need(token(entry.get('domain')) and integer(entry.get('timestamp_ms'),0,2**63-1),'MANIFEST_DOMAIN_OR_TIMESTAMP')
        entries[name]=entry
    need(set(recording_groups)==set(entries),'GROUP_MAP_COVERAGE')
    samples=[];receipts=[];seen=set();domains={}
    for frame in frames:
        need(isinstance(frame,dict) and isinstance(frame.get('path'),str),'FRAME_ROW')
        name=frame['path'];need(name in entries and name.casefold() not in seen,'FRAME_MANIFEST_COVERAGE');seen.add(name.casefold())
        entry=entries[name];group=recording_groups[name];need(token(group),'GROUP_ID')
        need(group not in domains or domains[group]==entry['domain'],'RECORDING_DOMAIN_DISAGREEMENT');domains[group]=entry['domain']
        path=safe_path(root,name);need(0<path.stat().st_size<=MAX_IMAGE_BYTES,'IMAGE_SIZE')
        data=path.read_bytes();digest=hashlib.sha256(data).hexdigest()
        need(sha(frame.get('sha256')) and frame['sha256']==entry.get('sha256')==digest,'IMAGE_SHA')
        width,height=frame.get('width'),frame.get('height')
        need(integer(width,1,3072) and integer(height,1,3072),'IMAGE_DIMENSIONS')
        _png(data,width,height)
        need(frame.get('label_source')=='DIRECT_VISUAL_REVIEW_IN_THIS_SESSION' and frame.get('current_app_Vision_prediction') is None,'LEGACY_LABEL_SCOPE')
        current,maximum,percent=frame.get('own_hp'),frame.get('own_max_hp'),frame.get('opponent_hp_percent')
        need(integer(maximum,1,9999) and integer(current,0,maximum),'HP_LABEL')
        need(type(percent) in (int,float) and math.isfinite(percent) and 0<=percent<=100,'PERCENT_LABEL')
        moves,pp=frame.get('moves'),frame.get('pp_current_maximum')
        need(isinstance(moves,list) and len(moves)==4 and all(isinstance(m,str) and 0<len(m.encode())<=128 for m in moves),'MOVE_LABELS')
        need(isinstance(pp,list) and len(pp)==4,'PP_LABELS')
        for pair in pp:need(isinstance(pair,list) and len(pair)==2 and integer(pair[1],1,99) and integer(pair[0],0,pair[1]),'PP_LABEL')
        screen=frame.get('screen_kind');need(token(screen),'SCREEN_CLASS')
        def label(field,value,side='field',slot=None,visibility='PRESENT'):
            return dict(field=field,slot=slot,side=side,visibility=visibility,value=value)
        converted=[label('own_hp',dict(current=current,maximum=maximum),'own'),label('opponent_hp',percent,'opponent'),label('screen_class',screen)]
        for index in range(4):
            converted.extend([label('move_name',moves[index],'own',index),label('move_pp',dict(current=pp[index][0],maximum=pp[index][1]),'own',index)])
        for field in ('mega_form','major_status','field_state','battle_id','turn'):
            need(frame.get(field) is None,'UNREVIEWED_LEGACY_VALUE')
            converted.append(label(field,None,'UNKNOWN_OWNER',visibility='UNKNOWN'))
        identity='legacy:'+Path(name).stem
        samples.append(dict(sample_id=identity,image_sha256=digest,capture_group_id=group,split='development',
            label_origin='LEGACY_PROVISIONAL_VISUAL_REVIEW',screen_class=screen,capture_domain=entry['domain'],labels=converted))
        receipts.append(dict(sample_id=identity,path=name,sha256=digest,bytes=len(data),width=width,height=height,
            capture_group_id=group,declared_video_timestamp_ms=entry['timestamp_ms']))
    dataset=dict(schema=DATA_SCHEMA,dataset_id='legacy-r385-provisional-development',samples=samples)
    validate_dataset(dataset)
    audit=dict(schema='trueplan.screen-read.corpus-audit.v1',source='LEGACY_R385_EXISTING_PRIVATE_DEVELOPMENT_ASSETS',
        original_labels_sha256=hashlib.sha256(labels_path.read_bytes()).hexdigest(),original_manifest_sha256=hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        images=len(samples),capture_groups=len(domains),positive_labels=sum(l['visibility']=='PRESENT' for s in samples for l in s['labels']),
        unknown_labels=sum(l['visibility']=='UNKNOWN' for s in samples for l in s['labels']),sealed_holdout_images=0,
        image_CRC_SHA_and_dimensions='PASS',label_status='PRIOR_PROVISIONAL_VISUAL_REVIEW_NOT_REANNOTATED',
        capture_group_provenance='EXPLICIT_LEGACY_RECORDING_MAP_NOT_SOURCE_VIDEO_HASH_ATTESTED',
        current_app_executed=False,game_accuracy_certified=False,owner_certified=False,identity_certified=False,device_certified=False,frames=receipts)
    return dataset,audit

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--legacy-root',type=Path,required=True)
    parser.add_argument('--groups',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    dataset,audit=import_legacy(args.legacy_root,read_json(args.groups))
    need(not args.output.exists(),'OUTPUT_EXISTS');args.output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent,prefix='.corpus_stage_') as temporary:
        stage=Path(temporary)/'ready';stage.mkdir()
        for name,value in [('labels.json',dataset),('CORPUS_AUDIT.json',audit)]:
            (stage/name).write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
        stage.rename(args.output)
    print('CORPUS_VERIFIED',audit['images'],'images',audit['capture_groups'],'declared recordings; LEGACY_DEVELOPMENT_ONLY_NO_RECOGNITION_CERTIFICATION')

if __name__=='__main__':main()
