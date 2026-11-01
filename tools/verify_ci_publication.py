"""Bind an uploaded workflow/run to the expected bytes before native auditing.

Offline: callers supply connector snapshots. Publication or report transport
success never certifies OCR, either native role, a build, or real-game accuracy.
This checkpoint tool is outside the frozen R560 192-input CI payload.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import stat
import zipfile
import zlib

REPOSITORY = 'zeek10191019-stack/true-plan-showdown-verification'
MAX_ZIP_BYTES = 8 * 1024 * 1024
MAX_MEMBER_BYTES = 2_000_000
MAX_PLAIN_BYTES = 32 * 1024 * 1024
MAX_MEMBERS = 256
TIMESTAMP = re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z (.*)$')


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def git_blob(value):
    return hashlib.sha1(b'blob ' + str(len(value)).encode() + b'\0' + value).hexdigest()


def valid_sha(value):
    return isinstance(value, str) and re.fullmatch(r'[a-f0-9]{40}', value) is not None


def positive(value):
    return type(value) is int and value > 0


def expected_workflow(revision, contents):
    require(isinstance(revision, str) and re.fullmatch(r'R[0-9]+', revision), 'REVISION')
    require(isinstance(contents, bytes) and 0 < len(contents) < 500_000, 'WORKFLOW_BYTES')
    contents.decode('utf-8', errors='strict')
    filename=revision.lower()+'.yml' if int(revision[1:])>=571 else 's'+revision.lower()+'.yml'
    return dict(repository=REPOSITORY, revision=revision, branch='main',
                path='.github/workflows/' + filename,
                workflow_bytes=len(contents), workflow_sha256=sha(contents),
                workflow_blob_sha=git_blob(contents))


def audit_publication(expected, snapshot, remote_workflow=None):
    """Reject incomplete evidence; give an actionable stage, never a CI PASS."""
    repo = snapshot['repository']
    require(repo.get('repository_full_name', repo.get('full_name')) == expected['repository'], 'REPOSITORY')
    require(repo.get('visibility') == 'public' and repo.get('default_branch') == expected['branch'], 'PUBLIC_MAIN_REQUIRED')
    head = snapshot['head_commit']
    commit = head.get('sha')
    require(valid_sha(commit), 'HEAD_COMMIT')
    tree = snapshot['tree']
    require(tree.get('truncated') is False and isinstance(tree.get('tree'), list), 'COMPLETE_TREE_REQUIRED')
    require(valid_sha(tree.get('sha')) and tree['sha'] == head['commit']['tree']['sha'], 'HEAD_TREE_BINDING')
    result = {**expected, 'head_commit': commit, 'native_CI_certified': False,
              'real_game_accuracy_certified': False, 'IPA_created': False,
              'scope': 'publication_and_transport_only', 'matching_run_id': None}
    parent = snapshot.get('parent_commit')
    if parent:
        require(head.get('parents') and parent['sha'] == head['parents'][0]['sha'], 'PARENT_BINDING')
        result['head_has_same_tree_as_parent'] = parent['commit']['tree']['sha'] == tree['sha']
    matches = [row for row in tree['tree'] if isinstance(row.get('path'), str)
               and row['path'].casefold() == expected['path'].casefold()]
    require(len(matches) <= 1, 'AMBIGUOUS_WORKFLOW_PATH')
    if not matches:
        return dict(result, status='NOT_REGISTERED_AT_HEAD', action='UPLOAD_EXACT_WORKFLOW')
    item = matches[0]
    if item['path'] != expected['path']:
        return dict(result, status='WRONG_PATH_CASE', action='USE_EXACT_WORKFLOW_PATH')
    if (item.get('type') != 'blob' or item.get('mode') != '100644'
            or type(item.get('size')) is not int or item['size'] != expected['workflow_bytes']
            or item.get('sha') != expected['workflow_blob_sha']):
        return dict(result, status='UPLOADED_CONTENT_MISMATCH', action='REPLACE_WITH_EXACT_WORKFLOW')
    if remote_workflow is None:
        return dict(result, status='UPLOADED_BYTES_REQUIRED', action='FETCH_WORKFLOW_AT_HEAD_COMMIT')
    require(isinstance(remote_workflow, bytes), 'REMOTE_WORKFLOW_BYTES')
    if len(remote_workflow) != expected['workflow_bytes'] or sha(remote_workflow) != expected['workflow_sha256']:
        return dict(result, status='UPLOADED_CONTENT_MISMATCH', action='REPLACE_WITH_EXACT_WORKFLOW')
    runs = snapshot['runs']
    require(isinstance(runs.get('workflow_runs'), list), 'WORKFLOW_RUNS_RESPONSE')
    candidates = []
    for run in runs['workflow_runs']:
        if (run.get('path') == expected['path'] and run.get('head_sha') == commit
                and run.get('head_branch') == expected['branch']):
            require(run.get('repository', {}).get('full_name') == expected['repository'], 'RUN_REPOSITORY')
            require(positive(run.get('id')) and positive(run.get('run_attempt')), 'RUN_ID_OR_ATTEMPT')
            candidates.append(run)
    if not candidates:
        return dict(result, status='NO_MATCHING_RUN_IN_RESPONSE', action='OPEN_THIS_WORKFLOW_ACTIONS')
    require(len({row['id'] for row in candidates}) == len(candidates), 'DUPLICATE_RUN')
    run = max(candidates, key=lambda row: row['id'])
    result.update(matching_run_id=run['id'], run_attempt=run['run_attempt'],
                  run_status=run.get('status'), run_conclusion=run.get('conclusion'))
    if run.get('status') in {'queued', 'in_progress', 'waiting', 'pending', 'requested'}:
        return dict(result, status='MATCHING_RUN_PENDING', action='WAIT_FOR_BOTH_NATIVE_ROLES')
    require(run.get('status') == 'completed', 'UNKNOWN_RUN_STATUS')
    if run.get('conclusion') != 'success':
        return dict(result, status='MATCHING_RUN_NOT_SUCCESSFUL', action='AUDIT_BOTH_JOB_LOGS')
    return dict(result, status='RUN_SUCCEEDED_NATIVE_EVIDENCE_REQUIRED',
                action='AUDIT_IOS27_NATIVE_AND_PORTABLE_OCR_SEPARATELY')


def decode_report_log(contents, revision):
    """Validate log framing, transport SHA and every bounded ZIP member/CRC.

    Returns verified bytes in memory, without extracting paths or certifying
    their semantic claims. Log echoes of the Python script are not markers.
    """
    require(isinstance(contents, str) and len(contents) <= 16 * 1024 * 1024, 'LOG_SIZE_OR_TYPE')
    # D (diagnostic) and G (named subgate) are transport namespaces only.
    # expected_workflow still accepts plain app revisions exclusively.
    require(isinstance(revision, str) and re.fullmatch(r'R[0-9]+[DG]?', revision), 'REVISION')
    prefix = revision + '_REPORT_B85'
    state = 'before'
    parts = []
    encoded_count = 0
    digest = None
    expected_size = None
    for line in contents.splitlines():
        match = TIMESTAMP.fullmatch(line)
        if not match:
            continue
        text = match[1]
        if text.startswith(prefix + '_BEGIN '):
            require(state == 'before', 'REPORT_DUPLICATE_OR_NESTED_BEGIN')
            header = re.fullmatch(re.escape(prefix) + r'_BEGIN ([a-f0-9]{64}) ([0-9]{1,9})', text)
            require(header is not None, 'REPORT_HEADER')
            digest, size = header.groups()
            expected_size = int(size)
            require(0 < expected_size <= MAX_ZIP_BYTES, 'REPORT_ZIP_SIZE_LIMIT')
            state = 'inside'
        elif text == prefix + '_END':
            require(state == 'inside', 'REPORT_UNEXPECTED_END')
            state = 'after'
        elif text.startswith(prefix + ' '):
            require(state == 'inside', 'REPORT_PART_ORDER')
            part = text[len(prefix) + 1:]
            require(re.fullmatch(r'[!-~]{1,500}', part), 'REPORT_PART_FORMAT')
            encoded_count += len(part)
            require(encoded_count <= ((MAX_ZIP_BYTES + 3) // 4) * 5, 'REPORT_ENCODED_SIZE_LIMIT')
            parts.append(part)
    require(state == 'after' and parts, 'REPORT_INCOMPLETE')
    try:
        data = base64.b85decode(''.join(parts).encode('ascii'))
    except (ValueError, UnicodeError) as error:
        raise ValueError('REPORT_BASE85') from error
    require(len(data) == expected_size and sha(data) == digest, 'REPORT_SIZE_OR_SHA256')
    entries = {}
    seen = set()
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = archive.infolist()
            require(0 < len(members) <= MAX_MEMBERS, 'REPORT_MEMBER_COUNT')
            require(sum(item.file_size for item in members) <= MAX_PLAIN_BYTES, 'REPORT_PLAIN_SIZE_LIMIT')
            for item in members:
                name = item.filename
                require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,159}\.(?:json|log)', name), 'REPORT_UNSAFE_OR_UNEXPECTED_PATH')
                require(name.casefold() not in seen, 'REPORT_DUPLICATE_MEMBER')
                seen.add(name.casefold())
                kind = stat.S_IFMT(item.external_attr >> 16)
                require(kind in {0, stat.S_IFREG} and not item.is_dir(), 'REPORT_NONREGULAR_MEMBER')
                require(not (item.flag_bits & 1) and item.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}, 'REPORT_UNSUPPORTED_ENCODING')
                require(0 <= item.file_size < MAX_MEMBER_BYTES, 'REPORT_MEMBER_SIZE_LIMIT')
            # All metadata is checked before any member is decompressed.
            for item in members:
                value = archive.read(item)
                require(len(value) == item.file_size, 'REPORT_MEMBER_SIZE')
                entries[item.filename] = value
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, OSError, zlib.error) as error:
        raise ValueError('REPORT_ZIP_OR_CRC') from error
    return {'zip_bytes': data, 'zip_sha256': digest, 'entries': entries,
            'native_CI_certified': False, 'real_game_accuracy_certified': False}


def strict_json(text):
    def object_pairs(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'DUPLICATE_JSON_KEY')
            result[key] = value
        return result
    def invalid_constant(value):
        raise ValueError('NONFINITE_JSON')
    return json.loads(text, object_pairs_hook=object_pairs, parse_constant=invalid_constant)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--workflow', required=True, type=Path)
    parser.add_argument('--remote-workflow', type=Path)
    args = parser.parse_args()
    try:
        result = audit_publication(expected_workflow(args.revision, args.workflow.read_bytes()),
                                   strict_json(args.snapshot.read_text()),
                                   args.remote_workflow.read_bytes() if args.remote_workflow else None)
    except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
        reason = str(error)
        if not re.fullmatch(r'[A-Z][A-Z0-9_]{0,79}', reason):
            reason = 'INVALID_PUBLICATION_EVIDENCE'
        print(json.dumps(dict(status='INVALID_EVIDENCE', reason=reason, native_CI_certified=False)))
        return 1
    print(json.dumps(result, indent=2))
    # Success here means ready for a separate audit, never native CI PASS.
    return 0 if result['status'] == 'RUN_SUCCEEDED_NATIVE_EVIDENCE_REQUIRED' else 2


if __name__ == '__main__':
    raise SystemExit(main())
