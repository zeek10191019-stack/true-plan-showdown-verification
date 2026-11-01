"""Compile/run the exact shared Apple reader locally; no SDK/model download.

A nonzero native reader can still yield valid failure ZIPs for scoring. Evidence
verification, recognition success and device certification remain separate.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
from png_replay_inputs import validate_inputs
from verify_screen_evidence import parse_json,require
from verify_png_replay import verify_replay_archive,validate_report_header
from release_config import release_config

NAMES=['R548ResearchArchive.swift','R551EvidenceIntegrity.swift','R555StoredZIPReadback.swift','FrameEvidenceExportGate.swift',
 'ResearchScreenClassifier.swift','R551ScreenReadState.swift','R552StateValues.swift','R553OCRAlternatives.swift','R553LayoutReading.swift',
 'R557ScreenEvidence.swift','R564OwnerHintFence.swift','R565SourceEvidenceFence.swift','R566RoleTextFence.swift','R567EvidenceGroupFence.swift',
 'R568ObservationReferenceFence.swift','R569RoleConsensusFence.swift','ResearchBattleWire.swift','TP530VisionRect.swift','R558FullFrameOCR.swift',
 'R559VisionInput.swift','R559OCRFailure.swift','R560OCRRecovery.swift','R560VisionExecutor.swift']

def source_files(source_root):
    root=Path(source_root)
    return [root/'app/ios/ChampionsOnDevice'/name for name in NAMES]+[root/'tools/R574PNGReplay.swift']

def finalize_results(root,inputs,output,app_version,app_build):
    output=Path(output);report=parse_json((output/'REPLAY_REPORT.json').read_bytes());rows=report.get('results')
    validate_report_header(report,len(inputs['samples']),app_version,app_build)
    require(report.get('status')=='EXPORTED_UNVERIFIED_OFFLINE_PNGS' and isinstance(rows,list) and len(rows)==len(inputs['samples']),'REPLAY_RESULT_COVERAGE')
    mappings=[];receipts=[];failures=0
    for row,expected in zip(rows,inputs['samples']):
        require(row.get('sample_id')==expected['sample_id'] and row.get('status') in ('SUCCESS','FAILED'),'REPLAY_RESULT_IDENTITY')
        name=row.get('archive_file');require(isinstance(name,str) and __import__('re').fullmatch(r'replay_[1-9][0-9]*\.zip',name) is not None,'REPLAY_ARCHIVE_NAME')
        path=output/'archives'/name
        receipt=verify_replay_archive(path,expected,row['archive_sha256'])
        require(receipt['replay']['app_version']==app_version and receipt['replay']['app_build']==app_build and
            receipt['replay']['status']==row['status'],'REPLAY_VERSION_OR_STATUS')
        failures+=row['status']=='FAILED';receipts.append(receipt)
        mappings.append(dict(sample_id=expected['sample_id'],path='archives/'+name))
    # Neither this mapping nor the native reader consumes ground-truth labels.
    (output/'archives.json').write_text(json.dumps(mappings,indent=2)+'\n')
    summary=dict(status='EVIDENCE_READY_WITH_READING_FAILURES' if failures else 'EVIDENCE_READY_RECOGNITION_NOT_CERTIFIED',
        images=len(rows),reading_failures=failures,archives=receipts,game_accuracy_certified=False,device_certified=False)
    (output/'REPLAY_VERIFIED.json').write_text(json.dumps(summary,indent=2)+'\n')
    return summary

def run(source_root,input_root,manifest_path,output):
    require(platform.system()=='Darwin','APPLE_SDK_REQUIRED_NO_AUTOMATIC_DOWNLOAD')
    compiler=shutil.which('swiftc');require(compiler is not None,'SWIFTC_REQUIRED_NO_DOWNLOAD')
    source_root=Path(source_root);input_root=Path(input_root).resolve();output=Path(output).resolve()
    document=validate_inputs(input_root,parse_json(Path(manifest_path).read_bytes()))
    require(not output.exists(),'REPLAY_OUTPUT_EXISTS');output.mkdir(parents=True)
    files=source_files(source_root);config=release_config(source_root)
    identity=dict(app_version=config['app_version'],app_build=config['revision'][1:],
        sources=[dict(path=str(p.relative_to(source_root)),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in files],
        input_manifest_sha256=hashlib.sha256(Path(manifest_path).read_bytes()).hexdigest(),game_accuracy_certified=False,device_certified=False)
    (output/'SOURCE_IDENTITY.json').write_text(json.dumps(identity,indent=2)+'\n')
    with tempfile.TemporaryDirectory(prefix='png_replay_binary_') as temporary:
        binary=Path(temporary)/'png_replay'
        compile_result=subprocess.run([compiler,'-O','-assert-config','Debug','-swift-version','5','-parse-as-library',*map(str,files),'-o',str(binary)],capture_output=True,text=True,timeout=180)
        (output/'compile.log').write_text(compile_result.stdout+compile_result.stderr);compile_result.check_returncode()
        command=[str(binary),str(input_root),str(Path(manifest_path).resolve()),str(output/'archives'),str(output/'REPLAY_REPORT.json'),config['app_version'],config['revision'][1:]]
        try:result=subprocess.run(command,capture_output=True,text=True,timeout=1500)
        except subprocess.TimeoutExpired as error:
            def text(value):return value.decode(errors='replace') if isinstance(value,bytes) else value or ''
            (output/'reader.log').write_text(text(error.stdout)+text(error.stderr));raise
        (output/'reader.log').write_text(result.stdout+result.stderr)
        # Inspect returned records even if native OCR failed. Do not drop failures.
        summary=finalize_results(input_root,document,output,config['app_version'],config['revision'][1:])
        require(result.returncode==0 if not summary['reading_failures'] else result.returncode==1,'REPLAY_EXIT_STATUS')
    return summary

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--inputs',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);args=parser.parse_args()
    result=run(Path(__file__).resolve().parents[1],args.root,args.inputs,args.output)
    print(result['status'],result['images'],'images',result['reading_failures'],'reading failures; GAME_AND_DEVICE_UNVERIFIED')
    return 2 if result['reading_failures'] else 0

if __name__=='__main__':sys.exit(main())
