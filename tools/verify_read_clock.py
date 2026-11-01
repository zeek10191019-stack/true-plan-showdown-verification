"""Verify relative-clock/work-slot declarations, never selected-frame age."""
VERDICTS={'RELATIVE_PTS_ORDER_ONLY_UNCERTIFIED','PTS_STREAM_NOT_STARTED_HOLD','PTS_INVALID_STAMP_HOLD',
 'PTS_EPOCH_MISMATCH_HOLD','PTS_FRAME_REPLAY_HOLD','PTS_FRAME_ROLLBACK_HOLD','PTS_DELIVERY_CLOCK_ROLLBACK_HOLD',
 'PTS_MISSING_OR_UNCALIBRATED_HOLD','PTS_REPEATED_HOLD','PTS_ROLLBACK_HOLD','PTS_DELTA_DIVERGENCE_HOLD'}
RETIRE={'PTS_FRAME_ROLLBACK_HOLD','PTS_DELIVERY_CLOCK_ROLLBACK_HOLD','PTS_ROLLBACK_HOLD','PTS_DELTA_DIVERGENCE_HOLD'}
MAX=2**63-1


def require(ok,reason):
    if not ok:raise ValueError('READ_CLOCK_'+reason)


def integer(value,minimum=0):return type(value) is int and minimum<=value<=MAX


def expected_action(verdict,delivered,previous):
    if previous is not None and delivered<previous:return 'RETIRE_READ_SCOPE','DELIVERY_CLOCK_ROLLBACK'
    if verdict in RETIRE:return 'RETIRE_READ_SCOPE',verdict
    if previous is not None and delivered-previous>2500:return 'RETIRE_READ_SCOPE','DELIVERY_GAP_EXCEEDS_2500MS'
    if verdict=='RELATIVE_PTS_ORDER_ONLY_UNCERTIFIED':
        return 'ALLOW_RELATIVE_ONLY','RELATIVE_ORDER_ONLY_CAPTURE_AGE_UNVERIFIED'
    return 'HOLD_AUTOMATIC_OCR',verdict


def validate_decision(value):
    fields={'schema','policy_id','scope','epoch','frame_id','delivered_uptime_ms','previous_delivered_uptime_ms',
        'delivery_delta_ms','pts_verdict','action','reason','allows_automatic_ocr','requires_new_epoch',
        'capture_timestamp_calibrated','owner_certified','current_state_eligible','battle_advice_authorized'}
    require(isinstance(value,dict) and set(value)==fields,'FIELDS')
    require(isinstance(value,dict) and value.get('schema')=='trueplan.screen-read.clock-admission.v1' and
        value.get('policy_id')=='RELATIVE_PTS_FENCE_V1' and
        value.get('scope')=='LAST_CALLBACK_CLOCK_DIAGNOSTICS_NOT_SELECTED_FRAME_CERTIFICATION','SCOPE')
    for key in ('epoch','frame_id','delivered_uptime_ms'):require(integer(value.get(key),1),'STAMP')
    require('previous_delivered_uptime_ms' in value and 'delivery_delta_ms' in value,'PREVIOUS_KEYS')
    previous=value['previous_delivered_uptime_ms'];delivered=value['delivered_uptime_ms']
    require(previous is None or integer(previous,1),'PREVIOUS_TYPE')
    delta=value['delivery_delta_ms']
    require((previous is None and delta is None) or
        (previous is not None and type(delta) is int and delta==delivered-previous),'DELTA')
    verdict=value.get('pts_verdict');require(isinstance(verdict,str) and verdict in VERDICTS,'VERDICT')
    action,reason=expected_action(verdict,delivered,previous)
    require(value.get('action')==action and value.get('reason')==reason,'ACTION')
    require(value.get('allows_automatic_ocr') is (action=='ALLOW_RELATIVE_ONLY') and
        value.get('requires_new_epoch') is (action=='RETIRE_READ_SCOPE'),'ACTION_FLAGS')
    for key in ('capture_timestamp_calibrated','owner_certified','current_state_eligible','battle_advice_authorized'):
        require(value.get(key) is False,'PROMOTION')
    return dict(status='PASS_RELATIVE_CLOCK_POLICY_ONLY',action=action,capture_age_certified=False)


def validate_slot(value):
    fields={'schema','scope','capacity','active_requests','last_ticket','active_ticket','available',
        'owner_certified','current_state_eligible','battle_advice_authorized'}
    require(isinstance(value,dict) and set(value)==fields,'SLOT_FIELDS')
    require(isinstance(value,dict) and value.get('schema')=='trueplan.screen-read.live-work-slot.v1' and
        value.get('scope')=='ONE_LIVE_OCR_WORKER_ACROSS_CAPTURE_EPOCHS','SLOT_SCOPE')
    require(type(value.get('capacity')) is int and value['capacity']==1 and integer(value.get('last_ticket')),'SLOT_CAPACITY')
    require('active_ticket' in value and type(value.get('active_requests')) is int,'SLOT_KEYS')
    active,last=value['active_ticket'],value['last_ticket']
    require(active is None or (integer(active,1) and active==last),'SLOT_TICKET')
    require(value['active_requests']==(0 if active is None else 1) and value.get('available') is (active is None and last<MAX),'SLOT_AVAILABILITY')
    for key in ('owner_certified','current_state_eligible','battle_advice_authorized'):require(value.get(key) is False,'SLOT_PROMOTION')
    return dict(status='PASS_SINGLE_LIVE_WORKER_DECLARATION_ONLY',active_requests=value['active_requests'])


