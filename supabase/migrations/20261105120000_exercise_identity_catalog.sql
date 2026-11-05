-- Account-scoped exercise identity. Apply before releasing the schema-3 client.
-- Installation alone does not upgrade any account; activation remains explicit.
alter table public.account_training_capabilities
  drop constraint account_training_capabilities_minimum_training_schema_check,
  add constraint account_training_capabilities_minimum_training_schema_check
    check (minimum_training_schema in (1, 2, 3));

create table public.exercise_definitions (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (length(id) between 1 and 200),
  data jsonb not null,
  updated_at timestamptz not null,
  server_seq timestamptz not null default now(),
  primary key (user_id, id),
  check (jsonb_typeof(data) = 'object' and data ?& array['id','name','aliases','category','builtIn'] and data->>'id' = id),
  check (jsonb_typeof(data->'name') = 'string' and length(btrim(data->>'name')) > 0),
  check (jsonb_typeof(data->'aliases') = 'array'),
  check (data->>'mergedIntoId' is null or data->>'mergedIntoId' <> id)
);
alter table public.exercise_definitions enable row level security;
revoke all on public.exercise_definitions from public, anon, authenticated;
grant select, insert, update on public.exercise_definitions to authenticated;
create policy exercise_definitions_select on public.exercise_definitions
  for select to authenticated using ((select auth.uid()) = user_id);
create policy exercise_definitions_insert on public.exercise_definitions
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy exercise_definitions_update on public.exercise_definitions
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create index exercise_definitions_delta on public.exercise_definitions(user_id, server_seq, id);

create function training_internal.keep_exercise_definition() returns trigger
language plpgsql set search_path = '' as $$
begin
  -- A late unmerged copy cannot undo an explicit merge. Conflicting merges
  -- otherwise follow LWW; the client resolves opposing offline cycles by ID.
  if old.data->>'mergedIntoId' is not null and new.data->>'mergedIntoId' is null then return old; end if;
  if old.data->>'mergedIntoId' is null and new.data->>'mergedIntoId' is not null then return new; end if;
  if new.updated_at < old.updated_at then return old; end if;
  return new;
end
$$;
revoke all on function training_internal.keep_exercise_definition() from public, anon, authenticated;
create trigger a_exercise_lww before update on public.exercise_definitions
  for each row execute function training_internal.keep_exercise_definition();
create trigger t_exercise_seq before insert or update on public.exercise_definitions
  for each row execute function public.touch_server_seq();

create or replace function public.activate_training_schema() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := auth.uid();
  header text := coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-opengym-training-schema','');
  requested integer;
  previous integer;
begin
  if owner is null then raise insufficient_privilege; end if;
  if header not in ('1','2','3') then
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
notify pgrst, 'reload schema';
