"""Audit registered schema objects inside current native report JSON, offline."""
from pathlib import Path
import argparse,json
from schema_contract import validators,validate_document,verify_vendor

def audit(folder):
    known=validators();checked=[];unknown=set()
    def visit(value,ref):
        if isinstance(value,dict):
            schema=value.get('schema')
            if isinstance(schema,str):
                if schema in known:
                    validate_document(value);checked.append({'ref':ref,'schema':schema})
                else:unknown.add(schema)
            for key,child in value.items():visit(child,ref+'.'+key)
        elif isinstance(value,list):
            for index,child in enumerate(value):visit(child,ref+f'[{index}]')
    for path in sorted(Path(folder).glob('*.json')):
        # A schema-audit receipt lists schema identifiers as references, not
        # as new data objects; do not recursively re-audit our own receipts.
        if path.name.endswith('_SCHEMA_AUDIT.json'):continue
        visit(json.loads(path.read_text()),path.name)
    if not checked:raise ValueError('NO_REGISTERED_NATIVE_SCHEMA_OBJECTS')
    manifest=verify_vendor()
    return {'status':'PASS_REGISTERED_STRUCTURAL_SCHEMAS_ONLY','dialect':'draft-07','validator':'fastjsonschema '+manifest['version'],
        'validator_commit':manifest['commit'],'offline':True,'defaults_injected':False,'data_objects_checked':len(checked),
        'objects':checked,'unhandled_schema_ids':sorted(unknown),'scope':'Structural conformance only; independent source/semantics verification and real-game/device gates remain separate'}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('reports');parser.add_argument('--output');args=parser.parse_args()
    result=audit(args.reports)
    if args.output:Path(args.output).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))
