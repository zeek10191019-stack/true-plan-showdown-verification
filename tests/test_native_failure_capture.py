"""A failing or timed-out native subprocess must leave its actual output."""
import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from run_r571_native import capture_checked

class NativeFailureCaptureTests(unittest.TestCase):
    def test_success_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'native.log';result=capture_checked([sys.executable,'-c','print("complete")'],path,5)
            self.assertEqual(result.returncode,0);self.assertEqual(path.read_text(),'complete\n')
    def test_failure_output_is_saved_before_exception(self):
        with tempfile.TemporaryDirectory() as td,contextlib.redirect_stdout(io.StringIO()):
            path=Path(td)/'native.log'
            with self.assertRaises(subprocess.CalledProcessError):
                capture_checked([sys.executable,'-c','import sys;print("guard failed",file=sys.stderr);sys.exit(7)'],path,5)
            self.assertIn('guard failed',path.read_text())
    def test_timeout_partial_output_is_saved(self):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'native.log'
            with self.assertRaises(subprocess.TimeoutExpired):
                capture_checked([sys.executable,'-c','import time;print("started",flush=True);time.sleep(30)'],path,2)
            self.assertIn('started',path.read_text())

if __name__=='__main__':unittest.main()
