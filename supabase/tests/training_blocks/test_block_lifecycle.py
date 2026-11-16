"""Schema 4 checks (duration clock, delete_training_block) against the named,
isolated loopback database only. Needs the same PostgreSQL/PostgREST setup as
test_api.py; see README.md. Every case asserts on stored state."""
import concurrent.futures
import datetime
import json
import os
import time
import unittest
import uuid

import psycopg

import test_api
from test_api import BLOCK, FOREIGN, OTHER, OWNER, PLAN, SECOND, SPLIT, api, session_row, sql

T1, T2, T3, T4 = ('2026-11-16T00:00:0%dZ' % n for n in (1, 2, 3, 4))
EARLY = '2026-11-15T00:00:00Z'
LATE = '2030-01-01T00:00:00Z'


def when(value):
    return None if value is None else datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))


def rpc_delete(block_id, owner=OWNER, schema=4, capable=True):
    return api('rpc/delete_training_block', 'POST', {'target': block_id}, owner=owner, schema=schema, capable=capable)


def block_row(block_id=None, split=SPLIT, name='Extra', position=5, count=None, clock=None, updated=T1, owner=OWNER, **extra):
    row = {'id': block_id or str(uuid.uuid4()), 'user_id': owner, 'split_id': split, 'name': name,
           'position': position, 'created_at': EARLY, 'updated_at': updated, **extra}
    if count is not None or 'planned_week_count' in extra:
        row.setdefault('planned_week_count', count)
    if clock is not None:
        row['planned_week_count_updated_at'] = clock
    return row


def week_row(block_id, number, week_id=None, split=SPLIT, owner=OWNER, updated=T1, **extra):
    return {'id': week_id or str(uuid.uuid4()), 'user_id': owner, 'split_id': split, 'block_id': block_id,
            'number': number, 'created_at': EARLY, 'updated_at': updated, **extra}


