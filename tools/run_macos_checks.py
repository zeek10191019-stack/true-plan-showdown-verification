"""Actual macOS Swift/Apple SDK checks. Does not make a distribution IPA."""
from pathlib import Path
import argparse,hashlib,json,os,platform,plistlib,re,shutil,subprocess,sys,tempfile,time
from release_config import release_config
from ci_execution_policy import execution_policy

parser=argparse.ArgumentParser()
parser.add_argument('--source-guard-only',action='store_true',help='Listed native/build subchecks only; never full OCR/app certification')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
os.chdir(root)
sys.path[:0]=[str(root/'tests'),str(root/'tools')]
from test_evidence_verifier import fixture
from r553_fixture import menu_fixture
from r556_fixture import projection_fixture
from r557_fixture import screen_fixture
from verify_screen_evidence import verify_archive
from verify_candidate_lease import validate_candidate_lease
reports=root/'reports';reports.mkdir(exist_ok=True)
source=root/'app/ios/ChampionsOnDevice'
files=sorted(source.glob('*.swift'))
config=release_config(root);revision=config['revision']
record={**config,'release':revision,'scope':'screen_read_only','started':time.time(),'platform':platform.platform(),
        'new_ipa_distributed':False,'checks':[],
        'validation_scope':'SOURCE_GUARD_SUBCHECKS_ONLY' if args.source_guard_only else 'FULL_LISTED_APP_CI_CHECKS',
        'full_app_CI_certified':False,'iOS_runtime_executed':False,
        'requested_CI_role':os.environ.get('SCREEN_READ_CI_ROLE','IOS27_NATIVE')}
