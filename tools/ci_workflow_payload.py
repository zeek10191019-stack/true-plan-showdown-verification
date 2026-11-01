"""Single-file CI transport, without GitHub expression or run-size hazards."""
import base64
import hashlib
import lzma
import re
import textwrap

RUN_CHARACTER_LIMIT = 21000
CHUNK_CHARACTERS = 12000


def validate_run_script(script):
    if len(script) > RUN_CHARACTER_LIMIT:
        raise ValueError('GITHUB_RUN_CHARACTER_LIMIT')
    if '$' + '{{' in script:
        raise ValueError('GITHUB_EXPRESSION_IN_LITERAL_SCRIPT')


def payload_steps(data, source_count, revision):
    if not re.fullmatch(r'R[0-9]+', revision):
        raise ValueError('INVALID_REVISION')
    if type(source_count) is not int or source_count < 1:
        raise ValueError('INVALID_SOURCE_COUNT')
    # Standard base64 cannot contain $, { or }, including across line boundaries.
    encoded = base64.b64encode(lzma.compress(data)).decode('ascii')
    chunks = [encoded[i:i + CHUNK_CHARACTERS]
              for i in range(0, len(encoded), CHUNK_CHARACTERS)]
    steps = []
    for index, chunk in enumerate(chunks):
        lines = '\n'.join('    b' + repr(chunk[i:i + 100])
                          for i in range(0, len(chunk), 100))
        script = ("set -euo pipefail\npython3 - <<'PAYLOAD_PART'\n"
                  "from pathlib import Path\n"
                  "folder=Path('.screen_read_ci_payload');folder.mkdir(exist_ok=True)\n"
                  f"with (folder/'part_{index:04d}.b64').open('xb') as stream:\n"
                  "    stream.write(\n" + textwrap.indent(lines, '    ') +
                  "\n    )\nPAYLOAD_PART\n")
        validate_run_script(script)
        steps.append({'name':f'Stage pinned source part {index + 1} of {len(chunks)}',
                      'shell':'bash', 'run':script})
    program = f'''import base64,hashlib,io,lzma,tarfile
from pathlib import Path,PurePosixPath
folder=Path('.screen_read_ci_payload')
expected=[f'part_{{index:04d}}.b64' for index in range({len(chunks)})]
assert sorted(p.name for p in folder.iterdir())==expected,'PAYLOAD_PART_SET'
encoded=''.join((folder/name).read_text(encoding='ascii') for name in expected)
data=lzma.decompress(base64.b64decode(encoded,validate=True))
assert len(data)=={len(data)},'SOURCE_INPUT_SIZE'
assert hashlib.sha256(data).hexdigest()=={hashlib.sha256(data).hexdigest()!r},'SOURCE_INPUT_SHA256'
root=Path.cwd().resolve()
with tarfile.open(fileobj=io.BytesIO(data),mode='r:') as archive:
    members=archive.getmembers();seen=set()
    for member in members:
        path=PurePosixPath(member.name)
        assert member.name and not path.is_absolute() and '..' not in path.parts,'UNSAFE_SOURCE_PATH'
        assert path.as_posix()==member.name and '\\\\' not in member.name,'NONCANONICAL_SOURCE_PATH'
        target=(root/member.name).resolve()
        assert target.is_relative_to(root) and target!=root,'SOURCE_PATH_ESCAPE'
        assert member.isfile() and 0<=member.size<200000,'SOURCE_MEMBER_TYPE_OR_SIZE'
        assert member.name.casefold() not in seen,'DUPLICATE_SOURCE_PATH'
        seen.add(member.name.casefold())
    for member in members:
        target=root/member.name;target.parent.mkdir(parents=True,exist_ok=True)
        with target.open('xb') as stream:stream.write(archive.extractfile(member).read())
assert len(list(Path('app/ios/ChampionsOnDevice').glob('*.swift')))=={source_count},'SWIFT_SOURCE_COUNT'
print({(revision+'_SOURCE_INPUT_SHA256='+hashlib.sha256(data).hexdigest()+'; NO_PRIVATE_CAPTURES')!r})
'''
    script = "set -euo pipefail\npython3 - <<'RESTORE_PINNED_SOURCE'\n" + program + 'RESTORE_PINNED_SOURCE\n'
    validate_run_script(script)
    steps.append({'name':'Verify all parts and restore pinned source and synthetic fixtures',
                  'shell':'bash', 'run':script})
    return steps
