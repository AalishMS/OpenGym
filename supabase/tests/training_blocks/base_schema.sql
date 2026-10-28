-- Test fixture reconstructed from read-only OpenGym catalog inventory, 2026-10-28.
-- PostgreSQL 17.6.1.155; schema only, no account or workout data.
-- Auth roles/JWT helpers below are local test scaffolding.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role authenticator login noinherit;
grant anon, authenticated to authenticator;
create schema auth;
create schema extensions;
create extension "uuid-ossp" with schema extensions;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select (nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'sub')::uuid $$;
grant usage on schema auth, extensions to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
create table public.splits (
  "id" uuid not null,
  "user_id" uuid not null,
  "name" text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "server_seq" timestamp with time zone default now() not null,
  "deleted_at" timestamp with time zone
);
create table public.split_preferences (
  "user_id" uuid not null,
  "active_split_id" uuid not null,
  "updated_at" timestamp with time zone default now() not null,
  "server_seq" timestamp with time zone default now() not null
);
create table public.workout_plans (
  "id" uuid not null,
  "user_id" uuid not null,
  "name" text not null,
  "plan_color" bigint,
  "data" jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "server_seq" timestamp with time zone default now() not null,
  "deleted_at" timestamp with time zone,
  "split_id" uuid not null
);
create table public.workout_sessions (
  "id" uuid not null,
  "user_id" uuid not null,
  "plan_id" uuid,
  "plan_name" text not null,
  "week_number" integer default 1 not null,
  "date" timestamp with time zone not null,
  "data" jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "server_seq" timestamp with time zone default now() not null,
  "deleted_at" timestamp with time zone,
  "split_id" uuid not null
);
alter table public.split_preferences add constraint "split_preferences_pkey" PRIMARY KEY (user_id);
alter table public.splits add constraint "splits_id_user_key" UNIQUE (id, user_id);
alter table public.splits add constraint "splits_name_length_check" CHECK (((char_length(name) >= 1) AND (char_length(name) <= 24)));
alter table public.splits add constraint "splits_name_trimmed_check" CHECK ((name = btrim(name)));
alter table public.splits add constraint "splits_pkey" PRIMARY KEY (id);
alter table public.workout_plans add constraint "workout_plans_pkey" PRIMARY KEY (id);
alter table public.workout_sessions add constraint "workout_sessions_pkey" PRIMARY KEY (id);
alter table public.split_preferences add constraint "split_preferences_active_owner_fkey" FOREIGN KEY (active_split_id, user_id) REFERENCES splits(id, user_id) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.split_preferences add constraint "split_preferences_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.splits add constraint "splits_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.workout_plans add constraint "workout_plans_split_owner_fkey" FOREIGN KEY (split_id, user_id) REFERENCES splits(id, user_id) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.workout_plans add constraint "workout_plans_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.workout_sessions add constraint "workout_sessions_split_owner_fkey" FOREIGN KEY (split_id, user_id) REFERENCES splits(id, user_id) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.workout_sessions add constraint "workout_sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX splits_user_name_active_uidx ON public.splits USING btree (user_id, lower(btrim(name))) WHERE (deleted_at IS NULL);
CREATE INDEX splits_user_seq_idx ON public.splits USING btree (user_id, server_seq);
CREATE INDEX splits_user_active_idx ON public.splits USING btree (user_id, created_at, id) WHERE (deleted_at IS NULL);
CREATE INDEX split_preferences_active_owner_idx ON public.split_preferences USING btree (active_split_id, user_id);
CREATE INDEX workout_plans_user_seq_idx ON public.workout_plans USING btree (user_id, server_seq);
CREATE INDEX workout_plans_user_split_active_idx ON public.workout_plans USING btree (user_id, split_id) WHERE (deleted_at IS NULL);
CREATE INDEX workout_plans_split_owner_idx ON public.workout_plans USING btree (split_id, user_id);
CREATE INDEX workout_sessions_user_seq_idx ON public.workout_sessions USING btree (user_id, server_seq);
CREATE INDEX workout_sessions_user_plan_idx ON public.workout_sessions USING btree (user_id, plan_id, week_number);
CREATE INDEX workout_sessions_user_split_date_active_idx ON public.workout_sessions USING btree (user_id, split_id, date DESC) WHERE (deleted_at IS NULL);
CREATE INDEX workout_sessions_split_owner_idx ON public.workout_sessions USING btree (split_id, user_id);
CREATE OR REPLACE FUNCTION public.assign_plan_split()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.assign_session_split()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.cascade_split_tombstone()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.deleted_at is null and new.deleted_at is not null then
    update public.workout_plans p
    set
      deleted_at = new.deleted_at,
      updated_at = greatest(p.updated_at, new.updated_at),
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
      updated_at = greatest(s.updated_at, new.updated_at),
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

