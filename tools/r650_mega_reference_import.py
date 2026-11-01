#!/usr/bin/env python3
"""R650 local-only PNG -> R595 reference-candidate import.

This is not a trained model or Mega-state certification. Only the
operator's own consented Pokémon Champions frames may be imported.
No internet access, no image upload, no public media redistribution.
"""
import argparse
import hashlib
import json
import re
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

SCHEMA = "trueplan.r650.local-capture-manifest.v1"
CATALOG = "trueplan.r595.manual-form-reference-library.v1"
LUMA_SPACE = "RGBA_MEMORY_ROW_ORDER_UNVERIFIED"
REGIONS = {
    "MEMORY_LEFT_ACTOR_HYPOTHESIS": (.06, .60, .30, .80),
    "MEMORY_RIGHT_ACTOR_HYPOTHESIS": (.60, .78, .35, .82),
}
PNG_SIGNATURE = bytes.fromhex("89504e470d0a1a0a")
MAX_FILE = 12 * 1024 * 1024
MAX_OUTPUT = 64 * 1024 * 1024
SHA = re.compile(r"[0-9a-f]{64}\Z")
TOKEN = re.compile(r"[A-Z0-9_-]{1,64}\Z")


class InvalidCapture(ValueError):
    pass


def require(test, reason):
    if not test:
        raise InvalidCapture(reason)


def read_json(path):
    return json.loads(Path(path).read_text("utf-8"))


def load_registry(path):
    x = read_json(path)
    forms = x["forms"]
    require(x["regulation"] == "M-C", "REGULATION_MISMATCH")
    require(len(forms) == 81, "REGISTRY_NOT_81")
    d = {x["id"]: x for x in forms}
    require(len(d) == 81, "DUPLICATE_FORM")
    require([sum(r["phase"] == p for r in forms)
             for p in ("M-A", "M-B", "M-C")] ==
            [59, 16, 6], "PHASE_COUNTS_WRONG")
    return d


def safe_read_png(root, rel):
    require(isinstance(rel, str) and rel.endswith(".png"),
            "NOT_RELATIVE_PNG")
    require(not rel.startswith("/") and "\\" not in rel and
            all(part not in ("", ".", "..")
                for part in rel.split("/")), "PATH_TRAVERSAL")
    base = root.resolve(strict=True)
    p = (base / rel).resolve(strict=True)
    require(base in p.parents and p.is_file() and
            not p.is_symlink(), "PATH_OUTSIDE_CAPTURE_ROOT")
    require(p.stat().st_size <= MAX_FILE, "PNG_TOO_LARGE")
    data = p.read_bytes()
    return data


