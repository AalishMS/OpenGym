-- Schema 4: block duration resolves on its own clock, and an empty block can be
-- deleted through one guarded RPC. Apply before releasing the schema-4 client.
-- Installation alone does not upgrade any account: schema 1-3 writers never send
-- the clock, so they keep the grow-only duration rule until their account is
-- activated at 4 (which fences those writers off with PT426).
alter table public.training_blocks
  add column if not exists planned_week_count_updated_at timestamptz;
alter table public.account_training_capabilities
  drop constraint if exists account_training_capabilities_minimum_training_schema_check,
  add constraint account_training_capabilities_minimum_training_schema_check
    check (minimum_training_schema in (1, 2, 3, 4));

-- Re-created from the 20261029135002 definition (no later migration touched it).
-- Only the training_blocks duration rule changes: the newer clock wins, a tie
-- (including null vs null, which is every pre-4 writer) keeps the larger count,
-- and a null count never replaces a stored one. A write that omits the clock
-- column (an old client upsert) leaves the stored clock in NEW, so it ties.
-- Like the count, the clock is merged independently of row LWW, so a stale
-- rename cannot undo a shorten and a stale shorten cannot undo a rename.
create or replace function training_internal.keep_newest_row() returns trigger
language plpgsql set search_path = '' as $$
declare
  old_clock timestamptz;
  new_clock timestamptz;
begin
  if tg_table_name='split_preferences' then
    if new.updated_at < old.updated_at then return old; end if;
    return new;
  end if;
  if old.deleted_at is not null and new.deleted_at is null then return old; end if;
  if tg_table_name='training_blocks' then
    old_clock := coalesce(old.planned_week_count_updated_at,'-infinity'::timestamptz);
    new_clock := coalesce(new.planned_week_count_updated_at,'-infinity'::timestamptz);
    if new.planned_week_count is null or
       (old.planned_week_count is not null and old_clock > new_clock) then
      new.planned_week_count := old.planned_week_count;
      new.planned_week_count_updated_at := old.planned_week_count_updated_at;
    elsif old.planned_week_count is not null and old_clock = new_clock then
      new.planned_week_count := greatest(new.planned_week_count,old.planned_week_count);
    end if;
    old.planned_week_count := new.planned_week_count;
    old.planned_week_count_updated_at := new.planned_week_count_updated_at;
  end if;
  if old.deleted_at is null and new.deleted_at is not null then return new; end if;
  if new.updated_at < old.updated_at then return old; end if;
  if tg_table_name='workout_progress' then
    if old.available_week_ids is null and new.available_week_ids is not null and
       (to_jsonb(new)-'available_week_ids'-'server_seq') =
       (to_jsonb(old)-'available_week_ids'-'server_seq') then return new; end if;
    if new.revision=training_internal.initial_revision(new.split_id,new.plan_id) then return old; end if;
    if new.updated_at=old.updated_at and new.revision::text < old.revision::text then return old; end if;
  end if;
  return new;
end
$$;

-- Re-created from the 20261028072415 definition (no later migration touched it).
-- Two changes, both about a session or progress row that is rescued out of a
-- tombstoned block (a restore / Clear All Data pushes block and week tombstones as
-- plain upserts, so a live row can sit under a tombstoned parent on the server).
--
-- 1. An upsert row that is identical to the stored one is a no-op, so it is not
--    validated again. This is what an upsert that lost last-write-wins looks like
--    here: keep_newest_row (trigger a_, fires first) returned the stored row, so
--    NEW = OLD, and without this the stored row's tombstoned parent made the
--    whole request fail. The incoming row was already validated by the BEFORE
--    INSERT pass of the same upsert. Any row that changes at all, including a
--    live row moving under a tombstoned parent, is still fully validated.
create or replace function training_internal.check_training_parent() returns trigger
language plpgsql set search_path = '' as $$
declare
  parent_deleted timestamptz;
  parent_owner uuid;
  parent_split uuid;