def validate_diagnostics(value):
    require(isinstance(value,dict) and set(value)=={'scope','clock_decision','live_work_slot'} and
        value['scope']=='CAPTURE_STREAM_DIAGNOSTICS_NOT_SELECTED_FRAME_CLOCK_PROOF','DIAGNOSTIC_SCOPE')
    decision=value['clock_decision']
    return dict(clock=validate_decision(decision) if decision is not None else None,slot=validate_slot(value['live_work_slot']))


RELATIVE='RELATIVE_PTS_ORDER_ONLY_UNCERTIFIED'
MISSING='PTS_MISSING_OR_UNCALIBRATED_HOLD'
SEQUENCES={
 'rewind_after_missing':[(1000,1000,RELATIVE),(1100,None,MISSING),(1200,900,'PTS_ROLLBACK_HOLD')],
 'repeat_after_missing':[(1000,1000,RELATIVE),(1100,None,MISSING),(1200,1000,'PTS_REPEATED_HOLD')],
 'source_clock_stalls':[(1000,1000,RELATIVE),(1601,1001,'PTS_DELTA_DIVERGENCE_HOLD')],
 'source_clock_jumps':[(1000,1000,RELATIVE),(1001,1602,'PTS_DELTA_DIVERGENCE_HOLD')],
 'divergence_boundary':[(1000,1000,RELATIVE),(1600,1100,RELATIVE)],
 'missing_then_relative_progress':[(1000,1000,RELATIVE),(1100,None,MISSING),(1200,1200,RELATIVE)],
 'delivery_clock_rewinds':[(1000,1000,RELATIVE),(999,1100,'PTS_DELIVERY_CLOCK_ROLLBACK_HOLD')],
 'invalid_pts_remembers_reference':[(1000,1000,RELATIVE),(1100,-1,MISSING),(1200,900,'PTS_ROLLBACK_HOLD')]}
SLOT_PHASES=[('idle',0,None),('first_running',1,1),('after_1000_epoch_offer_attempts',1,1),
 ('first_finished',1,None),('second_running',2,2),('wrong_old_finish',2,2),('after_1000_completed_workers',1002,None)]


