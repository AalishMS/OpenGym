-- AI Coach quota. See docs/coach.md, "Quota".
--
-- One row per user per Pacific day. Only the coach Edge Function touches it,
-- through the two service-role-only functions below, so the table has RLS on
-- and no policies.

create table public.coach_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null,
  calls int not null default 0,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  primary key (user_id, day)
);

alter table public.coach_usage enable row level security;
-- No policies: only the function's service role reads or writes it.

revoke all on table public.coach_usage from anon, authenticated;

-- Charges one Coach request against the user's and the project's daily caps.
--
-- "Today" is the day in America/Los_Angeles, which is when Google's free-tier
-- quota resets. A refused call is not counted. Calls are serialised per day by
-- an advisory lock, so two requests can't both take the last global slot.
--
-- blocked_by is null when allowed, otherwise 'user' or 'global'. used is the
-- caller's count after this call (or the unchanged count when refused).
create or replace function public.coach_charge(
  user_id uuid,
  user_limit int,
  global_limit int
)
returns table (
  allowed boolean,
  used int,
  blocked_by text,
  day date,
  resets_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  v_day date := (pg_catalog.now() at time zone 'America/Los_Angeles')::date;
  v_resets_at timestamptz :=
    ((v_day + 1)::timestamp at time zone 'America/Los_Angeles');
  v_calls int;
  v_total bigint;
begin
  if coach_charge.user_id is null then
    raise exception 'coach_charge: user_id is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('coach_charge:' || v_day::text, 0)
  );

  insert into public.coach_usage as u (user_id, day)
  values (coach_charge.user_id, v_day)
  on conflict on constraint coach_usage_pkey do nothing;

  select u.calls into v_calls
  from public.coach_usage u
  where u.user_id = coach_charge.user_id and u.day = v_day;

  if v_calls >= coach_charge.user_limit then
    return query select false, v_calls, 'user'::text, v_day, v_resets_at;
    return;
  end if;

  select coalesce(pg_catalog.sum(u.calls), 0) into v_total
  from public.coach_usage u
  where u.day = v_day;

  if v_total >= coach_charge.global_limit then
    return query select false, v_calls, 'global'::text, v_day, v_resets_at;
    return;
  end if;

  update public.coach_usage u
  set calls = u.calls + 1
  where u.user_id = coach_charge.user_id and u.day = v_day
  returning u.calls into v_calls;

  return query select true, v_calls, null::text, v_day, v_resets_at;
end;
$function$;

-- Adds a finished model call's token counts to the row coach_charge charged.
-- Takes the charged day rather than recomputing it, so a call that crosses
-- midnight Pacific is recorded against the day it was counted on.
create or replace function public.coach_record_tokens(
  user_id uuid,
  day date,
  input_tokens int,
  output_tokens int
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
#variable_conflict use_column
begin
  update public.coach_usage u
  set
    input_tokens = u.input_tokens + greatest(coalesce(coach_record_tokens.input_tokens, 0), 0),
    output_tokens = u.output_tokens + greatest(coalesce(coach_record_tokens.output_tokens, 0), 0)
  where u.user_id = coach_record_tokens.user_id
    and u.day = coach_record_tokens.day;
end;
$function$;

-- Supabase grants execute on new public functions to anon and authenticated
-- by default, so revoking from public alone would leave them callable.
revoke execute on function public.coach_charge(uuid, int, int)
  from public, anon, authenticated;
revoke execute on function public.coach_record_tokens(uuid, date, int, int)
  from public, anon, authenticated;

grant execute on function public.coach_charge(uuid, int, int) to service_role;
grant execute on function public.coach_record_tokens(uuid, date, int, int)
  to service_role;
