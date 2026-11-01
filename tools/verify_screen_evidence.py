"""Independent, bounded PC verification of an R551 screen-read evidence ZIP.

Only the Python standard library is needed. No extraction and no network.
An internally consistent ZIP does not certify OCR accuracy or a physical device.
"""
from pathlib import Path, PurePosixPath
import argparse, base64, binascii, hashlib, json, math, re, stat, struct, sys, zipfile, zlib
from screen_read_semantics import expected_value, expected_conflicts, expected_domains, normalized, canonical
from screen_read_layout import variants, layout_report
from verify_source_bound_hints import verify_source_bound_report
from screen_read_classification import classification_report
from verify_ocr_request import validate_ocr_request
from verify_ocr_failures import validate_ocr_failure
from verify_candidate_lease import validate_candidate_lease

INDEX = 'evidence_integrity.json'
SCHEMA = 'trueplan.screen-read.evidence-integrity.v1'
MAX_ARCHIVE = 128 * 1024 * 1024
MAX_ENTRY = 48 * 1024 * 1024
MAX_TOTAL = 96 * 1024 * 1024

class EvidenceError(ValueError): pass

def require(condition, code):
    if not condition: raise EvidenceError(code)

def integer(value, minimum=0):
    return type(value) is int and minimum <= value <= 2**63-1

def sha(data): return hashlib.sha256(data).hexdigest()

def is_sha(value): return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None

def _declared_row_sources(packet):
    rows = packet.get('readings')
    require(isinstance(rows,list) and len(rows)<=512,'ROW_SOURCE_READING_SET')
    fields = ('source_frame_id','source_epoch','source_image_sha256')
    for row in rows:
        require(isinstance(row,dict),'ROW_SOURCE_READING_TYPE')
        if row.get('reason') != 'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND':continue
        present = [key in row for key in fields]
        if not any(present):continue  # Legacy: packet declaration only, never truth/owner/current.
        require(all(present),'ROW_SOURCE_PARTIAL_DECLARATION')
        require(integer(row['source_frame_id'],1) and row['source_frame_id']==packet['frame_id'] and
                integer(row['source_epoch'],1) and row['source_epoch']==packet['epoch'] and
                row['source_image_sha256']==packet['image_sha256'],'ROW_SOURCE_CONFLICT')

def _pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'DUPLICATE_JSON_KEY')
        result[key] = value
    return result

def parse_json(data):
    try:
        result = json.loads(data, object_pairs_hook=_pairs,
                            parse_constant=lambda _: (_ for _ in ()).throw(EvidenceError('NONFINITE_JSON')))
    except EvidenceError: raise
    except (ValueError, UnicodeError, RecursionError) as error: raise EvidenceError('INVALID_JSON') from error
    require(isinstance(result, dict), 'JSON_ROOT_NOT_OBJECT')
    return result

def _path(name):
    return (isinstance(name, str) and 0 < len(name) <= 120 and
            re.fullmatch('[A-Za-z0-9_./-]+', name) is not None and '..' not in name and
            not name.startswith('/') and
            all(part not in ('', '.', '..') for part in name.split('/')))