begin
  if tg_op='UPDATE' and pg_catalog.to_jsonb(new) is not distinct from pg_catalog.to_jsonb(old) then return new; end if;
  select user_id,deleted_at into parent_owner,parent_deleted from public.splits where id=new.split_id for share;
  if parent_owner is distinct from new.user_id or (new.deleted_at is null and parent_deleted is not null) then raise check_violation using message='Training split is unavailable'; end if;
  if tg_table_name='training_weeks' then
    select user_id,split_id,deleted_at into parent_owner,parent_split,parent_deleted from public.training_blocks where id=new.block_id for share;
    if parent_owner is distinct from new.user_id or parent_split is distinct from new.split_id or (new.deleted_at is null and parent_deleted is not null) then raise check_violation using message='Training block is unavailable'; end if;
  elsif tg_table_name='workout_progress' then
    select user_id,split_id,deleted_at into parent_owner,parent_split,parent_deleted from public.workout_plans where id=new.plan_id for share;
    if parent_owner is distinct from new.user_id or parent_split is distinct from new.split_id or (new.deleted_at is null and parent_deleted is not null) then raise check_violation using message='Progress plan is unavailable'; end if;
    select user_id,split_id,deleted_at into parent_owner,parent_split,parent_deleted from public.training_weeks where id=new.active_week_id for share;
    if parent_owner is distinct from new.user_id or parent_split is distinct from new.split_id or (new.deleted_at is null and parent_deleted is not null) then raise check_violation using message='Progress week is unavailable'; end if;
  end if;
  return new;
end
$$;

-- 2. link_session: the same no-op rule on UPDATE (for an already linked row), and one new rule. A session that
--    changes training_week_id out of a TOMBSTONED week is being rescued: the
--    client rewrote sourceWeekId / nextWeekId to the new week, so the INCOMING
--    completion evidence is validated and kept instead of the stored copy being
--    forced back (which could never name the new week). It is only accepted when
--    the stored evidence is unchanged apart from those two week ids; a session
--    with no stored evidence behaves as before (incoming evidence is validated).
--    Moving out of a LIVE week, or any update that keeps the week, still restores
--    the stored evidence exactly as before. Everything else link_session enforces
--    on the new week (live, same owner and split, same week number, evidence
--    names the new week, nextWeekId in the same block) applies unchanged.
create or replace function training_internal.link_session() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  parent public.training_weeks;
  candidate uuid;
  count_matches integer;
  evidence jsonb;
  target public.training_weeks;
  old_week_deleted boolean := false;
  stored public.workout_sessions;
