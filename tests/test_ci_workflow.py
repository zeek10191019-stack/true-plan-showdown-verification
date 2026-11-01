"""Exercise the actual emitted shell scripts, including pre-run failure causes."""
from pathlib import Path
import io
import random
import subprocess
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from ci_workflow_payload import payload_steps,validate_run_script

SWIFT='app/ios/ChampionsOnDevice/Fixture.swift'


def archive_bytes(extra=()):
    buffer=io.BytesIO()
    with tarfile.open(fileobj=buffer,mode='w') as archive:
        for name,data,kind in [(SWIFT,b'struct Fixture {}\n',tarfile.REGTYPE),*extra]:
            member=tarfile.TarInfo(name);member.type=kind
            if kind==tarfile.SYMTYPE:member.linkname='../outside'
            else:member.size=len(data)
            archive.addfile(member,io.BytesIO(data) if kind==tarfile.REGTYPE else None)
    return buffer.getvalue()


class WorkflowTransportTests(unittest.TestCase):
    def run_step(self,step,directory):
        return subprocess.run(['bash','--noprofile','--norc','-eo','pipefail','-c',step['run']],
                              cwd=directory,capture_output=True,text=True)

    def staged(self,directory,data=None,count=1):
        steps=payload_steps(data or archive_bytes(),count,'R554')
        for step in steps[:-1]:
            result=self.run_step(step,directory)
            self.assertEqual(result.returncode,0,result.stderr[-1000:])
        return steps

    def reject_archive(self,extra,reason):
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory,archive_bytes(extra))
            result=self.run_step(steps[-1],directory)
            self.assertNotEqual(result.returncode,0)
            self.assertIn(reason,result.stderr)
            self.assertFalse((Path(directory)/'app').exists(),'all paths validated before extraction')

    def test_expression_like_data_round_trips_without_workflow_expressions(self):
        data=(b'$'+b'{{ secrets.EXAMPLE }}\n')+bytes(range(256))
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory,archive_bytes([('fixtures/literal.bin',data,tarfile.REGTYPE)]))
            for step in steps:self.assertNotIn('$'+'{{',step['run'])
            result=self.run_step(steps[-1],directory)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual((Path(directory)/'fixtures/literal.bin').read_bytes(),data)

    def test_large_incompressible_input_splits_below_official_step_limit(self):
        data=random.Random(554).randbytes(150000)
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory,archive_bytes([('fixtures/noise.bin',data,tarfile.REGTYPE)]))
            self.assertGreater(len(steps),10)
            self.assertTrue(all(len(step['run'])<=21000 for step in steps))
            result=self.run_step(steps[-1],directory)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual((Path(directory)/'fixtures/noise.bin').read_bytes(),data)

    def test_expression_marker_inside_quoted_heredoc_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'GITHUB_EXPRESSION'):
            validate_run_script("cat <<'LITERAL'\n"+'$'+'{{ accidental }}\nLITERAL\n')

    def test_oversized_run_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'CHARACTER_LIMIT'):
            validate_run_script('x'*21001)

    def test_exact_step_limit_is_accepted(self):
        validate_run_script('x'*21000)

    def test_transport_is_deterministic(self):
        self.assertEqual(payload_steps(archive_bytes(),1,'R554'),payload_steps(archive_bytes(),1,'R554'))

    def test_corrupt_part_stops_before_source_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory)
            p=Path(directory)/'.screen_read_ci_payload/part_0000.b64'
            p.write_text('!' + p.read_text()[1:])
            result=self.run_step(steps[-1],directory)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse((Path(directory)/'app').exists())

    def test_missing_part_stops_before_source_extraction(self):
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory)
            (Path(directory)/'.screen_read_ci_payload/part_0000.b64').unlink()
            result=self.run_step(steps[-1],directory)
            self.assertIn('PAYLOAD_PART_SET',result.stderr)
            self.assertNotEqual(result.returncode,0)

    def test_unexpected_part_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory)
            (Path(directory)/'.screen_read_ci_payload/part_9999.b64').write_text('extra')
            result=self.run_step(steps[-1],directory)
            self.assertIn('PAYLOAD_PART_SET',result.stderr)
            self.assertNotEqual(result.returncode,0)

    def test_duplicate_archive_path_is_rejected_before_writing(self):
        self.reject_archive([(SWIFT,b'replaced',tarfile.REGTYPE)],'DUPLICATE_SOURCE_PATH')

    def test_case_collisions_are_rejected_for_macos(self):
        self.reject_archive([(SWIFT.upper(),b'replaced',tarfile.REGTYPE)],'DUPLICATE_SOURCE_PATH')

    def test_parent_traversal_is_rejected_before_writing(self):
        self.reject_archive([('../escape',b'x',tarfile.REGTYPE)],'UNSAFE_SOURCE_PATH')

    def test_absolute_path_is_rejected_before_writing(self):
        self.reject_archive([('/escape',b'x',tarfile.REGTYPE)],'UNSAFE_SOURCE_PATH')

    def test_symbolic_link_is_rejected_before_writing(self):
        self.reject_archive([('fixtures/link',b'',tarfile.SYMTYPE)],'SOURCE_MEMBER_TYPE_OR_SIZE')

    def test_oversized_member_is_rejected_before_writing(self):
        self.reject_archive([('fixtures/oversized',b'x'*200000,tarfile.REGTYPE)],'SOURCE_MEMBER_TYPE_OR_SIZE')

    def test_noncanonical_path_is_rejected(self):
        self.reject_archive([('fixtures//aliased',b'x',tarfile.REGTYPE)],'NONCANONICAL_SOURCE_PATH')

    def test_wrong_swift_count_cannot_report_success(self):
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory,count=2)
            result=self.run_step(steps[-1],directory)
            self.assertIn('SWIFT_SOURCE_COUNT',result.stderr)
            self.assertNotEqual(result.returncode,0)

    def test_existing_source_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            steps=self.staged(directory)
            p=Path(directory)/SWIFT;p.parent.mkdir(parents=True);p.write_text('existing')
            result=self.run_step(steps[-1],directory)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(p.read_text(),'existing')

    def test_boolean_source_count_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'INVALID_SOURCE_COUNT'):
            payload_steps(archive_bytes(),True,'R554')

    def test_revision_cannot_inject_shell_or_python(self):
        with self.assertRaisesRegex(ValueError,'INVALID_REVISION'):
            payload_steps(archive_bytes(),1,"R554'; exit 0 #")


if __name__=='__main__':unittest.main()
