#!/usr/bin/env python3
"""R596 local-only form reference importer. Does not infer Pokémon labels.

Requires a human-labelled, actual Pokémon Champions PNG crop AND the 192-value
feature vector emitted by the matching R595 capture extractor. Never generates
features from unrelated artwork or automatically assigns a form.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import struct
import tempfile
import zlib

SCHEMA = "trueplan.r596.visual_catalog.v1"
EXTRACTOR = "R595-16x12-unverified-scale"  # locked until exact R595 vector contract audited
ALLOWED_FORMS = {"normal", "mega", "mega-x", "mega-y", "mega-z"}
SAFE_ID = re.compile(r"^[a-z0-9_.:-]{1,96}$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def check_png(png: bytes) -> tuple[int, int]:
    """CRC-checks all PNG chunks, forbids truncated/ambiguous streams."""
    if not png.startswith(PNG_SIGNATURE) or len(png) < 70:
        raise ValueError("PNG_MISSING_OR_TOO_SHORT")
    p = 8
    dimensions = None
    idat = 0
    done = False
    while p < len(png):
        if p + 12 > len(png):
            raise ValueError("PNG_CHUNK_TRUNCATED")
        size = struct.unpack(">I", png[p : p + 4])[0]
        if size > 20_000_000 or p + 12 + size > len(png):
            raise ValueError("PNG_CHUNK_SIZE_INVALID")
        typ = png[p + 4 : p + 8]
        body = png[p + 8 : p + 8 + size]
        expected = struct.unpack(">I", png[p + 8 + size : p + 12 + size])[0]
        if zlib.crc32(typ + body) != expected:
            raise ValueError("PNG_CRC_INVALID")
        if dimensions is None:
            if typ != b"IHDR" or size != 13:
                raise ValueError("PNG_FIRST_CHUNK_NOT_IHDR")
            width, height = struct.unpack(">II", body[:8])
            if not (16 <= width <= 4096 and 16 <= height <= 4096):
                raise ValueError("PNG_INVALID_CROP_DIMENSIONS")
            dimensions = (width, height)
        elif typ == b"IHDR":
            raise ValueError("PNG_DUPLICATE_IHDR")
        if typ == b"IDAT":
            idat += size
        if typ == b"IEND":
            if size != 0 or p + 12 != len(png):
                raise ValueError("PNG_INVALID_END")
            done = True
            break
        p += 12 + size
    if not done or not idat:
        raise ValueError("PNG_NO_IMAGE_DATA_OR_END")
    return dimensions


def validate_feature_vector(data: bytes) -> list[float]:
    vector = json.loads(data)
    if not isinstance(vector, list) or len(vector) != 192:
        raise ValueError("R595_FEATURE_COUNT_MISMATCH")
    # Exclude booleans, NaN, infinity, ill-formed JSON/huge elements.
    if any(type(x) not in (float, int) or not math.isfinite(x) or abs(x) > 1e6 for x in vector):
        raise ValueError("R595_FEATURE_INVALID")
    return vector


def register(catalog_path: Path, png_path: Path, feature_path: Path, *,
             reference_id: str, species_id: str, form_id: str, side: str,
             session_id: str, frame_id: int, confirm_capture: bool,
             confirm_label: bool) -> dict:
    for value in (reference_id, species_id, session_id):
        if not SAFE_ID.fullmatch(value):
            raise ValueError("REFERENCE_ID_INVALID")
    if form_id not in ALLOWED_FORMS:
        raise ValueError("FORM_LABEL_INVALID")
    if side not in ("own", "opponent") or frame_id < 0:
        raise ValueError("SIDE_OR_FRAME_INVALID")
    if not (confirm_capture and confirm_label):
        raise ValueError("CAPTURE_AND_LABEL_HUMAN_ATTESTATION_REQUIRED")
    png = png_path.read_bytes()
    if len(png) > 20_000_000:
        raise ValueError("CROP_TOO_LARGE")
    check_png(png)
    vector = validate_feature_vector(feature_path.read_bytes())
    sha = hashlib.sha256(png).hexdigest()
    if catalog_path.exists():
        catalog = json.loads(catalog_path.read_bytes())
        if catalog.get("schema") != SCHEMA or not isinstance(catalog.get("references"),list):
            raise ValueError("CATALOG_SCHEMA_MISMATCH")
    else:
        catalog = {"schema": SCHEMA, "references": []}
    for entry in catalog["references"]:
        if entry.get("referenceID") == reference_id:
            raise ValueError("REFERENCE_ID_ALREADY_REGISTERED")
        if entry.get("imageSHA256") == sha:
            raise ValueError("IMAGE_CROP_ALREADY_REGISTERED")
    catalog["references"].append({
        "referenceID": reference_id,
        "speciesID": species_id,
        "formID": form_id,
        "captureSide": side,
        "sessionID": session_id,
        "frameID": frame_id,
        "sourceKind": "champions-screen-capture",
        "labelEvidence": "human-confirmed",
        "extractorID": EXTRACTOR,
        "imageSHA256": sha,
        "features": vector,
    })
    # Must not expose crop images publicly; only the SHA and numeric features
    # are kept in the catalog, and no upload operation exists in this tool.
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".r596_catalog_",dir=str(catalog_path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(catalog, out, ensure_ascii=False, separators=(",",":"), allow_nan=False)
            out.write("\n")
        os.replace(tmp_name, catalog_path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
    return {"referenceID":reference_id,"imageSHA256":sha,"references":len(catalog["references"]),"certified":False}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--catalog",required=True,type=Path)
    p.add_argument("--crop-png",required=True,type=Path)
    p.add_argument("--features-json",required=True,type=Path)
    p.add_argument("--reference-id",required=True)
    p.add_argument("--species-id",required=True)
    p.add_argument("--form-id",required=True)
    p.add_argument("--side",required=True)
    p.add_argument("--session-id",required=True)
    p.add_argument("--frame-id",required=True,type=int)
    p.add_argument("--confirm-champions-screen-capture",action="store_true")
    p.add_argument("--confirm-human-form-label",action="store_true")
    args=p.parse_args()
    result=register(args.catalog,args.crop_png,args.features_json,reference_id=args.reference_id,
                    species_id=args.species_id,form_id=args.form_id,side=args.side,
                    session_id=args.session_id,frame_id=args.frame_id,
                    confirm_capture=args.confirm_champions_screen_capture,confirm_label=args.confirm_human_form_label)
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
    main()
