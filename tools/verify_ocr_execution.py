"""Inspect declared execution policy, never hardware use or OCR accuracy."""
from verify_ocr_failures import ALLOWED_ERROR_DOMAINS

def require(ok,reason):
    if not ok:raise ValueError(reason)
def integer(v,minimum=0):return type(v) is int and minimum<=v<=2**63-1
def retryable(errors):return any(e['domain']=='TextRecognition.CRImageReaderError' and e['code']==9 for e in errors)

def validate_ocr_execution(audit,success=None):
    fields={'schema','policy_id','status','attempt_count','attempts','same_input_reused','configuration_only',
        'compute_execution_attested','ocr_accuracy_certified','owner_certified','current_state_eligible','battle_advice_authorized'}
    require(isinstance(audit,dict) and set(audit)==fields,'OCR_EXECUTION_FIELDS')
    require(audit['schema']=='trueplan.ocr.execution.v1' and
        audit['policy_id']=='DEFAULT_THEN_CPU_SOFTWARE_ON_IMAGE_ERROR_9_V1','OCR_EXECUTION_POLICY')
    require(audit['same_input_reused'] is True and audit['configuration_only'] is True,'OCR_EXECUTION_SOURCE_OR_SCOPE')
    for flag in ['compute_execution_attested','ocr_accuracy_certified','owner_certified','current_state_eligible','battle_advice_authorized']:
        require(audit[flag] is False,'OCR_EXECUTION_FALSE_ATTESTATION')
    attempts=audit['attempts'];count=audit['attempt_count']
    require(integer(count,1) and count<=2 and isinstance(attempts,list) and len(attempts)==count,'OCR_EXECUTION_LIMIT')
    fields={'mode','outcome','configuration_accepted','request_performed','supported_stage_count','main_stage_present',
        'cpu_assigned_stage_count','software_context_requested','error_codes'}
    for index,row in enumerate(attempts):
        require(isinstance(row,dict) and set(row)==fields,'OCR_EXECUTION_ATTEMPT_FIELDS')
        require(row['mode']==('FRAMEWORK_DEFAULT' if index==0 else 'CPU_SOFTWARE'),'OCR_EXECUTION_ORDER')
        for flag in ['configuration_accepted','request_performed','main_stage_present','software_context_requested']:
            require(type(row[flag]) is bool,'OCR_EXECUTION_BOOLEAN_TYPE')
        n,assigned=row['supported_stage_count'],row['cpu_assigned_stage_count']
        require(integer(n) and integer(assigned) and assigned<=n,'OCR_EXECUTION_STAGE_COUNTS')
        errors=row['error_codes']
        require(isinstance(errors,list) and len(errors)<=4,'OCR_EXECUTION_ERROR_COUNT')
        for e in errors:
            require(isinstance(e,dict) and set(e)=={'domain','code'} and isinstance(e['domain'],str) and e['domain'] in ALLOWED_ERROR_DOMAINS and
                type(e['code']) is int and -2**63<=e['code']<=2**63-1,'OCR_EXECUTION_ERROR_CODE')
        require(row['outcome'] in ['SUCCEEDED','REQUEST_FAILED','CONFIGURATION_FAILED'],'OCR_EXECUTION_OUTCOME')
        if index==0:
            require(n==assigned==0 and row['main_stage_present'] is False and row['software_context_requested'] is False and
                row['configuration_accepted'] is True and row['request_performed'] is True,'OCR_EXECUTION_DEFAULT_CONFIG')
        else:
            require(attempts[0]['outcome']=='REQUEST_FAILED' and retryable(attempts[0]['error_codes']),'OCR_EXECUTION_RETRY_TRIGGER')
            require(row['software_context_requested'] is True,'OCR_EXECUTION_SOFTWARE_CONTEXT')
            if row['configuration_accepted']:
                require(1<=n<=16 and row['main_stage_present'] is True and assigned==n and row['request_performed'] is True,
                    'OCR_EXECUTION_CPU_ASSIGNMENT')
            else:require(assigned==0 and row['request_performed'] is False,'OCR_EXECUTION_REJECTED_CONFIG')
        if row['outcome']=='SUCCEEDED':require(row['configuration_accepted'] and row['request_performed'] and not errors and index==count-1,'OCR_EXECUTION_SUCCESS')
        elif row['outcome']=='REQUEST_FAILED':require(row['configuration_accepted'] and row['request_performed'] and bool(errors),'OCR_EXECUTION_REQUEST_FAILURE')
        else:require(index==1 and not row['configuration_accepted'] and not row['request_performed'] and bool(errors),'OCR_EXECUTION_CONFIG_FAILURE')
    succeeded=attempts[-1]['outcome']=='SUCCEEDED'
    require(audit['status']==('SUCCEEDED' if succeeded else 'FAILED'),'OCR_EXECUTION_FINAL_STATUS')
    if count==1 and not succeeded:require(not retryable(attempts[0]['error_codes']),'OCR_EXECUTION_MISSING_RETRY')
    if success is not None:require(succeeded is success,'OCR_EXECUTION_PARENT_STATUS')
    return {'status':'PASS_DECLARED_EXECUTION_POLICY_ONLY','attempts':count,'compute_execution_attested':False}
