"""Validate receipt-lease diagnostics, not capture age or OCR/game truth."""
import re

def validate_candidate_lease(d):
    def require(ok,reason):
        if not ok:raise ValueError('LEASE_'+reason)
    def uint(v):return type(v) is int and 0 <= v <= 2**63-1
    require(isinstance(d,dict),'OBJECT')
    require(d.get('schema')=='trueplan.screen-read.candidate-lease.v1' and
            d.get('scope')=='HOST_RECEIPT_DIAGNOSTICS_ONLY' and
            d.get('clock_basis')=='UNCALIBRATED_HOST_RECEIPT_UPTIME','SCHEMA_SCOPE')
    for key in ('source_image_attached','owner_certified','current_state_eligible','battle_advice_authorized'):
        require(d.get(key) is False,'FALSE_CERTIFICATION')
    for key in ('battle_id','turn','capture_timestamp_ms'):
        require(key in d and d[key] is None,'GAME_IDENTITY_OR_TIME')
    for key in ('host_now_ms','last_clock_ms','scope_revision','last_request_id','last_issued_frame_id',
                'last_issued_receipt_ms','accepted_results','rejected_operations','duplicate_png_digests_not_refreshed','invalidations'):
        require(uint(d.get(key)),'INTEGER_'+key)
    require(type(d.get('ttl_ms')) is int and 1 <= d['ttl_ms'] <= 30000,'TTL')
    require(type(d.get('active')) is bool,'ACTIVE_TYPE')
    # R570: if enabled on the two live UI leases, pending work and an older
    # publishable result may never coexist (the old image may be a switch screen).
    strict=d.get('strict_retirement_on_new_request',False)
    require(type(strict) is bool,'STRICT_RETIREMENT_TYPE')
    require(d['accepted_results']+d['duplicate_png_digests_not_refreshed'] <= d['last_request_id'],'COUNTER_TOTAL')
    require(d.get('last_reason') in ('NOT_STARTED','SOURCE_SCOPE_BEGAN','OCR_PENDING','FRESH_HOST_RECEIPT_ONLY',
        'DUPLICATE_PIXELS_NO_REFRESH','RESULT_REJECTED_OR_EXPIRED','HOST_CLOCK_REWIND','CAPTURE_START',
        'SOURCE_STOPPED','APP_BACKGROUND','APP_FOREGROUND','MEMORY_PRESSURE','MANUAL_CLEAR','CAPTURE_CLOCK_HELD','CAPTURE_INPUT_HELD'),'REASON')
    session,epoch=d.get('capture_session_id'),d.get('epoch')
    require('capture_session_id' in d and 'epoch' in d,'SOURCE_KEYS')
    if session is None:
        require(epoch is None and not d['active'] and d['last_issued_frame_id']==d['last_issued_receipt_ms']==0,'EMPTY_SOURCE')
    else:
        require(isinstance(session,str) and 0 < len(session.encode()) <= 128 and uint(epoch) and epoch > 0 and d['scope_revision'] > 0,'SOURCE')
    require('pending' in d and 'latest' in d,'TICKET_KEYS')
    pending,latest=d['pending'],d['latest']
    if strict:require(not (pending is not None and latest is not None),'STRICT_PENDING_AND_LATEST')
    if d['last_reason']=='CAPTURE_CLOCK_HELD':require(pending is None and latest is None,'CLOCK_HELD_WITH_VALUE')
    if d['last_reason']=='CAPTURE_INPUT_HELD':require(pending is None and latest is None,'INPUT_HELD_WITH_VALUE')
    ticket_keys={'scope_revision','request_id','capture_session_id','epoch','frame_id','receipt_uptime_ms','deadline_uptime_ms'}
    for value,is_latest in ((pending,False),(latest,True)):
        if value is None:continue
        require(isinstance(value,dict) and set(value)==ticket_keys|({'image_sha256'} if is_latest else set()),'TICKET_FIELDS')
        require(all(uint(value.get(k)) for k in ('scope_revision','request_id','epoch','frame_id','receipt_uptime_ms','deadline_uptime_ms')),'TICKET_NUMBERS')
        require(value['scope_revision']==d['scope_revision'] and value['capture_session_id']==session and
                value['epoch']==epoch and 0 < value['request_id'] <= d['last_request_id'] and
                0 < value['frame_id'] <= d['last_issued_frame_id'] and
                0 < value['receipt_uptime_ms'] <= d['last_issued_receipt_ms'] and
                value['deadline_uptime_ms']==value['receipt_uptime_ms']+d['ttl_ms'],'TICKET_BINDING')
        require(value['receipt_uptime_ms'] <= d['host_now_ms'],'TICKET_FUTURE')
        if is_latest:
            require(d['accepted_results']>0,'LATEST_WITHOUT_ACCEPT')
            digest=value.get('image_sha256')
            require(isinstance(digest,str) and re.fullmatch('[0-9a-f]{64}',digest) is not None,'IMAGE_DIGEST')
        else:
            require(value['request_id']==d['last_request_id'] and value['frame_id']==d['last_issued_frame_id'] and
                    value['receipt_uptime_ms']==d['last_issued_receipt_ms'],'PENDING_WATERMARK')
    if not d['active']:
        require(pending is None and latest is None,'STOPPED_WITH_VALUE')
        status='STOPPED'
    elif latest is not None:
        status='FRESH_RECEIPT_ONLY' if d['host_now_ms'] < latest['deadline_uptime_ms'] else 'EXPIRED'
    else:status='PENDING' if pending is not None else 'EMPTY'
    require(d.get('view_status')==status,'VIEW_STATUS_OR_EXPIRY')
    if pending is not None and latest is not None:
        require(pending['request_id'] > latest['request_id'] and pending['frame_id'] > latest['frame_id'],'PENDING_ORDER')
    if d['last_reason']=='HOST_CLOCK_REWIND':
        require(not d['active'] and pending is None and latest is None,'CLOCK_REWIND_NOT_WITHHELD')
    else:require(d['last_clock_ms']==d['host_now_ms'],'HOST_CLOCK_MISMATCH')
    return {'status':'PASS_DIAGNOSTIC_INVARIANTS_ONLY','view_status':status,'source_image_proof':'NOT_ATTACHED',
            'current_state_eligible':False,'capture_timestamp_calibrated':False}
