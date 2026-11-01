"""Score labelled exported observations without inventing recognition accuracy.

Value candidates, owner assertions and capture groups have separate denominators.
The scorer never certifies label correctness, holdout independence or real games.
No model, network, SDK, image upload or third-party dependency is used.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

DATA_SCHEMA='trueplan.screen-read.evaluation-set.v1'
REPORT_SCHEMA='trueplan.screen-read.evaluation-report.v1'
SPLITS={'development','sealed_holdout'}
SIDES={'own','opponent','field','UNKNOWN_OWNER'}
MAX_SAMPLES=10000

def need(condition,reason):
    if not condition:raise ValueError('EVALUATION_'+reason)

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)

def token(value):return isinstance(value,str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}',value) is not None

def sha(value):return isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value) is not None

def sample_stratum(sample,name):
    value=sample.get(name,'UNSPECIFIED')
    need(token(value),'SAMPLE_'+name.upper())
    return value

def elapsed_summary(rows):
    """Nearest-rank percentiles for the same declared processing scope only.

    No capture timestamp subtraction, compile timings, or live-latency claim.
    """
    grouped={}
    for row in rows:
        timing=row.get('processing_time')
        if timing is None:continue
        need(isinstance(timing,dict) and set(timing)=={'clock_basis','scope','elapsed_ms'},'PROCESSING_TIME_FIELDS')
        need(timing['clock_basis']=='HOST_MONOTONIC_ELAPSED','PROCESSING_TIME_CLOCK')
        need(isinstance(timing['scope'],str) and timing['scope'] in {'OCR_REQUEST','OFFLINE_FRAME_PIPELINE'},'PROCESSING_TIME_SCOPE')
        value=timing['elapsed_ms']
        need(type(value) in (int,float) and math.isfinite(value) and 0<=value<=3_600_000,'PROCESSING_TIME_VALUE')
        grouped.setdefault(timing['scope'],[]).append(value)
    summaries={}
    for scope,values in sorted(grouped.items()):
        values=sorted(values);size=len(values)
        def percentile(p):return values[max(0,math.ceil(p*size)-1)]
        summaries[scope]=dict(measured_samples=size,minimum_ms=values[0],mean_ms=sum(values)/size,
            p50_ms=percentile(.5),p95_ms=percentile(.95),maximum_ms=values[-1],percentile_method='NEAREST_RANK')
    return dict(samples_with_measurement=sum(map(len,grouped.values())),samples_without_measurement=len(rows)-sum(map(len,grouped.values())),
        per_scope=summaries,clock_basis='HOST_MONOTONIC_ELAPSED',attestation='SELF_REPORTED_NOT_ATTESTED',
        capture_to_display_latency_certified=False,device_latency_certified=False)

def field_key(row):
    name=row.get('field');slot=row.get('slot')
    need(token(name),'FIELD_NAME')
    need('slot' in row and (slot is None or type(slot) is int and 0<=slot<4),'FIELD_SLOT')
    return name,slot

def literal(value):
    need(value is not None,'NULL_PRESENT_VALUE')
    if type(value) is int:need(-(2**63)<value<2**63,'INTEGER_RANGE')
    if type(value) is float:need(math.isfinite(value),'NONFINITE_VALUE')
    need(len(canonical(value).encode())<=4096,'VALUE_SIZE')
    return canonical(value)

def validate_dataset(dataset):
    need(isinstance(dataset,dict) and dataset.get('schema')==DATA_SCHEMA and token(dataset.get('dataset_id')),'DATASET')
    samples=dataset.get('samples');need(isinstance(samples,list) and 1<=len(samples)<=MAX_SAMPLES,'SAMPLE_COUNT')
    ids=set();images=set();groups={}
    for sample in samples:
        need(isinstance(sample,dict) and token(sample.get('sample_id')),'SAMPLE_ID')
        identity=sample['sample_id'];image=sample.get('image_sha256');group=sample.get('capture_group_id');split=sample.get('split')
        need(identity not in ids and sha(image) and image not in images,'DUPLICATE_SAMPLE_OR_IMAGE')
        need(token(group) and split in SPLITS,'GROUP_OR_SPLIT')
        need(group not in groups or groups[group]==split,'CAPTURE_GROUP_SPLIT_LEAKAGE')
        need(sample.get('label_origin') in {'HUMAN_REVIEWED_VISIBLE_PIXELS','SYNTHETIC_CONTRACT','LEGACY_PROVISIONAL_VISUAL_REVIEW'},'LABEL_ORIGIN')
        sample_stratum(sample,'screen_class');sample_stratum(sample,'capture_domain')
        ids.add(identity);images.add(image);groups[group]=split
        labels=sample.get('labels');need(isinstance(labels,list) and 1<=len(labels)<=128,'LABEL_COUNT')
        fields=set()
        for label in labels:
            need(isinstance(label,dict),'LABEL');key=field_key(label)
            need(key not in fields,'DUPLICATE_LABEL');fields.add(key)
            need(label.get('visibility') in {'PRESENT','ABSENT','UNKNOWN'},'VISIBILITY')
            need(label.get('side') in SIDES,'LABEL_SIDE')
            need('value' in label,'LABEL_VALUE_REQUIRED')
            if label['visibility']=='PRESENT':literal(label['value'])
            else:need(label['value'] is None,'NONPRESENT_VALUE')
    return samples

def _counts():
    return dict(positive_labels=0,negative_labels=0,unknown_labels=0,value_tp=0,value_fp=0,value_fn=0,value_tn=0,
        attempted_positive_labels=0,owner_labels=0,owner_returned=0,owner_correct=0,unlabelled_predictions=0,
        current_state_assertions=0,identity_assertions=0)

def equal_literal(first,second):
    if type(first) in (int,float) and type(second) in (int,float):return first==second
    return canonical(first)==canonical(second)

def _finish(counts):
    def ratio(a,b):return a/b if b else None
    result=dict(counts)
    result.update(value_precision=ratio(counts['value_tp'],counts['value_tp']+counts['value_fp']),
        value_recall=ratio(counts['value_tp'],counts['positive_labels']),
        value_coverage=ratio(counts['attempted_positive_labels'],counts['positive_labels']),
        owner_accuracy_among_assertions=ratio(counts['owner_correct'],counts['owner_returned']),
        owner_coverage=ratio(counts['owner_returned'],counts['owner_labels']))
    return result

def evaluate(dataset,predictions):
    samples=validate_dataset(dataset)
    need(isinstance(predictions,list) and len(predictions)<=len(samples),'PREDICTION_COUNT')
    expected={s['sample_id']:s for s in samples};by_sample={};reader_versions=set()
    for prediction in predictions:
        need(isinstance(prediction,dict) and token(prediction.get('sample_id')) and prediction['sample_id'] in expected,'PREDICTION_SAMPLE')
        identity=prediction['sample_id'];need(identity not in by_sample,'DUPLICATE_PREDICTION')
        need(prediction.get('reader_status','NORMALIZED_OBSERVATIONS') in {
            'NORMALIZED_OBSERVATIONS','SOURCE_BOUND_LITERAL_CANDIDATES','NO_SOURCE_BOUND_VALUES',
            'NO_STRUCTURED_STATE','OCR_FAILURE_RECORDED'},'READER_STATUS')
        need(prediction.get('image_sha256')==expected[identity]['image_sha256'],'PREDICTION_IMAGE_BINDING')
        need(isinstance(prediction.get('source'),dict) and prediction['source'].get('kind') in {'APP_EVIDENCE_ZIP','PNG_REPLAY_ZIP','OFFLINE_PNG_DIAGNOSTIC_ZIP','SYNTHETIC_CONTRACT'},'PREDICTION_SOURCE')
        if prediction['source']['kind'] in {'APP_EVIDENCE_ZIP','PNG_REPLAY_ZIP','OFFLINE_PNG_DIAGNOSTIC_ZIP'}:
            origin=prediction['source'];need(sha(origin.get('archive_sha256')),'ARCHIVE_SHA')
            need(all(isinstance(origin.get(k),str) and 0<len(origin[k])<=128 for k in ('app_version','app_build','engine_version')),'READER_VERSION')
            reader_versions.add((origin['kind'],origin['app_version'],origin['app_build'],origin['engine_version']))
        else:reader_versions.add(('SYNTHETIC_CONTRACT',))
        need(len(reader_versions)<=1,'MIXED_READER_VERSIONS')
        fields=prediction.get('fields');need(isinstance(fields,list) and len(fields)<=128,'PREDICTION_FIELDS')
        seen=set()
        for field in fields:
            need(isinstance(field,dict),'PREDICTION_FIELD');key=field_key(field)
            need(key not in seen,'DUPLICATE_PREDICTED_FIELD');seen.add(key)
            need(field.get('side') in SIDES,'PREDICTED_SIDE')
            need(type(field.get('current_state_eligible')) is bool and type(field.get('identity_certified')) is bool,'PREDICTION_CLAIM_TYPES')
            need('value' in field,'PREDICTED_VALUE_REQUIRED')
            if field['value'] is not None:literal(field['value'])
            if field['side'] in {'own','opponent'}:need(field['value'] is not None,'OWNER_WITHOUT_VALUE')
        by_sample[identity]=prediction
    # Validate timing even for failed/empty readers, and retain their measurements.
    timing=elapsed_summary(predictions)
    overall=_counts();group_counts={};split_counts={};domain_counts={};class_counts={};capture_counts={};sample_counts=[]
    for sample in samples:
        counters=_counts();prediction=by_sample.get(sample['sample_id'])
        fields={field_key(f):f for f in prediction['fields']} if prediction else {}
        label_keys={field_key(l) for l in sample['labels']}
        counters['unlabelled_predictions']=sum(f['value'] is not None for k,f in fields.items() if k not in label_keys)
        counters['current_state_assertions']=sum(f['current_state_eligible'] for f in fields.values())
        counters['identity_assertions']=sum(f['identity_certified'] for f in fields.values())
        for label in sample['labels']:
            local=_counts();key=field_key(label);field=fields.get(key)
            returned=field is not None and field['value'] is not None
            if label['visibility']=='UNKNOWN':local['unknown_labels']=1
            elif label['visibility']=='ABSENT':
                local['negative_labels']=1;local['value_fp' if returned else 'value_tn']=1
            else:
                local['positive_labels']=1;local['attempted_positive_labels']=int(returned)
                correct=returned and equal_literal(field['value'],label['value'])
                local['value_tp']=int(correct);local['value_fn']=int(not correct)
                local['value_fp']=int(returned and not correct)
                if label['side'] in {'own','opponent'}:
                    local['owner_labels']=1
                    owner_returned=returned and field['side'] in {'own','opponent'}
                    local['owner_returned']=int(owner_returned)
                    local['owner_correct']=int(owner_returned and field['side']==label['side'])
            for name,value in local.items():counters[name]+=value
            target=domain_counts.setdefault(label['field'],_counts())
            for name,value in local.items():target[name]+=value
        for target in [overall,group_counts.setdefault(sample['capture_group_id'],_counts()),split_counts.setdefault(sample['split'],_counts()),
                class_counts.setdefault(sample_stratum(sample,'screen_class'),_counts()),capture_counts.setdefault(sample_stratum(sample,'capture_domain'),_counts())]:
            for name,value in counters.items():target[name]+=value
        sample_counts.append(dict(sample_id=sample['sample_id'],metrics=_finish(counters),prediction_received=prediction is not None,
            reader_status=prediction.get('reader_status','NORMALIZED_OBSERVATIONS') if prediction else 'NO_ARCHIVE_PROVIDED',
            declared_screen_class=sample_stratum(sample,'screen_class'),declared_capture_domain=sample_stratum(sample,'capture_domain')))
    groups={k:_finish(v) for k,v in sorted(group_counts.items())}
    recalls=[v['value_recall'] for v in groups.values() if v['value_recall'] is not None]
    return dict(schema=REPORT_SCHEMA,dataset_id=dataset['dataset_id'],
        scope='DECLARED_LABELS_AND_EXPORTED_VALUE_CANDIDATES_ONLY_NOT_COMPLETE_RECOGNITION',
        dataset_sha256=hashlib.sha256(canonical(dataset).encode()).hexdigest(),
        predictions_sha256=hashlib.sha256(canonical(predictions).encode()).hexdigest(),
        samples=len(samples),unique_images=len(samples),capture_groups=len(group_counts),
        prediction_samples_received=len(predictions),prediction_samples_missing=len(samples)-len(predictions),
        reader_failure_samples=sum(p.get('reader_status')=='OCR_FAILURE_RECORDED' for p in predictions),
        reader_versions=[list(version) for version in sorted(reader_versions)],
        label_origins=sorted({s['label_origin'] for s in samples}),
        overall=_finish(overall),per_capture_group=groups,per_split={k:_finish(v) for k,v in sorted(split_counts.items())},
        per_domain={k:_finish(v) for k,v in sorted(domain_counts.items())},per_sample=sample_counts,
        per_declared_screen_class={k:_finish(v) for k,v in sorted(class_counts.items())},
        per_declared_capture_domain={k:_finish(v) for k,v in sorted(capture_counts.items())},
        processing_time={**timing,'samples_without_measurement':len(samples)-timing['samples_with_measurement']},
        macro_capture_group_value_recall=sum(recalls)/len(recalls) if recalls else None,
        holdout_independence='DECLARED_SPLIT_ONLY_NOT_ATTESTED',
        prediction_source_integrity='ARCHIVE_BYTES_VERIFIED_BY_CLI_ADAPTER_ONLY_NORMALIZED_CALLER_RECORDS_NOT_ATTESTED',
        label_correctness_certified=False,full_game_accuracy_certified=False,device_certified=False)

def prediction_from_archive(path,sample_id):
    """Use actual verified app exports; never manufacture a prediction from a label."""
    import zipfile
    from verify_offline_png_bundle import EXPECTED as OFFLINE_NAMES,verify_archive as verify_offline
    # The R578 offline bundle uses a different evidence format from live frame
    # archives. Dispatch only by its exact three-file member set. Never fall
    # back to a less strict parser after an offline-integrity failure.
    try:
        with zipfile.ZipFile(path) as _z:
            _is_offline=set(_z.namelist())==OFFLINE_NAMES
    except (OSError,zipfile.BadZipFile):
        _is_offline=False
    if _is_offline:
        proof=verify_offline(path)
        state=proof['snapshot'];report=state.get('owner_position_hints') or {}
        fields=[]
        if report.get('schema')=='trueplan.screen-read.source-bound-hints.v2' and report.get('status')=='PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION':
            for hint in report.get('hints',[]):
                need(hint.get('side')=='UNKNOWN_OWNER' and hint.get('current_state_eligible') is False and hint.get('identity_certified') is False,'OFFLINE_OWNER_ASSERTION')
                fields.append(dict(field=hint['role_hint'],slot=hint['slot'],value=hint['literal_value'],
                    side='UNKNOWN_OWNER',current_state_eligible=False,identity_certified=False))
        classification=state.get('screen_classification') or {}
        if classification.get('status')=='PRIMARY_AND_ALTERNATIVES_AGREE' and classification.get('screen_kind')!='unknown':
            fields.append(dict(field='screen_class',slot=None,value=classification['screen_kind'],
                side='field',current_state_eligible=False,identity_certified=False))
        return dict(sample_id=sample_id,image_sha256=proof['image_sha256'],fields=fields,
            reader_status='SOURCE_BOUND_LITERAL_CANDIDATES' if fields else 'NO_SOURCE_BOUND_VALUES',
            source=dict(kind='OFFLINE_PNG_DIAGNOSTIC_ZIP',archive_sha256=proof['archive_sha256'],
                app_version='OFFLINE',app_build='R578+',engine_version=state.get('screen_read_engine_version') or proof['payload'].get('ocr_engine_version') or 'UNKNOWN'))
    from verify_screen_evidence import verify_archive,parse_json
    receipt=verify_archive(path)
    with zipfile.ZipFile(path) as archive:
        selected=parse_json(archive.read('selected_evidence.json'));index=parse_json(archive.read('evidence_integrity.json'))
        manifest=parse_json(archive.read('capture_manifest.json'))
    state=selected.get('screen_read_state') or {}
    report=state.get('owner_position_hints') or {}
    fields=[]
    if report.get('schema')=='trueplan.screen-read.source-bound-hints.v2' and report.get('status')=='PROVISIONAL_SOURCE_BOUND_HINTS_NO_OWNER_CERTIFICATION':
        for hint in report['hints']:
            fields.append(dict(field=hint['role_hint'],slot=hint['slot'],value=hint['literal_value'],
                side=hint['side'],current_state_eligible=hint['current_state_eligible'],identity_certified=hint['identity_certified']))
    classification=state.get('screen_classification') or {}
    if classification.get('status')=='PRIMARY_AND_ALTERNATIVES_AGREE' and classification.get('screen_kind')!='unknown':
        fields.append(dict(field='screen_class',slot=None,value=classification['screen_kind'],side='field',
            current_state_eligible=False,identity_certified=False))
    analysis=selected.get('analysis_image') or {}
    image=state.get('image_sha256') or analysis.get('png_sha256') or selected['png_sha256']
    status='SOURCE_BOUND_LITERAL_CANDIDATES' if fields else 'NO_SOURCE_BOUND_VALUES' if state else 'NO_STRUCTURED_STATE'
    if not state and selected.get('r559_ocr_failure') is not None:status='OCR_FAILURE_RECORDED'
    result=dict(sample_id=sample_id,image_sha256=image,fields=fields,reader_status=status,
        source=dict(kind='APP_EVIDENCE_ZIP',archive_sha256=receipt['archive_sha256'],
            app_version=index.get('app_version','UNKNOWN'),app_build=index.get('app_build','UNKNOWN'),engine_version=state.get('screen_read_engine_version','UNKNOWN')))
    if 'png_replay' in selected or selected.get('source')=='offline_exact_png_replay':
        from verify_png_replay import validate_replay_record
        record=validate_replay_record(selected,index,manifest)
        need(record['sample_id']==sample_id,'REPLAY_SAMPLE_ID')
        result['source']['kind']='PNG_REPLAY_ZIP';result['source']['engine_version']=record['reader_policy_version']
        result['processing_time']=dict(record['processing_time'])
    return result

def attach_processing_times(predictions,records):
    """Attach optional durations to the exact sample, image AND evidence archive."""
    need(isinstance(records,list) and len(records)<=len(predictions),'TIMING_MAPPING_COUNT')
    known={p['sample_id']:p for p in predictions};seen=set();times={}
    for row in records:
        need(isinstance(row,dict) and set(row)=={'sample_id','image_sha256','archive_sha256','processing_time'},'TIMING_MAPPING_FIELDS')
        identity=row['sample_id'];need(token(identity) and identity in known and identity not in seen,'TIMING_MAPPING_SAMPLE')
        seen.add(identity);prediction=known[identity]
        need(row['image_sha256']==prediction['image_sha256'] and row['archive_sha256']==prediction['source']['archive_sha256'],'TIMING_MAPPING_BINDING')
        need(isinstance(row['processing_time'],dict),'TIMING_MAPPING_DURATION')
        elapsed_summary([row]);times[identity]=dict(row['processing_time'])
    return [{**p,**({'processing_time':times[p['sample_id']]} if p['sample_id'] in times else {})} for p in predictions]

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('dataset',type=Path)
    parser.add_argument('--archives',type=Path,required=True,help='JSON array of sample_id/path pairs; paths relative to this mapping file')
    parser.add_argument('--processing-times',type=Path,help='Optional self-reported durations bound to sample/image/archive SHA; never live-latency attestation')
    parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    from verify_screen_evidence import parse_json
    from verify_ci_publication import strict_json
    dataset=parse_json(args.dataset.read_bytes());validate_dataset(dataset)
    need(args.archives.stat().st_size<=2_000_000,'ARCHIVE_MAPPING_SIZE')
    mapping=strict_json(args.archives.read_text());need(isinstance(mapping,list),'ARCHIVE_MAPPING')
    predictions=[prediction_from_archive(args.archives.parent/row['path'],row['sample_id']) for row in mapping]
    if args.processing_times:
        need(args.processing_times.stat().st_size<=2_000_000,'TIMING_MAPPING_SIZE')
        predictions=attach_processing_times(predictions,strict_json(args.processing_times.read_text()))
    result=evaluate(dataset,predictions)
    with args.output.open('x',encoding='utf-8') as stream:json.dump(result,stream,ensure_ascii=False,indent=2,allow_nan=False);stream.write('\n')
    print('EVALUATION_COMPLETE',result['samples'],'images',result['capture_groups'],'capture groups; FULL_GAME_AND_DEVICE_UNVERIFIED')

if __name__=='__main__':main()
