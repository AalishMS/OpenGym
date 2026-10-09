
create table public.splits (
  id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_seq timestamptz not null default now(),
  deleted_at timestamptz,
  constraint splits_pkey primary key (id),
  constraint splits_id_user_key unique (id, user_id),
  constraint splits_name_trimmed_check check (name = btrim(name)),
  constraint splits_name_length_check check (char_length(name) between 1 and 24)
);

create unique index splits_user_name_active_uidx
  on public.splits (user_id, lower(btrim(name)))
  where deleted_at is null;

create index splits_user_seq_idx
  on public.splits (user_id, server_seq);

create index splits_user_active_idx
  on public.splits (user_id, created_at, id)
  where deleted_at is null;

alter table public.workout_plans
  add column split_id uuid;

alter table public.workout_sessions
  add column split_id uuid;

insert into public.splits (id, user_id, name, created_at, updated_at, server_seq)
select
  extensions.uuid_generate_v5(
    extensions.uuid_ns_url(),
    'https://opengym.app/users/' || u.id::text || '/default-split'
  ),
  u.id,
  'My Split',
  now(),
  now(),
  now()
from auth.users u;

update public.workout_plans p
set
  split_id = extensions.uuid_generate_v5(
    extensions.uuid_ns_url(),
    'https://opengym.app/users/' || p.user_id::text || '/default-split'
  ),
  data = jsonb_set(
    p.data,
    '{splitId}',
    to_jsonb(
      extensions.uuid_generate_v5(
        extensions.uuid_ns_url(),
        'https://opengym.app/users/' || p.user_id::text || '/default-split'
      )::text
    ),
    true
  );

update public.workout_sessions s
set
  split_id = extensions.uuid_generate_v5(
    extensions.uuid_ns_url(),
    'https://opengym.app/users/' || s.user_id::text || '/default-split'
  ),
  data = jsonb_set(
    s.data,
    '{splitId}',
    to_jsonb(
      extensions.uuid_generate_v5(
        extensions.uuid_ns_url(),
        'https://opengym.app/users/' || s.user_id::text || '/default-split'
      )::text
    ),
    true
  );

alter table public.workout_plans
  alter column split_id set not null;

alter table public.workout_sessions
  alter column split_id set not null;

alter table public.workout_plans
  add constraint workout_plans_split_owner_fkey
  foreign key (split_id, user_id)
  references public.splits (id, user_id)
  on update cascade
  on delete cascade;

alter table public.workout_sessions
  add constraint workout_sessions_split_owner_fkey
  foreign key (split_id, user_id)
  references public.splits (id, user_id)
  on update cascade
  on delete cascade;

create index workout_plans_user_split_active_idx
  on public.workout_plans (user_id, split_id)
  where deleted_at is null;

create index workout_sessions_user_split_date_active_idx
  on public.workout_sessions (user_id, split_id, date desc)
  where deleted_at is null;

create table public.split_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  active_split_id uuid not null,
  updated_at timestamptz not null default now(),
  server_seq timestamptz not null default now(),
  constraint split_preferences_pkey primary key (user_id),
  constraint split_preferences_active_owner_fkey
    foreign key (active_split_id, user_id)
    references public.splits (id, user_id)
    on update cascade
    on delete cascade
);

insert into public.split_preferences (
  user_id,
  active_split_id,
  updated_at,
  server_seq
)
select
  u.id,
  extensions.uuid_generate_v5(
    extensions.uuid_ns_url(),
    'https://opengym.app/users/' || u.id::text || '/default-split'
  ),
  now(),
  now()
from auth.users u;

create or replace function public.touch_server_seq()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.server_seq := now();
  return new;
end;
$function$;

create trigger t_splits_seq
  before insert or update on public.splits
  for each row execute function public.touch_server_seq();

create trigger t_split_preferences_seq
  before insert or update on public.split_preferences
  for each row execute function public.touch_server_seq();

create or replace function public.enforce_split_limit()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  active_count integer;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 0)
  );

  select count(*)
  into active_count
  from public.splits s
  where s.user_id = new.user_id
    and s.deleted_at is null;

  if active_count >= 5 then
    raise exception 'A user can have at most 5 active splits'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

create trigger a_splits_limit
  before insert on public.splits
  for each row execute function public.enforce_split_limit();

create or replace function public.validate_split_preference()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if not exists (
    select 1
    from public.splits s
    where s.id = new.active_split_id
      and s.user_id = new.user_id
      and s.deleted_at is null
  ) then
    raise exception 'Active split must be a non-deleted split owned by the user'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

create trigger a_validate_split_preference
  before insert or update on public.split_preferences
  for each row execute function public.validate_split_preference();

create or replace function public.guard_split_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.deleted_at is not null and new.deleted_at is null then
    raise exception 'Deleted splits cannot be restored'
      using errcode = '23514';
  end if;

  if old.deleted_at is null and new.deleted_at is not null then
    if exists (
      select 1
      from public.split_preferences p
      where p.user_id = old.user_id
        and p.active_split_id = old.id
    ) then
      raise exception 'Choose a replacement active split before deleting this split'
        using errcode = '23514';
    end if;

    if not exists (
      select 1
      from public.splits s
      where s.user_id = old.user_id
        and s.id <> old.id
        and s.deleted_at is null
    ) then
      raise exception 'The last active split cannot be deleted'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$function$;

create trigger a_guard_split_lifecycle
  before update of deleted_at on public.splits
  for each row execute function public.guard_split_lifecycle();