def run(name,command):
 started=time.monotonic()
 result=subprocess.run(list(map(str,command)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 (reports/(name+'.log')).write_text(result.stdout)
 print(name,'PASS' if result.returncode==0 else 'FAIL',flush=True)
 if result.returncode:
  print(result.stdout[-16000:],flush=True)
 record['checks'].append({'name':name,'returncode':result.returncode,'elapsed_seconds':round(time.monotonic()-started,3),'log':name+'.log'})
 (reports/(revision+'_MACOS_CHECKS.json')).write_text(json.dumps(record,indent=2))
 if result.returncode:raise SystemExit(result.returncode)
 return result.stdout

assert platform.system()=='Darwin','APPLE_SDK_REQUIRED_NOT_A_PASS'
run('xcode_version',['xcodebuild','-version'])
sdk=run('iphoneos_sdk',['xcrun','--sdk','iphoneos','--show-sdk-version']).strip()
record.update(host_macOS=platform.mac_ver()[0],iphoneos_sdk=sdk)
try:
 policy=execution_policy(record['requested_CI_role'],platform.system(),platform.machine(),sdk,platform.mac_ver()[0])
except ValueError as error:
 record.update(status='FAIL_CI_EXECUTION_POLICY',failure_reason=str(error),Swift_executed=False,Vision_executed=False)
 (reports/(revision+'_MACOS_CHECKS.json')).write_text(json.dumps(record,indent=2))
 raise
record['execution_policy']=policy
if policy['role']=='PORTABLE_OCR':record['validation_scope']='PORTABLE_MACOS_NATIVE_OCR_ONLY_NO_IOS_BUILD'
if policy['role']=='MACOS26_BUILD_AND_OCR':
 assert not args.source_guard_only,'MACOS26_OCR_ROLE_REQUIRES_ACTUAL_VISION_CHECKS'
 record.update(validation_scope='MACOS26_NATIVE_OCR_AND_IOS27_CROSS_BUILD_ONLY',iOS_runtime_executed=False)
run('python_adversarial',[sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'])
swift=shutil.which('swiftc');assert swift
with tempfile.TemporaryDirectory(prefix='screen-read-'+config['slug']+'-') as directory:
 lab=Path(directory)
 for name,data in fixture().items():
  p=lab/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 def native(name,sources,args=()):
  binary=lab/name
  run(name+'_compile',[swift,'-O','-assert-config','Debug','-swift-version','5','-parse-as-library',*sources,'-o',binary])
  return run(name,[binary,*args])
 native('r518',[source/'TP517VisionROISidecar.swift',source/'TP518VisionBudgetGate.swift',root/'tests/regression/r518_tests.swift'])
 archive_sources=[source/'R548ResearchArchive.swift',source/'R551EvidenceIntegrity.swift',source/'R555StoredZIPReadback.swift']
 native('r549',archive_sources+[root/'source/tests/R549VerifyHarness.swift'],[root/'fixtures'])
 native('r550',archive_sources+[root/'source/tests/R550WriterHarness.swift'])
 state_sources=[source/name for name in ['FrameEvidenceExportGate.swift','ResearchScreenClassifier.swift','R551ScreenReadState.swift','R552StateValues.swift','R553OCRAlternatives.swift','R553LayoutReading.swift','R557ScreenEvidence.swift','R564OwnerHintFence.swift','R565SourceEvidenceFence.swift','R566RoleTextFence.swift','R567EvidenceGroupFence.swift','R568ObservationReferenceFence.swift','R569RoleConsensusFence.swift']]
 core=native('r551_core',archive_sources+state_sources+[root/'tests/R551CoreHarness.swift'],[lab])
 receipt=verify_archive(lab/'swift_written.zip')
 (reports/(revision+'_SWIFT_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_SWIFT_WRITER_PYTHON_INDEPENDENT_VERIFY_PASS',flush=True)
 values=native('r552_values',archive_sources+state_sources+[root/'tests/R552StateValueHarness.swift'],[lab,reports/(revision+'_NATIVE_STATE_SNAPSHOT.json')])
 receipt=verify_archive(lab/'r552_values.zip')
 (reports/(revision+'_SWIFT_STATE_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_STRUCTURED_STATE_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 menu=lab/'menu';menu.mkdir()
 for name,data in menu_fixture().items():
  p=menu/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 layout=native('r553_layout',archive_sources+state_sources+[source/'ResearchBattleWire.swift',root/'tests/R553LayoutHarness.swift'],[menu,reports/(revision+'_NATIVE_LAYOUT_SNAPSHOT.json')])
 receipt=verify_archive(menu/'r553_layout.zip')
 (reports/(revision+'_SWIFT_LAYOUT_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_LAYOUT_ALTERNATIVES_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 lease=native('r554_lease',archive_sources+[source/'R554CandidateLease.swift',source/'ResearchAutomaticCaptureR494.swift',source/'ResearchObservationAdmissionR495.swift',root/'tests/R554LeaseHarness.swift'],[lab,reports/(revision+'_NATIVE_LEASE_SNAPSHOTS.json')])
 snapshots=json.loads((reports/(revision+'_NATIVE_LEASE_SNAPSHOTS.json')).read_text())
 validated=[validate_candidate_lease(snapshot) for snapshot in snapshots]
 (reports/(revision+'_LEASE_DIAGNOSTICS_INDEPENDENT.json')).write_text(json.dumps(validated,indent=2))
 receipt=verify_archive(lab/'r554_lease.zip')
 (reports/(revision+'_SWIFT_LEASE_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_RECEIPT_LEASE_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 stream=native('r555_stream',archive_sources+[root/'tests/R555StreamHarness.swift'],[lab,reports/(revision+'_NATIVE_STREAM_AUDIT.json')])
 receipt=verify_archive(lab/'r555_stream.zip')
 (reports/(revision+'_SWIFT_STREAM_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 audit=json.loads((reports/(revision+'_NATIVE_STREAM_AUDIT.json')).read_text())
 assert audit['archive_sha256']==receipt['archive_sha256'],'STREAM_RECEIPT_ARCHIVE_MISMATCH'
 assert audit['entry_count']==receipt['entries'] and 0<audit['maximum_read_request_bytes']<=65536
 assert 0<audit['maximum_write_request_bytes']<=65536 and audit['stress_payload_bytes']>4*1024*1024
 print(revision+'_STREAMING_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 projection_dir=lab/'projection';projection_dir.mkdir()
 for name,data in projection_fixture().items():
  p=projection_dir/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 projection_sources=[source/'R556AnalysisProjection.swift',source/'R556PixelTransform.swift']
 projection=native('r556_projection',archive_sources+state_sources+projection_sources+[root/'tests/R556ProjectionHarness.swift'],[projection_dir,reports/(revision+'_NATIVE_PROJECTION_AUDIT.json')])
 receipt=verify_archive(projection_dir/'r556_projection.zip')
 (reports/(revision+'_SWIFT_PROJECTION_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_PROJECTION_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 screen_dir=lab/'screen';screen_dir.mkdir()
 for name,data in screen_fixture().items():
  p=screen_dir/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 screen=native('r557_screen',archive_sources+state_sources+[root/'tests/R557ScreenHarness.swift'],[screen_dir,reports/(revision+'_NATIVE_SCREEN_AUDIT.json')])
 receipt=verify_archive(screen_dir/'r557_screen.zip')
 (reports/(revision+'_SWIFT_SCREEN_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_SCREEN_CLASSIFICATION_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 if int(revision[1:])>=561:
  from verify_source_guard_report import verify_report as verify_source_guard_report
  guard_dir=lab/'source_guard';guard_dir.mkdir()
  for name,data in fixture().items():
   p=guard_dir/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
  native('r561_source_guard',archive_sources+state_sources+[source/'R556AnalysisProjection.swift',root/'tests/R561SourceGuardHarness.swift'],[guard_dir,reports/(revision+'_NATIVE_SOURCE_GUARD.json'),config['app_version'],revision[1:]])
  source_guard=json.loads((reports/(revision+'_NATIVE_SOURCE_GUARD.json')).read_text())
  independent=verify_source_guard_report(source_guard,lab/'source_guard_independent',config['app_version'],revision[1:])
  (reports/(revision+'_SOURCE_GUARD_INDEPENDENT.json')).write_text(json.dumps(independent,indent=2))
  print(revision+'_SOURCE_GUARD_SWIFT_TO_PYTHON_VERIFY_PASS; NO_VISION_EXECUTED_HERE',flush=True)
 if int(revision[1:])>=562:
  from verify_read_clock import verify_report as verify_read_clock_report
  clock_dir=lab/'read_clock';clock_dir.mkdir()
  for name,data in fixture().items():
   p=clock_dir/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
  native('r562_read_clock',archive_sources+[source/'ResearchSampleClockAudit.swift',source/'R562ReadClockGate.swift',source/'R562ReadWorkSlot.swift',source/'R554CandidateLease.swift',root/'tests/R562ReadClockHarness.swift'],[clock_dir,reports/(revision+'_NATIVE_READ_CLOCK.json'),config['app_version'],revision[1:]])
  clock=json.loads((reports/(revision+'_NATIVE_READ_CLOCK.json')).read_text())
  independent=verify_read_clock_report(clock,lab/'clock_independent',config['app_version'],revision[1:])
  (reports/(revision+'_READ_CLOCK_INDEPENDENT.json')).write_text(json.dumps(independent,indent=2))
  print(revision+'_CLOCK_AND_WORK_SLOT_SWIFT_TO_PYTHON_VERIFY_PASS; NO_CAPTURE_AGE_CERTIFICATION',flush=True)
 if int(revision[1:])>=563:
  from verify_input_health import verify_report as verify_input_report
  health_dir=lab/'input_health';health_dir.mkdir()
  for name,data in fixture().items():
   p=health_dir/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
  native('r563_input_health',archive_sources+[source/'R563InputHealthFence.swift',source/'R562ReadWorkSlot.swift',source/'R554CandidateLease.swift',root/'tests/R563InputHealthHarness.swift'],[health_dir,reports/(revision+'_NATIVE_INPUT_HEALTH.json')])
  health=json.loads((reports/(revision+'_NATIVE_INPUT_HEALTH.json')).read_text())
  independent=verify_input_report(health,lab/'input_health_independent')
  (reports/(revision+'_INPUT_HEALTH_INDEPENDENT.json')).write_text(json.dumps(independent,indent=2))
  print(revision+'_INPUT_HEALTH_SWIFT_TO_PYTHON_VERIFY_PASS; NO_UIKIT_CAPTURE_EXECUTION_CLAIM',flush=True)
 run('all_swift_parse',[swift,'-frontend','-parse',*sorted(source.glob('*.swift'))])
 if policy['requires_iPhoneOS27_build']:
  run('project_generation',[sys.executable,'tools/generate_xcode_project.py'])
  run('xcode_iphoneos_build',['xcodebuild','-project',root/'app/ios/ChampionsOnDeviceResearch.xcodeproj',
      '-target','ChampionsOnDeviceResearch','-configuration','Debug','-sdk','iphoneos',
      'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO',
      'CONFIGURATION_BUILD_DIR='+str(lab/'built'),'OBJROOT='+str(lab/'objects'),'SYMROOT='+str(lab/'symbols'),'build'])
  manifest=lab/'built/ChampionsOnDeviceResearch.app/PrivacyInfo.xcprivacy'
  assert manifest.is_file(),'PRIVACY_MANIFEST_NOT_BUNDLED'
  assert plistlib.loads(manifest.read_bytes())==plistlib.loads((source/'PrivacyInfo.xcprivacy').read_bytes()),'PRIVACY_MANIFEST_CHANGED'
  record['privacy_manifest_bundled']='PASS'
 if not args.source_guard_only:
  native('r551_vision',archive_sources+[source/'FrameEvidenceExportGate.swift',source/'R548MegaSceneProbe.swift',root/'tests/R551VisionHarness.swift'],[lab/'frames/frame_17.png',reports/(revision+'_VISION_SYNTHETIC.json')])
 input_sources=[source/'ResearchBattleWire.swift',source/'R559VisionInput.swift',source/'R559OCRFailure.swift',source/'FrameEvidenceExportGate.swift']
 native('r559_input',archive_sources+input_sources+[root/'tests/R559VisionInputHarness.swift'],[lab,reports/(revision+'_NATIVE_VISION_INPUT_AUDIT.json')])
 receipt=verify_archive(lab/'r559_failure.zip')
 (reports/(revision+'_SWIFT_FAILURE_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_OCR_FAILURE_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 recovery_sources=archive_sources+[source/'ResearchBattleWire.swift',source/'R559OCRFailure.swift',source/'R560OCRRecovery.swift']
 native('r560_recovery',recovery_sources+[root/'tests/R560RecoveryHarness.swift'],[lab,reports/(revision+'_NATIVE_RECOVERY_AUDIT.json')])
 recovery=json.loads((reports/(revision+'_NATIVE_RECOVERY_AUDIT.json')).read_text())
 from verify_ocr_execution import validate_ocr_execution
 for execution in recovery['audits']:validate_ocr_execution(execution)
 receipt=verify_archive(lab/'r560_recovery_failure.zip')
 (reports/(revision+'_SWIFT_RECOVERY_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
 print(revision+'_OCR_RECOVERY_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 if not args.source_guard_only:
  text_dir=lab/'fullframe';text_dir.mkdir()
  for name,data in fixture().items():
   p=text_dir/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
  ocr_sources=[source/'ResearchBattleWire.swift',source/'TP530VisionRect.swift',source/'R558FullFrameOCR.swift',source/'R559VisionInput.swift',source/'R559OCRFailure.swift',source/'R560OCRRecovery.swift',source/'R560VisionExecutor.swift']
  try:
   fullframe=native('r558_fullframe',archive_sources+state_sources+ocr_sources+[root/'tests/R558FullFrameHarness.swift'],[text_dir,reports/(revision+'_NATIVE_FULLFRAME_AUDIT.json'),config['app_version'],revision[1:]])
  except SystemExit:
   run('structural_schema_audit_after_OCR_failure',[sys.executable,'tools/audit_json_schemas.py',reports,'--output',reports/(revision+'_STANDARD_SCHEMA_AUDIT.json')])
   raise
  receipt=verify_archive(text_dir/'r558_fullframe.zip')
  # Preserve exact public synthetic input bytes for independent recovery from logs.
  import base64
  from verify_screen_evidence import _png
  native_report=json.loads((reports/(revision+'_NATIVE_FULLFRAME_AUDIT.json')).read_text())
  preserved=native_report['synthetic_literal_probes'];assert len(preserved)==4
  for probe in preserved:
   png=base64.b64decode(probe['rendered_png_base64'],validate=True)
   assert hashlib.sha256(png).hexdigest()==probe['rendered_png_sha256']==probe['request_audit']['image_sha256'],'PRESERVED_PROBE_SOURCE'
   _png(png,probe['request_audit']['image_width'],probe['request_audit']['image_height'])
  archive_bytes=base64.b64decode(native_report['archive_base64'],validate=True)
  assert archive_bytes==(text_dir/'r558_fullframe.zip').read_bytes() and hashlib.sha256(archive_bytes).hexdigest()==native_report['archive_sha256'],'PRESERVED_VISION_ARCHIVE'
  assert native_report['app_version']==config['app_version'] and native_report['app_build']==revision[1:],'PRESERVED_VISION_VERSION'
  record['preserved_native_Vision_probe_PNGs']=4
  if int(revision[1:])>=573:
   from screen_read_metrics import elapsed_summary
   timing=elapsed_summary(preserved)
   assert timing['samples_with_measurement']==4 and timing['samples_without_measurement']==0,'VISION_PROCESSING_TIME_COVERAGE'
   record['native_Vision_processing_time']=timing
  if int(revision[1:])>=574:
   from png_replay_inputs import prepare_inputs
   from run_png_replay import source_files as replay_sources
   from verify_png_replay import verify_native_report as verify_replay_report
   import copy
   replay_root=lab/'replay_inputs';replay_root.mkdir();rows=[]
   for probe in preserved:
    data=base64.b64decode(probe['rendered_png_base64'],validate=True);name=probe['probe_id']+'.png'
    (replay_root/name).write_bytes(data)
    rows.append(dict(sample_id=probe['probe_id'],path=name,sha256=hashlib.sha256(data).hexdigest(),bytes=len(data),width=1200,height=180))
   inputs=prepare_inputs(replay_root,rows);manifest=replay_root/'inputs.json';manifest.write_text(json.dumps(inputs))
   replay_out=lab/'replay_output';report_path=reports/(revision+'_NATIVE_PNG_REPLAY.json')
   native('r574_png_replay',replay_sources(root),[replay_root,manifest,replay_out,report_path,config['app_version'],revision[1:]])
   replay_report=json.loads(report_path.read_text())
   for result in replay_report['results']:
    raw=(replay_out/result['archive_file']).read_bytes();result['archive_base64']=base64.b64encode(raw).decode()
   report_path.write_text(json.dumps(replay_report,indent=2))
   checked=verify_replay_report(replay_report,lab/'replay_independent',rows,config['app_version'],revision[1:])
   for index,(receipt,probe) in enumerate(zip(checked['archives'],preserved)):
    import zipfile
    with zipfile.ZipFile(lab/'replay_independent'/('replay_'+str(index)+'.zip')) as z:
     selected=json.loads(z.read('selected_evidence.json'))
    assert receipt['replay']['status']=='SUCCESS' and any(c['domain']==probe['expected_domain'] and c['value']==probe['expected_value'] for c in selected['screen_read_state']['candidates']),'REPLAY_SYNTHETIC_LITERAL'
   (reports/(revision+'_PNG_REPLAY_INDEPENDENT.json')).write_text(json.dumps(checked,indent=2))
   bad=copy.deepcopy(inputs);bad['samples']=bad['samples'][:1];bad['samples'][0]['sha256']='0'*64
   bad_path=replay_root/'bad_sha.json';bad_path.write_text(json.dumps(bad));bad_report=reports/(revision+'_NATIVE_PNG_REPLAY_REJECTION.json')
   rejected=subprocess.run([str(lab/'r574_png_replay'),str(replay_root),str(bad_path),str(lab/'rejected_replay'),str(bad_report),config['app_version'],revision[1:]],capture_output=True,text=True)
   (reports/'r574_replay_rejects_wrong_sha.log').write_text(rejected.stdout+rejected.stderr)
   bad_result=json.loads(bad_report.read_text());assert rejected.returncode==1 and len(bad_result['results'])==1 and bad_result['results'][0]['status']=='INPUT_OR_EXPORT_REJECTED' and 'archive_file' not in bad_result['results'][0],'REPLAY_SHA_REJECTION'
   record['checks'].append(dict(name='r574_replay_rejects_wrong_sha',returncode=0,observed_native_exit_code=1,scope='EXPECTED_INPUT_REJECTION'))
   record['offline_PNG_replay_verified_archives']=4
  (reports/(revision+'_SWIFT_FULLFRAME_ARCHIVE_INDEPENDENT.json')).write_text(json.dumps(receipt,indent=2))
  print(revision+'_FULLFRAME_OCR_SWIFT_TO_PYTHON_VERIFY_PASS',flush=True)
 run('structural_schema_audit',[sys.executable,'tools/audit_json_schemas.py',reports,'--output',reports/(revision+'_STANDARD_SCHEMA_AUDIT.json')])
 record['native_core_output']=core.strip()
 record['native_state_value_output']=values.strip()
 record['native_layout_output']=layout.strip()
 record['native_lease_output']=lease.strip()
 record['native_stream_output']=stream.strip()
 record['native_projection_output']=projection.strip()
 record['native_screen_output']=screen.strip()
 record['native_fullframe_output']=fullframe.strip() if not args.source_guard_only else 'NOT_RUN_SOURCE_GUARD_SCOPE'
record['status']='PASS_APPLE_SDK_AND_NATIVE_CHECKS_ONLY' if policy['requires_iPhoneOS27_build'] else 'PASS_PORTABLE_MACOS_OCR_NATIVE_ONLY'
if args.source_guard_only:
 record['status']='PASS_SOURCE_GUARD_AND_LISTED_NATIVE_APPLE_SDK_SUBCHECKS_ONLY'
 record['real_Vision_execution']='NOT_RUN_SOURCE_GUARD_SCOPE'
if policy['role']=='MACOS26_BUILD_AND_OCR':
 record['status']='PASS_MACOS26_NATIVE_OCR_AND_IOS27_CROSS_BUILD_SUBCHECKS_ONLY'
 record['validation_scope']='MACOS26_NATIVE_OCR_AND_IOS27_CROSS_BUILD_ONLY'
 record['iOS_runtime_executed']=False
 record['full_app_CI_certified']=False
record['device_gate']='DEVICE_VALIDATION_PENDING'
record['game_accuracy']='NEEDS_REAL_CAPTURE_LABELS_AND_VISION_EXECUTION'
(reports/(revision+'_MACOS_CHECKS.json')).write_text(json.dumps(record,indent=2))
message=('_SOURCE_GUARD_SUBCHECKS_PASS_NO_FULL_APP_CERTIFICATION' if args.source_guard_only else
 '_MACOS26_NATIVE_OCR_AND_IOS27_CROSS_BUILD_PASS_NO_IOS_RUNTIME_CERTIFICATION' if policy['role']=='MACOS26_BUILD_AND_OCR' else
 '_APPLE_CI_PASS_NO_DISTRIBUTION_IPA' if policy['requires_iPhoneOS27_build'] else '_PORTABLE_MACOS_OCR_PASS_NO_IOS_BUILD')
print(revision+message,flush=True)