def _png(data, width, height):
    require(len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n' and
            data[8:16] == b'\x00\x00\x00\rIHDR', 'PNG_HEADER')
    actual = struct.unpack('>II', data[16:24])
    require(integer(width, 1) and integer(height, 1) and actual == (width, height) and
            max(actual) <= 3072 and width * height <= 4_500_000, 'PNG_DIMENSIONS')
    # Validate every PNG chunk CRC and the complete IEND boundary, not just IHDR.
    offset, seen_iend, idat = 8, False, bytearray()
    bit_depth, color_type, compression, filtering, interlace = data[24:29]
    channels = {0:1,2:3,3:1,4:2,6:4}.get(color_type)
    depths = {0:{1,2,4,8,16},2:{8,16},3:{1,2,4,8},4:{8,16},6:{8,16}}
    require(channels is not None and bit_depth in depths[color_type] and compression == filtering == 0 and interlace in (0,1), 'PNG_FORMAT')
    while offset < len(data):
        require(offset + 12 <= len(data), 'PNG_TRUNCATED_CHUNK')
        size = struct.unpack('>I', data[offset:offset+4])[0]
        require(size <= len(data) - offset - 12, 'PNG_CHUNK_SIZE')
        kind = data[offset+4:offset+8]
        body = data[offset+4:offset+8+size]
        crc = struct.unpack('>I', data[offset+8+size:offset+12+size])[0]
        require(binascii.crc32(body) & 0xffffffff == crc, 'PNG_CHUNK_CRC')
        offset += size + 12
        if kind == b'IDAT': idat.extend(body[4:])
        if kind == b'IEND':
            require(size == 0 and offset == len(data), 'PNG_IEND_BOUNDARY')
            seen_iend = True
    require(seen_iend, 'PNG_MISSING_IEND')
    passes = [(0,0,1,1)] if interlace == 0 else [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
    rows = []
    for x0,y0,dx,dy in passes:
        pw,ph = max(0,(width-x0+dx-1)//dx),max(0,(height-y0+dy-1)//dy)
        if pw and ph: rows.extend([1+(pw*bit_depth*channels+7)//8]*ph)
    expected_output = sum(rows)
    try:
        decoder = zlib.decompressobj()
        pixels = decoder.decompress(idat, expected_output+1)
        require(len(pixels) == expected_output and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, 'PNG_DECODE_SIZE_OR_STREAM')
    except zlib.error as error: raise EvidenceError('PNG_DECODE') from error
    cursor = 0
    for length in rows:
        require(pixels[cursor] in range(5), 'PNG_FILTER')
        cursor += length

def _embedded_image(root, width_key, height_key):
    try: data = base64.b64decode(root.get('image_png_base64', ''), validate=True)
    except (ValueError, TypeError, binascii.Error) as error: raise EvidenceError('IMAGE_BASE64') from error
    require(0 < len(data) <= 12_000_000, 'EMBEDDED_IMAGE_LIMIT')
    require(root.get('png_bytes') == len(data) and is_sha(root.get('png_sha256')) and
            sha(data) == root['png_sha256'], 'EMBEDDED_IMAGE_SHA_OR_SIZE')
    _png(data, root.get(width_key), root.get(height_key))
    return data

def _rotation_ocr(root, expected_image_sha):
    require(isinstance(root, dict) and root.get('image_sha256') == expected_image_sha, 'ROTATION_IMAGE_BINDING')
    require(root.get('mega_certified') is False and root.get('own_opponent') == 'UNKNOWN', 'MEGA_OR_OWNER_CLAIM')
    completed, failed, skipped = (root.get(k) for k in ('rotations_completed', 'rotations_failed', 'rotations_skipped'))
    require(all(isinstance(x, list) for x in (completed, failed, skipped)), 'ROTATION_LISTS')
    all_degrees = completed + failed + skipped
    require(all(type(x) is int for x in all_degrees) and sorted(all_degrees) == [0,90,180,270], 'ROTATION_COVERAGE')
    rows = root.get('orientation_evidence')
    require(isinstance(rows, list) and len(rows) <= 4, 'ROTATION_EVIDENCE')
    degrees = []
    for orientation in rows:
        require(isinstance(orientation, dict), 'ROTATION_ROW')
        degree = orientation.get('orientation_degrees')
        require(degree in completed + failed and degree not in degrees, 'ROTATION_ROW_BINDING')
        degrees.append(degree)
        observations = orientation.get('observations')
        require(isinstance(observations, list) and len(observations) <= 250, 'OCR_ROW_LIMIT')
        for observation in observations:
            require(isinstance(observation, dict), 'OCR_OBSERVATION')
            candidates, rect = observation.get('candidates'), observation.get('roi')
            require(isinstance(candidates, list) and 1 <= len(candidates) <= 3 and isinstance(rect, dict), 'OCR_CANDIDATES_OR_ROI')
            for candidate in candidates:
                require(isinstance(candidate, dict), 'OCR_CANDIDATE')
                text, confidence = candidate.get('text'), candidate.get('confidence')
                require(isinstance(text, str) and len(text) <= 1024 and type(confidence) in (int,float) and
                        math.isfinite(confidence) and 0 <= confidence <= 1, 'OCR_TEXT_OR_CONFIDENCE')
            values = [rect.get(k) for k in ('x','y','width','height')]
            require(all(type(v) in (int,float) and math.isfinite(v) for v in values), 'ROI_NUMBERS')
            x,y,w,h = values
            require(x >= 0 and y >= 0 and w > 0 and h > 0 and x+w <= 1.000001 and y+h <= 1.000001, 'ROI_BOUNDS')
    require(sorted(degrees) == sorted(completed + failed), 'ROTATION_RAW_EVIDENCE_MISSING')
    if root.get('schema') == 'trueplan.r551.rotation-ocr-evidence.v1':
        require(root.get('megascene_observed') is None and root.get('mega_event_status') == 'UNKNOWN' and
                root.get('visual_form_certified') is False and root.get('orientation_certified') is False, 'UNVERIFIED_STATE_PROMOTION')

def _snapshot(state, packet, session, frame, epoch, image_sha, width, height):
    require(isinstance(state, dict) and state.get('schema') == 'trueplan.screen-read.snapshot.v1', 'SNAPSHOT_SCHEMA')
    require(state.get('capture_session_id') == session and state.get('frame_id') == frame and type(state.get('frame_id')) is int and
            state.get('epoch') == epoch and type(state.get('epoch')) is int and state.get('image_sha256') == image_sha and
            state.get('battle_id') is None and state.get('turn') is None and state.get('capture_timestamp_ms') is None,
            'SNAPSHOT_SOURCE_BINDING')
    require(state.get('validity') == 'HISTORICAL_FRAME_ONLY' and state.get('current_state_eligible') is False and
            state.get('battle_advice_authorized') is False, 'SNAPSHOT_CURRENT_OR_ADVICE_CLAIM')
    def unknowns(value):
        if isinstance(value, dict):
            if 'knowledge_state' in value:
                require(value.get('knowledge_state') == 'UNKNOWN' and value.get('value') is None, 'UNVERIFIED_SIDE_VALUE')
            else:
                for child in value.values(): unknowns(child)
        elif isinstance(value, list):
            for child in value: unknowns(child)
        else: raise EvidenceError('SNAPSHOT_FIELD_STRUCTURE')
    for side in ('own','opponent','field'):
        require(isinstance(state.get(side), dict), 'SNAPSHOT_SIDE_MISSING')
        unknowns(state[side])
    readings = packet.get('readings')
    require(isinstance(readings, list) and len(readings) <= 512, 'SNAPSHOT_SOURCE_READINGS')
    candidates = state.get('candidates')
    require(isinstance(candidates, list) and len(candidates) <= 4096, 'SNAPSHOT_CANDIDATES')
    source_values_enabled = state.get('screen_read_engine_version') == 'r571.snapshot.v1'
    screen_evidence_enabled = state.get('screen_read_engine_version') in ('r557.snapshot.v1','r571.snapshot.v1')
    require('screen_classification' not in state or screen_evidence_enabled,'SNAPSHOT_SCREEN_POLICY_VERSION')
    alternatives_enabled = state.get('screen_read_engine_version') in ('r553.snapshot.v1','r557.snapshot.v1','r571.snapshot.v1')
    structured = state.get('screen_read_engine_version') in ('r552.snapshot.v1','r553.snapshot.v1','r557.snapshot.v1','r571.snapshot.v1')
    require('owner_position_hints' not in state or alternatives_enabled,'SNAPSHOT_OWNER_HINT_POLICY_VERSION')
    sources = {}
    if alternatives_enabled:
        for index,row in enumerate(readings):
            require(isinstance(row,dict),'SNAPSHOT_SOURCE_ROW')
            if row.get('reason') != 'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND':continue
            try:
                for variant in variants(row,index):sources[variant['reference']] = (row,variant)
            except ValueError as error:raise EvidenceError(str(error)) from error
    if structured:
        required_state = {'schema','capture_session_id','battle_id','frame_id','epoch','receipt_uptime_ms',
            'capture_timestamp_ms','turn','orientation','image_sha256','knowledge_state','validity','stale_deadline_ms',
            'current_state_eligible','battle_advice_authorized','own','opponent','field','candidates','source_validation','conflicts'}
        require(required_state <= state.keys() and state.get('source_validation') in ('HOLD','PASS_FRAME_BINDING_ONLY') and
                (not candidates or state['source_validation'] == 'PASS_FRAME_BINDING_ONLY'), 'SNAPSHOT_REQUIRED_FIELDS')
        require(type(state.get('receipt_uptime_ms')) is int and state['receipt_uptime_ms'] == packet['observed_at_ms'] and
                state.get('timestamp_basis') == 'UNCALIBRATED_HOST_RECEIPT_UPTIME' and
                state.get('orientation') == 'ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED' and
                state.get('stale_deadline_ms') is None, 'SNAPSHOT_TIME_OR_TRANSFORM')
    for candidate in candidates:
        require(isinstance(candidate, dict), 'SNAPSHOT_CANDIDATE')
        ref = candidate.get('evidence_ref')
        pattern = r'payload_json\.readings\[([0-9]+)\](?:\.ocr_alternatives\[([12])\])?' if alternatives_enabled else r'payload_json\.readings\[([0-9]+)\]'
        match = re.fullmatch(pattern, ref) if isinstance(ref,str) else None
        require(match is not None and int(match[1]) < len(readings), 'SNAPSHOT_EVIDENCE_REF')
        row = readings[int(match[1])]
        source_text = row.get('raw_text') if isinstance(row,dict) else None
        source_confidence = row.get('confidence') if isinstance(row,dict) else None
        if alternatives_enabled:
            require(ref in sources, 'SNAPSHOT_ALTERNATIVE_REF')
            row, variant = sources[ref]
            source_text, source_confidence = variant['text'], variant['confidence']
            require(type(candidate.get('ocr_rank')) is int and candidate['ocr_rank'] == variant['rank'], 'SNAPSHOT_ALTERNATIVE_RANK')
        require(isinstance(row,dict) and candidate.get('raw_text') == source_text and
                candidate.get('image_sha256') == image_sha and candidate.get('capture_session_id') == session and
                candidate.get('frame_id') == frame and type(candidate.get('frame_id')) is int and
                candidate.get('epoch') == epoch and type(candidate.get('epoch')) is int and
                row.get('reason') == 'FULL_FRAME_TEXT_OWNER_AND_TURN_UNBOUND',
                'SNAPSHOT_CANDIDATE_SOURCE')
        require(candidate.get('knowledge_state') == 'INFERRED' and candidate.get('side') == 'UNKNOWN_OWNER' and
                candidate.get('verification_status') == 'UNVERIFIED' and candidate.get('current_state_eligible') is False and
                candidate.get('validity') == 'HISTORICAL_FRAME_ONLY', 'SNAPSHOT_UNVERIFIED_PROMOTION')
        raw, domain = candidate.get('raw_text'), candidate.get('domain')
        require(isinstance(raw,str) and 0 < len(raw) <= 256 and isinstance(domain,str), 'SNAPSHOT_LITERAL_INPUT')
        try:
            value = expected_value(raw, domain, structured=structured or isinstance(candidate.get('value'),dict))
        except ValueError as error:
            raise EvidenceError(str(error)) from error
        # JSON has no boolean-as-number coercion here. Numerically equal percent
        # ints/floats are acceptable; structured integers and counters are exact.
        actual = candidate.get('value')
        if domain == 'hp_percent':
            require(type(actual) in (int,float) and math.isfinite(actual) and actual == value, 'SNAPSHOT_LITERAL_VALUE')
        else:
            require(canonical(actual) == canonical(value), 'SNAPSHOT_LITERAL_VALUE')
        roi = candidate.get('roi')
        if roi is not None:
            require(isinstance(roi,dict) and set(roi) == {'x','y','width','height'} and
                    all(integer(roi.get(k)) for k in ('x','y','width','height')), 'SNAPSHOT_ROI_NUMBERS')
            x,y,w,h = (roi[k] for k in ('x','y','width','height'))
            require(w > 0 and h > 0 and x+w <= width and y+h <= height and
                    row.get('roi_rect') == roi and row.get('source_frame_id') == frame and type(row.get('source_frame_id')) is int and
                    row.get('source_epoch') == epoch and type(row.get('source_epoch')) is int and
                    row.get('source_image_sha256') == image_sha and
                    candidate.get('roi_coordinate_space') == 'ANALYSIS_PIXELS_TOP_LEFT', 'SNAPSHOT_ROI_BINDING')
        if structured:
            required_candidate = {'domain','value','knowledge_state','raw_text','normalized_text','side','battle_id',
                'capture_session_id','frame_id','epoch','turn','capture_timestamp_ms','receipt_uptime_ms','orientation',
                'image_sha256','roi','roi_coordinate_space','confidence','source','evidence_ref','validity','stale_deadline_ms',
                'verification_status','current_state_eligible'}
            require(required_candidate <= candidate.keys() and candidate.get('source') == 'VISION_OCR_TEXT_CANDIDATE' and
                    candidate.get('roi_coordinate_space') == 'ANALYSIS_PIXELS_TOP_LEFT', 'SNAPSHOT_CANDIDATE_REQUIRED_FIELDS')
            confidence = source_confidence
            safe_confidence = confidence if type(confidence) in (int,float) and math.isfinite(confidence) and 0 <= confidence <= 1 else None
            actual_confidence = candidate.get('confidence')
            require((safe_confidence is None and actual_confidence is None) or
                    (type(actual_confidence) in (int,float) and actual_confidence == safe_confidence), 'SNAPSHOT_CONFIDENCE_SOURCE')
            require(candidate.get('normalized_text') == normalized(raw) and
                    type(candidate.get('receipt_uptime_ms')) is int and candidate['receipt_uptime_ms'] == packet['observed_at_ms'] and
                    candidate.get('battle_id') is None and candidate.get('turn') is None and
                    candidate.get('capture_timestamp_ms') is None and candidate.get('stale_deadline_ms') is None and
                    candidate.get('orientation') == 'ANALYSIS_UP_SOURCE_TRANSFORM_UNVERIFIED', 'SNAPSHOT_CANDIDATE_TIME_OR_TRANSFORM')
    if structured or 'conflicts' in state:
        conflicts = state.get('conflicts')
        require(isinstance(conflicts,list) and len(conflicts) <= 8192, 'SNAPSHOT_CONFLICTS')
        expected = expected_conflicts(candidates)
        require(canonical(conflicts) == canonical(expected), 'SNAPSHOT_CONFLICT_BINDING')
        layout_conflicts = 0
        classification_conflict = False
        if alternatives_enabled:
            keys=[(c['evidence_ref'],c['domain']) for c in candidates]
            expected_keys={(ref,domain) for ref,(_,variant) in sources.items() for domain in expected_domains(variant['text'])}
            require(len(keys)==len(set(keys)) and set(keys)==expected_keys,'SNAPSHOT_ALTERNATIVE_COVERAGE')
            require('layout_candidates' in state and isinstance(state.get('screen_kind'),str),'SNAPSHOT_LAYOUT_REQUIRED')
            if screen_evidence_enabled:
                try:
                    classification = classification_report(packet,width,height,session,frame,epoch,image_sha,packet['observed_at_ms'])
                except ValueError as error:raise EvidenceError(str(error)) from error
                require(canonical(state.get('screen_classification'))==canonical(classification),'SNAPSHOT_SCREEN_CLASSIFICATION_SOURCE')
                require(state['screen_kind']==classification['screen_kind'],'SNAPSHOT_SCREEN_CLASSIFICATION_KIND')
                classification_conflict=classification['status'] in ('HOLD_OCR_SCREEN_CONFLICT','HOLD_PACKET_KIND_DISAGREEMENT')
            elif 'screen_kind' in packet:
                require(packet['screen_kind'] == state['screen_kind'],'SNAPSHOT_SCREEN_KIND_SOURCE')
            try:
                computed = layout_report(packet,width,height,state['screen_kind'],session,frame,epoch,image_sha,packet['observed_at_ms'],allow_details_overlay=screen_evidence_enabled)
            except ValueError as error:raise EvidenceError(str(error)) from error
            require(canonical(state['layout_candidates']) == canonical(computed),'SNAPSHOT_LAYOUT_SOURCE_OR_VALUE')
            if source_values_enabled or 'owner_position_hints' in state:
                try:
                    verify_source_bound_report(state.get('owner_position_hints'),packet,computed,width,height,
                        session,frame,epoch,image_sha,require_current=source_values_enabled)
                except ValueError as error:raise EvidenceError(str(error)) from error
            layout_conflicts = computed['conflict_count']
        require(state.get('knowledge_state') == ('CONFLICT' if expected or layout_conflicts or classification_conflict else 'UNKNOWN'), 'SNAPSHOT_CONFLICT_STATE')

def verify_archive(path, expected_sha256=None):
    path = Path(path)
    require(path.is_file() and 22 <= path.stat().st_size <= MAX_ARCHIVE, 'ARCHIVE_SIZE')
    raw = path.read_bytes()
    digest = sha(raw)
    if expected_sha256 is not None:
        require(is_sha(expected_sha256) and digest == expected_sha256, 'TRUSTED_ARCHIVE_SHA_MISMATCH')
    # Our writer has no ZIP comments. Reject prefixed/trailing bytes and hidden entries.
    require(raw[-22:-18] == b'PK\x05\x06', 'EOCD_OR_TRAILING_BYTES')
    end = struct.unpack('<4s4H2IH', raw[-22:])
    _, disk, cd_disk, disk_count, count, cd_size, cd_offset, comment = end
    require(disk == cd_disk == comment == 0 and disk_count == count and 1 <= count <= 16 and
            cd_offset + cd_size == len(raw)-22, 'CENTRAL_DIRECTORY_RANGE')
    contents = {}
    try:
        with zipfile.ZipFile(path) as z:
            infos = z.infolist()
            require(len(infos) == count, 'ZIP_ENTRY_COUNT')
            total, cursor = 0, 0
            for info in sorted(infos, key=lambda x:x.header_offset):
                require(_path(info.filename) and info.filename not in contents and not info.is_dir(), 'UNSAFE_OR_DUPLICATE_NAME')
                require(not stat.S_ISLNK(info.external_attr >> 16), 'ZIP_SYMLINK')
                require(info.compress_type in (0,8) and not info.flag_bits & ~0x800, 'ZIP_FEATURE_NOT_ALLOWED')
                require(0 <= info.file_size <= MAX_ENTRY and total <= MAX_TOTAL-info.file_size, 'ZIP_OUTPUT_LIMIT')
                total += info.file_size
                offset = info.header_offset
                require(offset == cursor and offset + 30 <= cd_offset and raw[offset:offset+4] == b'PK\x03\x04', 'ZIP_LOCAL_RANGE')
                _,ver,flags,method,tm,dt,crc,packed,plain,nlen,xlen = struct.unpack('<4s5H3I2H', raw[offset:offset+30])
                name = raw[offset+30:offset+30+nlen]
                require(name == info.filename.encode('utf-8') and flags == info.flag_bits and method == info.compress_type and
                        crc == info.CRC and packed == info.compress_size and plain == info.file_size, 'LOCAL_CENTRAL_MISMATCH')
                cursor = offset+30+nlen+xlen+packed
                require(cursor <= cd_offset, 'ZIP_OVERLAP_OR_TRUNCATION')
                with z.open(info) as member: data = member.read(MAX_ENTRY+1)
                require(len(data) == info.file_size and binascii.crc32(data)&0xffffffff == info.CRC, 'ZIP_CRC_OR_SIZE')
                contents[info.filename] = data
            require(cursor == cd_offset, 'HIDDEN_LOCAL_ZIP_BYTES')
    except EvidenceError: raise
    except (ValueError, OSError, zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        raise EvidenceError('ZIP_READ_OR_CRC_FAILURE') from error
    require(INDEX in contents, 'NO_PORTABLE_SHA_INDEX_LEGACY_HOLD')
    index = parse_json(contents[INDEX])
    require(index.get('schema') == SCHEMA and index.get('self_hash_included') is False and
            index.get('battle_advice_authorized') is False, 'INDEX_SCHEMA_OR_SCOPE')
    session, frame, epoch = index.get('capture_session_id'), index.get('selected_frame_id'), index.get('selected_epoch')
    require(isinstance(session, str) and 0 < len(session) <= 128 and integer(frame,1) and integer(epoch,1) and
            index.get('battle_id') is None, 'INDEX_SOURCE_IDENTITY')
    rows = index.get('entries')
    require(isinstance(rows, list) and len(rows) == len(contents)-1 and
            type(index.get('entry_count_excluding_index')) is int and index['entry_count_excluding_index'] == len(rows), 'INDEX_ENTRY_COUNT')
    indexed = set()
    for row in rows:
        require(isinstance(row, dict), 'INDEX_ROW')
        name = row.get('path')
        require(_path(name) and name != INDEX and name not in indexed and name in contents, 'INDEX_NAME')
        indexed.add(name)
        data = contents[name]
        require(integer(row.get('bytes')) and row['bytes'] == len(data) and
                is_sha(row.get('sha256')) and row['sha256'] == sha(data) and
                integer(row.get('crc32')) and row['crc32'] == binascii.crc32(data)&0xffffffff, 'INDEX_SHA_CRC_OR_SIZE')
    require(indexed == set(contents)-{INDEX}, 'INDEX_MISSING_MEMBER')
    require({'selected_evidence.json','capture_manifest.json'} <= indexed, 'MISSING_REQUIRED_EVIDENCE')
    selected = parse_json(contents['selected_evidence.json'])
    manifest = parse_json(contents['capture_manifest.json'])
    require(selected.get('frame_id') == frame and type(selected.get('frame_id')) is int and
            selected.get('epoch') == epoch and type(selected.get('epoch')) is int and
            selected.get('capture_session_id') == session and selected.get('battle_id') is None and
            selected.get('production_enabled') is False and selected.get('battle_advice_authorized') is False and
            integer(selected.get('observed_ms_monotonic'),1), 'SELECTED_SOURCE_OR_SCOPE')
    selected_png = _embedded_image(selected, 'image_width', 'image_height')
    candidate = selected.get('research_candidate_envelope')
    failure = selected.get('r559_ocr_failure')
    if failure is not None:
        try:validate_ocr_failure(failure,selected)
        except ValueError as error:raise EvidenceError(str(error)) from error
        if selected.get('analysis_image') is not None:_embedded_image(selected['analysis_image'],'width','height')
    packet = None
    if candidate is not None:
        require(isinstance(candidate, str), 'OCR_ENVELOPE_TYPE')
        wrapper = parse_json(candidate)
        require(wrapper.get('schema') == 'trueplan.mobile-envelope.v1','ROW_SOURCE_ENVELOPE_SCHEMA')
        payload_text = wrapper.get('payload_json')
        require(isinstance(payload_text, str) and is_sha(wrapper.get('payload_sha256')) and
                sha(payload_text.encode()) == wrapper['payload_sha256'], 'OCR_PAYLOAD_SHA')
        packet = parse_json(payload_text)
        require(packet.get('schema') == 'trueplan.mobile-observation.v1','OCR_PACKET_SCHEMA')
        analysis = selected.get('analysis_image')
        require(isinstance(analysis, dict), 'OCR_ANALYSIS_IMAGE_MISSING')
        _embedded_image(analysis, 'width', 'height')
        require(packet.get('frame_id') == frame and type(packet.get('frame_id')) is int and
                packet.get('epoch') == epoch and type(packet.get('epoch')) is int and
                packet.get('battle_id') == session and packet.get('image_sha256') == analysis['png_sha256'] and
                packet.get('observed_at_ms') == selected['observed_ms_monotonic'] and
                packet.get('production_enabled') is False, 'OCR_SOURCE_OR_SCOPE_MISMATCH')
    if packet is not None:
        _declared_row_sources(packet)
        rows=packet.get('readings')
        audit_present=('ocr_request_audit' in packet or 'ocr_engine_version' in packet or
                       (isinstance(rows,list) and any(isinstance(r,dict) and 'ocr_observation_index' in r for r in rows)))
        if audit_present:
            try:validate_ocr_request(packet,selected)
            except ValueError as error:raise EvidenceError(str(error)) from error
    projection=selected.get('analysis_projection')
    if projection is not None:
        from screen_read_projection import validate_projection
        try:validate_projection(projection,selected,packet)
        except ValueError as error:raise EvidenceError(str(error)) from error
    state = selected.get('screen_read_state')
    if 'r563_input_health' in selected:
        from verify_input_health import validate_input_health
        try:validate_input_health(selected['r563_input_health'])
        except ValueError as error:raise EvidenceError(str(error)) from error
    leases = selected.get('r554_candidate_leases')
    if 'r562_read_clock_diagnostics' in selected:
        from verify_read_clock import validate_diagnostics
        try:validate_diagnostics(selected['r562_read_clock_diagnostics'])
        except ValueError as error:raise EvidenceError(str(error)) from error
    if leases is not None:
        require(isinstance(leases,dict) and set(leases)=={'automatic_full_frame','paired_move_candidates'},'LEASE_CHANNELS')
        try:
            for lease in leases.values():validate_candidate_lease(lease)
        except ValueError as error:raise EvidenceError(str(error)) from error
    if state is not None:
        require(packet is not None, 'SNAPSHOT_WITHOUT_OCR')
        _snapshot(state, packet, session, frame, epoch, selected['analysis_image']['png_sha256'],
                  selected['analysis_image']['width'], selected['analysis_image']['height'])
    require(manifest.get('selected_frame_id') == frame and type(manifest.get('selected_frame_id')) is int and
            manifest.get('selected_epoch') == epoch and type(manifest.get('selected_epoch')) is int and
            manifest.get('capture_session_id') == session and manifest.get('battle_id') is None and
            manifest.get('battle_advice_authorized') is False, 'CAPTURE_MANIFEST_SOURCE')
    frames = manifest.get('frames')
    require(isinstance(frames, list) and len(frames) <= 8 and type(manifest.get('captured_frame_count')) is int and
            manifest.get('captured_frame_count') == len(frames), 'CAPTURE_FRAME_COUNT')
    referenced, frame_ids = set(), set()
    last_observed = -1
    for snapshot in frames:
        require(isinstance(snapshot, dict), 'CAPTURE_FRAME_ROW')
        name, fid, obs = snapshot.get('file'), snapshot.get('frame_id'), snapshot.get('observed_ms_monotonic')
        require(_path(name) and name in contents and name.startswith('frames/') and name not in referenced and
                integer(fid,1) and fid not in frame_ids and snapshot.get('epoch') == epoch and type(snapshot.get('epoch')) is int and
                integer(obs,1) and obs > last_observed, 'CAPTURE_FRAME_IDENTITY_OR_ORDER')
        referenced.add(name); frame_ids.add(fid); last_observed = obs
        data = contents[name]
        require(snapshot.get('png_bytes') == len(data) and snapshot.get('png_sha256') == sha(data), 'CAPTURE_FRAME_SHA_OR_SIZE')
        _png(data, snapshot.get('width'), snapshot.get('height'))
        require(snapshot.get('own_opponent_certified') is False and snapshot.get('mega_form_visual_certified') is False, 'CAPTURE_FALSE_CERTIFICATION')
        if fid == frame: require(data == selected_png and obs == selected['observed_ms_monotonic'], 'SELECTED_FRAME_PIXEL_MISMATCH')
        _rotation_ocr(snapshot.get('mega_scene_ocr_hints'), sha(data))
    require(referenced == {n for n in contents if n.startswith('frames/')}, 'UNREFERENCED_FRAME')
    return {'status':'INTERNAL_BYTE_INTEGRITY_PASS','archive_sha256':digest,'entries':len(contents),
            'captured_frames':len(frames),'crc32':'PASS','all_entry_sha256':'PASS',
            'source_binding':'PASS','trusted_archive_sha_checked':expected_sha256 is not None,
            'ocr_accuracy_certified':False,'device_certified':False,'battle_advice_authorized':False}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive'); parser.add_argument('--expected-sha256')
    args=parser.parse_args()
    try: result=verify_archive(args.archive,args.expected_sha256)
    except (EvidenceError,OSError) as error:
        print(json.dumps({'status':'FAIL','reason':str(error)}));return 1
    print(json.dumps(result,ensure_ascii=False,indent=2));return 0

if __name__ == '__main__': sys.exit(main())
