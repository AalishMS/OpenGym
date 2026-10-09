
revoke all on table public.workout_plans from authenticated;
revoke all on table public.workout_sessions from authenticated;

grant select, insert, update, delete on table public.workout_plans to authenticated;
grant select, insert, update, delete on table public.workout_sessions to authenticated;
;
