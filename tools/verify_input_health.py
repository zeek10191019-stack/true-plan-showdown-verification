"""Input health is stream diagnostics, never selected-frame capture or game truth."""
REASONS={'INVALID_CURRENT_SCREEN_SAMPLE','CURRENT_SCREEN_IMAGE_MISSING',
    'CURRENT_STREAM_CONTINUITY_REJECTED','CURRENT_STREAM_INGRESS_REJECTED'}
MAX=2**63-1


def require(value,reason):
    if not value:raise ValueError('INPUT_HEALTH_'+reason)


def validate_input_health(value):
    fields={'schema','scope','status','accepted_inputs','rejected_inputs','consecutive_rejections',
        'retirement_requests','last_reason','capture_timestamp_calibrated','current_state_eligible','owner_certified','battle_advice_authorized'}
    require(isinstance(value,dict) and set(value)==fields,'FIELDS')
    require(value['schema']=='trueplan.screen-read.input-health.v1' and
        value['scope']=='CURRENT_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_PROOF','SCOPE')
    keys=('accepted_inputs','rejected_inputs','consecutive_rejections','retirement_requests')
    require(all(type(value[k]) is int and 0<=value[k]<=MAX for k in keys),'COUNTERS')
    accepted,rejected,consecutive,retirements=(value[k] for k in keys)
    require(consecutive<=rejected and retirements<=rejected and retirements<=accepted+1 and
        (retirements>0 if rejected>0 else retirements==0),'COUNTER_RELATION')
    reason=value['last_reason']
    if consecutive>0:
        require(isinstance(reason,str) and reason in REASONS,'REJECT_REASON');status='INPUT_HELD'
    else:
        require(reason is None,'NONHELD_REASON')
        status='READY_DELIVERY_ONLY' if accepted>0 else 'NOT_OBSERVED'
        if not accepted:require(rejected==retirements==0,'UNOBSERVED_COUNTERS')
    require(value['status']==status,'STATUS')
    for key in ('capture_timestamp_calibrated','current_state_eligible','owner_certified','battle_advice_authorized'):
        require(value[key] is False,'PROMOTION')
    return dict(status='PASS_CURRENT_STREAM_INPUT_HEALTH_DECLARATION_ONLY',input_status=status,capture_age_certified=False)


def verify_report(record,destination):
    import base64,hashlib,zipfile
    from pathlib import Path
    from verify_screen_evidence import parse_json,verify_archive
    from verify_candidate_lease import validate_candidate_lease
    from verify_read_clock import validate_slot
    require(isinstance(record,dict) and record.get('scope')=='SYNTHETIC_INPUT_HEALTH_LEASE_AND_WORK_SLOT_ONLY','REPORT_SCOPE')
    require(type(record.get('checks')) is int and record['checks']==1025,'REPORT_CHECKS')
    for key in ('Vision_executed','capture_age_certified','game_accuracy_certified','device_certified','full_app_CI_certified'):
        require(record.get(key) is False,'REPORT_PROMOTION')
    cases=record.get('preflight_cases');require(isinstance(cases,list) and len(cases)==16,'PREFLIGHT_COUNT')
    seen=set()
    for row in cases:
        keys=('current_stream','screen','valid','image_available')
        require(isinstance(row,dict) and set(row)==set(keys)|{'result'} and all(type(row[k]) is bool for k in keys),'PREFLIGHT_FIELDS')
        current,screen,valid,image=(row[k] for k in keys);vector=(current,screen,valid,image)
        require(vector not in seen,'PREFLIGHT_DUPLICATE');seen.add(vector)
        expected='IGNORE_FOREIGN_OR_NONSCREEN' if not current or not screen else 'HOLD_INVALID_SAMPLE' if not valid else 'READY_INPUT_ONLY' if image else 'HOLD_MISSING_IMAGE'
        require(row['result']==expected,'PREFLIGHT_RESULT')
    phases=[('none',0,0,0,0,None),('ready',1,0,0,0,None),('held_once',1,1,1,1,'CURRENT_SCREEN_IMAGE_MISSING'),
        ('held_1000_more',1,1001,1001,1,'CURRENT_STREAM_INGRESS_REJECTED'),('ready_again',2,1001,0,1,None),
        ('held_again',2,1002,1,2,'CURRENT_STREAM_CONTINUITY_REJECTED')]
    snapshots=record.get('snapshots');require(isinstance(snapshots,list) and len(snapshots)==len(phases),'PHASE_COUNT')
    for row,(identity,accepted,rejected,consecutive,retirements,reason) in zip(snapshots,phases):
        require(isinstance(row,dict) and row.get('id')==identity,'PHASE_ID');value=row.get('health');validate_input_health(value)
        require(tuple(value[k] for k in ('accepted_inputs','rejected_inputs','consecutive_rejections','retirement_requests','last_reason'))==
            (accepted,rejected,consecutive,retirements,reason),'PHASE_COUNTERS')
    lease=record.get('held_lease');validate_candidate_lease(lease)
    require(lease.get('last_reason')=='CAPTURE_INPUT_HELD' and lease.get('pending') is None and lease.get('latest') is None,'LEASE_HELD')
    slots=record.get('work_slots');require(isinstance(slots,list) and len(slots)==3,'SLOT_COUNT')
    for value,(last,active) in zip(slots,[(1,1),(1,None),(2,2)]):
        validate_slot(value);require(value['last_ticket']==last and value['active_ticket']==active,'SLOT_SEQUENCE')
    encoded=record.get('archive_base64');require(isinstance(encoded,str) and len(encoded)<2000000,'ARCHIVE_BOUND')
    blob=base64.b64decode(encoded,validate=True);require(hashlib.sha256(blob).hexdigest()==record.get('archive_sha256'),'ARCHIVE_SHA')
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False);path=destination/'r563_input_health.zip'
    with path.open('xb') as stream:stream.write(blob)
    receipt=verify_archive(path,expected_sha256=record['archive_sha256'])
    with zipfile.ZipFile(path) as archive:
        selected=parse_json(archive.read('selected_evidence.json'));index=parse_json(archive.read('evidence_integrity.json'))
    require(selected.get('r563_input_health')==snapshots[-1]['health'] and
        selected.get('r554_candidate_leases')==dict(automatic_full_frame=lease,paired_move_candidates=lease),'ARCHIVE_BINDING')
    require(index.get('app_version')=='0.5.63' and index.get('app_build')=='563','ARCHIVE_VERSION')
    return dict(status='PASS_INPUT_HEALTH_FIXED_CASES_AND_ONE_SWIFT_ARCHIVE_ONLY',native_checks=record['checks'],
        preflight_cases=16,phases=6,archive=receipt,Vision_executed=False,capture_age_certified=False,device_certified=False)
