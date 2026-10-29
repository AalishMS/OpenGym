-- Generated with `supabase migration new`; verified against the captured base
-- schema in supabase/tests/training_blocks. Apply only through a later authorized
-- deployment. This file does not activate existing accounts on installation.
create schema if not exists training_internal;
revoke all on schema training_internal from public, anon, authenticated;

create table public.account_training_capabilities (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minimum_training_schema integer not null check (minimum_training_schema = 1)
);
alter table public.account_training_capabilities enable row level security;
revoke all on public.account_training_capabilities from public, anon, authenticated;
grant select on public.account_training_capabilities to authenticated;
create policy training_capability_read on public.account_training_capabilities
  for select to authenticated using ((select auth.uid()) = user_id);

create table public.training_blocks (
  id uuid primary key,
  user_id uuid not null,
  split_id uuid not null,
  name text not null check (name = btrim(name) and char_length(name) between 1 and 40),
  position integer not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_seq timestamptz not null default now(),
  unique (id, split_id, user_id),
  foreign key (split_id, user_id) references public.splits(id, user_id) on delete cascade
);
create table public.training_weeks (
  id uuid primary key,
  user_id uuid not null,
  split_id uuid not null,
  block_id uuid not null,
  number integer not null check (number > 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_seq timestamptz not null default now(),
  unique (id, split_id, user_id),
  foreign key (block_id, split_id, user_id)
    references public.training_blocks(id, split_id, user_id) on delete cascade
);
create unique index training_weeks_live_number on public.training_weeks(block_id, number) where deleted_at is null;
alter table public.workout_plans add constraint workout_plans_id_split_owner_key unique(id, split_id, user_id);
create table public.workout_progress (
  id uuid primary key,
  user_id uuid not null,
  split_id uuid not null,
  plan_id uuid not null,
  active_week_id uuid not null,
  state text not null check (state in ('ready', 'awaitingBoundary')),
  revision uuid not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_seq timestamptz not null default now(),
  foreign key (plan_id, split_id, user_id) references public.workout_plans(id, split_id, user_id) on delete cascade,
  foreign key (active_week_id, split_id, user_id) references public.training_weeks(id, split_id, user_id) on delete cascade
);
create unique index workout_progress_live_plan on public.workout_progress(plan_id) where deleted_at is null;
alter table public.workout_sessions add column training_week_id uuid;
alter table public.workout_sessions add constraint workout_sessions_week_split_owner_fkey
  foreign key (training_week_id, split_id, user_id) references public.training_weeks(id, split_id, user_id) on delete cascade;
-- Deliberately retain the existing nullable, non-FK plan_id for orphan history.

create function training_internal.legacy_block(split uuid) returns uuid
language sql immutable set search_path = '' as $$
  select extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'https://opengym.app/splits/' || split::text || '/training-blocks/legacy-v1')
$$;
create function training_internal.legacy_week(split uuid, number integer) returns uuid
language sql immutable set search_path = '' as $$
  select extensions.uuid_generate_v5(training_internal.legacy_block(split), number::text)
$$;
create function training_internal.progress_id(split uuid, plan uuid) returns uuid
language sql immutable set search_path = '' as $$
  select extensions.uuid_generate_v5(extensions.uuid_ns_url(), 'https://opengym.app/splits/' || split::text || '/plans/' || plan::text || '/progress-v1')
$$;
create function training_internal.initial_revision(split uuid, plan uuid) returns uuid
language sql immutable set search_path = '' as $$
  select extensions.uuid_generate_v5(training_internal.progress_id(split, plan), 'initial-v1')
$$;

-- Writes for one account serialize with activation and other graph mutations.
-- Reads hold the shared lock through transaction end, so an old request that
-- passed the gate must finish before activation snapshots/backfills its rows.
create function training_internal.guard_training_schema() returns void
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := auth.uid();
  required_version integer;
  header text := coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-opengym-training-schema','');
begin
  if owner is null then return; end if;
  if current_setting('request.method',true) in ('POST','PATCH','PUT','DELETE') then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-account:' || owner::text,0));
  else
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('training-account:' || owner::text,0));
  end if;
  select minimum_training_schema into required_version from public.account_training_capabilities where user_id=owner;
  if required_version is not null and (header !~ '^[0-9]{1,4}$' or header::integer < required_version) then
    raise sqlstate 'PT426' using message='Update OpenGym to sync this account';
  end if;
