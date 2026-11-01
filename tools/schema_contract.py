"""Offline Draft-07 structural checks; protocol/source checks remain independent."""
from pathlib import Path
from functools import lru_cache
import copy,hashlib,json

ROOT=Path(__file__).resolve().parents[1]
DRAFT='http://json-schema.org/draft-07/schema#'

def verify_vendor():
    manifest=json.loads((ROOT/'tools/_vendor/VENDOR_MANIFEST.json').read_text())
    if manifest['commit']!='4f1ed6d9c0462f3522a66f49c8f3dc482300101b':raise ValueError('SCHEMA_VALIDATOR_PIN')
    for row in manifest['files']:
        data=(ROOT/row['path']).read_bytes()
        if hashlib.sha256(data).hexdigest()!=row['sha256']:raise ValueError('SCHEMA_VALIDATOR_SOURCE_SHA')
    return manifest

def no_remote(uri):raise ValueError('REMOTE_SCHEMA_RESOLUTION_FORBIDDEN')

def compile_standard(schema):
    if not isinstance(schema,dict) or schema.get('$schema')!=DRAFT:raise ValueError('DRAFT07_REQUIRED_NO_SILENT_DOWNGRADE')
    def inspect(obj):
        if isinstance(obj,dict):
            if '$ref' in obj and (not isinstance(obj['$ref'],str) or not obj['$ref'].startswith('#')):
                raise ValueError('ONLY_LOCAL_SCHEMA_REFERENCES')
            if '$defs' in obj:raise ValueError('DRAFT2020_DEFINITIONS_NOT_ALLOWED')
            for value in obj.values():inspect(value)
        elif isinstance(obj,list):
            for value in obj:inspect(value)
    inspect(schema);verify_vendor()
    from _vendor import fastjsonschema
    if fastjsonschema.VERSION!='2.21.2':raise ValueError('SCHEMA_VALIDATOR_VERSION')
    return fastjsonschema.compile(copy.deepcopy(schema),handlers={s:no_remote for s in ['http','https','file','urn','']},
        use_default=False,use_formats=False)

@lru_cache(maxsize=8)
def validators():
    result={}
    for path in sorted((ROOT/'schema').glob('*.schema.json')):
        schema=json.loads(path.read_text())
        identity=schema['properties']['schema']['const']
        result[identity]=compile_standard(schema)
    snapshot=json.loads((ROOT/'schema/screen-read.snapshot.v1.schema.json').read_text())
    result['trueplan.screen-read.layout-candidates.v1']=compile_standard({'$schema':DRAFT,
        'definitions':snapshot['definitions'],'$ref':snapshot['properties']['layout_candidates']['$ref']})
    return result

def validate_document(document):
    if not isinstance(document,dict):raise ValueError('SCHEMA_DATA_OBJECT_REQUIRED')
    validate=validators().get(document.get('schema'))
    if validate is None:raise ValueError('UNREGISTERED_SCHEMA')
    before=json.dumps(document,sort_keys=True,ensure_ascii=False,allow_nan=False)
    validate(document)
    if json.dumps(document,sort_keys=True,ensure_ascii=False,allow_nan=False)!=before:raise ValueError('SCHEMA_VALIDATOR_MUTATED_INPUT')
    return True
