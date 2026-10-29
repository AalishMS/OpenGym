-- Intended duration and per-workout reached slots. No account is upgraded until
-- its updated client explicitly negotiates schema 2. Existing session JSON stays
-- at version 1: its durable week/session representation has not changed.
alter table public.training_blocks
  add column planned_week_count integer check (planned_week_count > 0);
alter table public.workout_progress add column available_week_ids uuid[];
alter table public.account_training_capabilities
  drop constraint account_training_capabilities_minimum_training_schema_check,
  add constraint account_training_capabilities_minimum_training_schema_check
    check (minimum_training_schema in (1, 2));

-- Metadata-only backfill must preserve a bootstrap revision and active slot.
-- Keep the previous LWW/tombstone rules for every other mutation.
create or replace function training_internal.keep_newest_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name='split_preferences' then
    if new.updated_at < old.updated_at then return old; end if;
    return new;
  end if;
  if old.deleted_at is not null and new.deleted_at is null then return old; end if;
  -- Duration is monotonic: a concurrent rename or partially uploaded v1
  -- block cannot undo an explicit extension or a larger legacy backfill.
  if tg_table_name='training_blocks' then
    new.planned_week_count := greatest(new.planned_week_count,old.planned_week_count);
    old.planned_week_count := new.planned_week_count;
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

create function training_internal.check_available_weeks() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- Null is retained for v1 clients and rows awaiting the v2 backfill.
  if new.available_week_ids is null then return new; end if;
  if array_position(new.available_week_ids, null) is not null or
     cardinality(new.available_week_ids) <>
       (select count(distinct id) from unnest(new.available_week_ids) as supplied(id)) or
     not (new.active_week_id = any(new.available_week_ids)) then
    raise check_violation using message='Invalid available training weeks';
  end if;
  if exists (
    select 1 from unnest(new.available_week_ids) as supplied(id)
    left join public.training_weeks w on w.id=supplied.id
    where w.id is null or w.split_id<>new.split_id or w.user_id<>new.user_id
  ) then
    raise check_violation using message='Available weeks belong to another split or account';
  end if;
  return new;
end
$$;
revoke all on function training_internal.check_available_weeks() from public, anon, authenticated;
create trigger c_available_weeks before insert or update on public.workout_progress
  for each row execute function training_internal.check_available_weeks();

create function training_internal.prepare_lazy_weeks(owner uuid) returns void
language plpgsql set search_path = '' as $$
begin
  update public.training_blocks b set planned_week_count=coalesce(
    (select max(w.number) from public.training_weeks w where w.block_id=b.id and w.deleted_at is null), 1)
    where b.user_id=owner and b.planned_week_count is null;
  -- Infer each workout's past reach from its own slots, including durable
  -- completion destinations. Empty slots belonging only to another plan do
  -- not contribute. Repeat activation leaves explicit availability unchanged.
  with reached as (
    select p.id as progress_id,p.split_id,p.active_week_id as week_id
      from public.workout_progress p where p.user_id=owner and p.available_week_ids is null
    union
    select p.id,p.split_id,s.training_week_id
      from public.workout_progress p join public.workout_sessions s
        on s.plan_id=p.plan_id and s.split_id=p.split_id
      where p.user_id=owner and p.available_week_ids is null and s.training_week_id is not null
    union
    select p.id,p.split_id,(s.data->'completionTransition'->>'nextWeekId')::uuid
      from public.workout_progress p join public.workout_sessions s
        on s.plan_id=p.plan_id and s.split_id=p.split_id
      where p.user_id=owner and p.available_week_ids is null and
        s.data->'completionTransition'->>'nextWeekId' is not null
  ), highest as (
    select r.progress_id,r.split_id,w.block_id,max(w.number) as number
      from reached r join public.training_weeks w on w.id=r.week_id
      group by r.progress_id,r.split_id,w.block_id
  ), available as (
    select h.progress_id,array_agg(w.id order by b.position,b.id,w.number,w.id) as ids
      from highest h join public.training_weeks w
        on w.split_id=h.split_id and w.block_id=h.block_id and w.number<=h.number
      join public.training_blocks b on b.id=w.block_id
      group by h.progress_id
  )
  update public.workout_progress p set available_week_ids=a.ids
    from available a where p.id=a.progress_id and p.available_week_ids is null;
end
$$;
revoke all on function training_internal.prepare_lazy_weeks(uuid) from public, anon, authenticated;

create or replace function public.activate_training_schema() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := auth.uid();
  header text := coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-opengym-training-schema','');
  requested integer;
  previous integer;
begin
  if owner is null then raise insufficient_privilege; end if;
  if header not in ('1','2') then
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
  if requested=2 then perform training_internal.prepare_lazy_weeks(owner); end if;
  return requested;
end
$$;
revoke all on function public.activate_training_schema() from public, anon;
grant execute on function public.activate_training_schema() to authenticated;