begin
  if auth.uid() is not null and new.user_id<>auth.uid() then raise insufficient_privilege; end if;
  -- Not for a row that still lacks its link: normalize_account repairs those with
  -- a deliberate no-op update (set updated_at=updated_at) that must reach the code below.
  if tg_op='UPDATE' and old.training_week_id is not null and old.data->>'trainingWeekId'=old.training_week_id::text and
     pg_catalog.to_jsonb(new) is not distinct from pg_catalog.to_jsonb(old) then return new; end if;
  if not exists(select 1 from public.account_training_capabilities where user_id=new.user_id) then return new; end if;
  -- 3. A tombstone never moves a session. Deleting must always be accepted, even
  --    from a device that still holds the session in a week it has since been
  --    rescued out of (or names a week that is gone, foreign or unrelated). The
  --    week a tombstone names is not evidence of anything, so a row that is a
  --    tombstone and already has a stored link is pinned to the STORED link, its
  --    week number and the stored evidence (or its absence), and then validated
  --    like any other row against that week. This runs in the BEFORE INSERT pass
  --    of an upsert too (it looks the stored row up by id and owner), because
  --    ON CONFLICT DO UPDATE receives the row as that pass left it. It applies
  --    only to rows with deleted_at set, so a live row can never change week by
  --    this path, and it only ever copies values from the stored row, so it
  --    cannot point a session anywhere new. A tombstone still cannot be undone:
  --    keep_newest_row refuses a live row over a stored tombstone.
  if new.deleted_at is not null then
    if tg_op='UPDATE' then stored := old;
    else select * into stored from public.workout_sessions where id=new.id and user_id=new.user_id; end if;
    if stored.training_week_id is not null and
       (new.training_week_id is distinct from stored.training_week_id or
        (new.data->>'trainingWeekId' is not null and new.data->>'trainingWeekId' is distinct from stored.training_week_id::text)) then
      new.training_week_id := stored.training_week_id;
      new.week_number := stored.week_number;
      new.data := jsonb_set(jsonb_set(new.data,'{trainingWeekId}',to_jsonb(stored.training_week_id::text)),'{weekNumber}',to_jsonb(stored.week_number));
      if stored.data->'completionTransition' is null then new.data := new.data - 'completionTransition';
      else new.data := jsonb_set(new.data,'{completionTransition}',stored.data->'completionTransition'); end if;
    end if;
  end if;
  if new.week_number < 1 then raise check_violation using message='Invalid legacy training week'; end if;
  if coalesce(new.data->>'trainingSchemaVersion','1')<>'1' then raise check_violation using message='Unsupported training schema version'; end if;
  if new.data->>'splitId' is not null and (new.data->>'splitId')::uuid<>new.split_id then raise check_violation using message='Conflicting session split'; end if;
  if new.data->>'planId' is not null and (new.data->>'planId')::uuid is distinct from new.plan_id then raise check_violation using message='Conflicting session plan'; end if;
  if new.data->>'trainingWeekId' is not null then
    candidate := (new.data->>'trainingWeekId')::uuid;
    if new.training_week_id is not null and new.training_week_id<>candidate then raise check_violation using message='Conflicting session week'; end if;
    new.training_week_id := candidate;
  end if;
  if new.training_week_id is null then new.training_week_id := training_internal.ensure_legacy_week(new.split_id,new.week_number); end if;
  select * into strict parent from public.training_weeks where id=new.training_week_id for share;
  if parent.user_id<>new.user_id or parent.split_id<>new.split_id or parent.number<>new.week_number or (new.deleted_at is null and parent.deleted_at is not null) then raise check_violation using message='Conflicting or deleted session week'; end if;
  if new.plan_id is null then
    select count(*), (array_agg(id))[1] into count_matches,candidate from public.workout_plans where user_id=new.user_id and split_id=new.split_id and name=new.plan_name;
    if count_matches=1 then new.plan_id := candidate; end if;
  elsif exists(select 1 from public.workout_plans where id=new.plan_id and (user_id<>new.user_id or split_id<>new.split_id)) then
    raise check_violation using message='Conflicting session plan owner or split';
  end if;
  new.data := jsonb_set(jsonb_set(jsonb_set(jsonb_set(new.data,'{trainingSchemaVersion}','1'::jsonb),'{trainingWeekId}',to_jsonb(new.training_week_id::text)),'{splitId}',to_jsonb(new.split_id::text)),'{planId}',coalesce(to_jsonb(new.plan_id::text),'null'::jsonb));
  if tg_op='UPDATE' and old.data->'completionTransition' is not null and old.data->'completionTransition'<>'null'::jsonb then
    if old.training_week_id is not null and new.training_week_id is distinct from old.training_week_id then
      select w.deleted_at is not null into old_week_deleted from public.training_weeks w where w.id=old.training_week_id;
    end if;
    if coalesce(old_week_deleted,false) and pg_catalog.jsonb_typeof(old.data->'completionTransition')='object' then
      -- Rescue out of a tombstoned week: keep the incoming evidence, but only if
      -- it is the stored evidence re-pointed at the new week.
      if pg_catalog.jsonb_typeof(new.data->'completionTransition') is distinct from 'object' or
         (new.data->'completionTransition') - 'sourceWeekId' - 'nextWeekId' is distinct from
         (old.data->'completionTransition') - 'sourceWeekId' - 'nextWeekId' then
        raise check_violation using message='Invalid completion evidence';
      end if;
    else
      new.data := jsonb_set(new.data,'{completionTransition}',old.data->'completionTransition');
    end if;
  end if;
  evidence := new.data->'completionTransition';
  if evidence is not null and evidence<>'null'::jsonb then
    if jsonb_typeof(evidence)<>'object' or evidence->>'sourceWeekId' is distinct from new.training_week_id::text or evidence->>'resultRevision' is distinct from new.id::text or evidence->>'expectedRevision' is null or evidence->>'committedAt' is null or coalesce(new.data->>'isCompleted','true')<>'true' then raise check_violation using message='Invalid completion evidence'; end if;
    perform (evidence->>'expectedRevision')::uuid, (evidence->>'committedAt')::timestamptz;
    if evidence->>'nextWeekId' is not null then
      select * into strict target from public.training_weeks where id=(evidence->>'nextWeekId')::uuid;
      if target.block_id<>parent.block_id or target.split_id<>parent.split_id or target.id=parent.id then raise check_violation using message='Invalid completion target'; end if;
    end if;
  end if;
  return new;
end
$$;

-- Same as 20261105120000, now accepting header 4. An account already above the
-- header is refused (PT426), an account below it is raised, and an equal level
-- is a no-op that returns the level.
create or replace function public.activate_training_schema() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := auth.uid();
  header text := coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-opengym-training-schema','');
  requested integer;
  previous integer;
begin
  if owner is null then raise insufficient_privilege; end if;
  if header not in ('1','2','3','4') then
    raise sqlstate 'PT426' using message='Update OpenGym to prepare training data';
  end if;
  requested := header::integer;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-account:' || owner::text,0));
  select minimum_training_schema into previous from public.account_training_capabilities where user_id=owner;
  if previous is not null and requested<previous then
    raise sqlstate 'PT426' using message='Update OpenGym to sync this account';
  end if;
  if previous is null then
    insert into public.account_training_capabilities values(owner,requested);
    perform training_internal.normalize_account();
  elsif requested>previous then
    update public.account_training_capabilities set minimum_training_schema=requested where user_id=owner;
  end if;
  if requested>=2 then perform training_internal.prepare_lazy_weeks(owner); end if;
  return requested;
