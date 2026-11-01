"""A fail-closed production snapshot must also satisfy its offline schema."""
import copy
import json
import unittest
from r557_fixture import screen_fixture
from schema_contract import validate_document
from r556_fixture import projection_fixture


def held_snapshot():
    state=json.loads(screen_fixture()['selected_evidence.json'])['screen_read_state']
    state.update(source_validation='HOLD',candidates=[],conflicts=[],knowledge_state='UNKNOWN',screen_kind='unknown',
                 reason='OCR_ROW_SOURCE_CONFLICT')
    state.pop('screen_classification');state.pop('layout_candidates')
    return state


class SourceGuardSchemaTests(unittest.TestCase):
    def test_empty_fail_closed_snapshot_is_valid(self):
        validate_document(held_snapshot())

    def test_held_snapshot_cannot_publish_candidate(self):
        state=held_snapshot()
        state['candidates']=json.loads(screen_fixture()['selected_evidence.json'])['screen_read_state']['candidates']
        with self.assertRaises(ValueError):validate_document(state)

    def test_held_snapshot_cannot_publish_layout_or_classification(self):
        original=json.loads(screen_fixture()['selected_evidence.json'])['screen_read_state']
        for key in ('screen_classification','layout_candidates'):
            with self.subTest(key=key):
                state=held_snapshot();state[key]=original[key]
                with self.assertRaises(ValueError):validate_document(state)

    def test_passed_current_screen_contract_still_requires_reports(self):
        for key in ('screen_classification','layout_candidates'):
            with self.subTest(key=key):
                state=json.loads(screen_fixture()['selected_evidence.json'])['screen_read_state'];state.pop(key)
                with self.assertRaises(ValueError):validate_document(state)

    def test_held_projection_contains_no_partial_mapped_geometry(self):
        projection=json.loads(projection_fixture()['selected_evidence.json'])['analysis_projection']
        original=copy.deepcopy(projection)
        projection.update(status='HOLD',mapped_rois=[],omitted_rois=[])
        validate_document(projection)
        for key in ('mapped_rois','omitted_rois'):
            if original[key]:
                changed=copy.deepcopy(projection);changed[key]=original[key]
                with self.assertRaises(ValueError):validate_document(changed)
