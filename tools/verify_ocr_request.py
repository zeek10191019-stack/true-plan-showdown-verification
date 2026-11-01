"""Verify self-reported OCR metadata and its exact source/row coverage.

This does not attest that Vision ran, its speed, or recognition accuracy.
"""
from screen_read_layout import variants,bound_roi
from verify_ocr_failures import validate_vision_input

ENGINE='r558.full-frame.v1'
ENGINE_V2='r559.full-frame.v2'
ENGINE_V3='r560.full-frame.v3'
REASON='FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND'
FIELDS={'schema','engine_version','scope','input_binding','execution_attestation','capture_session_id','frame_id','epoch',
    'receipt_uptime_ms','timestamp_basis','image_sha256','image_width','image_height','requested_mode','effective_recognition_level',
    'requested_languages','effective_supported_languages','fast_language_check','fast_supported_languages','request_revision',
    'uses_language_correction','maximum_regions','maximum_candidates_per_region','raw_region_count','examined_region_count',
    'emitted_region_count','truncated_region_count','omitted_observations','unbound_roi_count','ocr_accuracy_certified',
    'device_certified','owner_certified','current_state_eligible','battle_advice_authorized'}

def require(ok,reason):
    if not ok:raise ValueError(reason)

def uint(value,minimum=0):return type(value) is int and minimum<=value<=2**63-1

def languages(value):
    return (isinstance(value,list) and len(value)<=1024 and
            all(isinstance(v,str) and 0<len(v)<=128 and v.isascii() for v in value) and
            value==sorted(set(value)))

