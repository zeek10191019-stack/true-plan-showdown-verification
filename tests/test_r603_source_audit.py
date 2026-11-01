import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.r603_source_audit import inspect, TARGETS


class AuditTest(unittest.TestCase):
    def test_scanner_bound_and_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            for p in TARGETS:
                (root / p).write_text('struct Example {}\nstatic func extractRaster() {}\n')
            data=inspect(root)
            self.assertFalse(data['actual_frame_producer_wired'])
            self.assertFalse(data['feature_parity_certified'])
            self.assertEqual(len(data['source']),4)
            self.assertEqual(len(data['source'][0]['sha256']),64)
            self.assertEqual(data['source'][0]['symbols'][0]['line'],2)

    def test_missing_parent_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(RuntimeError,'MISSING_PINNED_SOURCE'):
                inspect(Path(tmp))

if __name__=='__main__': unittest.main()