class BlockLifecycleTest(unittest.TestCase):
    setUp = test_api.TrainingBlocksApiTest.setUp

    def activate(self, schema=4, owner=OWNER):
        status, body = api('rpc/activate_training_schema', 'POST', {}, owner=owner, schema=schema)
        self.assertEqual((status, body), (200, schema), body)

    def post(self, table, body, schema=4, owner=OWNER):
        status, result = api(table, 'POST', body, owner=owner, schema=schema)
        self.assertLess(status, 300, result)
        return result[0]

    def get(self, path, schema=4, owner=OWNER):
        status, rows = api(path, schema=schema, owner=owner)
        self.assertEqual(status, 200, rows)
        return rows

    def stored_block(self, block_id):
        return self.get(f'training_blocks?id=eq.{block_id}')[0]

    def duration(self, block_id):
        row = self.stored_block(block_id)
        return row['planned_week_count'], when(row['planned_week_count_updated_at'])

    def new_block(self, split=SPLIT, count=None, clock=None, weeks=(), **extra):
        block = self.post('training_blocks', block_row(split=split, count=count, clock=clock, **extra))
        ids = [self.post('training_weeks', week_row(block['id'], n, split=split))['id'] for n in weeks]
        return block['id'], ids

    def session_in(self, week_id, number, **extra):
        row = session_row(number, training_week_id=week_id, **extra)
        row['data']['trainingWeekId'] = week_id
        return row

    def move_progress(self, week_id, revision=None, updated=T2):
        progress = self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]
        progress.update(active_week_id=week_id, available_week_ids=[week_id],
                        revision=revision or str(uuid.uuid4()), updated_at=updated)
        return self.post('workout_progress', progress)

    def unused_pair(self):
        """SECOND has no plans, so both of its blocks are free to delete."""
        self.activate()
        legacy = self.get(f'training_blocks?split_id=eq.{SECOND}')
        self.assertEqual(len(legacy), 1)
        other, _ = self.new_block(split=SECOND, name='Other', count=4, clock=T1, weeks=[1])
        return legacy[0]['id'], other

    # --- schema level -----------------------------------------------------

    def test_activation_to_4_fences_older_headers_exactly_like_3_did_for_2(self):
        self.activate(3)
        self.assertEqual(sql(f"select minimum_training_schema from account_training_capabilities where user_id='{OWNER}'"), '3')
        self.assertEqual(api('workout_progress', schema=3)[0], 200)
        self.activate(4)
        self.activate(4)  # Idempotent.
        self.assertEqual(sql(f"select minimum_training_schema from account_training_capabilities where user_id='{OWNER}'"), '4')
        for version in (1, 2, 3):
            for table in ['splits', 'workout_plans', 'workout_sessions', 'training_blocks', 'training_weeks', 'workout_progress']:
                status, body = api(table, schema=version)
                self.assertEqual((status, body['code']), (426, 'PT426'), (version, table, body))
            status, body = api('rpc/activate_training_schema', 'POST', {}, schema=version)
            self.assertEqual((status, body['code']), (426, 'PT426'), body)
            self.assertEqual(api('training_blocks', 'POST', block_row(count=3), schema=version)[0], 426)
            self.assertEqual(rpc_delete(BLOCK, schema=version)[0], 426)
        self.assertEqual(api('training_blocks')[0], 426)  # No header at all.
        self.assertEqual(sql(f"select minimum_training_schema from account_training_capabilities where user_id='{OWNER}'"), '4')
        self.assertEqual(api('splits', schema=4)[0], 200)
        # Another account stays legacy-compatible until its own activation.
        self.assertEqual(api('splits', owner=OTHER, capable=False)[0], 200)

    def test_header_4_activates_a_fresh_account_directly_and_unknown_headers_are_refused(self):
        self.activate(4)
        self.assertEqual(len(self.get(f'training_blocks?split_id=eq.{SPLIT}')), 1)
        self.assertEqual(sql(f"select count(*) from workout_progress where user_id='{OWNER}'"), '1')
        status, body = api('rpc/activate_training_schema', 'POST', {}, owner=OTHER, schema=5)
        self.assertEqual((status, body['code']), (426, 'PT426'), body)
        self.assertEqual(sql('select count(*) from account_training_capabilities'), '1')
        # The capability check constraint knows level 4 and nothing above it.
        sql(f"update account_training_capabilities set minimum_training_schema=4 where user_id='{OWNER}'")
        with self.assertRaises(psycopg.errors.CheckViolation):
            sql(f"update account_training_capabilities set minimum_training_schema=5 where user_id='{OWNER}'")

    def test_activation_to_4_backfills_lazy_metadata_like_3_and_leaves_the_clock_null(self):
        self.assertLess(api('workout_sessions', 'POST', session_row(2), capable=False)[0], 300)
        self.activate(4)
        progress = self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]
        self.assertEqual(len(progress['available_week_ids']), 1)
        block = self.get(f'training_blocks?split_id=eq.{SPLIT}')[0]
        self.assertEqual(block['planned_week_count'], 2)
        self.assertIsNone(block['planned_week_count_updated_at'])

    # --- duration clock ---------------------------------------------------

    def test_legacy_writes_without_a_clock_stay_grow_only(self):
        self.activate(3)
        block_id, _ = self.new_block(count=6, updated=T1)
        for count, updated in [(4, T2), (3, T3)]:
            self.post('training_blocks', block_row(block_id, name='Renamed', count=count, updated=updated), schema=3)
        stored = self.stored_block(block_id)
        self.assertEqual((stored['name'], stored['planned_week_count']), ('Renamed', 6))
        self.assertIsNone(stored['planned_week_count_updated_at'])
        self.post('training_blocks', block_row(block_id, name='Renamed', count=8, updated=T4), schema=3)
        self.assertEqual(self.duration(block_id), (8, None))

    def test_clock_shortens_extends_and_ties_keep_the_larger_count(self):
        self.activate()
        block_id, _ = self.new_block(count=6, clock=T1)
        self.assertEqual(self.duration(block_id), (6, when(T1)))
        self.post('training_blocks', block_row(block_id, count=4, clock=T2, updated=T2))
        self.assertEqual(self.duration(block_id), (4, when(T2)))
        self.post('training_blocks', block_row(block_id, count=5, clock=T3, updated=T3))
        self.assertEqual(self.duration(block_id), (5, when(T3)))
        # Same clock: the larger count wins, whichever arrives first.
        self.post('training_blocks', block_row(block_id, count=4, clock=T3, updated=T4))
        self.assertEqual(self.duration(block_id), (5, when(T3)))
        self.post('training_blocks', block_row(block_id, count=7, clock=T3, updated=T4))
        self.assertEqual(self.duration(block_id), (7, when(T3)))
        # An older clock never wins, even carrying the larger count.
        self.post('training_blocks', block_row(block_id, count=9, clock=T2, updated=LATE))
        self.assertEqual(self.duration(block_id), (7, when(T3)))

    def test_null_count_is_ignored_and_omitted_clock_ties_with_the_stored_one(self):
        self.activate()
        block_id, _ = self.new_block(count=5, clock=T2)
        # A row with no count (a partially uploaded block) keeps count and clock,
        # even when it brings a newer clock.
        self.post('training_blocks', block_row(block_id, name='Partial', planned_week_count=None, clock=T4, updated=T3))
        self.assertEqual(self.duration(block_id), (5, when(T2)))
        self.assertEqual(self.stored_block(block_id)['name'], 'Partial')
        # An older client upsert omits the clock column entirely. PostgREST leaves
        # the stored value in NEW, so it is a tie: the larger count wins.
        grown = block_row(block_id, name='Partial', count=8, updated=T4)
        self.assertNotIn('planned_week_count_updated_at', grown)
        self.post('training_blocks', grown)
        self.assertEqual(self.duration(block_id), (8, when(T2)))
        self.post('training_blocks', block_row(block_id, name='Partial', count=3, updated=LATE))
        self.assertEqual(self.duration(block_id), (8, when(T2)))
        # A clock-less insert of a new block and a first stamp on a legacy block.
        legacy_id, _ = self.new_block(count=6)
        self.assertEqual(self.duration(legacy_id), (6, None))
        self.post('training_blocks', block_row(legacy_id, count=4, clock=T1, updated=T2))
        self.assertEqual(self.duration(legacy_id), (4, when(T1)))

    def test_concurrent_rename_keeps_the_name_but_not_the_stale_count(self):
        self.activate()
        block_id, _ = self.new_block(name='Build', count=6, clock=T1, updated=T1)
        # Device A shortens at T3 while device B renames at T4 with its stale 6.
        self.post('training_blocks', block_row(block_id, name='Build', count=4, clock=T3, updated=T3))
        self.post('training_blocks', block_row(block_id, name='Renamed', count=6, clock=T1, updated=T4))
        stored = self.stored_block(block_id)
        self.assertEqual((stored['name'], stored['planned_week_count']), ('Renamed', 4))
        self.assertEqual(when(stored['planned_week_count_updated_at']), when(T3))
        # The reverse order: the older rename arrives after the newer shorten
        # and must not revive its name or its count; the newer clock still wins
        # the count even though the row timestamp is older.
        self.post('training_blocks', block_row(block_id, name='Stale name', count=2, clock=T4, updated=T2))
        stored = self.stored_block(block_id)
        self.assertEqual((stored['name'], stored['planned_week_count']), ('Renamed', 2))
        self.assertEqual(when(stored['planned_week_count_updated_at']), when(T4))

    def test_heal_raise_at_the_stored_clock_wins_a_tie(self):
        self.activate()
        block_id, _ = self.new_block(count=6, clock=T1)
        self.post('training_blocks', block_row(block_id, count=4, clock=T2, updated=T2))
        # The client raises 4 to 5 (a week was reached) keeping clock and updated_at.
        self.post('training_blocks', block_row(block_id, count=5, clock=T2, updated=T2))
        self.assertEqual(self.duration(block_id), (5, when(T2)))

    # --- delete_training_block --------------------------------------------

    def test_delete_tombstones_block_and_weeks_with_one_stamp_and_returns_api_rows(self):
        self.activate()
        block_id, week_ids = self.new_block(count=3, clock=T1, weeks=[1, 2, 3])
        # An already-deleted week and an untouched sibling block must not change.
        spare, _ = self.new_block(name='Spare', position=6, count=2, clock=T1, weeks=[1])
        before_spare = self.get(f'training_weeks?block_id=eq.{spare}')
        status, result = rpc_delete(block_id)
        self.assertEqual(status, 200, result)
        self.assertEqual(set(result), {'block', 'weeks'})
        block = self.stored_block(block_id)
        weeks = self.get(f'training_weeks?block_id=eq.{block_id}&order=number')
        # Same JSON the REST API serves, so the client applies it through its normal row path.
        self.assertEqual(result['block'], block)
        self.assertEqual(result['weeks'], weeks)
        self.assertEqual(sorted(result['block']), sorted(self.get(f'training_blocks?id=eq.{spare}')[0]))
        self.assertEqual([w['number'] for w in weeks], [1, 2, 3])
        self.assertEqual({w['id'] for w in weeks}, set(week_ids))
        stamps = {row['deleted_at'] for row in [block, *weeks]}
        self.assertEqual(len(stamps), 1)
        self.assertIsNotNone(stamps.copy().pop())
        for row in [block, *weeks]:
            self.assertGreaterEqual(when(row['updated_at']), when(row['deleted_at']))
        self.assertEqual((block['name'], block['planned_week_count']), ('Extra', 3))
        self.assertEqual(self.get(f'training_weeks?block_id=eq.{spare}'), before_spare)
        self.assertIsNone(self.stored_block(spare)['deleted_at'])
        self.assertEqual(sql(f"select count(*) from training_blocks where split_id='{SPLIT}' and deleted_at is null"), '2')

    def test_delete_is_idempotent_and_keeps_the_original_tombstones(self):
        self.activate()
        block_id, _ = self.new_block(count=2, clock=T1, weeks=[1, 2])
        first = rpc_delete(block_id)
        time.sleep(0.05)
        self.assertEqual(rpc_delete(block_id), first)
        self.assertEqual(first[0], 200)
        self.assertEqual(first[1]['block'], self.stored_block(block_id))
        self.assertEqual(rpc_delete(block_id), first)

    def test_a_week_already_tombstoned_keeps_its_own_stamp(self):
        self.activate()
        block_id, week_ids = self.new_block(count=2, clock=T1, weeks=[1, 2])
        self.post('training_weeks', week_row(block_id, 2, week_id=week_ids[1], updated=T2, deleted_at=T2))
        status, result = rpc_delete(block_id)
        self.assertEqual(status, 200, result)
        by_number = {w['number']: w for w in result['weeks']}
        self.assertEqual(when(by_number[2]['deleted_at']), when(T2))
        self.assertNotEqual(when(by_number[1]['deleted_at']), when(T2))
        self.assertEqual(when(result['block']['deleted_at']), when(by_number[1]['deleted_at']))

    def test_unknown_and_foreign_ids_return_null_and_change_nothing(self):
        self.activate()
        self.activate(owner=OTHER)
        foreign = self.get('training_blocks', owner=OTHER)
        self.assertEqual(len(foreign), 1)
        extra = self.post('training_blocks', block_row(split=FOREIGN, owner=OTHER, name='Theirs', count=2, clock=T1), owner=OTHER)
        self.post('training_weeks', week_row(extra['id'], 1, split=FOREIGN, owner=OTHER), owner=OTHER)
        before = sql("select jsonb_agg(to_jsonb(b) order by id) from training_blocks b") + sql("select jsonb_agg(to_jsonb(w) order by id) from training_weeks w")
        for target in [str(uuid.uuid4()), extra['id'], foreign[0]['id']]:
            self.assertEqual(rpc_delete(target), (200, None), target)
        after = sql("select jsonb_agg(to_jsonb(b) order by id) from training_blocks b") + sql("select jsonb_agg(to_jsonb(w) order by id) from training_weeks w")
        self.assertEqual(before, after)
        self.assertEqual(self.stored_block(BLOCK)['deleted_at'], None)
        # The foreign owner can delete their own spare block, and it is theirs alone.
        status, result = rpc_delete(extra['id'], owner=OTHER)
        self.assertEqual((status, result['block']['user_id']), (200, OTHER), result)

    def test_account_below_4_or_unactivated_gets_426(self):
        status, body = rpc_delete(BLOCK, capable=False)
        self.assertEqual((status, body['code']), (426, 'PT426'), body)
        status, body = rpc_delete(BLOCK)  # Header 4, but no capability row yet.
        self.assertEqual((status, body['code'], body['message']), (426, 'PT426', 'Update OpenGym to delete training blocks'), body)
        self.activate(3)
        status, body = rpc_delete(BLOCK)  # Header 4 on an account still at 3.
        self.assertEqual((status, body['code'], body['message']), (426, 'PT426', 'Update OpenGym to delete training blocks'), body)
        status, body = rpc_delete(BLOCK, schema=3)
        self.assertEqual((status, body['code']), (426, 'PT426'), body)
        self.assertEqual(sql('select count(*) from training_blocks where deleted_at is not null'), '0')
        self.assertEqual(sql(f"select minimum_training_schema from account_training_capabilities where user_id='{OWNER}'"), '3')

    def test_last_block_is_refused_with_details(self):
        self.activate()
        status, body = rpc_delete(BLOCK)
        self.assertEqual((status, body['code'], body['message'], body['details']),
                         (409, 'PT409', 'A split keeps at least one block', 'last_block'), body)
        self.assertIsNone(self.stored_block(BLOCK)['deleted_at'])
        self.assertEqual(sql(f"select count(*) from training_weeks where block_id='{BLOCK}' and deleted_at is not null"), '0')

    def test_a_split_never_loses_its_last_block_to_two_sequential_deletes(self):
        first, second = self.unused_pair()
        self.assertEqual(rpc_delete(first)[0], 200)
        status, body = rpc_delete(second)
        self.assertEqual((status, body['details']), (409, 'last_block'), body)
        self.assertEqual(sql(f"select count(*) from training_blocks where split_id='{SECOND}' and deleted_at is null"), '1')

    def test_concurrent_deletes_of_the_last_two_blocks_leave_exactly_one(self):
        first, second = self.unused_pair()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(rpc_delete, [first, second]))
        statuses = sorted(status for status, _ in results)
        self.assertEqual(statuses, [200, 409], results)
        loser = next(body for status, body in results if status == 409)
        self.assertEqual(loser['details'], 'last_block')
        self.assertEqual(sql(f"select count(*) from training_blocks where split_id='{SECOND}' and deleted_at is null"), '1')
        self.assertEqual(sql(f"select count(*) from training_weeks w join training_blocks b on b.id=w.block_id where b.split_id='{SECOND}' and b.deleted_at is null and w.deleted_at is not null"), '0')

    def test_in_use_by_a_session_is_refused_in_any_week_and_a_deleted_session_is_not(self):
        self.activate()
        block_id, (week_one, week_two) = self.new_block(count=2, clock=T1, weeks=[1, 2])
        draft = self.session_in(week_two, 2)
        draft['data']['isCompleted'] = False  # A draft/running session blocks like any other.
        session = self.post('workout_sessions', draft)
        status, body = rpc_delete(block_id)
        self.assertEqual((status, body['code'], body['message'], body['details']),
                         (409, 'PT409', 'This block is in use', 'in_use'), body)
        self.assertIsNone(self.stored_block(block_id)['deleted_at'])
        self.assertEqual(sql(f"select count(*) from training_weeks where block_id='{block_id}' and deleted_at is not null"), '0')
        # An orphan session of a deleted plan in the block still counts.
        sql(f"update workout_plans set deleted_at=now(), updated_at=now() where id='{PLAN}'")
        self.assertEqual(rpc_delete(block_id)[1]['details'], 'in_use')
        # Once the session is a tombstone the block is free (the week it sat in
        # is irrelevant: only live sessions count).
        tombstone = {**session, 'deleted_at': T3, 'updated_at': T3}
        self.post('workout_sessions', tombstone)
        self.assertIsNotNone(self.get(f"workout_sessions?id=eq.{session['id']}")[0]['deleted_at'])
        status, result = rpc_delete(block_id)
        self.assertEqual(status, 200, result)
        self.assertIsNotNone(self.stored_block(block_id)['deleted_at'])
        self.assertIn(week_one, {w['id'] for w in result['weeks']})

    def test_in_use_by_active_progress_is_refused_and_moving_away_frees_the_block(self):
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        self.move_progress(week)
        status, body = rpc_delete(block_id)
        self.assertEqual((status, body['code'], body['details']), (409, 'PT409', 'in_use'), body)
        self.assertIsNone(self.stored_block(block_id)['deleted_at'])
        # Progress back in the legacy block: the new block is free, the legacy one is now in use.
        legacy_week = str(uuid.uuid5(uuid.UUID(BLOCK), '1'))
        self.move_progress(legacy_week, updated=T3)
        self.assertEqual(rpc_delete(block_id)[0], 200)
        # The legacy block is the split's only live block again, so it is last_block first.
        self.assertEqual(rpc_delete(BLOCK)[1]['details'], 'last_block')

    def test_available_weeks_pointing_into_the_block_do_not_block_deletion(self):
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        legacy_week = str(uuid.uuid5(uuid.UUID(BLOCK), '1'))
        progress = self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]
        progress.update(available_week_ids=[legacy_week, week], revision=str(uuid.uuid4()), updated_at=T2)
        self.post('workout_progress', progress)
        self.assertEqual(rpc_delete(block_id)[0], 200)
        self.assertEqual(self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]['available_week_ids'], [legacy_week, week])

    def test_a_live_progress_row_of_a_tombstoned_plan_does_not_block(self):
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        self.move_progress(week)
        sql(f"update workout_plans set deleted_at=now(), updated_at=now() where id='{PLAN}'")
        self.assertIsNotNone(self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]['deleted_at'])
        self.assertEqual(rpc_delete(block_id)[0], 200)

    def test_deleted_split_is_refused_with_details(self):
        self.activate()
        block_id, _ = self.new_block(count=2, clock=T1, weeks=[1])
        try:
            # The split tombstone normally cascades to its blocks first, so a live
            # block under a deleted split needs the cascade switched off.
            sql('alter table splits disable trigger y_cascade_training_structure')
            sql(f"update splits set deleted_at=now(), updated_at=now() where id='{SPLIT}'")
        finally:
            sql('alter table splits enable trigger y_cascade_training_structure')
        self.assertIsNone(self.stored_block(block_id)['deleted_at'])
        status, body = rpc_delete(block_id)
        self.assertEqual((status, body['code'], body['message'], body['details']),
                         (409, 'PT409', 'Training split is unavailable', 'split_deleted'), body)
        self.assertIsNone(self.stored_block(block_id)['deleted_at'])

    def test_a_split_tombstone_leaves_the_block_rpc_idempotent(self):
        self.activate()
        block_id, _ = self.new_block(count=2, clock=T1, weeks=[1])
        self.assertLess(api(f'splits?id=eq.{SPLIT}', 'PATCH', {'deleted_at': T3, 'updated_at': T3}, schema=4)[0], 300)
        status, result = rpc_delete(block_id)
        self.assertEqual(status, 200, result)
        self.assertEqual(result['block'], self.stored_block(block_id))
        self.assertEqual(when(result['block']['deleted_at']), when(T3))

    def test_live_writes_into_the_deleted_structure_are_rejected_afterwards(self):
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        self.assertEqual(rpc_delete(block_id)[0], 200)
        # A new live week under the deleted block.
        status, body = api('training_weeks', 'POST', week_row(block_id, 2, updated=LATE), schema=4)
        self.assertGreaterEqual(status, 400, body)
        # A live session in a deleted week.
        status, body = api('workout_sessions', 'POST', self.session_in(week, 1), schema=4)
        self.assertGreaterEqual(status, 400, body)
        self.assertEqual(sql(f"select count(*) from workout_sessions where training_week_id='{week}'"), '0')
        # Live progress on a deleted week.
        progress = self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]
        progress.update(active_week_id=week, available_week_ids=[week], revision=str(uuid.uuid4()), updated_at=LATE)
        status, body = api('workout_progress', 'POST', progress, schema=4)
        self.assertGreaterEqual(status, 400, body)
        self.assertNotEqual(self.get(f'workout_progress?plan_id=eq.{PLAN}')[0]['active_week_id'], week)
        self.assertEqual(sql(f"select count(*) from training_weeks where block_id='{block_id}'"), '1')
        # Tombstone uploads for the same rows remain legal (a device pushing its own delete).
        self.assertLess(api('training_weeks', 'POST', week_row(block_id, 2, updated=LATE, deleted_at=LATE), schema=4)[0], 300)

    def test_tombstone_wins_over_a_stale_rename_or_extension_of_the_block(self):
        self.activate()
        block_id, (week,) = self.new_block(name='Build', count=4, clock=T1, weeks=[1])
        _, deleted = rpc_delete(block_id)
        tombstone = self.stored_block(block_id)
        self.post('training_blocks', block_row(block_id, name='Renamed', count=9, clock=LATE, updated=LATE, deleted_at=None))
        status, _ = api('training_weeks', 'POST', week_row(block_id, 1, week_id=week, updated=LATE, deleted_at=None), schema=4)
        self.assertGreaterEqual(status, 400)
        stored = self.stored_block(block_id)
        self.assertEqual({k: v for k, v in stored.items() if k != 'server_seq'},
                         {k: v for k, v in tombstone.items() if k != 'server_seq'})
        self.assertEqual(self.get(f'training_weeks?id=eq.{week}')[0]['deleted_at'], deleted['weeks'][0]['deleted_at'])

    def test_rescue_replay_after_a_delete_is_accepted_without_orphans(self):
        """Device B was offline: it pulls the tombstone, creates X', and re-uploads
        its plan progress and sessions into X' (blocks, weeks, sessions, progress)."""
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        self.assertEqual(rpc_delete(block_id)[0], 200)
        rescued = self.post('training_blocks', block_row(name='Extra', position=5, count=2, clock=T1))
        rescued_week = self.post('training_weeks', week_row(rescued['id'], 1))['id']
        session = self.post('workout_sessions', self.session_in(rescued_week, 1))
        progress = self.move_progress(rescued_week, updated=T4)
        self.assertEqual(session['training_week_id'], rescued_week)
        self.assertEqual(progress['active_week_id'], rescued_week)
        self.assertEqual(sql(f"""select count(*) from workout_sessions s join training_weeks w on w.id=s.training_week_id
                                 join training_blocks b on b.id=w.block_id
                                 where s.deleted_at is null and (w.deleted_at is not null or b.deleted_at is not null)"""), '0')
        self.assertEqual(sql(f"""select count(*) from workout_progress p join training_weeks w on w.id=p.active_week_id
                                 join training_blocks b on b.id=w.block_id
                                 where p.deleted_at is null and (w.deleted_at is not null or b.deleted_at is not null)"""), '0')
        # And the rescued block is now in use.
        self.assertEqual(rpc_delete(rescued['id'])[1]['details'], 'in_use')

    def test_stale_push_after_the_rpc_is_rejected_then_succeeds_against_the_rescued_block(self):
        """The RPC lands between device B's pull and push: its session push into X is
        rejected (retryable, nothing stored), then goes through into X'."""
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        pushed = self.session_in(week, 1)
        self.assertEqual(rpc_delete(block_id)[0], 200)
        status, body = api('workout_sessions', 'POST', pushed, schema=4)
        self.assertGreaterEqual(status, 400, body)
        self.assertEqual(sql(f"select count(*) from workout_sessions where id='{pushed['id']}'"), '0')
        rescued = self.post('training_blocks', block_row(count=2, clock=T1))
        rescued_week = self.post('training_weeks', week_row(rescued['id'], 1))['id']
        retry = self.session_in(rescued_week, 1)
        retry['id'] = pushed['id']
        retry['data']['id'] = pushed['id']
        self.post('workout_sessions', retry)
        self.assertEqual(self.get(f"workout_sessions?id=eq.{pushed['id']}")[0]['training_week_id'], rescued_week)

    def test_a_session_pushed_while_the_rpc_waits_for_the_account_lock_makes_it_in_use(self):
        """The RPC is serialised with the account's other writes: a session already
        being written when the RPC arrives is seen by the in-use check."""
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        session = self.session_in(week, 1)
        with psycopg.connect(host='127.0.0.1', port=55439, dbname='opengym_training_blocks_test',
                             user=os.environ.get('USER', 'aalish'), autocommit=False) as writer:
            writer.execute("select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-account:' || %s,0))", (OWNER,))
            writer.execute('''insert into public.workout_sessions(id,user_id,split_id,plan_id,plan_name,week_number,date,data,training_week_id)
                              values(%s,%s,%s,%s,'Push',1,'2026-01-01T00:00:00Z',%s::jsonb,%s)''',
                           (session['id'], OWNER, SPLIT, PLAN, json.dumps(session['data']), week))
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as workers:
                racing = workers.submit(rpc_delete, block_id)
                deadline = time.monotonic() + 5
                while sql("select count(*) from pg_stat_activity where wait_event='advisory'") == '0':
                    self.assertLess(time.monotonic(), deadline, 'RPC did not wait on the account lock')
                    time.sleep(0.01)
                self.assertFalse(racing.done())
                writer.commit()
                status, body = racing.result()
        self.assertEqual((status, body['details']), (409, 'in_use'), body)
        self.assertIsNone(self.stored_block(block_id)['deleted_at'])
        self.assertEqual(sql(f"select count(*) from workout_sessions where id='{session['id']}'"), '1')

    def test_progress_pushed_while_the_rpc_waits_makes_it_in_use(self):
        self.activate()
        block_id, (week,) = self.new_block(count=2, clock=T1, weeks=[1])
        with psycopg.connect(host='127.0.0.1', port=55439, dbname='opengym_training_blocks_test',
                             user=os.environ.get('USER', 'aalish'), autocommit=False) as writer:
            writer.execute("select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-account:' || %s,0))", (OWNER,))
            writer.execute("update public.workout_progress set active_week_id=%s, available_week_ids=array[%s]::uuid[], revision=%s, updated_at=%s where plan_id=%s",
                           (week, week, str(uuid.uuid4()), '2026-11-16T00:00:09Z', PLAN))
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as workers:
                racing = workers.submit(rpc_delete, block_id)
                deadline = time.monotonic() + 5
                while sql("select count(*) from pg_stat_activity where wait_event='advisory'") == '0':
                    self.assertLess(time.monotonic(), deadline, 'RPC did not wait on the account lock')
                    time.sleep(0.01)
                writer.commit()
                status, body = racing.result()
        self.assertEqual((status, body['details']), (409, 'in_use'), body)
        self.assertIsNone(self.stored_block(block_id)['deleted_at'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
