
create index split_preferences_active_owner_idx
  on public.split_preferences (active_split_id, user_id);

create index workout_plans_split_owner_idx
  on public.workout_plans (split_id, user_id);

create index workout_sessions_split_owner_idx
  on public.workout_sessions (split_id, user_id);

revoke all on table public.splits from authenticated;
revoke all on table public.split_preferences from authenticated;

grant select, insert, update on table public.splits to authenticated;
grant select, insert, update on table public.split_preferences to authenticated;
;
