#!/usr/bin/env python3
"""Read-only R597 admission audit; never asserts that image form recognition is certified.

Deliberately does not invent image vectors or download copyrighted game frames.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
from collections import defaultdict

SCHEMA = 'trueplan.r596.visual_catalog.v1'
EXTRACTOR = 'R595-16x12-unverified-scale'


def audit(catalog: dict) -> dict:
    if not isinstance(catalog, dict) or catalog.get('schema') != SCHEMA or not isinstance(catalog.get('references'), list):
        raise ValueError('R597_CATALOG_SCHEMA_INVALID')
    seen_ids, seen_hashes = set(), set()
    sessions = defaultdict(set)
    session_labels = defaultdict(set)
    holds = set()
    for entry in catalog['references']:
        if not isinstance(entry, dict):
            raise ValueError('R597_REFERENCE_NOT_OBJECT')
        rid = entry.get('referenceID')
        h = entry.get('imageSHA256')
        if not isinstance(rid, str) or not rid or rid in seen_ids:
            raise ValueError('R597_ID_MISSING_OR_DUPLICATE')
        if not isinstance(h, str) or len(h)!=64 or any(c not in '0123456789abcdef' for c in h) or h in seen_hashes:
            raise ValueError('R597_SHA_INVALID_OR_DUPLICATE')
        seen_ids.add(rid);seen_hashes.add(h)
        if entry.get('sourceKind')!='champions-screen-capture' or entry.get('labelEvidence')!='human-confirmed':
            raise ValueError('R597_SOURCE_OR_LABEL_UNVERIFIED')
        if entry.get('extractorID')!=EXTRACTOR:
            raise ValueError('R597_EXTRACTOR_INCOMPATIBLE')
        if entry.get('captureSide') not in ('own','opponent'):
            raise ValueError('R597_SIDE_UNVERIFIED')
        if entry.get('formID') not in ('normal','mega','mega-x','mega-y','mega-z'):
            raise ValueError('R597_FORM_INVALID')
        if not isinstance(entry.get('sessionID'),str) or not entry['sessionID']:
            raise ValueError('R597_SESSION_MISSING')
        if not isinstance(entry.get('speciesID'),str) or not entry['speciesID']:
            raise ValueError('R597_SPECIES_MISSING')
        v=entry.get('features')
        if not isinstance(v,list) or len(v)!=192 or any(type(n) not in (int,float) or not math.isfinite(n) or abs(n)>1e6 for n in v):
            raise ValueError('R597_FEATURES_INVALID')
        key = f"{entry['speciesID']}/{entry['formID']}/{entry['captureSide']}"
        sessions[key].add(entry['sessionID'])
        session_labels[(entry['sessionID'], entry['captureSide'], entry.get('frameID'))].add((entry['speciesID'],entry['formID']))
    for labels in session_labels.values():
        if len(labels)>1:
            holds.add('CONFLICTING_LABELS_IN_SAME_FRAME')
    ready = sorted(k for k,v in sessions.items() if len(v)>=2)
    if not ready:
        holds.add('INSUFFICIENT_INDEPENDENT_SESSIONS')
    # This isn't a trusted ML evaluation: withheld battles and independently labelled
    # real-game images are absent. 'READY' is never returned.
    holds.update(['R595_FEATURE_REPRESENTATION_UNVERIFIED', 'REAL_GAME_HELDOUT_NOT_CERTIFIED',
                  'IOS_ONE_BUTTON_WIRING_UNVERIFIED'])
    return {'schema':'trueplan.r597.catalog_audit.v1','references':len(seen_ids),
            'distinctFormsWithTwoSessions':ready,'independentSessionCounts':{k:len(v) for k,v in sorted(sessions.items())},
            'status':'HOLD','holds':sorted(holds),'canDeclareMega':False}


def audit_files(catalog_path:Path, output_path:Path):
    catalog=json.loads(catalog_path.read_text(encoding='utf-8'))
    report=audit(catalog)
    # No screenshots or crops are included in report.
    output_path.parent.mkdir(parents=True,exist_ok=True)
    output_path.write_text(json.dumps(report,ensure_ascii=False,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    return report


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--catalog',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    print(json.dumps(audit_files(a.catalog,a.output),ensure_ascii=False))

if __name__=='__main__': main()
