"""Enforced Swift regression checks, shared app readout/UI, ZIPs, and existing CI suites.

Standard public runners only. No distribution IPA, simulator boot, artifacts,
cache, paid APIs, package/model/SDK installation, or private game images.
"""
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
FLAGS=['-O','-assert-config','Debug','-swift-version','5','-parse-as-library']
STATE_NAMES=['FrameEvidenceExportGate.swift','ResearchScreenClassifier.swift','R551ScreenReadState.swift',
    'R552StateValues.swift','R553OCRAlternatives.swift','R553LayoutReading.swift','R557ScreenEvidence.swift',
    'R564OwnerHintFence.swift','R565SourceEvidenceFence.swift','R566RoleTextFence.swift',
    'R567EvidenceGroupFence.swift','R568ObservationReferenceFence.swift','R569RoleConsensusFence.swift']
REGRESSIONS=[('R564OwnerHintHarness.swift','PASS_R564_OWNER_HINT_FENCE_ALL_18_CASES',18),
    ('R565SourceEvidenceHarness.swift','PASS_R565_ALL_18_TESTS',18),
    ('R566RoleTextHarness.swift','PASS_R566_27_TESTS',27),
    ('R567EvidenceGroupHarness.swift','PASS_R567_ALL_26_TESTS',26),
    ('R568ObservationReferenceHarness.swift','PASS_R568_ALL_26_CASES',26),
    ('R569RoleConsensusHarness.swift','PASS_R569_ALL_32_CASES',32),
    ('R570LeaseRetirementHarness.swift','PASS_R570_ALL_34_LEASE_RETIREMENT_CHECKS',34)]

def capture_checked(command, log_path, timeout):
    """Keep the actual failure/timeout output before a checked call raises."""
    def decoded(value):return value.decode('utf-8',errors='replace') if isinstance(value,bytes) else value or ''
    try:
        result=subprocess.run(command,capture_output=True,text=True,check=False,timeout=timeout)
    except subprocess.TimeoutExpired as error:
        Path(log_path).write_text(decoded(error.stdout)+decoded(error.stderr))
        raise
    Path(log_path).write_text(result.stdout+result.stderr)
    if result.returncode:print((result.stdout+result.stderr)[-12000:],flush=True)
    result.check_returncode()
    return result

def main():
    os.chdir(ROOT)
    role=os.environ.get('SCREEN_READ_CI_ROLE')
    if platform.system()!='Darwin' or role not in ('IOS27_NATIVE','PORTABLE_OCR'):
        raise RuntimeError('R571_APPLE_PUBLIC_STANDARD_ROLE_REQUIRED')
    reports=ROOT/'reports';reports.mkdir(exist_ok=True)
    from release_config import release_config
    config=release_config(ROOT);revision=config['revision']
    record=dict(revision=revision,role=role,status='RUNNING',compiler_flags=FLAGS,
        assert_enforcement='NOT_YET_EXECUTED',regressions=[],
        game_accuracy_certified=False,device_certified=False,final_IPA_created=False)
    def save(): (reports/(revision+'_ENFORCED_NATIVE_SUMMARY.json')).write_text(json.dumps(record,indent=2)+'\n')
    save()
    try:
        swift=shutil.which('swiftc')
        if swift is None:raise RuntimeError('SWIFTC_REQUIRED')
        source=ROOT/'app/ios/ChampionsOnDevice'
        state=[source/name for name in STATE_NAMES]
        archive=[source/name for name in ['R548ResearchArchive.swift','R551EvidenceIntegrity.swift','R555StoredZIPReadback.swift']]
        with tempfile.TemporaryDirectory(prefix='r571_native_') as temporary:
            lab=Path(temporary)
            canary=lab/'canary.swift'
            canary.write_text('@main struct Canary { static func main() { var evaluated=false; assert({ evaluated=true; return true }()); guard evaluated else { fatalError("ASSERTS_DISABLED") }; print("ASSERT_CANARY_EVALUATED") } }\n')
            binary=lab/'canary'
            subprocess.run([swift,*FLAGS,str(canary),'-o',str(binary)],check=True,timeout=120)
            record['current_phase']='ASSERT_EVALUATION_CANARY';save()
            result=capture_checked([str(binary)],reports/(revision+'_ASSERT_CANARY.log'),timeout=15)
            if result.stdout.strip()!='ASSERT_CANARY_EVALUATED':raise RuntimeError('ASSERT_CANARY_MISMATCH')
            record['assert_enforcement']='PASS_EVALUATION_CANARY';save()
            sys.path[:0]=[str(ROOT/'tests'),str(ROOT/'tools')]
            for name,marker,count in REGRESSIONS:
                record['current_phase']=name;save()
                sources=[source/'R554CandidateLease.swift'] if name.startswith('R570') else state
                binary=lab/name.removesuffix('.swift')
                command=[swift,*FLAGS,*map(str,sources),str(ROOT/'tests'/name),'-o',str(binary)]
                subprocess.run(command,check=True,timeout=180)
                result=capture_checked([str(binary)],reports/(binary.name+'.log'),timeout=120)
                if marker not in result.stdout.splitlines():raise RuntimeError('R571_REGRESSION_MARKER_'+name)
                record['regressions'].append(dict(test=name,checks=count,status='PASS_ENFORCED_NATIVE'))
                save();print('R571_ENFORCED_NATIVE_REGRESSION_PASS',name,count,flush=True)
            from r557_fixture import screen_fixture
            for name,data in screen_fixture().items():
                path=lab/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
            binary=lab/'r571_source_values'
            subprocess.run([swift,*FLAGS,*map(str,archive+state),str(ROOT/'tests/R571SourceValueHarness.swift'),'-o',str(binary)],check=True,timeout=180)
            record['current_phase']='SOURCE_VALUE_HARNESS';save()
            report=reports/(revision+'_NATIVE_SOURCE_VALUES.json')
            result=capture_checked([str(binary),str(lab),str(report),config['app_version'],revision[1:]],reports/(revision+'_NATIVE_SOURCE_VALUES.log'),timeout=120)
            from verify_source_bound_hints import verify_native_report
            independent=verify_native_report(json.loads(report.read_text()),lab/'independent_source_values',config['app_version'],revision[1:])
            (reports/(revision+'_SOURCE_VALUES_INDEPENDENT.json')).write_text(json.dumps(independent,indent=2)+'\n')
            record.update(new_source_value_checks=62,new_Swift_archives=3,independent_source_value_verifier='PASS',
                enforced_regression_check_count=sum(r['checks'] for r in record['regressions']))
            save();print('R571_NATIVE_SOURCE_VALUES_AND_THREE_ARCHIVES_PASS',flush=True)
        # Current-source broad regressions and SDK build on ARM; genuine Vision on Intel.
        command=[sys.executable,str(ROOT/'tools/run_macos_checks.py')]
        if role=='IOS27_NATIVE':command.append('--source-guard-only')
        record['current_phase']='BROAD_NATIVE_BUILD_OR_VISION_AND_SCHEMA_AUDIT';save()
        subprocess.run(command,check=True,timeout=1500)
        record['status']='PASS_LISTED_CURRENT_SOURCE_NATIVE_CONTRACTS_ONLY';save()
        print('R571_ENFORCED_CURRENT_SOURCE_CONTRACTS_PASS_NO_GAME_OR_DEVICE_CERTIFICATION',flush=True)
    except BaseException as error:
        record.update(status='FAIL',failure_type=type(error).__name__,failure_reason=str(error)[:1500]);save()
        raise

if __name__=='__main__':main()
