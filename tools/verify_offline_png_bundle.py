"""R580: verify R578 on-device offline PNG+OCR evidence ZIP, byte for byte.

No inference about owner, Mega identity, image truth, live capture or model quality.
Only accepts the three-file STORE archive emitted by R578OfflineBundleWriter.
"""
import hashlib
import json
import re
import struct
import zipfile
import zlib
from pathlib import Path

IMAGE='original.png'
DIAGNOSTIC='diagnostic.json'
MANIFEST='manifest.json'
EXPECTED={IMAGE,DIAGNOSTIC,MANIFEST}
SCHEMA='trueplan.r578.offline-source-diagnostic-bundle.v1'
REPORT_SCHEMA='trueplan.r577.offline-ocr-mega-diagnostic.v1'
MAX_ZIP=19_000_000
MAX_PNG=12_000_000
MAX_DIAGNOSTIC=6_000_000
MAX_MANIFEST=32_000
SHA_RE=re.compile(r'[a-f0-9]{64}\Z')


def need(ok,reason):
    if not ok:raise ValueError('R580_'+reason)


def sha(blob):return hashlib.sha256(blob).hexdigest()


def strict_json(blob):
    def no_duplicate(pairs):
        o={}
        for k,v in pairs:
            need(k not in o,'DUPLICATE_JSON_KEY');o[k]=v
        return o
    def no_invalid(token):raise ValueError('R580_NONFINITE_NUMBER')
    return json.loads(blob.decode('utf-8'),object_pairs_hook=no_duplicate,parse_constant=no_invalid)


def no_claims(o,fields):
    need(isinstance(o,dict),'OBJECT_REQUIRED')
    for key in fields:need(o.get(key) is False,'UNAUTHORIZED_CLAIM_'+key.upper())


def png_dimensions(data):
    need(45<=len(data)<=MAX_PNG,'PNG_SIZE')
    need(data[:8]==b'\x89PNG\r\n\x1a\n' and data[-12:]==b'\x00\x00\x00\x00IEND\xaeB`\x82','PNG_FORMAT')
    need(data[8:16]==b'\x00\x00\x00\x0dIHDR','PNG_IHDR')
    width,height=struct.unpack('>II',data[16:24])
    need(0<width<=8192 and 0<height<=8192 and width*height<=36_000_000,'PNG_DIMENSIONS')
    # Validate the integrity of the full PNG stream, not merely a header and suffix.
    offset=8;seen_ihdr=False;seen_iend=False;has_idat=False
    while offset<len(data):
        need(offset+12<=len(data),'PNG_CHUNK_OVERFLOW')
        length=struct.unpack_from('>I',data,offset)[0]
        need(length<=MAX_PNG and offset+12+length<=len(data),'PNG_CHUNK_LENGTH')
        kind=data[offset+4:offset+8];body=data[offset+8:offset+8+length]
        checksum=struct.unpack_from('>I',data,offset+8+length)[0]
        need((zlib.crc32(kind+body)&0xffffffff)==checksum,'PNG_CHUNK_CRC')
        if offset==8:need(kind==b'IHDR' and length==13,'PNG_FIRST_CHUNK')
        if kind==b'IHDR':
            need(not seen_ihdr and offset==8,'PNG_IHDR_DUPLICATE');seen_ihdr=True
        if kind==b'IDAT':has_idat=True
        if kind==b'IEND':
            need(length==0 and offset+12==len(data),'PNG_TRAILING_DATA');seen_iend=True
        offset+=12+length
    need(seen_ihdr and seen_iend and has_idat,'PNG_REQUIRED_CHUNKS')
    return width,height