create or replace function public.cascade_split_tombstone()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    update public.workout_plans p
    set
      deleted_at = new.deleted_at,
      updated_at = pg_catalog.greatest(p.updated_at, new.updated_at),
      data = pg_catalog.jsonb_set(
        p.data,
        '{deletedAt}',
        pg_catalog.to_jsonb(new.deleted_at::text),
        true
      )
    where p.split_id = new.id
      and p.user_id = new.user_id
      and p.deleted_at is null;

    update public.workout_sessions s
    set
      deleted_at = new.deleted_at,
      updated_at = pg_catalog.greatest(s.updated_at, new.updated_at),
      data = pg_catalog.jsonb_set(
        s.data,
        '{deletedAt}',
        pg_catalog.to_jsonb(new.deleted_at::text),
        true
      )
    where s.split_id = new.id
      and s.user_id = new.user_id
      and s.deleted_at is null;
  end if;

  return new;
end;
$function$;

create trigger z_cascade_split_tombstone
  after update of deleted_at on public.splits
  for each row execute function public.cascade_split_tombstone();

create or replace function public.assign_plan_split()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  candidate uuid;
begin
  if new.split_id is not null then
    return new;
  end if;

  select p.split_id
  into candidate
  from public.workout_plans p
  where p.id = new.id
    and p.user_id = new.user_id;

  if candidate is null then
    select s.id
    into candidate
    from public.splits s
    where s.user_id = new.user_id
      and s.deleted_at is null
    order by s.created_at, s.id
    limit 1;
  end if;

  if candidate is null then
    candidate := extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://opengym.app/users/' || new.user_id::text || '/default-split'
    );

    insert into public.splits (
      id,
      user_id,
      name,
      created_at,
      updated_at,
      server_seq
    )
    values (
      candidate,
      new.user_id,
      'My Split',
      now(),
      now(),
      now()
    )
    on conflict (id) do nothing;
  end if;

  new.split_id := candidate;
  return new;
end;
$function$;

create trigger a_assign_plan_split
  before insert on public.workout_plans
  for each row execute function public.assign_plan_split();

create or replace function public.assign_session_split()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  candidate uuid;
begin
  if new.split_id is not null then
    return new;
  end if;

  select s.split_id
  into candidate
  from public.workout_sessions s
  where s.id = new.id
    and s.user_id = new.user_id;

  if candidate is null and new.plan_id is not null then
    select p.split_id
    into candidate
    from public.workout_plans p
    where p.id = new.plan_id
      and p.user_id = new.user_id;
  end if;

  if candidate is null then
    select s.id
    into candidate
    from public.splits s
    where s.user_id = new.user_id
      and s.deleted_at is null
    order by s.created_at, s.id
    limit 1;
  end if;

  if candidate is null then
    candidate := extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'https://opengym.app/users/' || new.user_id::text || '/default-split'
    );

    insert into public.splits (
      id,
      user_id,
      name,
      created_at,
      updated_at,
      server_seq
    )
    values (
      candidate,
      new.user_id,
      'My Split',
      now(),
      now(),
      now()
    )
    on conflict (id) do nothing;
  end if;

  new.split_id := candidate;
  return new;
end;
$function$;

create trigger a_assign_session_split
  before insert on public.workout_sessions
  for each row execute function public.assign_session_split();

alter table public.splits enable row level security;
alter table public.split_preferences enable row level security;

create policy splits_own_select on public.splits
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy splits_own_insert on public.splits
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy splits_own_update on public.splits
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy split_preferences_own_select on public.split_preferences
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy split_preferences_own_insert on public.split_preferences
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy split_preferences_own_update on public.split_preferences
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists plans_own_select on public.workout_plans;
create policy plans_own_select on public.workout_plans
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists plans_own_insert on public.workout_plans;
create policy plans_own_insert on public.workout_plans
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists plans_own_update on public.workout_plans;
create policy plans_own_update on public.workout_plans
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists plans_own_delete on public.workout_plans;
create policy plans_own_delete on public.workout_plans
  for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists sessions_own_select on public.workout_sessions;
create policy sessions_own_select on public.workout_sessions
  for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists sessions_own_insert on public.workout_sessions;
create policy sessions_own_insert on public.workout_sessions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists sessions_own_update on public.workout_sessions;
create policy sessions_own_update on public.workout_sessions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists sessions_own_delete on public.workout_sessions;
create policy sessions_own_delete on public.workout_sessions
  for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.splits from anon;
revoke all on table public.split_preferences from anon;
revoke all on table public.workout_plans from anon;
revoke all on table public.workout_sessions from anon;

grant select, insert, update on table public.splits to authenticated;
grant select, insert, update on table public.split_preferences to authenticated;
grant select, insert, update, delete on table public.workout_plans to authenticated;
grant select, insert, update, delete on table public.workout_sessions to authenticated;

grant select, insert, update, delete on table public.splits to service_role;
grant select, insert, update, delete on table public.split_preferences to service_role;

revoke execute on function public.touch_server_seq() from public, anon, authenticated;
revoke execute on function public.enforce_split_limit() from public, anon, authenticated;
revoke execute on function public.validate_split_preference() from public, anon, authenticated;
revoke execute on function public.guard_split_lifecycle() from public, anon, authenticated;
revoke execute on function public.cascade_split_tombstone() from public, anon, authenticated;
revoke execute on function public.assign_plan_split() from public, anon, authenticated;
revoke execute on function public.assign_session_split() from public, anon, authenticated;
;
