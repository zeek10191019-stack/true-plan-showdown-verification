"""R601: verify exact R596..R600 workflow byte pins then materialize their deltas.

This deliberately NEVER executes any historical R597-R600 parent replay scripts.
It preserves R595 as the single previously Apple-verified baseline.
"""
import ast
import base64
import hashlib
import json
import lzma
import re
from pathlib import Path

PINS = {
    'an.yml': (17075, '4b3880df46b8151341e52181bcebee8dfe841e46', 'R596_DELTA', 'encoded', 'b64', 'json'),
    'ao.yml': (17880, '6856d53255adeac47e386e9841b447f0b52f7867', 'R597_ADDITIVE_DELTA', 'packed', 'b64', 'json'),
    'ar.yml': (15537, '6c6a31330626e59ff03052dbca5a865c5247b99b', 'R598_COMPACT', 'packed', 'b85', 'rows'),
    'as.yml': (13503, '889a80ab3354f909935f16e69dbcef7ddae52889', 'R599_REPLAY', 'packed', 'b85', 'rows'),
    'at.yml': (14696, 'SHA256:58c1753b390db98cb73b0c275a2f1c9d5c9e74f672906f299a8482c01540dd17', 'R600_REPLAY', 'encoded', 'b85', 'rows'),
}
# R600 is pinned by its SHA-256 digest rather than a Git blob digest.


def verify_file(name, raw):
    size, pin, _, _, _, _ = PINS[name]
    if len(raw) != size:
        raise ValueError('PIN_SIZE:' + name)
    if pin.startswith('SHA256:'):
        digest = hashlib.sha256(raw).hexdigest()
        pin = pin.split(':', 1)[1]
    else:
        digest = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
    if digest != pin:
        raise ValueError('PIN_DIGEST:' + name)


def block(raw, marker):
    pat = r"python3 - <<'" + re.escape(marker) + r"'\n(.*?)\n\s+" + re.escape(marker) + r"(?=\n|$)"
    m = re.search(pat, raw.decode('utf-8'), re.S)
    if not m:
        raise ValueError('MISSING_BLOCK:' + marker)
    import textwrap
    return textwrap.dedent(m.group(1))


def assigned(tree, key):
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == key for t in node.targets):
            return node.value
    raise ValueError('MISSING_VAR:' + key)


def payload_text(value):
    strings = [n.value for n in ast.walk(value) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    strings = [s for s in strings if len(s) > 500]
    if len(strings) != 1:
        raise ValueError('PAYLOAD_LITERAL_AMBIGUOUS')
    return ''.join(strings[0].split())


def delta_records(name, raw):
    verify_file(name, raw)
    _, _, marker, key, codec, fmt = PINS[name]
    source = block(raw, marker)
    tree = ast.parse(source)
    compressed_text = payload_text(assigned(tree, key))
    blob = base64.b64decode(compressed_text, validate=True) if codec == 'b64' else base64.b85decode(compressed_text)
    data = lzma.decompress(blob)
    result = []
    if fmt == 'json':
        manifest = json.loads(data)
        expected = 'trueplan.r596.embedded_delta.v1' if name == 'an.yml' else 'trueplan.r597.additive_delta.v1'
        if manifest['schema'] != expected:
            raise ValueError('DELTA_SCHEMA')
        for e in manifest['files']:
            encoded = e.get('text_b64', e.get('data_b64'))
            part = base64.b64decode(encoded, validate=True)
            if len(part) != e['size'] or hashlib.sha256(part).hexdigest() != e['sha256']:
                raise ValueError('DELTA_MEMBER_SHA:' + e['path'])
            result.append((e['path'], part))
    else:
        rows = ast.literal_eval(assigned(tree, 'rows'))
        pos = 0
        for path, size, sha in rows:
            part = data[pos:pos + size]
            pos += size
            if len(part) != size or hashlib.sha256(part).hexdigest() != sha:
                raise ValueError('DELTA_MEMBER_SHA:' + path)
            result.append((path, part))
        if pos != len(data):
            raise ValueError('TRAILING_MEMBER_DATA')
    if len(set(x[0] for x in result)) != len(result):
        raise ValueError('DUPLICATE_MEMBER')
    return result


def materialize(workflows, root):
    root = Path(root)
    all_rows = []
    for name in PINS:
        for relative, content in delta_records(name, workflows[name]):
            p = Path(relative)
            if p.is_absolute() or '..' in p.parts or not str(p).startswith(('app/ios/ChampionsOnDevice/', 'tests/', 'tools/')):
                raise ValueError('INVALID_PATH:' + relative)
            if p.suffix not in ('.swift', '.py'):
                raise ValueError('INVALID_TYPE:' + relative)
            target = root / p
            if target.exists() or target.is_symlink():
                raise ValueError('NON_ADDITIVE_OVERWRITE:' + relative)
            all_rows.append((target, content))
    if len(set(p for p, _ in all_rows)) != len(all_rows):
        raise ValueError('MULTISTAGE_DUPLICATE')
    for target, content in all_rows:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    return len(all_rows)