def verify_archive(path):
    path=Path(path)
    need(path.is_file() and 0<path.stat().st_size<=MAX_ZIP,'ZIP_SIZE')
    with zipfile.ZipFile(path) as z:
        infos=z.infolist()
        need(len(infos)==3 and {i.filename for i in infos}==EXPECTED,'ZIP_MEMBERS')
        need(all(i.compress_type==zipfile.ZIP_STORED and i.flag_bits&1==0 and not i.is_dir() for i in infos),'ZIP_FORMAT')
        need(all(0<i.file_size<=({IMAGE:MAX_PNG,DIAGNOSTIC:MAX_DIAGNOSTIC,MANIFEST:MAX_MANIFEST}[i.filename]) for i in infos),'ZIP_MEMBER_SIZE')
        data={i.filename:z.read(i) for i in infos}
        need(all(len(data[i.filename])==i.file_size and zlib.crc32(data[i.filename])&0xffffffff==i.CRC for i in infos),'ZIP_CRC')
    w,h=png_dimensions(data[IMAGE]);image_hash=sha(data[IMAGE]);report=strict_json(data[DIAGNOSTIC]);manifest=strict_json(data[MANIFEST])
    need(isinstance(manifest,dict) and manifest.get('schema')==SCHEMA and manifest.get('source_kind')=='USER_IMPORTED_PNG_OFFLINE_ONLY','MANIFEST_SCHEMA')
    need(manifest.get('image_sha256')==image_hash and SHA_RE.fullmatch(image_hash) is not None,'MANIFEST_SOURCE')
    no_claims(manifest,('current_state_eligible','owner_certified','mega_visual_certified','game_accuracy_certified','battle_advice_authorized'))
    need(manifest.get('user_explicit_share_required') is True and manifest.get('bundle_contains_original_png') is True,'MANIFEST_SHARE')
    entries=manifest.get('entries')
    need(isinstance(entries,list) and len(entries)==2 and {e.get('path') for e in entries if isinstance(e,dict)}=={IMAGE,DIAGNOSTIC},'MANIFEST_ENTRIES')
    for entry in entries:
        need(isinstance(entry,dict) and set(entry)=={'path','bytes','sha256','crc32'},'MANIFEST_ENTRY_FORMAT')
        source=data[entry['path']]
        need(type(entry['bytes']) is int and entry['bytes']==len(source),'MANIFEST_SIZE')
        need(entry['sha256']==sha(source),'MANIFEST_SHA')
        need(type(entry['crc32']) is int and entry['crc32']==zlib.crc32(source)&0xffffffff,'MANIFEST_CRC')
    need(isinstance(report,dict) and report.get('schema')==REPORT_SCHEMA,'DIAGNOSTIC_SCHEMA')
    need(report.get('source_kind')=='USER_IMPORTED_PNG_OFFLINE_ONLY' and report.get('image_sha256')==image_hash,'DIAGNOSTIC_SOURCE')
    need(type(report.get('image_width')) is int and report['image_width']==w and
         type(report.get('image_height')) is int and report['image_height']==h and
         type(report.get('png_bytes')) is int and report['png_bytes']==len(data[IMAGE]),'DIAGNOSTIC_GEOMETRY')
    no_claims(report,('current_state_eligible','owner_certified','turn_certified','mega_form_visual_certified','real_game_accuracy_certified','battle_advice_authorized','ground_truth_labels_present','source_png_in_report'))
    need(report.get('user_opt_in_share_required') is True,'DIAGNOSTIC_SHARE')
    packet=report.get('payload');snapshot=report.get('snapshot');mega=report.get('mega_text_probe')
    need(all(isinstance(v,dict) for v in (packet,snapshot,mega)),'DIAGNOSTIC_GROUPS')
    need(packet.get('image_sha256')==image_hash and type(packet.get('frame_id')) is int and packet['frame_id']==1 and type(packet.get('epoch')) is int and packet['epoch']==1 and packet.get('source_ref')=='user-imported-exact-png-not-live','PAYLOAD_PROVENANCE')
    need(snapshot.get('image_sha256')==image_hash and mega.get('image_sha256')==image_hash,'CROSS_PROVENANCE')
    no_claims(snapshot,('current_state_eligible','battle_advice_authorized'))
    no_claims(mega,('mega_certified','visual_form_certified'))
    need(manifest.get('capture_session_id') is None and manifest.get('turn') is None and report.get('capture_session_id') is None,'HISTORICAL_ONLY')
    return {'archive_sha256':sha(path.read_bytes()),'image_sha256':image_hash,'payload':packet,'snapshot':snapshot,'mega':mega,
            'image_width':w,'image_height':h,'report_sha256':sha(data[DIAGNOSTIC]),'manifest_sha256':sha(data[MANIFEST])}