def validate_ocr_request(packet,selected):
    require(isinstance(packet,dict) and packet.get('ocr_engine_version') in (ENGINE,ENGINE_V2,ENGINE_V3),'OCR_REQUEST_ENGINE')
    engine=packet['ocr_engine_version']
    audit=packet.get('ocr_request_audit')
    required=FIELDS | ({'vision_input'} if engine in (ENGINE_V2,ENGINE_V3) else set()) | ({'execution_audit'} if engine==ENGINE_V3 else set())
    require(isinstance(audit,dict) and set(audit)==required,'OCR_REQUEST_FIELDS')
    for key,value in {'schema':'trueplan.ocr.request-audit.v1','engine_version':engine,'scope':'PROVISIONAL_TEXT_REQUEST_ONLY',
            'input_binding':'EXACT_PNG_BYTES_DECODED_UP','execution_attestation':'SELF_REPORTED_NO_SIGNATURE',
            'timestamp_basis':'UNCALIBRATED_HOST_RECEIPT_UPTIME'}.items():require(audit.get(key)==value,'OCR_REQUEST_SCOPE')
    image=selected.get('analysis_image')
    require(isinstance(image,dict),'OCR_REQUEST_IMAGE')
    for key in ('frame_id','epoch'):
        require(uint(audit.get(key),1) and uint(packet.get(key),1) and audit[key]==packet[key]==selected.get(key),'OCR_REQUEST_SOURCE_ID')
    require(audit.get('capture_session_id')==packet.get('battle_id')==selected.get('capture_session_id') and
            isinstance(audit.get('capture_session_id'),str) and 0<len(audit['capture_session_id'].encode())<=256,'OCR_REQUEST_SESSION')
    require(uint(audit.get('receipt_uptime_ms'),1) and uint(packet.get('observed_at_ms'),1) and
            audit['receipt_uptime_ms']==packet['observed_at_ms']==selected.get('observed_ms_monotonic'),'OCR_REQUEST_RECEIPT')
    require(audit.get('image_sha256')==image.get('png_sha256')==packet.get('image_sha256'),'OCR_REQUEST_IMAGE_SHA')
    for a,b in [('image_width','width'),('image_height','height')]:
        require(uint(audit.get(a),1) and audit[a]==image.get(b),'OCR_REQUEST_DIMENSIONS')
    if engine in (ENGINE_V2,ENGINE_V3):validate_vision_input(audit['vision_input'],audit['image_width'],audit['image_height'])
    if engine==ENGINE_V3:
        from verify_ocr_execution import validate_ocr_execution
        validate_ocr_execution(audit['execution_audit'],success=True)
    for flag in ('uses_language_correction','ocr_accuracy_certified','device_certified','owner_certified','current_state_eligible','battle_advice_authorized'):
        require(audit.get(flag) is False,'OCR_REQUEST_FALSE_CERTIFICATION_OR_CORRECTION')
    require(audit.get('requested_languages')==['ja-JP','en-US'] and
            languages(audit.get('effective_supported_languages')) and
            set(audit['requested_languages'])<=set(audit['effective_supported_languages']),'OCR_REQUEST_LANGUAGES')
    require(languages(audit.get('fast_supported_languages')) and uint(audit.get('request_revision'),1),'OCR_REQUEST_REVISION_OR_FAST_LANGUAGES')
    mode,check,level=audit.get('requested_mode'),audit.get('fast_language_check'),audit.get('effective_recognition_level')
    fast=set(audit['fast_supported_languages']);required={'ja-JP','en-US'}
    if mode=='MANUAL_ACCURATE':
        require(check=='NOT_REQUESTED' and not fast and level=='accurate','OCR_REQUEST_MANUAL_MODE')
    elif mode=='AUTOMATIC_SPEED_PRIORITY':
        if check=='SUPPORTED':
            require(required<=fast and level=='fast' and audit['effective_supported_languages']==audit['fast_supported_languages'],'OCR_REQUEST_FAST_MODE')
        elif check=='UNSUPPORTED':
            require(not required<=fast and level=='accurate','OCR_REQUEST_FAST_FALLBACK')
        elif check=='QUERY_FAILED':require(not fast and level=='accurate','OCR_REQUEST_FAST_QUERY_FALLBACK')
        else:raise ValueError('OCR_REQUEST_FAST_CHECK')
    else:raise ValueError('OCR_REQUEST_MODE')
    require(type(audit.get('maximum_regions')) is int and audit['maximum_regions']==96 and
            type(audit.get('maximum_candidates_per_region')) is int and audit['maximum_candidates_per_region']==3,'OCR_REQUEST_LIMITS')
    for key in ('raw_region_count','examined_region_count','emitted_region_count','truncated_region_count','unbound_roi_count'):
        require(uint(audit.get(key)),'OCR_REQUEST_COUNT_TYPE')
    raw,examined,emitted=(audit[k] for k in ('raw_region_count','examined_region_count','emitted_region_count'))
    require(examined==min(raw,96) and emitted<=examined and audit['truncated_region_count']==raw-examined,'OCR_REQUEST_COUNTS')
    readings=packet.get('readings')
    require(isinstance(readings,list) and len(readings)<=512,'OCR_REQUEST_ROWS')
    indices=[];unbound=0
    for index,row in enumerate(readings):
        require(isinstance(row,dict),'OCR_REQUEST_ROW')
        if row.get('reason')!=REASON:
            require('ocr_observation_index' not in row,'OCR_REQUEST_NONFULL_INDEX');continue
        oi=row.get('ocr_observation_index')
        require(uint(oi) and oi<examined and oi not in indices,'OCR_REQUEST_INDEX')
        indices.append(oi)
        require(row.get('key') is None and row.get('value') is None and row.get('roi_owner_certified') is False,'OCR_REQUEST_ROW_PROMOTION')
        require(uint(row.get('source_frame_id'),1) and row['source_frame_id']==packet['frame_id'] and
                uint(row.get('source_epoch'),1) and row['source_epoch']==packet['epoch'] and
                row.get('source_image_sha256')==packet['image_sha256'],'OCR_REQUEST_ROW_SOURCE')
        require(isinstance(row.get('ocr_alternatives'),list),'OCR_REQUEST_ALTERNATIVES_REQUIRED')
        choices=variants(row,index)
        require(all(c['confidence'] is not None and len(c['text'].encode())<=1024 for c in choices),'OCR_REQUEST_ALTERNATIVES')
        if row.get('roi_rect') is None:
            require(row.get('roi_source') is None,'OCR_REQUEST_UNBOUND_GEOMETRY');unbound+=1
        else:
            require(bound_roi(row,audit['image_width'],audit['image_height'],packet['frame_id'],packet['epoch'],packet['image_sha256']) is not None and
                    row.get('roi_source')=='VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED','OCR_REQUEST_ROW_GEOMETRY')
    require(indices==sorted(indices) and len(indices)==emitted and unbound==audit['unbound_roi_count'],'OCR_REQUEST_EMISSION_COVERAGE')
    omissions=audit.get('omitted_observations')
    require(isinstance(omissions,list) and len(omissions)==examined-emitted,'OCR_REQUEST_OMISSIONS')
    omitted=[]
    for row in omissions:
        require(isinstance(row,dict) and set(row)=={'observation_index','reason'},'OCR_REQUEST_OMISSION_FIELDS')
        oi=row['observation_index']
        require(uint(oi) and oi<examined and oi not in omitted and row['reason'] in
                ('NO_TEXT_CANDIDATE','INVALID_TEXT_OR_CONFIDENCE','INVALID_ALTERNATIVE_ORDER'),'OCR_REQUEST_OMISSION')
        omitted.append(oi)
    require(omitted==sorted(omitted) and set(omitted).isdisjoint(indices) and set(omitted)|set(indices)==set(range(examined)),'OCR_REQUEST_OBSERVATION_COVERAGE')
    return {'status':'PASS_INTERNAL_REQUEST_METADATA_ONLY','emitted_regions':emitted,'omitted_regions':len(omitted),
            'truncated_regions':audit['truncated_region_count'],'execution_attested':False,'ocr_accuracy_certified':False}