def decode_png(data):
    require(data.startswith(PNG_SIGNATURE), "BAD_SIGNATURE")
    pos = 8
    header = None
    compressed = bytearray()
    ended = False
    chunk_names = []
    while pos + 12 <= len(data):
        size = struct.unpack(">I", data[pos:pos + 4])[0]
        name = data[pos + 4:pos + 8]
        pos += 8
        require(size <= MAX_FILE and pos + size + 4 <= len(data),
                "INVALID_CHUNK_LENGTH")
        buf = data[pos:pos + size]
        crc = struct.unpack(">I", data[pos + size:pos + size + 4])[0]
        pos += size + 4
        require(zlib.crc32(name + buf) & 0xffffffff == crc,
                "PNG_CRC_MISMATCH")
        require(name in (b"IHDR", b"IDAT", b"IEND") or
                name[0] & 0x20, "UNSUPPORTED_CRITICAL_PNG_CHUNK")
        if name == b"IHDR":
            require(header is None and not chunk_names, "DUP_IHDR")
            require(size == 13, "BAD_IHDR")
            w, h, bits, color, comp, filt, inter = struct.unpack(
                ">IIBBBBB", buf)
            require(256 <= w <= 4096 and 192 <= h <= 4096,
                    "UNSUPPORTED_DIMENSIONS")
            require(bits == 8 and color in (2, 6) and
                    comp == filt == inter == 0, "UNSUPPORTED_PNG_FORMAT")
            channels = 3 if color == 2 else 4
            require(h * (1 + w * channels) <= MAX_OUTPUT,
                    "PIXEL_DECOMPRESSION_BUDGET")
            header = (w, h, channels)
        elif name == b"IDAT":
            require(header is not None, "IDAT_BEFORE_HEADER")
            require(not ended, "IDAT_AFTER_END")
            compressed.extend(buf)
            require(len(compressed) <= MAX_FILE,
                    "COMPRESSED_PNG_TOO_LARGE")
        elif name == b"IEND":
            require(header is not None and size == 0,
                    "BAD_IEND")
            ended = True
            break
        chunk_names.append(name)
    require(header is not None and ended and pos == len(data),
            "PNG_MISSING_END_OR_TRAILING_DATA")
    w, h, channels = header
    maxraw = h * (1 + w * channels)
    dec = zlib.decompressobj()
    raw = dec.decompress(bytes(compressed), maxraw + 1)
    require(len(raw) == maxraw and dec.eof and not dec.unused_data
            and not dec.unconsumed_tail, "PNG_DECOMPRESSION_INVALID")
    stride = w * channels
    prior = bytearray(stride)
    rgb_rows = []
    idx = 0
    for _ in range(h):
        kind = raw[idx]
        idx += 1
        require(kind <= 4, "INVALID_PNG_FILTER")
        scan = bytearray(raw[idx:idx + stride])
        idx += stride
        for x in range(stride):
            a = scan[x - channels] if x >= channels else 0
            b = prior[x]
            c = prior[x - channels] if x >= channels else 0
            if kind == 1:
                scan[x] = (scan[x] + a) & 255
            elif kind == 2:
                scan[x] = (scan[x] + b) & 255
            elif kind == 3:
                scan[x] = (scan[x] + ((a + b) // 2)) & 255
            elif kind == 4:
                p = a + b - c
                da, db, dc = abs(p - a), abs(p - b), abs(p - c)
                q = a if da <= db and da <= dc else (b if db <= dc else c)
                scan[x] = (scan[x] + q) & 255
        rgb_rows.append(scan)
        prior = scan
    return w, h, channels, rgb_rows


def sample_luma(png, region):
    w, h, n, rows = png
    x0, x1, y0, y1 = REGIONS[region]
    result = []
    for y in range(12):
        for x in range(16):
            xx = min(w - 1, int(w * (x0 + (x1 - x0) *
                                       (x + .5) / 16)))
            yy = min(h - 1, int(h * (y0 + (y1 - y0) *
                                       (y + .5) / 12)))
            k = xx * n
            vals = rows[yy]
            if n == 4 and vals[k + 3] < 160:
                result.append(-1)
            else:
                result.append((77 * vals[k] + 150 * vals[k + 1] +
                               29 * vals[k + 2]) >> 8)
    visible = [v for v in result if v >= 0]
    require(len(visible) >= 180, "INSUFFICIENT_VISIBLE_CELLS")
    require(max(visible) - min(visible) >= 25,
            "INSUFFICIENT_SHAPE_TEXTURE")
    return result


def make_references(registry, labels, root):
    require(labels.get("schema") == SCHEMA, "MANIFEST_SCHEMA_WRONG")
    require(labels.get("rights_scope") == "OWN_GAMEPLAY_LOCAL_ONLY",
            "CAPTURE_RIGHTS_NOT_REVIEWED")
    shots = labels.get("shots")
    require(isinstance(shots, list) and len(shots) <= 5000,
            "INVALID_SHOT_COUNT")
    seen = set()
    identity = {}
    refs = []
    counts = Counter()
    for shot in shots:
        require(isinstance(shot, dict), "INVALID_SHOT")
        rel = shot.get("file")
        source = shot.get("source_kind")
        form_id = shot.get("form_id")
        region = shot.get("region")
        session = shot.get("capture_session_id")
        frame = shot.get("frame_id")
        epoch = shot.get("epoch")
        require(source == "USER_CAPTURED_CHAMPIONS_GAMEPLAY",
                "WRONG_CAPTURE_SOURCE")
        require(shot.get("human_label_reviewed") is True and
                shot.get("privacy_reviewed") is True,
                "LABEL_OR_PRIVACY_UNREVIEWED")
        require(isinstance(session, str) and
                1 <= len(session) <= 80 and
                isinstance(frame, int) and type(frame) is int and
                frame > 0 and isinstance(epoch, int) and
                type(epoch) is int and epoch > 0,
                "INVALID_FRAME_PROVENANCE")
        require(region in REGIONS, "INVALID_ACTOR_REGION")
        require(isinstance(form_id, str), "INVALID_FORM_ID")
        mega = registry.get(form_id)
        base_species = form_id.removesuffix("-base")
        base = next((r for r in registry.values()
                     if r["species"].lower() == base_species), None)
        require(mega is not None or
                (form_id.endswith("-base") and base is not None),
                "UNKNOWN_FORM_ID")
        effective = mega or base
        require(isinstance(rel, str), "MISSING_FILE_PATH")
        key = (session, epoch, frame, region)
        require(key not in seen, "DUPLICATE_ACTOR_FRAME")
        seen.add(key)
        image = safe_read_png(root, rel)
        digest = hashlib.sha256(image).hexdigest()
        require(SHA.fullmatch(digest), "INVALID_HASH")
        previous = identity.get((session, epoch, frame))
        require(previous in (None, digest),
                "FRAME_ID_REFERENCES_DIFFERENT_PNG")
        identity[(session, epoch, frame)] = digest
        spec = effective["species"].upper()
        form = ("MEGA_" + effective["variant"]
                if mega and effective["variant"] != "N" else
                ("MEGA" if mega else "BASE"))
        require(TOKEN.fullmatch(spec) and TOKEN.fullmatch(form),
                "INVALID_SPECIES_TOKEN")
        pixels = decode_png(image)
        grid = sample_luma(pixels, region)
        ref_id = f"R650_{len(refs):05d}"
        refs.append({
            "reference_id": ref_id,
            "region": region,
            "species_token": spec,
            "form_token": form,
            "mega_label_claim": mega is not None,
            "human_label_reviewed": True,
            "reference_image_sha256": digest,
            "luma_grid": grid,
            "coordinate_space": LUMA_SPACE,
            "certified_as_game_state": False
        })
        counts[form_id] += 1
    # R595 currently accepts no more than 512 references per catalog.
    # Explicitly split; never pretend each shard covers all candidates.
    shards = []
    for i in range(0, len(refs), 512):
        shards.append({"schema": CATALOG,
                       "references": refs[i:i + 512]})
    return shards, counts


def run(args):
    registry = load_registry(args.registry)
    labels = read_json(args.manifest)
    shards, counts = make_references(registry, labels,
                                      Path(args.capture_root))
    root = Path(args.output)
    root.mkdir(parents=True, exist_ok=True)
    for i, part in enumerate(shards):
        (root / f"r650_local_refs_{i:03d}.json").write_text(
            json.dumps(part, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8")
    covered = [f for f in registry if counts[f] > 0]
    report = {
        "schema": "trueplan.r650.mega-capture-coverage.v1",
        "eligible_mega_form_count": 81,
        "mega_forms_with_human_labels": len(covered),
        "mega_form_count_unseen": 81 - len(covered),
        "samples_imported": sum(counts.values()),
        "shards": len(shards),
        "source_kind": "USER_CAPTURED_CHAMPIONS_GAMEPLAY",
        "scope": "LOCAL_REFERENCE_CANDIDATES_NOT_GAME_CERTIFICATION",
        "owner_certified": False,
        "mega_form_certified": False,
        "battle_advice_authorized": False,
        "original_pngs_stored_in_output": False,
        "held_out_accuracy": "NOT_MEASURED",
        "coverage_by_form": {k: counts.get(k, 0)
                             for k in registry}
    }
    (root / "r650_coverage.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8")
    print("R650_LOCAL_IMPORT_PASS", report["samples_imported"],
          report["mega_forms_with_human_labels"],len(shards))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--capture-root", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        run(args)
    except (OSError, InvalidCapture, KeyError, ValueError) as e:
        print("R650_LOCAL_IMPORT_REJECT", str(e), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
