"""Build a self-contained public, standard-runner CI workflow; never an IPA."""
from pathlib import Path
import hashlib,io,json,tarfile,textwrap
from release_config import release_config
from ci_workflow_payload import payload_steps,validate_run_script

root=Path(__file__).resolve().parents[1]
config=release_config(root);revision=config['revision'];slug=config['slug']
paths=sorted((root/'app/ios/ChampionsOnDevice').glob('*.swift'))+[root/'app/ios/ChampionsOnDevice/Info.plist']
paths += sorted((root/'app/ios/ChampionsOnDevice').glob('*.xcprivacy'))
paths += [root/p for p in ['tools/run_macos_checks.py','tools/generate_xcode_project.py','tools/verify_screen_evidence.py','tools/release_config.py','tools/screen_read_semantics.py','tools/screen_read_layout.py','tools/verify_candidate_lease.py','tools/ci_workflow_payload.py','tools/build_ci_workflow.py','tests/r553_fixture.py','tests/R551CoreHarness.swift','tests/R551VisionHarness.swift','tests/R552StateValueHarness.swift','tests/R553LayoutHarness.swift','tests/R554LeaseHarness.swift','tests/regression/r518_tests.swift','source/tests/R549VerifyHarness.swift','source/tests/R550WriterHarness.swift']]
paths += [root/'tests/R555StreamHarness.swift',root/'tests/R561SourceGuardHarness.swift',root/'tools/verify_source_guard_report.py']
paths += [root/'tests/R562ReadClockHarness.swift',root/'tools/verify_read_clock.py']
paths += [root/'tests/R563InputHealthHarness.swift',root/'tools/verify_input_health.py']
paths += [root/'tests/R556ProjectionHarness.swift',root/'tests/r556_fixture.py',root/'tools/screen_read_projection.py']
paths += [root/'tests/R557ScreenHarness.swift',root/'tests/r557_fixture.py',root/'tools/screen_read_classification.py']
paths += [root/'tests/R558FullFrameHarness.swift',root/'tests/r558_fixture.py',root/'tools/verify_ocr_request.py']
paths += [root/'tools/schema_contract.py',root/'tools/audit_json_schemas.py']
paths += [root/'tools/verify_ocr_failures.py',root/'tests/R559VisionInputHarness.swift']
paths += [root/'tools/verify_ocr_execution.py',root/'tools/ci_execution_policy.py',root/'tests/R560RecoveryHarness.swift']
if int(revision[1:])>=571:
 paths += [root/'tools/verify_source_bound_hints.py',root/'tools/run_r571_native.py',root/'tools/verify_ci_publication.py']
 paths += [root/'tests'/name for name in ['R564OwnerHintHarness.swift','R565SourceEvidenceHarness.swift',
     'R566RoleTextHarness.swift','R567EvidenceGroupHarness.swift','R568ObservationReferenceHarness.swift',
     'R569RoleConsensusHarness.swift','R570LeaseRetirementHarness.swift','R571SourceValueHarness.swift']]
if int(revision[1:])>=572:paths += [root/'tools/screen_read_metrics.py']
if int(revision[1:])>=573:paths += [root/'tools/screen_read_corpus.py']
if int(revision[1:])>=574:
 paths += [root/'tools'/name for name in ['png_replay_inputs.py','verify_png_replay.py','run_png_replay.py','R574PNGReplay.swift']]