end
$$;
revoke all on function training_internal.guard_training_schema() from public;
grant usage on schema training_internal to anon, authenticated;
grant execute on function training_internal.guard_training_schema() to anon, authenticated;

-- A stale whole-row upsert returns the canonical row, not the rejected payload.
create function training_internal.keep_newest_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name='split_preferences' then
    if new.updated_at < old.updated_at then return old; end if;
    return new;
  end if;
  if old.deleted_at is not null and new.deleted_at is null then return old; end if;
  if old.deleted_at is null and new.deleted_at is not null then return new; end if;
  if new.updated_at < old.updated_at then return old; end if;
  if tg_table_name='workout_progress' then
    if new.revision=training_internal.initial_revision(new.split_id,new.plan_id) then return old; end if;
    if new.updated_at=old.updated_at and new.revision::text < old.revision::text then return old; end if;
  end if;
  return new;
end
$$;

-- Rebase the random-ID occupant before reserving a deterministic legacy label.
-- IDs and performed data stay unchanged. Session timestamps remain unchanged:
-- this is link/display normalization, never a newer edit to performed sets.
create function training_internal.reserve_week_label() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  conflict public.training_weeks;
  next_number integer;
begin
  if auth.uid() is not null and new.user_id<>auth.uid() then raise insufficient_privilege; end if;
  if new.id <> training_internal.legacy_week(new.split_id,new.number) or new.deleted_at is not null then return new; end if;
  if new.block_id <> training_internal.legacy_block(new.split_id) then raise check_violation using message='Conflicting deterministic week block'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-block:' || new.block_id::text,0));
  for conflict in select * from public.training_weeks where block_id=new.block_id and number=new.number and id<>new.id and deleted_at is null order by id for update loop
    select greatest(coalesce(max(number),0),new.number)+1 into next_number from public.training_weeks where block_id=new.block_id and deleted_at is null;
    update public.training_weeks set number=next_number, updated_at=greatest(updated_at,now()) where id=conflict.id;
    update public.workout_sessions set week_number=next_number, data=jsonb_set(data,'{weekNumber}',to_jsonb(next_number)) where training_week_id=conflict.id;
  end loop;
  return new;
end
$$;

create function training_internal.ensure_legacy_week(split uuid, number integer) returns uuid
language plpgsql set search_path = '' as $$
declare
  parent public.splits;
  block uuid := training_internal.legacy_block(split);
  week uuid := training_internal.legacy_week(split,number);
  existing_deleted timestamptz;
begin
  if number < 1 then raise check_violation using message='Invalid legacy training week'; end if;
  select * into strict parent from public.splits where id=split for share;
  if auth.uid() is not null and parent.user_id<>auth.uid() then raise insufficient_privilege; end if;
  insert into public.training_blocks(id,user_id,split_id,name,position,created_at,updated_at,deleted_at)
    values(block,parent.user_id,split,'Block 1',0,parent.created_at,'epoch'::timestamptz,parent.deleted_at) on conflict(id) do nothing;
  select deleted_at into existing_deleted from public.training_blocks where id=block;
  if existing_deleted is not null and parent.deleted_at is null then raise check_violation using message='Deleted legacy block cannot be restored'; end if;
  insert into public.training_weeks(id,user_id,split_id,block_id,number,created_at,updated_at,deleted_at)
    values(week,parent.user_id,split,block,number,parent.created_at,'epoch'::timestamptz,parent.deleted_at) on conflict(id) do nothing;
  select deleted_at into existing_deleted from public.training_weeks where id=week;
  if existing_deleted is not null and parent.deleted_at is null then raise check_violation using message='Deleted legacy week cannot be restored'; end if;
  return week;
end
$$;

create function training_internal.check_training_parent() returns trigger
language plpgsql set search_path = '' as $$
declare
  parent_deleted timestamptz;
  parent_owner uuid;
  parent_split uuid;
begin
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

create function training_internal.link_session() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  parent public.training_weeks;
  candidate uuid;
  count_matches integer;
  evidence jsonb;
  target public.training_weeks;
