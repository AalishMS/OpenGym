"""Isolated SQL proof. Uses only a new temporary database on the loopback fixture.
Run with Python 3 and psycopg installed; see README.md.
"""
import json
import os
from pathlib import Path

import psycopg
from psycopg import sql

ROOT = Path(__file__).resolve().parents[3]
DB = f'opengym_exercise_identity_test_{os.getpid()}'
CONNECTION = dict(host='127.0.0.1', port=55439, user='aalish')
OWNER = '11111111-1111-4111-8111-111111111111'
OTHER = '22222222-2222-4222-8222-222222222222'


def expect_error(connection, statement, code):
    try:
        with connection.transaction():
            connection.execute(statement)
    except psycopg.Error as error:
        assert error.sqlstate == code, (error.sqlstate, error)
    else:
        raise AssertionError(f'Expected {code}: {statement}')


def actor(connection, owner=OWNER, version='3', role='authenticated'):
    connection.execute(sql.SQL('set role {}').format(sql.Identifier(role)))
    connection.execute("select set_config('request.jwt.claims', %s, false)", (json.dumps({'sub': owner}),))
    connection.execute("select set_config('request.headers', %s, false)", (json.dumps({'x-opengym-training-schema': version}),))
    connection.execute("select set_config('request.method', 'POST', false)")


def write(connection, owner=OWNER, name='DB Press', target=None, stamp='2026-11-05T01:00:00Z'):
    data = dict(id='custom-press', name=name, aliases=[], category='Custom', builtIn=False, mergedIntoId=target)
    return connection.execute('''insert into public.exercise_definitions(user_id,id,data,updated_at)
        values(%s,'custom-press',%s::jsonb,%s) on conflict(user_id,id)
        do update set data=excluded.data,updated_at=excluded.updated_at returning data''',
        (owner, json.dumps(data), stamp)).fetchone()[0]


with psycopg.connect(**CONNECTION, dbname='postgres', autocommit=True) as admin:
    admin.execute(sql.SQL('create database {}').format(sql.Identifier(DB)))
try:
    with psycopg.connect(**CONNECTION, dbname=DB, autocommit=True) as c:
        fixture = (ROOT / 'supabase/tests/training_blocks/base_schema.sql').read_text()
        fixture = '\n'.join(line for line in fixture.splitlines() if not line.startswith('create role '))
        c.execute(fixture, prepare=False)
        for filename in [
            '20261028072415_add_training_blocks_and_compatibility_gate.sql',
            '20261029135002_lazy_independent_block_weeks.sql',
            '20261105120000_exercise_identity_catalog.sql',
        ]:
            c.execute((ROOT / 'supabase/migrations' / filename).read_text(), prepare=False)
        c.execute('insert into auth.users values(%s),(%s)', (OWNER, OTHER))
        actor(c)
        assert c.execute('select public.activate_training_schema()').fetchone()[0] == 3
        assert write(c, stamp='2026-11-05T03:00:00Z')['name'] == 'DB Press'
        actor(c, OTHER)
        assert c.execute('select count(*) from public.exercise_definitions').fetchone()[0] == 0
        # The same catalog identity is independent in a different account.
        assert write(c, OTHER, name='Different movement')['name'] == 'Different movement'
        expect_error(c, f"insert into public.exercise_definitions values('{OWNER}','foreign','{{}}','now','now')", '42501')
        assert c.execute("update public.exercise_definitions set data=data where user_id=%s returning id", (OWNER,)).fetchall() == []
        actor(c)
        long_name = 'Legacy custom press ' * 20
        assert write(c, name=long_name, stamp='2026-11-05T04:00:00Z')['name'] == long_name
        merged = write(c, target='builtin:dumbbell-press', stamp='2026-11-05T02:00:00Z')
        assert merged['mergedIntoId'] == 'builtin:dumbbell-press'
        assert write(c, name='Late unmerged copy', stamp='2026-11-05T03:00:00Z') == merged
        assert write(c, name='Stale rename', target='builtin:dumbbell-press') == merged
        expect_error(c, 'delete from public.exercise_definitions', '42501')
        actor(c, version='2')
        expect_error(c, 'select training_internal.guard_training_schema()', 'PT426')
        expect_error(c, 'select public.activate_training_schema()', 'PT426')
        actor(c, role='anon')
        expect_error(c, 'select * from public.exercise_definitions', '42501')
        expect_error(c, "insert into public.exercise_definitions values(null,'x','{}','now','now')", '42501')
        expect_error(c, 'update public.exercise_definitions set data=data', '42501')
        expect_error(c, 'delete from public.exercise_definitions', '42501')
        print('Exercise catalog SQL: migration, account isolation, grants, LWW, durable merges, and compatibility gate passed.')
finally:
    with psycopg.connect(**CONNECTION, dbname='postgres', autocommit=True) as admin:
        admin.execute(sql.SQL('drop database {}').format(sql.Identifier(DB)))