paths += sorted((root/'schema').glob('*.schema.json'))
paths += [root/'schema/history/r557_draft202012/screen-read.snapshot.v1.schema.json']
paths += sorted(p for p in (root/'tools/_vendor').rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc')
paths += sorted((root/'tests').glob('test_*.py'))
paths += sorted(p for p in (root/'fixtures').glob('*') if p.is_file())
raw=io.BytesIO()
with tarfile.open(fileobj=raw,mode='w') as tar:
 for p in paths:
  data=p.read_bytes();i=tarfile.TarInfo(p.relative_to(root).as_posix());i.size=len(data);i.mode=0o644;tar.addfile(i,io.BytesIO(data))
data=raw.getvalue();digest=hashlib.sha256(data).hexdigest()
steps=payload_steps(data,config['source_count'],revision)
native_command='python3 tools/run_r571_native.py\n' if int(revision[1:])>=571 else 'python3 tools/run_macos_checks.py\n'
steps.append({'name':'Run native regressions, independent verifier and iPhoneOS Xcode build',
              'shell':'bash','run':native_command})
report='''from pathlib import Path
import base64,hashlib,io,json,zipfile
root=Path('reports');blob=io.BytesIO()
with zipfile.ZipFile(blob,'w',compression=zipfile.ZIP_DEFLATED) as z:
    for p in sorted(root.glob('*')):
        if p.suffix in ('.json','.log') and p.stat().st_size<2000000:
            z.write(p,p.name)
data=blob.getvalue();encoded=base64.b85encode(data).decode()
print('''+repr(revision+'_REPORT_B85_BEGIN')+''',hashlib.sha256(data).hexdigest(),len(data))
for i in range(0,len(encoded),500):print('''+repr(revision+'_REPORT_B85')+''',encoded[i:i+500])
print('''+repr(revision+'_REPORT_B85_END')+''')
p=root/'''+repr(revision+'_MACOS_CHECKS.json')+'''
if p.is_file():print(p.read_text())
'''
steps.append({'name':'Return numerical and compiler evidence through logs (no artifacts/cache)',
              'if':'always()','shell':'bash','run':"python3 - <<'REPORT_EVIDENCE'\n"+report+'REPORT_EVIDENCE\n'})
workflow_file=slug+'.yml' if int(revision[1:])>=571 else 's'+slug+'.yml'
workflow=f'''name: {revision} Screen Read Native and Apple SDK Audit (No IPA)
"on":
  push:
    branches: [main]
    paths: [.github/workflows/{workflow_file}]
  workflow_dispatch:
permissions:
  contents: read
jobs:
  verify:
    if: >-
      github.repository == 'zeek10191019-stack/true-plan-showdown-verification'
      && github.event.repository.private == false
    strategy:
      fail-fast: false
      matrix:
        include:
          - runner: xcode-27
            role: IOS27_NATIVE
          - runner: macos-26-intel
            role: PORTABLE_OCR
    runs-on: ${{{{ matrix.runner }}}}
    env:
      SCREEN_READ_CI_ROLE: ${{{{ matrix.role }}}}
      PYTHONOPTIMIZE: "0"
    timeout-minutes: 35
    steps:
'''
for step in steps:
 validate_run_script(step['run'])
 workflow+='      - name: '+json.dumps(step['name'])+'\n'
 if 'if' in step:workflow+='        if: '+step['if']+'\n'
 workflow+='        shell: bash\n        run: |\n'+textwrap.indent(step['run'],'          ')
assert len(workflow.encode())<500000,'WORKFLOW_FILE_SIZE'
p=root/('workflow/'+workflow_file);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(workflow)
record={**config,'source_files':len(paths),'source_tar_sha256':digest,'workflow_bytes':p.stat().st_size,
        'workflow_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),
        'transport':'LZMA_STANDARD_BASE64_MULTISTEP_V1',
        'run_steps':len(steps),'maximum_run_characters':max(len(s['run']) for s in steps),
        'expression_markers_in_run_scripts':0,
        'runner':'xcode-27 + macos-26-intel (public standard roles)' ,'repository_visibility_required':'public','artifacts_or_cache':False,
        'public_inputs':'Existing public R550 source, generic screen-read changes, synthetic fixtures and pinned BSD-3-Clause schema checker/contracts only',
        'private_captures_or_Apple_credentials_included':False,'baseline_source_count':93,
        'private_assets_excluded':['research_corpus','research_assets','development','upload','baseline IPA','Library metadata'],
        'files':[{'path':f.relative_to(root).as_posix(),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in paths]}
(root/'reports').mkdir(exist_ok=True)
(root/('reports/'+revision+'_CI_INPUT_AUDIT.json')).write_text(json.dumps(record,indent=2))
print('CI_INPUT_READY',len(paths),'files',len(steps),'steps',len(workflow),'UTF8 characters',digest)