begin
  if auth.uid() is not null and new.user_id<>auth.uid() then raise insufficient_privilege; end if;
  if not exists(select 1 from public.account_training_capabilities where user_id=new.user_id) then return new; end if;
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
    new.data := jsonb_set(new.data,'{completionTransition}',old.data->'completionTransition');
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

create function training_internal.normalize_account() returns void
language plpgsql set search_path = '' as $$
declare
  owner uuid := auth.uid();
  split public.splits;
  plan public.workout_plans;
  legacy_number integer;
  block uuid;
  selected_week uuid;
  highest integer;
  progress_state text;
begin
  for split in select * from public.splits where user_id=owner order by id loop
    for legacy_number in select distinct week_number from public.workout_sessions where split_id=split.id and user_id=owner and training_week_id is null order by week_number loop
      perform training_internal.ensure_legacy_week(split.id,legacy_number);
    end loop;
    if not exists(select 1 from public.training_blocks where split_id=split.id) then perform training_internal.ensure_legacy_week(split.id,1); end if;
  end loop;
  -- Row triggers fill only missing links from the current server revision.
  update public.workout_sessions set updated_at=updated_at where user_id=owner and training_week_id is null;
  for plan in select p.* from public.workout_plans p join public.splits s on s.id=p.split_id where p.user_id=owner and p.deleted_at is null and s.deleted_at is null order by p.id loop
    if exists(select 1 from public.workout_progress where plan_id=plan.id) then continue; end if;
    select id into block from public.training_blocks where split_id=plan.split_id and deleted_at is null order by position,id limit 1;
    if block is null then raise check_violation using message='No live training block'; end if;
    select s.training_week_id into selected_week from public.workout_sessions s join public.training_weeks w on w.id=s.training_week_id where s.plan_id=plan.id and s.split_id=plan.split_id and w.block_id=block and s.deleted_at is null and s.data->>'isCompleted'='false' order by (s.data->>'timerStartedAt' is not null) desc, coalesce(s.updated_at,s.date) desc,s.date desc,s.id desc limit 1;
    progress_state := 'ready';
    if selected_week is null then
      select max(s.week_number) into highest from public.workout_sessions s join public.training_weeks w on w.id=s.training_week_id where s.plan_id=plan.id and s.split_id=plan.split_id and w.block_id=block and s.deleted_at is null and coalesce(s.data->>'isCompleted','true')='true';
      select id into selected_week from public.training_weeks where block_id=block and deleted_at is null and (highest is null or number>highest) order by number,id limit 1;
      if selected_week is null then
        select id into selected_week from public.training_weeks where block_id=block and deleted_at is null order by number desc,id desc limit 1;
        progress_state := 'awaitingBoundary';
      end if;
    end if;
    if selected_week is null then raise check_violation using message='No supplied training week'; end if;
    insert into public.workout_progress(id,user_id,split_id,plan_id,active_week_id,state,revision,updated_at) values(training_internal.progress_id(plan.split_id,plan.id),owner,plan.split_id,plan.id,selected_week,progress_state,training_internal.initial_revision(plan.split_id,plan.id),'epoch'::timestamptz) on conflict(id) do nothing;
    selected_week := null;
  end loop;
end
$$;

create function public.activate_training_schema() returns integer
language plpgsql security definer set search_path = '' as $$
declare owner uuid := auth.uid();
begin
  if owner is null then raise insufficient_privilege; end if;
  if coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-opengym-training-schema','')<>'1' then raise sqlstate 'PT426' using message='Update OpenGym to prepare training data'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('training-account:' || owner::text,0));
  if exists(select 1 from public.account_training_capabilities where user_id=owner) then return 1; end if;
  insert into public.account_training_capabilities values(owner,1);
  perform training_internal.normalize_account();
  return 1;
end
$$;
revoke all on function public.activate_training_schema() from public, anon;
grant execute on function public.activate_training_schema() to authenticated;

