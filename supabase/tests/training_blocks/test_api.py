"""Real SQL/PostgREST tests. Only runs against the named loopback test database."""
import base64
import concurrent.futures
import hashlib
import hmac
import json
import os
import psycopg
import time
import unittest
import urllib.error
import urllib.request
import uuid

OWNER = '00000000-0000-4000-8000-000000000011'
OTHER = '00000000-0000-4000-8000-000000000012'
SPLIT = '05120ff6-66b5-48cd-9808-141bcb949f24'
SECOND = '00000000-0000-4000-8000-000000000022'
FOREIGN = '00000000-0000-4000-8000-000000000023'
PLAN = '00000000-0000-4000-8000-000000000001'
BLOCK = str(uuid.uuid5(uuid.NAMESPACE_URL, f'https://opengym.app/splits/{SPLIT}/training-blocks/legacy-v1'))
SECRET = 'opengym-training-blocks-isolated-test-secret-32-characters'
BASE = 'http://127.0.0.1:55440'


def sql(query):
    with psycopg.connect(host='127.0.0.1', port=55439, dbname='opengym_training_blocks_test', user=os.environ.get('USER', 'aalish'), autocommit=True) as connection:
        cursor = connection.execute(query, prepare=False)
        while cursor.nextset():
            pass
        if cursor.description:
            value = cursor.fetchone()[0]
            return json.dumps(value) if isinstance(value, (dict, list)) else str(value)
        return ''



def token(owner=OWNER):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).decode().rstrip('=')
    body = encode({'alg': 'HS256', 'typ': 'JWT'}) + '.' + encode({'sub': owner, 'role': 'authenticated', 'exp': int(time.time()) + 3600})
    sig = base64.urlsafe_b64encode(hmac.new(SECRET.encode(), body.encode(), hashlib.sha256).digest()).decode().rstrip('=')
    return body + '.' + sig


