
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

revoke execute on function public.cascade_split_tombstone()
  from public, anon, authenticated;
;
