"""Check exact-input replay metadata after the existing full evidence ZIP audit."""
import argparse
import json
from pathlib import Path
import zipfile
from schema_contract import validate_document
from verify_screen_evidence import verify_archive,parse_json,require,integer,sha
from screen_read_metrics import elapsed_summary

SCHEMA='trueplan.screen-read.png-replay.v1'
POLICY='EXACT_PNG_SHARED_READER_OFFLINE_V1'

def validate_replay_record(selected,index,manifest,expected=None):
    record=selected.get('png_replay')
    require(isinstance(record,dict),'PNG_REPLAY_RECORD_REQUIRED')
    validate_document(record)
    for flag in ('capture_time_calibrated','owner_certified','identity_certified','current_state_eligible','battle_advice_authorized','game_accuracy_certified','device_certified'):
        require(record.get(flag) is False,'PNG_REPLAY_CERTIFICATION_PROMOTION')
    require(selected.get('source')=='offline_exact_png_replay','PNG_REPLAY_SOURCE_KIND')
    frames=manifest.get('frames')
    require(manifest.get('source')=='OFFLINE_EXACT_PNG_NO_CAPTURE_TIMING' and manifest.get('capture_sample_spacing_ms') is None and
        isinstance(frames,list) and len(frames)==1 and frames[0].get('frame_id')==selected.get('frame_id'),'PNG_REPLAY_OFFLINE_MANIFEST')
    rotations=frames[0].get('mega_scene_ocr_hints') or {}
    require(rotations.get('rotations_completed')==[] and rotations.get('rotations_failed')==[] and
        rotations.get('rotations_skipped')==[0,90,180,270],'PNG_REPLAY_ROTATIONS_NOT_REQUESTED')
    image=selected.get('analysis_image')
    require(isinstance(image,dict) and record['input_sha256']==selected.get('png_sha256')==image.get('png_sha256') and
        record['input_png_bytes']==selected.get('png_bytes')==image.get('png_bytes') and
        record['image_width']==selected.get('image_width')==image.get('width') and
        record['image_height']==selected.get('image_height')==image.get('height'),'PNG_REPLAY_ORIGINAL_BYTES')
    require(selected.get('image_png_base64')==image.get('image_png_base64'),'PNG_REPLAY_NO_REENCODE')
    require(index.get('app_version')==record['app_version'] and index.get('app_build')==record['app_build'],'PNG_REPLAY_APP_VERSION')
    elapsed_summary([record])
    state=selected.get('screen_read_state');envelope=selected.get('research_candidate_envelope');failure=selected.get('r559_ocr_failure')
    if record['status']=='SUCCESS':
        require(isinstance(state,dict) and state.get('source_validation')=='PASS_FRAME_BINDING_ONLY' and
            state.get('screen_read_engine_version')=='r571.snapshot.v1' and isinstance(envelope,str) and failure is None,'PNG_REPLAY_SUCCESS_STATE')
        wrapper=parse_json(envelope);packet=parse_json(wrapper['payload_json'])
        require(integer(packet.get('received_at_ms'),1) and packet['received_at_ms']>=packet['observed_at_ms'],'PNG_REPLAY_RECEIPT_ORDER')
        require(packet.get('ocr_engine_version')=='r560.full-frame.v3' and isinstance(packet.get('ocr_request_audit'),dict),'PNG_REPLAY_SHARED_OCR_REQUIRED')
        require(packet['ocr_request_audit'].get('input_binding')=='EXACT_PNG_BYTES_DECODED_UP','PNG_REPLAY_EXACT_REQUEST')
    else:
        require(state is None and envelope is None and isinstance(failure,dict),'PNG_REPLAY_FAILED_WITHOUT_RESULT')
    if expected is not None:
        require(record['sample_id']==expected['sample_id'] and record['input_sha256']==expected['sha256'] and
            record['input_png_bytes']==expected['bytes'] and record['image_width']==expected['width'] and record['image_height']==expected['height'],'PNG_REPLAY_EXPECTED_INPUT')
    return record

def verify_replay_archive(path,expected=None,expected_sha256=None):
    receipt=verify_archive(path,expected_sha256)
    with zipfile.ZipFile(path) as archive:
        selected=parse_json(archive.read('selected_evidence.json'));index=parse_json(archive.read('evidence_integrity.json'))
        manifest=parse_json(archive.read('capture_manifest.json'))
        record=validate_replay_record(selected,index,manifest,expected)
        frames=[n for n in archive.namelist() if n.startswith('frames/')]
        require(len(frames)==1 and sha(archive.read(frames[0]))==record['input_sha256'],'PNG_REPLAY_SINGLE_ORIGINAL_FRAME')
    return dict(status='PASS_OFFLINE_PNG_REPLAY_INTERNAL_BYTES_AND_SHARED_READER_METADATA_ONLY',archive=receipt,replay=record,
        actual_execution_attested=False,game_accuracy_certified=False,device_certified=False)

def validate_report_header(report,count,app_version,app_build):
    require(isinstance(report,dict) and report.get('status')=='EXPORTED_UNVERIFIED_OFFLINE_PNGS' and
        report.get('scope')=='EXACT_PNG_SHARED_APP_READER_OFFLINE_ONLY','PNG_REPLAY_NATIVE_STATUS')
    require(type(report.get('expected_inputs')) is int and report['expected_inputs']==count and
        report.get('app_version')==app_version and report.get('app_build')==app_build,'PNG_REPLAY_NATIVE_HEADER')
    for flag in ('game_accuracy_certified','device_certified','iOS_runtime_executed'):
        require(report.get(flag) is False,'PNG_REPLAY_NATIVE_PROMOTION')

def verify_native_report(report,destination,expected_inputs,app_version,app_build):
    """Recover the actual Swift files; native success is still synthetic-only."""
    import base64,hashlib
    validate_report_header(report,len(expected_inputs),app_version,app_build)
    rows=report.get('results');require(isinstance(rows,list) and len(rows)==len(expected_inputs),'PNG_REPLAY_NATIVE_COUNT')
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False);receipts=[]
    for index,(row,expected) in enumerate(zip(rows,expected_inputs)):
        require(row.get('sample_id')==expected['sample_id'] and row.get('status') in ('SUCCESS','FAILED'),'PNG_REPLAY_NATIVE_SAMPLE')
        encoded=row.get('archive_base64');require(isinstance(encoded,str) and 0<len(encoded)<4_000_000,'PNG_REPLAY_NATIVE_SIZE')
        data=base64.b64decode(encoded,validate=True);require(hashlib.sha256(data).hexdigest()==row.get('archive_sha256'),'PNG_REPLAY_NATIVE_SHA')
        path=destination/('replay_'+str(index)+'.zip');path.write_bytes(data)
        receipt=verify_replay_archive(path,expected,row['archive_sha256'])
        require(receipt['replay']['app_version']==app_version and receipt['replay']['app_build']==app_build,'PNG_REPLAY_NATIVE_APP')
        require(receipt['replay']['status']==row['status'],'PNG_REPLAY_NATIVE_STATUS_BINDING');receipts.append(receipt)
    return dict(status='PASS_NATIVE_REPLAY_ZIPS_ONLY',archives=receipts,game_accuracy_certified=False,device_certified=False)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('archive',type=Path);args=parser.parse_args()
    print(json.dumps(verify_replay_archive(args.archive),indent=2))

if __name__=='__main__':main()
