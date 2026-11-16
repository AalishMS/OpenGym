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