end
$$;
revoke all on function public.activate_training_schema() from public, anon;
grant execute on function public.activate_training_schema() to authenticated;

-- Delete an unused block. A re-checking RPC rather than a trigger guard: a
-- trigger would also fire for restore / Clear All Data uploads (blocks before
-- sessions) and fail them. The check and the tombstones run in one transaction
-- under the account's exclusive lock, so a concurrent write of the same account
-- (a session or progress pushed into the block, another block delete) either
-- lands first and is seen here, or waits and is then rejected by
-- check_training_parent / link_session under the tombstoned block and weeks.
-- Runs as invoker, so RLS hides every other account's rows (unknown and foreign
-- ids both return null). Idempotent: a deleted block returns its tombstones.
create or replace function public.delete_training_block(target uuid) returns jsonb
language plpgsql set search_path = '' as $$
declare
  owner uuid := auth.uid();
  b public.training_blocks;
  stamp timestamptz := pg_catalog.now();
begin
  if owner is null then raise insufficient_privilege; end if;
  -- The pre-request guard already holds this lock for POST; taking it again is
  -- free in the same transaction and keeps the RPC safe on its own.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-account:' || owner::text,0));
  if coalesce((select minimum_training_schema from public.account_training_capabilities
               where user_id=owner),0) < 4 then
    raise sqlstate 'PT426' using message='Update OpenGym to delete training blocks';
  end if;
  select * into b from public.training_blocks where id=target and user_id=owner for update;
  if not found then return null; end if;
  if b.deleted_at is null then
    -- Row locks, so the checks below are correct even without the advisory lock
    -- (a write that skipped the pre-request guard). This RPC locks the block, then
    -- its weeks by id. That is NOT a global lock order: an upsert of an existing
    -- week locks the week row before check_training_parent takes the block FOR
    -- SHARE, and the split-tombstone cascade locks split, blocks, weeks while this
    -- RPC's block UPDATE takes the split FOR SHARE after the block is locked. Those
    -- orderings predate the RPC's row locks. In practice they are serialised by
    -- the per-account advisory lock that the pre-request guard and this RPC both
    -- take; a writer that skipped the guard could at worst deadlock with this
    -- RPC, and Postgres then aborts one side with a deadlock error.
    -- A session / progress write holds its week FOR SHARE (link_session,
    -- check_training_parent) until it commits, so either that write has
    -- committed by the time this lock is granted and the in-use check below, a
    -- new statement snapshot under READ COMMITTED, sees it, or it waits for this
    -- transaction and then reads the week tombstone and is rejected. The block
    -- lock freezes the week set: a new week takes the block FOR SHARE first.
    perform 1 from public.training_weeks where block_id=target and user_id=owner order by id for update;
    if exists(select 1 from public.splits where id=b.split_id and user_id=owner and deleted_at is not null) then
      raise sqlstate 'PT409' using message='Training split is unavailable', detail='split_deleted';
    end if;
    if not exists(select 1 from public.training_blocks where split_id=b.split_id and user_id=owner
                  and deleted_at is null and id<>target) then
      raise sqlstate 'PT409' using message='A split keeps at least one block', detail='last_block';
    end if;
    if exists(select 1 from public.workout_sessions s join public.training_weeks w on w.id=s.training_week_id
              where w.block_id=target and s.user_id=owner and s.deleted_at is null)
    or exists(select 1 from public.workout_progress p join public.training_weeks w on w.id=p.active_week_id
              where w.block_id=target and p.user_id=owner and p.deleted_at is null) then
      raise sqlstate 'PT409' using message='This block is in use', detail='in_use';
    end if;
    update public.training_blocks set deleted_at=stamp, updated_at=greatest(updated_at,stamp) where id=target;
    update public.training_weeks set deleted_at=stamp, updated_at=greatest(updated_at,stamp)
      where block_id=target and user_id=owner and deleted_at is null;
  end if;
  return jsonb_build_object(
    'block',(select to_jsonb(x) from public.training_blocks x where x.id=target),
    'weeks',coalesce((select jsonb_agg(to_jsonb(w) order by w.number,w.id)
                      from public.training_weeks w where w.block_id=target and w.user_id=owner),'[]'::jsonb));
end
$$;
revoke all on function public.delete_training_block(uuid) from public, anon;
grant execute on function public.delete_training_block(uuid) to authenticated;
notify pgrst, 'reload schema';
