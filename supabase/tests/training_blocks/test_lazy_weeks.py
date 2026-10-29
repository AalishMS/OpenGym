"""Lazy-week schema checks against the named, isolated loopback database only."""
import unittest
import uuid

import test_api
from test_api import OWNER, PLAN, SPLIT, api, session_row


class LazyWeeksApiTest(unittest.TestCase):
    setUp = test_api.TrainingBlocksApiTest.setUp

    def activate(self):
        self.assertEqual(api('rpc/activate_training_schema', 'POST', {}, schema=2), (200, 2))

    def test_upgrade_backfills_metadata_without_rewinding_progress_and_blocks_v1(self):
        for n in [1, 3]:
            self.assertLess(api('workout_sessions', 'POST', session_row(n), capable=False)[0], 300)
        self.assertEqual(api('rpc/activate_training_schema', 'POST', {}), (200, 1))
        before = api(f'workout_progress?plan_id=eq.{PLAN}')[1][0]
        self.activate()
        progress = api(f'workout_progress?plan_id=eq.{PLAN}', schema=2)[1][0]
        self.assertEqual(progress['active_week_id'], before['active_week_id'])
        self.assertEqual(progress['revision'], before['revision'])
        self.assertEqual(progress['state'], before['state'])
        self.assertEqual(len(progress['available_week_ids']), 2)
        block = api(f'training_blocks?split_id=eq.{SPLIT}', schema=2)[1][0]
        self.assertEqual(block['planned_week_count'], 3)
        self.assertEqual(api('workout_progress')[0], 426)
        self.assertEqual(api('rpc/activate_training_schema', 'POST', {})[0], 426)
        self.activate()
        self.assertEqual(api(f'workout_progress?plan_id=eq.{PLAN}', schema=2)[1][0], progress)

    def test_duration_and_independent_availability_survive_round_trip(self):
        self.activate()
        block_id = str(uuid.uuid4())
        first = str(uuid.uuid5(uuid.NAMESPACE_URL, f'https://opengym.app/splits/{SPLIT}/blocks/{block_id}/lazy-weeks/1'))
        second = str(uuid.uuid5(uuid.NAMESPACE_URL, f'https://opengym.app/splits/{SPLIT}/blocks/{block_id}/lazy-weeks/2'))
        def post(table, body):
            status, result = api(table, 'POST', body, schema=2)
            self.assertLess(status, 300, result)
            return result
        post('training_blocks', {'id': block_id, 'user_id': OWNER, 'split_id': SPLIT,
             'name': 'Build', 'position': 1, 'planned_week_count': 4,
             'created_at': '2026-10-29T00:00:00Z', 'updated_at': '2026-10-29T00:00:00Z'})
        def week(identity, number):
            return {'id': identity, 'user_id': OWNER, 'split_id': SPLIT, 'block_id': block_id,
                    'number': number, 'created_at': '2026-10-29T00:00:00Z', 'updated_at': '2026-10-29T00:00:00Z'}
        post('training_weeks', week(first, 1))
        push = api(f'workout_progress?plan_id=eq.{PLAN}', schema=2)[1][0]
        push.update(active_week_id=first, available_week_ids=[first], revision=str(uuid.uuid4()),
                    updated_at='2026-10-29T01:00:00Z')
        post('workout_progress', push)
        pull_id = str(uuid.uuid4())
        post('workout_plans', {'id': pull_id, 'user_id': OWNER, 'split_id': SPLIT, 'name': 'Pull',
                              'data': {'id': pull_id, 'splitId': SPLIT, 'name': 'Pull', 'exercises': []}})
        pull = {'id': str(uuid.uuid5(uuid.NAMESPACE_URL, f'https://opengym.app/splits/{SPLIT}/plans/{pull_id}/progress-v1')),
                'user_id': OWNER, 'split_id': SPLIT, 'plan_id': pull_id, 'active_week_id': first,
                'available_week_ids': [first], 'state': 'ready', 'revision': str(uuid.uuid4()),
                'updated_at': '2026-10-29T01:00:00Z'}
        post('workout_progress', pull)
        post('training_weeks', week(second, 2))
        post('training_weeks', week(second, 2))  # An independent replica reuses the logical slot.
        push.update(active_week_id=second, available_week_ids=[first, second], revision=str(uuid.uuid4()),
                    updated_at='2026-10-29T02:00:00Z')
        post('workout_progress', push)
        self.assertEqual(api(f'workout_progress?plan_id=eq.{pull_id}', schema=2)[1][0]['available_week_ids'], [first])
        self.assertEqual(api(f'workout_progress?plan_id=eq.{PLAN}', schema=2)[1][0]['available_week_ids'], [first, second])
        self.assertEqual([r['number'] for r in api(f'training_weeks?block_id=eq.{block_id}&order=number', schema=2)[1]], [1, 2])
        self.assertEqual(api(f'training_blocks?id=eq.{block_id}', schema=2)[1][0]['planned_week_count'], 4)
        original = api(f'training_blocks?id=eq.{block_id}', schema=2)[1][0]
        post('training_blocks', dict(original, planned_week_count=5, updated_at='2026-10-29T02:00:00Z'))
        # A later offline rename carries its stale duration of four.
        post('training_blocks', dict(original, name='Renamed', planned_week_count=4,
                                     updated_at='2026-10-29T03:00:00Z'))
        current = api(f'training_blocks?id=eq.{block_id}', schema=2)[1][0]
        self.assertEqual((current['name'], current['planned_week_count']), ('Renamed', 5))
        # An older extension must grow duration without reviving the old name.
        post('training_blocks', dict(original, planned_week_count=6,
                                     updated_at='2026-10-29T01:00:00Z'))
        current = api(f'training_blocks?id=eq.{block_id}', schema=2)[1][0]
        self.assertEqual((current['name'], current['planned_week_count']), ('Renamed', 6))
        bad = dict(push, available_week_ids=[first, str(uuid.uuid4())], updated_at='2026-10-29T03:00:00Z')
        self.assertEqual(api('workout_progress', 'POST', bad, schema=2)[0], 400)
        bad = dict(push, available_week_ids=[first, first], updated_at='2026-10-29T03:00:00Z')
        self.assertEqual(api('workout_progress', 'POST', bad, schema=2)[0], 400)


if __name__ == '__main__':
    unittest.main(verbosity=2)