def api(path, method='GET', body=None, owner=OWNER, capable=True):
    headers = {'Authorization': 'Bearer ' + token(owner), 'Content-Type': 'application/json', 'Prefer': 'return=representation,resolution=merge-duplicates'}
    if capable:
        headers['X-OpenGym-Training-Schema'] = '1'
    request = urllib.request.Request(BASE + '/' + path, data=None if body is None else json.dumps(body).encode(), headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            value = response.read()
            return response.status, json.loads(value) if value else None
    except urllib.error.HTTPError as error:
        with error:
            return error.code, json.loads(error.read())


def session_row(number=3, session_id=None, **extra):
    session_id = session_id or str(uuid.uuid4())
    data = {'id': session_id, 'splitId': SPLIT, 'planId': PLAN, 'planName': 'Push', 'date': '2026-01-01T00:00:00Z', 'weekNumber': number, 'exercises': [], 'isCompleted': True}
    return {'id': session_id, 'user_id': OWNER, 'split_id': SPLIT, 'plan_id': PLAN, 'plan_name': 'Push', 'week_number': number, 'date': data['date'], 'updated_at': '2026-01-01T00:00:00Z', 'data': data, **extra}


class TrainingBlocksApiTest(unittest.TestCase):
    def setUp(self):
        sql(f"truncate auth.users cascade; insert into auth.users values ('{OWNER}'), ('{OTHER}'); insert into public.splits(id,user_id,name,created_at,updated_at) values ('{SPLIT}','{OWNER}','A','2025-01-01','2025-01-01'),('{SECOND}','{OWNER}','B','2025-01-01','2025-01-01'),('{FOREIGN}','{OTHER}','Foreign','2025-01-01','2025-01-01'); insert into public.workout_plans(id,user_id,split_id,name,data) values ('{PLAN}','{OWNER}','{SPLIT}','Push','{{\"id\":\"{PLAN}\",\"splitId\":\"{SPLIT}\",\"name\":\"Push\",\"exercises\":[]}}');")

    def activate(self):
        status, body = api('rpc/activate_training_schema', 'POST', {})
        self.assertEqual((status, body), (200, 1), body)

    def test_uuid_fixtures_and_sparse_backfill_preserve_payload_timestamps(self):
        for n in [1, 3, 12]:
            status, body = api('workout_sessions', 'POST', session_row(n), capable=False)
            self.assertLess(status, 300, body)
        before = sql('select jsonb_agg(jsonb_build_object(\'id\',id,\'updated_at\',updated_at,\'data\',data) order by id) from workout_sessions')
        self.activate()
        rows = api(f'training_weeks?split_id=eq.{SPLIT}&order=number')[1]
        self.assertEqual([r['number'] for r in rows], [1, 3, 12])
        self.assertEqual(rows[1]['id'], '39e7f177-288f-5c49-bdcc-e0ccf45671de')
        progress = api(f'workout_progress?plan_id=eq.{PLAN}')[1][0]
        self.assertEqual(progress['id'], 'fe40b608-43e5-566a-ba8f-1a71159cd1a7')
        self.assertEqual(progress['revision'], 'f4b5039f-16e7-5024-b662-bf6b0b6f4b01')
        for old in json.loads(before):
            current = api(f"workout_sessions?id=eq.{old['id']}")[1][0]
            self.assertEqual(current['updated_at'], old['updated_at'])
            for key, value in old['data'].items():
                self.assertEqual(current['data'][key], value)
        self.activate()
        self.assertEqual(len(api(f'training_blocks?split_id=eq.{SPLIT}')[1]), 1)

    def test_activated_old_client_reads_upserts_deletes_and_preferences_raise_upgrade(self):
        self.activate()
        for table in ['splits', 'split_preferences', 'workout_plans', 'workout_sessions', 'training_blocks', 'training_weeks', 'workout_progress']:
            status, body = api(table, capable=False)
            self.assertEqual(status, 426, (table, body))
            self.assertEqual(body['code'], 'PT426')
        for path, method, body in [('workout_sessions', 'POST', session_row()), (f'workout_plans?id=eq.{PLAN}', 'DELETE', None), ('split_preferences', 'POST', {'user_id': OWNER, 'active_split_id': SECOND}), (f'splits?id=eq.{SPLIT}', 'PATCH', {'deleted_at':'2026-01-02T00:00:00Z'})]:
            self.assertEqual(api(path, method, body, capable=False)[0], 426)
        # Another account is still legacy-compatible until its own activation.
        self.assertEqual(api('splits', owner=OTHER, capable=False)[0], 200)
        # Capability is server-owned, never editable by the authenticated client.
        self.assertGreaterEqual(api('account_training_capabilities', 'POST', {'user_id':OWNER, 'minimum_training_schema':0})[0], 400)

    def test_owner_and_same_owner_wrong_split_links_are_rejected(self):
        self.activate()
        week = api(f'training_weeks?split_id=eq.{SPLIT}')[1][0]
        for user, split in [(OTHER, FOREIGN), (OWNER, SECOND)]:
            payload = {'id':str(uuid.uuid4()), 'user_id':user, 'split_id':split, 'block_id':week['block_id'], 'number':9, 'created_at':'2026-01-01T00:00:00Z', 'updated_at':'2026-01-01T00:00:00Z'}
            self.assertGreaterEqual(api('training_weeks', 'POST', payload, owner=user)[0], 400)
        payload = session_row(1, training_week_id=week['id'], split_id=SECOND)
        self.assertGreaterEqual(api('workout_sessions', 'POST', payload)[0], 400)
        self.assertEqual(api('training_weeks', owner=OTHER)[1], [])

    def test_server_rejects_stale_plan_and_progress_upserts(self):
        self.activate()
        plan = api(f'workout_plans?id=eq.{PLAN}')[1][0]
        newer = {**plan, 'name':'Newer', 'updated_at':'2030-01-01T00:00:00Z'}
        self.assertLess(api('workout_plans', 'POST', newer)[0], 300)
        self.assertLess(api('workout_plans', 'POST', plan)[0], 300)
        self.assertEqual(api(f'workout_plans?id=eq.{PLAN}')[1][0]['name'], 'Newer')
        progress = api(f'workout_progress?plan_id=eq.{PLAN}')[1][0]
        high = {**progress, 'revision':'ffffffff-ffff-4fff-8fff-ffffffffffff','updated_at':'2030-01-01T00:00:00Z','state':'awaitingBoundary'}
        low = {**high, 'revision':'00000000-0000-4000-8000-000000000099','state':'ready'}
        self.assertLess(api('workout_progress', 'POST', high)[0],300)
        self.assertLess(api('workout_progress', 'POST', low)[0],300)
        self.assertEqual(api(f'workout_progress?plan_id=eq.{PLAN}')[1][0]['revision'], high['revision'])
        self.assertLess(api('workout_progress', 'POST', progress)[0],300)
        self.assertEqual(api(f'workout_progress?plan_id=eq.{PLAN}')[1][0]['revision'], high['revision'])

    def test_late_legacy_number_reservation_in_both_arrival_orders(self):
        for legacy_first in [False, True]:
            with self.subTest(legacy_first=legacy_first):
                if legacy_first:
                    self.setUp()
                self.activate()
                block = api(f'training_blocks?split_id=eq.{SPLIT}')[1][0]
                if legacy_first:
                    self.assertLess(api('workout_sessions', 'POST', session_row(2))[0],300)
                random_id = str(uuid.uuid4())
                random = {'id':random_id,'user_id':OWNER,'split_id':SPLIT,'block_id':block['id'],'number':2,'created_at':'2026-01-01T00:00:00Z','updated_at':'2026-01-01T00:00:00Z'}
                status, body = api('training_weeks','POST',random)
                if legacy_first:
                    self.assertEqual(status,409,body)
                else:
                    self.assertLess(status,300,body)
                    destination = session_row(2,training_week_id=random_id)
                    destination['data']['trainingWeekId'] = random_id
                    self.assertLess(api('workout_sessions','POST',destination)[0],300)
                    self.assertLess(api('workout_sessions','POST',session_row(2))[0],300)
                    saved = api(f'training_weeks?id=eq.{random_id}')[1][0]
                    self.assertEqual(saved['number'],3)
                    moved = api(f"workout_sessions?id=eq.{destination['id']}")[1][0]
                    self.assertEqual(moved['training_week_id'], random_id)
                    self.assertEqual(moved['week_number'],3)
                    self.assertEqual(moved['data']['weekNumber'],3)
                canonical = str(uuid.uuid5(uuid.UUID(BLOCK),'2'))
                self.assertEqual(api(f'training_weeks?id=eq.{canonical}')[1][0]['number'],2)

    def test_existing_split_upsert_is_allowed_at_five_active_splits(self):
        self.activate()
        for number in range(3):
            status, body = api('splits', 'POST', {'id': str(uuid.uuid4()), 'user_id': OWNER, 'name': f'Extra {number}', 'created_at': '2026-01-01T00:00:00Z', 'updated_at': '2026-01-01T00:00:00Z'})
            self.assertLess(status, 300, body)
        status, body = api('splits', 'POST', {'id': SPLIT, 'user_id': OWNER, 'name': 'Renamed', 'created_at': '2025-01-01T00:00:00Z', 'updated_at': '2026-01-02T00:00:00Z'})
        self.assertLess(status, 300, body)
        self.assertEqual(body[0]['name'], 'Renamed')

    def test_parent_tombstone_rejects_newer_live_children(self):
        self.activate()
        self.assertLess(api('split_preferences','POST',{'user_id':OWNER,'active_split_id':SECOND})[0],300)
        self.assertLess(api(f'splits?id=eq.{SPLIT}','PATCH',{'deleted_at':'2026-01-02T00:00:00Z','updated_at':'2026-01-02T00:00:00Z'})[0],300)
        block = api(f'training_blocks?split_id=eq.{SPLIT}')[1][0]
        self.assertIsNotNone(block['deleted_at'])
        status, _ = api('training_weeks','POST',{'id':str(uuid.uuid4()),'user_id':OWNER,'split_id':SPLIT,'block_id':block['id'],'number':2,'created_at':'2031-01-01T00:00:00Z','updated_at':'2031-01-01T00:00:00Z'})
        self.assertGreaterEqual(status,400)

    def test_invalid_legacy_week_rolls_back_activation_and_preserves_exportable_source(self):
        status, body = api('workout_sessions','POST',session_row(0),capable=False)
        self.assertLess(status,300,body)
        status, body = api('rpc/activate_training_schema','POST',{})
        self.assertEqual(status,400,body)
        self.assertEqual(sql('select count(*) from account_training_capabilities'),'0')
        self.assertEqual(api('workout_sessions',capable=False)[1][0]['week_number'],0)

    def test_server_keeps_newer_session_sets_and_dangling_plan_ids(self):
        dangling = session_row(3,plan_id='00000000-0000-4000-8000-000000000099')
        dangling['data']['planId']=dangling['plan_id']
        dangling['data'].update({'isCompleted':False,'startedAt':'2026-01-01T00:00:00Z','timerStartedAt':'2026-01-01T00:00:00Z','durationSeconds':72,'exercises':[{'name':'Squat','sets':[{'reps':8,'weight':80,'rpe':7,'note':'Keep me'}]}]})
        self.assertLess(api('workout_sessions','POST',dangling,capable=False)[0],300)
        self.activate()
        saved=api(f"workout_sessions?id=eq.{dangling['id']}")[1][0]
        self.assertEqual(saved['plan_id'],dangling['plan_id'])
        for key,value in dangling['data'].items():
            self.assertEqual(saved['data'][key],value)
        newer={**saved,'updated_at':'2030-01-01T00:00:00Z','data':{**saved['data'],'exercises':[{'name':'Squat','sets':[{'reps':9,'weight':100}]}]}}
        self.assertLess(api('workout_sessions','POST',newer)[0],300)
        self.assertLess(api('workout_sessions','POST',saved)[0],300)
        self.assertEqual(api(f"workout_sessions?id=eq.{dangling['id']}")[1][0]['data']['exercises'][0]['sets'][0]['weight'],100)

    def test_preference_upserts_use_server_lww(self):
        self.activate()
        high={'user_id':OWNER,'active_split_id':SECOND,'updated_at':'2030-01-01T00:00:00Z'}
        low={**high,'active_split_id':SPLIT,'updated_at':'2026-01-01T00:00:00Z'}
        self.assertLess(api('split_preferences','POST',high)[0],300)
        status,body=api('split_preferences','POST',low)
        self.assertLess(status,300,body)
        self.assertEqual(api('split_preferences')[1][0]['active_split_id'],SECOND)

    def test_queued_old_write_finishes_before_activation_then_future_old_writes_fail(self):
        barrier = 712001
        sql(f"create or replace function training_internal.test_hold_old_write() returns trigger language plpgsql as $$ begin if new.plan_name='Queued' then perform pg_advisory_xact_lock({barrier}); end if; return new; end $$; create trigger test_hold_old_write before insert on workout_sessions for each row execute function training_internal.test_hold_old_write();")
        old_row = session_row(3)
        old_row['plan_name'] = old_row['data']['planName'] = 'Queued'
        try:
            with psycopg.connect(host='127.0.0.1',port=55439,dbname='opengym_training_blocks_test',user=os.environ.get('USER','aalish'),autocommit=True) as locker:
                locker.execute(f'select pg_advisory_lock({barrier})')
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as workers:
                    old = workers.submit(api,'workout_sessions','POST',old_row,OWNER,False)
                    deadline = time.monotonic()+5
                    while sql("select count(*) from pg_stat_activity where wait_event='advisory'") == '0':
                        self.assertLess(time.monotonic(),deadline,'old write did not reach the barrier')
                        time.sleep(0.01)
                    activation = workers.submit(api,'rpc/activate_training_schema','POST',{})
                    while int(sql("select count(*) from pg_stat_activity where wait_event='advisory'")) < 2:
                        self.assertLess(time.monotonic(),deadline,'activation did not wait for the old request')
                        time.sleep(0.01)
                    locker.execute(f'select pg_advisory_unlock({barrier})')
                    self.assertLess(old.result()[0],300)
                    self.assertEqual(activation.result(),(200,1))
                saved=api(f"workout_sessions?id=eq.{old_row['id']}")[1][0]
                self.assertEqual(saved['training_week_id'],str(uuid.uuid5(uuid.UUID(BLOCK),'3')))
                self.assertEqual(api('workout_sessions','POST',session_row(3),capable=False)[0],426)
        finally:
            sql('drop trigger if exists test_hold_old_write on workout_sessions; drop function if exists training_internal.test_hold_old_write();')

    def test_bootstrap_timestamps_do_not_inherit_split_or_plan_edits(self):
        sql("update splits set updated_at='2030-01-01'; update workout_plans set updated_at='2030-01-01';")
        self.activate()
        for table in ['training_blocks','training_weeks','workout_progress']:
            rows=api(table)[1]
            self.assertTrue(rows)
            self.assertTrue(all(row['updated_at']=='1970-01-01T00:00:00+00:00' for row in rows),(table,rows))

    def test_concurrent_activation_is_idempotent(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda _: api('rpc/activate_training_schema','POST',{}), range(2)))
        self.assertEqual(results,[(200,1),(200,1)])
        self.assertEqual(len(api(f'training_blocks?split_id=eq.{SPLIT}')[1]),1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
