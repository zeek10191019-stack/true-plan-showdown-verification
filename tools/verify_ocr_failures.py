"""Bounded, self-reported failure/input metadata. Never accuracy attestation."""
import re
ALLOWED_ERROR_DOMAINS={'com.apple.Vision','VNErrorDomain','NSCocoaErrorDomain','NSOSStatusErrorDomain',
    'NSPOSIXErrorDomain','TextRecognition.CRImageReaderError','OTHER_ERROR_DOMAIN'}

def require(ok,reason):
    if not ok:raise ValueError(reason)

def integer(value,minimum=0):return type(value) is int and minimum<=value<=2**63-1
def digest(value):return isinstance(value,str) and re.fullmatch('[0-9a-f]{64}',value) is not None

def validate_vision_input(value,width,height):
    require(isinstance(value,dict) and set(value)=={'schema','handler','normalization','width','height','bytes_per_row',
        'allocation_bytes','visible_pixel_bytes','visible_pixel_sha256','source_pixel_equality_certified'},'VISION_INPUT_FIELDS')
    require(value['schema']=='trueplan.ocr.vision-input.v1' and value['handler']=='CVPIXELBUFFER_BGRA8_UP' and
        value['normalization']=='SRGB8_WHITE_COMPOSITE_NO_GEOMETRY_CHANGE' and value['source_pixel_equality_certified'] is False,'VISION_INPUT_SCOPE')
    require(integer(width,1) and integer(height,1) and width<=3072 and height<=3072 and width*height<=4_500_000 and
        integer(value['width'],1) and integer(value['height'],1) and (value['width'],value['height'])==(width,height),'VISION_INPUT_DIMENSIONS')
    row,allocation,visible=(value[k] for k in ['bytes_per_row','allocation_bytes','visible_pixel_bytes'])
    require(all(integer(v,1) for v in (row,allocation,visible)) and width*4<=row<=16384 and
        row*height<=allocation<=20_000_000 and visible==width*height*4,'VISION_INPUT_BOUNDS')
    require(digest(value['visible_pixel_sha256']),'VISION_INPUT_SHA')
    return True

def validate_ocr_failure(value,selected):
    fields={'schema','status','capture_session_id','frame_id','epoch','receipt_uptime_ms',
        'attempted_image_sha256','attempted_image_width','attempted_image_height','error_codes','execution_attestation',
        'automatic_retry_count','raw_error_messages_included','current_state_eligible','owner_certified','ocr_accuracy_certified',
        'battle_advice_authorized'}
    require(isinstance(value,dict) and set(value) in (fields,fields|{'recovery_audit'}),'OCR_FAILURE_FIELDS')
    require(value['schema']=='trueplan.ocr.failure.v1' and value['status']=='OCR_FAILED_NO_RESULT' and
        value['execution_attestation']=='SELF_REPORTED_NO_SIGNATURE','OCR_FAILURE_SCOPE')
    for a,b in [('frame_id','frame_id'),('epoch','epoch'),('receipt_uptime_ms','observed_ms_monotonic')]:
        require(integer(value[a],1) and value[a]==selected.get(b),'OCR_FAILURE_SOURCE')
    require(value['capture_session_id']==selected.get('capture_session_id') and isinstance(value['capture_session_id'],str) and
        0<len(value['capture_session_id'].encode())<=256,'OCR_FAILURE_SESSION')
    require(selected.get('research_candidate_envelope') is None and selected.get('screen_read_state') is None,'OCR_FAILURE_WITH_RESULT')
    for flag in ['raw_error_messages_included','current_state_eligible','owner_certified','ocr_accuracy_certified','battle_advice_authorized']:
        require(value[flag] is False,'OCR_FAILURE_PROMOTION_OR_PRIVATE_DETAILS')
    if 'recovery_audit' in value:
        from verify_ocr_execution import validate_ocr_execution
        validate_ocr_execution(value['recovery_audit'],success=False)
        require(type(value['automatic_retry_count']) is int and value['automatic_retry_count']==value['recovery_audit']['attempt_count']-1,'OCR_FAILURE_RETRY')
    else:require(type(value['automatic_retry_count']) is int and value['automatic_retry_count']==0,'OCR_FAILURE_RETRY')
    codes=value['error_codes']
    require(isinstance(codes,list) and 1<=len(codes)<=4,'OCR_FAILURE_ERROR_COUNT')
    for row in codes:
        require(isinstance(row,dict) and set(row)=={'domain','code'} and isinstance(row['domain'],str) and
            row['domain'] in ALLOWED_ERROR_DOMAINS and type(row['code']) is int and
            -2**63<=row['code']<=2**63-1,'OCR_FAILURE_ERROR_CODE')
    if 'recovery_audit' in value:
        expected=[code for attempt in value['recovery_audit']['attempts'] for code in attempt['error_codes']][:4]
        require(codes==expected,'OCR_FAILURE_RECOVERY_CODES')
    image=selected.get('analysis_image')
    if image is None:
        require(value['attempted_image_sha256'] is None and type(value['attempted_image_width']) is int and
            type(value['attempted_image_height']) is int and value['attempted_image_width']==value['attempted_image_height']==0,'OCR_FAILURE_MISSING_IMAGE')
    else:
        require(isinstance(image,dict) and digest(value['attempted_image_sha256']) and
            value['attempted_image_sha256']==image.get('png_sha256') and integer(value['attempted_image_width'],1) and
            integer(value['attempted_image_height'],1) and value['attempted_image_width']==image.get('width') and
            value['attempted_image_height']==image.get('height'),'OCR_FAILURE_IMAGE_BINDING')
    return {'status':'PASS_INTERNAL_FAILURE_METADATA_ONLY','execution_attested':False,'ocr_accuracy_certified':False}
