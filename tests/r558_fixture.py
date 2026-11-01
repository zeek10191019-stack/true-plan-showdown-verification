"""Hand-specified request metadata over synthetic OCR rows, not Vision output."""
import json
from r557_fixture import screen_fixture
from r553_fixture import source_update

def request_metadata(selected,packet,count):
    return dict(schema='trueplan.ocr.request-audit.v1',engine_version='r558.full-frame.v1',scope='PROVISIONAL_TEXT_REQUEST_ONLY',
        input_binding='EXACT_PNG_BYTES_DECODED_UP',execution_attestation='SELF_REPORTED_NO_SIGNATURE',
        capture_session_id='capture-test',frame_id=17,epoch=3,receipt_uptime_ms=1200,timestamp_basis='UNCALIBRATED_HOST_RECEIPT_UPTIME',
        image_sha256=packet['image_sha256'],image_width=selected['analysis_image']['width'],image_height=selected['analysis_image']['height'],
        requested_mode='MANUAL_ACCURATE',effective_recognition_level='accurate',requested_languages=['ja-JP','en-US'],
        effective_supported_languages=['en-US','ja-JP'],fast_language_check='NOT_REQUESTED',fast_supported_languages=[],request_revision=3,
        uses_language_correction=False,maximum_regions=96,maximum_candidates_per_region=3,raw_region_count=count,examined_region_count=count,
        emitted_region_count=count,truncated_region_count=0,omitted_observations=[],unbound_roi_count=0,
        ocr_accuracy_certified=False,device_certified=False,owner_certified=False,current_state_eligible=False,battle_advice_authorized=False)

def request_fixture(omissions=False):
    files=screen_fixture();selected=json.loads(files['selected_evidence.json'])
    packet=json.loads(json.loads(selected['research_candidate_envelope'])['payload_json'])
    for index,row in enumerate(packet['readings']):
        row.update(key=None,value=None,ocr_observation_index=index,roi_owner_certified=False,roi_source='VISION_FIRST_PASS_GEOMETRY_UNCERTIFIED',
            ocr_alternatives=[dict(rank=0,raw_text=row['raw_text'],confidence=row['confidence'])])
    audit=request_metadata(selected,packet,len(packet['readings']))
    if omissions:
        audit.update(raw_region_count=120,examined_region_count=96,truncated_region_count=24,
            omitted_observations=[dict(observation_index=i,reason='NO_TEXT_CANDIDATE') for i in range(16,96)])
    packet.update(ocr_engine_version='r558.full-frame.v1',ocr_request_audit=audit)
    return source_update(files,selected,packet)
