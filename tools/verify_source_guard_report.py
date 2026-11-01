"""Independently check source decisions and real producer ZIP bytes, not OCR truth."""
import base64
import hashlib
from pathlib import Path
import zipfile
from verify_screen_evidence import parse_json, verify_archive, _declared_row_sources
from screen_read_semantics import canonical


def require(value, reason):
    if not value:raise ValueError(reason)


def source_valid(envelope):
    wrapper=parse_json(envelope)
    if wrapper.get('schema')!='trueplan.mobile-envelope.v1':return False
    payload=wrapper.get('payload_json')
    require(isinstance(payload,str) and hashlib.sha256(payload.encode()).hexdigest()==wrapper.get('payload_sha256'),
            'GUARD_REPORT_PAYLOAD_HASH')
    packet=parse_json(payload)
    if packet.get('schema')!='trueplan.mobile-observation.v1':return False
    require(packet.get('frame_id')==17 and type(packet.get('frame_id')) is int and
            packet.get('epoch')==3 and type(packet.get('epoch')) is int and
            packet.get('battle_id')=='capture-test' and packet.get('production_enabled') is False,
            'GUARD_REPORT_PACKET_SOURCE')
    try:_declared_row_sources(packet)
    except ValueError:return False
    return True


def match_archive_case(path, case, app_version='0.5.61', app_build='561'):
    # Caller has already run the bounded ZIP verifier, including CRC/SHA limits.
    with zipfile.ZipFile(path) as archive:
        selected=parse_json(archive.read('selected_evidence.json'))
        index=parse_json(archive.read('evidence_integrity.json'))
    require(selected.get('research_candidate_envelope')==case.get('envelope') and
            canonical(selected.get('screen_read_state'))==canonical(case.get('state')),'GUARD_REPORT_ARCHIVE_CASE_BINDING')
    require(index.get('app_version')==app_version and index.get('app_build')==app_build,'GUARD_REPORT_ARCHIVE_DECLARED_VERSION')


def verify_report(record, destination, app_version='0.5.61', app_build='561'):
    require(record.get('scope')=='SYNTHETIC_SOURCE_GUARD_ONLY' and type(record.get('checks')) is int and
            record['checks']==117,'GUARD_REPORT_SCOPE_OR_CHECKS')
    for flag in ('Vision_executed','game_accuracy_certified','device_certified','native_CI_certified'):
        require(record.get(flag) is False,'GUARD_REPORT_CERTIFICATION_CLAIM')
    cases=record.get('cases');require(isinstance(cases,list) and len(cases)==24,'GUARD_REPORT_CASE_COUNT')
    ids=[c.get('id') for c in cases];require(all(isinstance(i,str) for i in ids) and len(set(ids))==24,'GUARD_REPORT_CASE_IDS')
    expected_ids={'legacy_packet_only','explicit_no_roi','explicit_roi','float_integer_frame','late_foreign_discards_earlier_candidates'}
    expected_ids.update('invalid_'+str(i)+'_'+field for i,field in enumerate(
        ('source_frame_id','source_epoch','source_image_sha256','source_frame_id','source_frame_id','source_epoch','source_epoch'),3))
    expected_ids.update('partial_'+str(i) for i in range(1,7))
    expected_ids.update(target+'_schema_'+str(i) for target in ('wrapper','packet') for i in range(3))
    require(set(ids)==expected_ids,'GUARD_REPORT_CASE_SET')
    valid_ids=[]
    by_id={case['id']:case for case in cases}
    for case in cases:
        valid=source_valid(case['envelope']);state=case['state']
        require(case.get('expected_valid') is valid,'GUARD_REPORT_EXPECTED_DECISION')
        require(state.get('source_validation')==('PASS_FRAME_BINDING_ONLY' if valid else 'HOLD'), 'GUARD_REPORT_SWIFT_DECISION')
        require(state.get('current_state_eligible') is False and state.get('battle_advice_authorized') is False,'GUARD_REPORT_PROMOTION')
        if valid:valid_ids.append(case['id'])
        else:
            require(state.get('candidates')==[] and state.get('conflicts')==[] and
                    'screen_classification' not in state and 'layout_candidates' not in state and
                    state.get('knowledge_state')=='UNKNOWN','GUARD_REPORT_PARTIAL_PUBLICATION')
    require(set(valid_ids)=={'legacy_packet_only','explicit_no_roi','explicit_roi'},'GUARD_REPORT_VALID_CASES')
    projections=record.get('rejected_projections')
    require(isinstance(projections,list) and len(projections)==3 and all(p.get('status')=='HOLD' for p in projections),
            'GUARD_REPORT_PROJECTION_SCHEMA')
    archives=record.get('valid_archives');require(isinstance(archives,list) and len(archives)==3,'GUARD_REPORT_ARCHIVE_COUNT')
    require({row.get('id') for row in archives}==set(valid_ids),'GUARD_REPORT_ARCHIVE_CASES')
    destination=Path(destination);destination.mkdir(parents=True,exist_ok=False)
    receipts=[]
    for row in archives:
        encoded=row['archive_base64'];require(isinstance(encoded,str) and len(encoded)<2000000,'GUARD_REPORT_ARCHIVE_SIZE')
        data=base64.b64decode(encoded,validate=True)
        require(hashlib.sha256(data).hexdigest()==row['archive_sha256'],'GUARD_REPORT_ARCHIVE_SHA')
        path=destination/('r561_'+row['id']+'.zip')
        with path.open('xb') as stream:stream.write(data)
        receipt=verify_archive(path,expected_sha256=row['archive_sha256'])
        match_archive_case(path,by_id[row['id']],app_version,app_build)
        require(receipt['ocr_accuracy_certified'] is False and receipt['device_certified'] is False,'GUARD_REPORT_ZIP_PROMOTION')
        receipts.append(dict(id=row['id'],**receipt))
    return dict(status='PASS_SOURCE_GUARD_DECISIONS_AND_THREE_ZIPS_ONLY',cases=24,native_checks=117,
                archives=receipts,Vision_executed=False,game_accuracy_certified=False,device_certified=False)
