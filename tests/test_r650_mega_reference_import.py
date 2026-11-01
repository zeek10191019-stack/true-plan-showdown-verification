import importlib.util
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "r650", ROOT / "tools/r650_mega_reference_import.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def chunk(tag, body):
    return (struct.pack(">I", len(body)) + tag + body +
            struct.pack(">I", zlib.crc32(tag + body) & 0xffffffff))


def synthetic_png(w=256, h=192):
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            row.extend([(x * 7 + y * 3) % 256,
                        (x * 2 + y * 11) % 256,
                        (x * 13 + y * 5) % 256,
                        255])
        rows.append(bytes(row))
    header = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (mod.PNG_SIGNATURE + chunk(b"IHDR", header) +
            chunk(b"IDAT", zlib.compress(b"".join(rows))) +
            chunk(b"IEND", b""))


class MegaImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "a.png").write_bytes(synthetic_png())
        self.registry = mod.load_registry(
            ROOT / "research/mega_m_c_81_registry.json")
        self.shot = dict(
            file="a.png", form_id="gyarados-mega",
            source_kind="USER_CAPTURED_CHAMPIONS_GAMEPLAY",
            human_label_reviewed=True, privacy_reviewed=True,
            capture_session_id="session", frame_id=1, epoch=1,
            region="MEMORY_LEFT_ACTOR_HYPOTHESIS")
        self.labels = dict(schema=mod.SCHEMA,
                           rights_scope="OWN_GAMEPLAY_LOCAL_ONLY",
                           shots=[self.shot])

    def test_png_decoded_real_pixels(self):
        p = mod.decode_png((self.root / "a.png").read_bytes())
        self.assertEqual(p[:3], (256, 192, 4))
        self.assertEqual(len(mod.sample_luma(
            p, "MEMORY_LEFT_ACTOR_HYPOTHESIS")), 192)

    def test_reference_import_is_not_certifying(self):
        shards, counts = mod.make_references(
            self.registry, self.labels, self.root)
        ref = shards[0]["references"][0]
        self.assertEqual(len(ref["luma_grid"]), 192)
        self.assertEqual(ref["species_token"], "GYARADOS")
        self.assertEqual(ref["form_token"], "MEGA")
        self.assertTrue(ref["mega_label_claim"])
        self.assertFalse(ref["certified_as_game_state"])
        self.assertEqual(counts["gyarados-mega"], 1)

    def test_same_species_different_megas(self):
        for form, token in (("charizard-mega-x", "MEGA_X"),
                            ("charizard-mega-y", "MEGA_Y"),
                            ("absol-mega-z", "MEGA_Z"),
                            ("absol-mega", "MEGA"),
                            ("garchomp-base", "BASE")):
            self.labels["shots"] = [dict(self.shot, form_id=form)]
            shards, counts = mod.make_references(
                self.registry, self.labels, self.root)
            self.assertEqual(shards[0]["references"][0]
                             ["form_token"], token)

    def test_no_images_means_zero_samples(self):
        self.labels["shots"] = []
        shards, counts = mod.make_references(
            self.registry, self.labels, self.root)
        self.assertEqual(shards, [])
        self.assertEqual(sum(counts.values()), 0)

    def test_reject_traversal(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.make_references(self.registry,
                dict(self.labels, shots=[dict(self.shot, file="../a.png")]),
                self.root)

    def test_reject_unreviewed_labels(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.make_references(self.registry,
                dict(self.labels, shots=[dict(
                    self.shot, human_label_reviewed=False)]), self.root)

    def test_reject_wrong_source(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.make_references(self.registry,
                dict(self.labels, shots=[dict(
                    self.shot, source_kind="POKEMON_ARTWORK")]), self.root)

    def test_reject_spoofed_frame(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.make_references(self.registry,
                dict(self.labels, shots=[self.shot,
                                           dict(self.shot, form_id="gyarados-base")]),
                self.root)

    def test_reject_unlisted_form(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.make_references(self.registry,
                dict(self.labels, shots=[dict(
                    self.shot, form_id="mewtwo-mega-x")]), self.root)

    def test_reject_crc_tamper(self):
        p = bytearray(synthetic_png())
        p[55] ^= 1
        with self.assertRaises(mod.InvalidCapture):
            mod.decode_png(bytes(p))

    def test_reject_invalid_png_trailing_data(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.decode_png(synthetic_png() + b"hidden")

    def test_reject_fake_image(self):
        with self.assertRaises(mod.InvalidCapture):
            mod.decode_png(b"not really a png")


if __name__ == "__main__":
    unittest.main(verbosity=2)