CREATE OR REPLACE FUNCTION public.enforce_split_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.guard_split_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

CREATE OR REPLACE FUNCTION public.touch_server_seq()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.server_seq := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_split_preference()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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

CREATE TRIGGER t_plans_seq BEFORE INSERT OR UPDATE ON public.workout_plans FOR EACH ROW EXECUTE FUNCTION touch_server_seq();
CREATE TRIGGER t_sessions_seq BEFORE INSERT OR UPDATE ON public.workout_sessions FOR EACH ROW EXECUTE FUNCTION touch_server_seq();
CREATE TRIGGER t_splits_seq BEFORE INSERT OR UPDATE ON public.splits FOR EACH ROW EXECUTE FUNCTION touch_server_seq();
CREATE TRIGGER t_split_preferences_seq BEFORE INSERT OR UPDATE ON public.split_preferences FOR EACH ROW EXECUTE FUNCTION touch_server_seq();
CREATE TRIGGER a_splits_limit BEFORE INSERT ON public.splits FOR EACH ROW EXECUTE FUNCTION enforce_split_limit();
CREATE TRIGGER a_validate_split_preference BEFORE INSERT OR UPDATE ON public.split_preferences FOR EACH ROW EXECUTE FUNCTION validate_split_preference();
CREATE TRIGGER a_guard_split_lifecycle BEFORE UPDATE OF deleted_at ON public.splits FOR EACH ROW EXECUTE FUNCTION guard_split_lifecycle();
CREATE TRIGGER z_cascade_split_tombstone AFTER UPDATE OF deleted_at ON public.splits FOR EACH ROW EXECUTE FUNCTION cascade_split_tombstone();
CREATE TRIGGER a_assign_plan_split BEFORE INSERT ON public.workout_plans FOR EACH ROW EXECUTE FUNCTION assign_plan_split();
CREATE TRIGGER a_assign_session_split BEFORE INSERT ON public.workout_sessions FOR EACH ROW EXECUTE FUNCTION assign_session_split();
alter table public.splits enable row level security;
revoke all on public.splits from anon, authenticated;
alter table public.split_preferences enable row level security;
revoke all on public.split_preferences from anon, authenticated;
alter table public.workout_plans enable row level security;
revoke all on public.workout_plans from anon, authenticated;
alter table public.workout_sessions enable row level security;
revoke all on public.workout_sessions from anon, authenticated;
create policy "splits_own_insert" on public.splits for INSERT to authenticated with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "splits_own_select" on public.splits for SELECT to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "splits_own_update" on public.splits for UPDATE to authenticated using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "split_preferences_own_insert" on public.split_preferences for INSERT to authenticated with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "split_preferences_own_select" on public.split_preferences for SELECT to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "split_preferences_own_update" on public.split_preferences for UPDATE to authenticated using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "plans_own_delete" on public.workout_plans for DELETE to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "plans_own_insert" on public.workout_plans for INSERT to authenticated with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "plans_own_select" on public.workout_plans for SELECT to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "plans_own_update" on public.workout_plans for UPDATE to authenticated using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "sessions_own_delete" on public.workout_sessions for DELETE to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "sessions_own_insert" on public.workout_sessions for INSERT to authenticated with check ((( SELECT auth.uid() AS uid) = user_id));
create policy "sessions_own_select" on public.workout_sessions for SELECT to authenticated using ((( SELECT auth.uid() AS uid) = user_id));
create policy "sessions_own_update" on public.workout_sessions for UPDATE to authenticated using ((( SELECT auth.uid() AS uid) = user_id)) with check ((( SELECT auth.uid() AS uid) = user_id));
grant INSERT on public.splits to authenticated;
grant SELECT on public.splits to authenticated;
grant UPDATE on public.splits to authenticated;
grant INSERT on public.split_preferences to authenticated;
grant SELECT on public.split_preferences to authenticated;
grant UPDATE on public.split_preferences to authenticated;
grant INSERT on public.workout_plans to authenticated;
grant SELECT on public.workout_plans to authenticated;
grant UPDATE on public.workout_plans to authenticated;
grant DELETE on public.workout_plans to authenticated;
grant INSERT on public.workout_sessions to authenticated;
grant SELECT on public.workout_sessions to authenticated;
grant UPDATE on public.workout_sessions to authenticated;
grant DELETE on public.workout_sessions to authenticated;
revoke execute on function public.cascade_split_tombstone() from public, anon, authenticated;
revoke execute on function public.touch_server_seq() from public, anon, authenticated;
revoke execute on function public.enforce_split_limit() from public, anon, authenticated;
revoke execute on function public.validate_split_preference() from public, anon, authenticated;
revoke execute on function public.guard_split_lifecycle() from public, anon, authenticated;
revoke execute on function public.assign_plan_split() from public, anon, authenticated;
revoke execute on function public.assign_session_split() from public, anon, authenticated;