-- Existing split tombstones cascade to the new graph. Auth-user hard cascades
-- remain FK-driven and separate from this durable soft-deletion path.
create function training_internal.cascade_structure() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    update public.training_blocks set deleted_at=new.deleted_at,updated_at=greatest(updated_at,new.updated_at) where split_id=new.id and user_id=new.user_id and deleted_at is null;
    update public.training_weeks set deleted_at=new.deleted_at,updated_at=greatest(updated_at,new.updated_at) where split_id=new.id and user_id=new.user_id and deleted_at is null;
    update public.workout_progress set deleted_at=new.deleted_at,updated_at=greatest(updated_at,new.updated_at) where split_id=new.id and user_id=new.user_id and deleted_at is null;
  end if;
  return new;
end
$$;
create trigger y_cascade_training_structure after update of deleted_at on public.splits for each row execute function training_internal.cascade_structure();
create function training_internal.cascade_plan_progress() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.deleted_at is null and new.deleted_at is not null then update public.workout_progress set deleted_at=new.deleted_at,updated_at=greatest(updated_at,new.updated_at) where plan_id=new.id and user_id=new.user_id and deleted_at is null; end if;
  return new;
end
$$;
create trigger y_cascade_plan_progress after update of deleted_at on public.workout_plans for each row execute function training_internal.cascade_plan_progress();
create trigger b_reserve_legacy_week before insert on public.training_weeks for each row execute function training_internal.reserve_week_label();
create trigger b_link_training_week before insert or update on public.workout_sessions for each row execute function training_internal.link_session();

do $$
declare table_name text;
begin
  foreach table_name in array array['training_blocks','training_weeks','workout_progress'] loop
    execute format('alter table public.%I enable row level security',table_name);
    execute format('revoke all on public.%I from public,anon,authenticated',table_name);
    execute format('grant select,insert,update on public.%I to authenticated',table_name);
    execute format('create policy training_owner_select on public.%I for select to authenticated using ((select auth.uid())=user_id)',table_name);
    execute format('create policy training_owner_insert on public.%I for insert to authenticated with check ((select auth.uid())=user_id)',table_name);
    execute format('create policy training_owner_update on public.%I for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id)',table_name);
    execute format('create trigger b_training_parent before insert or update on public.%I for each row execute function training_internal.check_training_parent()',table_name);
    execute format('create trigger t_training_seq before insert or update on public.%I for each row execute function public.touch_server_seq()',table_name);
  end loop;
  foreach table_name in array array['splits','training_blocks','training_weeks','workout_plans','workout_sessions','workout_progress','split_preferences'] loop
    execute format('create trigger a_training_lww before update on public.%I for each row execute function training_internal.keep_newest_row()',table_name);
    execute format('create index %I on public.%I(user_id,server_seq,%I)',table_name || '_training_delta',table_name,case when table_name='split_preferences' then 'user_id' else 'id' end);
  end loop;
end
$$;
create index training_blocks_split_owner on public.training_blocks(split_id,user_id);
create index training_weeks_block_split_owner on public.training_weeks(block_id,split_id,user_id);
create index workout_progress_plan_split_owner on public.workout_progress(plan_id,split_id,user_id);
create index workout_progress_week_split_owner on public.workout_progress(active_week_id,split_id,user_id);
create index workout_sessions_week_split_owner on public.workout_sessions(training_week_id,split_id,user_id);

revoke all on all functions in schema training_internal from public, anon, authenticated;
grant execute on function training_internal.guard_training_schema() to anon,authenticated;
-- Trigger helpers are called by invoker triggers; only these pure identity
-- functions require authenticated execution. No owner-supplied mutation RPCs.
grant execute on function training_internal.legacy_block(uuid), training_internal.legacy_week(uuid,integer), training_internal.progress_id(uuid,uuid), training_internal.initial_revision(uuid,uuid) to authenticated;
alter role authenticator set pgrst.db_pre_request = 'training_internal.guard_training_schema';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

-- INSERT triggers also run for ON CONFLICT UPDATE. Count other live IDs so a
-- metadata upsert at the five-profile limit remains legal.
create or replace function public.enforce_split_limit() returns trigger
language plpgsql set search_path = '' as $$
declare active_count integer;
begin
  if new.deleted_at is not null then return new; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text,0));
  select count(*) into active_count from public.splits
    where user_id=new.user_id and deleted_at is null and id<>new.id;
  if active_count>=5 then
    raise exception 'A user can have at most 5 active splits' using errcode='23514';
  end if;
  return new;
end
$$;