def verify_report(record,destination,app_version='0.5.62',app_build='562'):
    """Check native output against fixed regressions and its actual writer archive."""
    import base64,hashlib,zipfile
    from pathlib import Path
    from verify_candidate_lease import validate_candidate_lease
    from verify_screen_evidence import parse_json,verify_archive
    require(isinstance(record,dict) and record.get('scope')=='SYNTHETIC_RELATIVE_CLOCK_AND_LIVE_WORKER_ONLY' and
        type(record.get('checks')) is int and record['checks']==2065,'NATIVE_SCOPE_OR_CHECKS')
    for flag in ('Vision_executed','capture_age_certified','game_accuracy_certified','device_certified','full_app_CI_certified'):
        require(record.get(flag) is False,'NATIVE_PROMOTION')
    expected={v:(v,1100,1000) for v in VERDICTS}
    expected.update(first_relative_stamp=(RELATIVE,1000,None),delivery_gap_boundary=(RELATIVE,3500,1000),
        delivery_gap_exceeded=(RELATIVE,3501,1000),missing_pts_after_delivery_gap=(MISSING,3501,1000),
        repeated_pts_after_delivery_gap=('PTS_REPEATED_HOLD',3501,1000),
        delivery_rollback_overrides_missing=(MISSING,999,1000),maximum_positive_delivery=(RELATIVE,MAX,MAX-1))
    decisions=record.get('decisions');require(isinstance(decisions,list) and len(decisions)==len(expected),'NATIVE_DECISION_COUNT')
    require(all(isinstance(row,dict) and set(row)=={'id','decision'} for row in decisions),'NATIVE_DECISION_ROWS')
    ids=[row['id'] for row in decisions]
    require(all(isinstance(i,str) for i in ids) and len(set(ids))==len(ids) and set(ids)==set(expected),'NATIVE_DECISION_IDS')
    for row in decisions:
        value=row['decision'];validate_decision(value)
        verdict,delivered,previous=expected[row['id']]
        require(value['pts_verdict']==verdict and value['delivered_uptime_ms']==delivered and
            value['previous_delivered_uptime_ms']==previous and value['epoch']==3 and value['frame_id']==17,'NATIVE_DECISION_INPUT')
    sequences=record.get('sequences')
    require(isinstance(sequences,list) and len(sequences)==len(SEQUENCES),'NATIVE_SEQUENCES')
    ids=[row.get('id') for row in sequences]
    require(all(isinstance(i,str) for i in ids) and len(set(ids))==len(ids) and set(ids)==set(SEQUENCES),'NATIVE_SEQUENCE_IDS')
    for row in sequences:
        events=row.get('events');gold=SEQUENCES[row['id']]
        require(isinstance(events,list) and len(events)==len(gold),'NATIVE_EVENTS')
        accepted=0;last_valid=None
        for index,(actual,(delivered,pts,verdict)) in enumerate(zip(events,gold),1):
            require(actual==dict(frame_id=index,delivered_ms=delivered,pts_ms=pts,verdict=verdict) and
                type(actual['frame_id']) is int and type(actual['delivered_ms']) is int and
                (pts is None or type(actual['pts_ms']) is int),'NATIVE_EVENT')
            if verdict==RELATIVE:
                accepted+=1;last_valid=dict(epoch=3,frameID=index,deliveredMs=delivered,presentationMs=pts)
        summary=row.get('summary')
        require(isinstance(summary,dict) and summary.get('schema')=='trueplan.sample-clock-audit.v1' and
            summary.get('activeEpoch')==3 and summary.get('lastValidPTSSample')==last_valid and
            summary.get('observed')==len(gold) and summary.get('relativeAccepted')==accepted and
            summary.get('relativeHeld')==len(gold)-accepted and summary.get('lastVerdict')==gold[-1][2] and
            summary.get('streamBegins')==1 and summary.get('epochRotations')==0,'NATIVE_SUMMARY')
        for flag in ('presentationToUptimeOffsetVerified','liveBattleStateCertified','productionEnabled'):
            require(summary.get(flag) is False,'NATIVE_SUMMARY_PROMOTION')
    rotated=record.get('retired_clock_summary')
    require(isinstance(rotated,dict) and rotated.get('activeEpoch')==4 and rotated.get('streamBegins')==1 and
        rotated.get('epochRotations')==1 and rotated.get('lastVerdict')==RELATIVE and
        rotated.get('lastValidPTSSample')==dict(epoch=4,frameID=3,deliveredMs=1200,presentationMs=100),'NATIVE_ROTATION')
    slots=record.get('work_slot_snapshots')
    require(isinstance(slots,list) and len(slots)==len(SLOT_PHASES),'NATIVE_SLOTS')
    for row,(identity,last,active) in zip(slots,SLOT_PHASES):
        require(isinstance(row,dict) and row.get('id')==identity,'NATIVE_SLOT_PHASE')
        validate_slot(row.get('slot'))
        require(row['slot']['last_ticket']==last and row['slot']['active_ticket']==active,'NATIVE_SLOT_SEQUENCE')
    validate_candidate_lease(record.get('lease_snapshot'))
    invalidated=record.get('invalidated_lease_snapshots')
    require(isinstance(invalidated,list) and len(invalidated)==2,'NATIVE_LEASE_COUNT')
    for value in invalidated:
        validate_candidate_lease(value)
        require(value.get('last_reason')=='CAPTURE_CLOCK_HELD' and value.get('pending') is None and
            value.get('latest') is None,'NATIVE_CLOCK_INVALIDATION')
    diagnostics=record.get('diagnostics');validate_diagnostics(diagnostics)
    require(diagnostics['clock_decision']==decisions[0]['decision'] and diagnostics['live_work_slot']==slots[-1]['slot'],
        'NATIVE_DIAGNOSTIC_BINDING')
    encoded=record.get('archive_base64');require(isinstance(encoded,str) and len(encoded)<2000000,'NATIVE_ARCHIVE_BOUND')
    data=base64.b64decode(encoded,validate=True)
    require(hashlib.sha256(data).hexdigest()==record.get('archive_sha256'),'NATIVE_ARCHIVE_SHA')
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False)
    path=destination/'r562_clock.zip'
    with path.open('xb') as stream:stream.write(data)
    receipt=verify_archive(path,expected_sha256=record['archive_sha256'])
    with zipfile.ZipFile(path) as archive:
        selected=parse_json(archive.read('selected_evidence.json'));index=parse_json(archive.read('evidence_integrity.json'))
    require(selected.get('r562_read_clock_diagnostics')==diagnostics and
        selected.get('r554_candidate_leases')==dict(automatic_full_frame=record['lease_snapshot'],paired_move_candidates=record['lease_snapshot']),
        'NATIVE_ARCHIVE_BINDING')
    require(index.get('app_version')==app_version and index.get('app_build')==app_build,'NATIVE_ARCHIVE_VERSION')
    return dict(status='PASS_FIXED_CLOCK_REGRESSIONS_SINGLE_LIVE_WORKER_AND_ONE_ZIP_ONLY',decisions=18,sequences=8,
        native_checks=2065,archive=receipt,Vision_executed=False,capture_age_certified=False,game_accuracy_certified=False,device_certified=False)
