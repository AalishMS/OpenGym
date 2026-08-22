# Phase 2 — Postgres schema + Row-Level Security

**Goal:** create the two cloud tables that mirror Hive, with the `server_seq` pull cursor and
Row-Level Security so each account sees only its own rows. **No app code in this phase** — this all
runs in the Supabase SQL editor.

**Depends on:** Phase 1 project exists (you have URL + anon key). The app doesn't need to be built
for this phase.

---

## Design recap (why the columns are shaped this way)

- **`data jsonb`** holds the full aggregate — exactly what `WorkoutPlan.toJson()` /
  `WorkoutSession.toJson()` produce. This is the source of truth for reconstruction on pull; the app
  calls `fromJson(data)` and then overrides id/meta from the promoted columns.
- **Promoted columns** (`name`, `plan_color`, `plan_name`, `week_number`, `date`, `plan_id`) exist
  only for future queryability/debugging in the Supabase table view. The app does not rely on them
  for reconstruction.
- **`updated_at`** is **client-set** (the record's `updatedAt`) — the **LWW tie-break**.
- **`server_seq`** is **server-set** by a trigger (`now()` on every insert/update) — the **pull
  cursor**, immune to client clock skew. The client pulls rows with `server_seq > lastPulled`.
- **`deleted_at`** makes a delete a normal versioned row (a **tombstone**), so deletes sync like
  edits.
- `user_id` references `auth.users(id)`; **RLS** gates every operation on `auth.uid() = user_id`.

---

## Step 2.1 — Run the schema SQL

Open **Supabase → SQL Editor → New query**, paste the whole block, and **Run**. It is idempotent
enough to read top-to-bottom; if you re-run it, drop the objects first or ignore "already exists".

```sql
-- ============================================================
-- OpenGym cloud schema  (run once, in the Supabase SQL editor)
-- ============================================================

-- ---------- tables ----------
create table if not exists public.workout_plans (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  plan_color  bigint,                                  -- Flutter Color is a 32-bit ARGB uint (> int4 max); needs bigint
  data        jsonb not null,                          -- == WorkoutPlan.toJson()
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),      -- client-set: LWW tie-break
  server_seq  timestamptz not null default now(),      -- server-set: pull cursor
  deleted_at  timestamptz
);

create table if not exists public.workout_sessions (
  id           uuid primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  plan_id      uuid,                                    -- soft link (no FK)
  plan_name    text not null,
  week_number  int not null default 1,
  date         timestamptz not null,
  data         jsonb not null,                          -- == WorkoutSession.toJson()
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  server_seq   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- ---------- indexes (pull cursor + per-plan lookups) ----------
create index if not exists workout_plans_user_seq_idx
  on public.workout_plans (user_id, server_seq);
create index if not exists workout_sessions_user_seq_idx
  on public.workout_sessions (user_id, server_seq);
create index if not exists workout_sessions_user_plan_idx
  on public.workout_sessions (user_id, plan_id, week_number);

-- ---------- server_seq trigger (stamps server clock on every write) ----------
create or replace function public.touch_server_seq()
returns trigger as $$
begin
  new.server_seq := now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists t_plans_seq on public.workout_plans;
create trigger t_plans_seq
  before insert or update on public.workout_plans
  for each row execute function public.touch_server_seq();

drop trigger if exists t_sessions_seq on public.workout_sessions;
create trigger t_sessions_seq
  before insert or update on public.workout_sessions
  for each row execute function public.touch_server_seq();

-- ---------- Row-Level Security ----------
alter table public.workout_plans    enable row level security;
alter table public.workout_sessions enable row level security;

-- plans: four policies, all gated on ownership
drop policy if exists plans_own_select on public.workout_plans;
create policy plans_own_select on public.workout_plans
  for select using (auth.uid() = user_id);

drop policy if exists plans_own_insert on public.workout_plans;
create policy plans_own_insert on public.workout_plans
  for insert with check (auth.uid() = user_id);

drop policy if exists plans_own_update on public.workout_plans;
create policy plans_own_update on public.workout_plans
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists plans_own_delete on public.workout_plans;
create policy plans_own_delete on public.workout_plans
  for delete using (auth.uid() = user_id);

-- sessions: the same four policies
drop policy if exists sessions_own_select on public.workout_sessions;
create policy sessions_own_select on public.workout_sessions
  for select using (auth.uid() = user_id);

drop policy if exists sessions_own_insert on public.workout_sessions;
create policy sessions_own_insert on public.workout_sessions
  for insert with check (auth.uid() = user_id);

drop policy if exists sessions_own_update on public.workout_sessions;
create policy sessions_own_update on public.workout_sessions
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists sessions_own_delete on public.workout_sessions;
create policy sessions_own_delete on public.workout_sessions
  for delete using (auth.uid() = user_id);
```

> **Already ran the earlier version (with `plan_color int`)?** Widen the column in place — safe,
> non-destructive:
>
> ```sql
> alter table public.workout_plans alter column plan_color type bigint;
> ```

> **Why `server_seq` is `timestamptz`, not a bigint sequence:** `now()` inside one transaction is
> the transaction start time, so multiple rows written in the same push get the *same* `server_seq`.
> The client cursor uses **strictly-greater-than** (`server_seq > cursor`) and stores the **max**
> seen, so same-timestamp rows in one batch are fetched together and not skipped. This is sufficient
> at friends scale. (A monotonic bigint via a sequence is the upgrade path if you ever need strict
> per-row ordering.)

---

## Step 2.2 — Sanity-check the objects exist

In the SQL editor:

```sql
select table_name from information_schema.tables
  where table_schema = 'public'
  and table_name in ('workout_plans','workout_sessions');

select tablename, policyname, cmd from pg_policies
  where schemaname = 'public'
  order by tablename, policyname;
```

You should see both tables and **8 policies** (4 per table).

---

## Step 2.3 — Verify RLS isolation (two test accounts)

This is the most important verification in the whole project — get it right before Phase 3.

1. In the app (Phase 1 build) or via the Supabase **Authentication → Users → Add user**, create two
   accounts: **A** and **B**.
2. In the SQL editor you run as the table owner (RLS is bypassed for the owner), so to *test* RLS
   you must act as a user. Easiest path: use the app in Phase 3, or use the Supabase REST endpoint
   with each user's JWT. A quick manual check without app code:
   - Supabase **SQL editor** → run as a specific role isn't exposed directly, so instead verify the
     **policy predicates** are present and `rowsecurity` is on:

```sql
select relname, relrowsecurity
  from pg_class
  where relname in ('workout_plans','workout_sessions');
-- relrowsecurity must be true for both.
```

3. The functional cross-account check (A cannot see B's rows; an insert with a mismatched `user_id`
   is rejected by `with check`) is performed end-to-end in **Phase 3 verification** once the client
   can authenticate and push/pull. Note it here and confirm it there.

> **Do NOT disable RLS to "make sync work"** if you hit permission errors in Phase 3. A permission
> error means the client isn't stamping `user_id` correctly (Phase 3 has a defensive assert for
> exactly this) — fix the client, never loosen the policy.

---

## Rollback

```sql
drop table if exists public.workout_sessions cascade;
drop table if exists public.workout_plans cascade;
drop function if exists public.touch_server_seq();
```

(Triggers and policies drop with the tables via `cascade`.)

## Verification checklist

- [ ] Both tables exist (`information_schema.tables` query returns 2 rows).
- [ ] 8 policies exist (`pg_policies` query).
- [ ] `relrowsecurity` is `true` for both tables.
- [ ] `touch_server_seq` function + both triggers exist (visible under Database → Functions /
      Triggers, or re-running the trigger block reports "already exists").
- [ ] Cross-account isolation confirmed — **deferred to Phase 3** end-to-end test (note it, verify
      there).

*(No commit — this phase is server-side SQL. Keep the SQL text in the repo for reference, e.g. save
this file; do not put the service_role key or DB password in the repo.)*
