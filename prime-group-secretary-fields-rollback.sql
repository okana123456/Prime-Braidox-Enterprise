begin;

do $$
begin
  if exists (
    select 1
    from public.pb_groups
    where coalesce(secretary_name,'') <> ''
       or coalesce(secretary_phone,'') <> ''
  ) then
    raise exception 'Rollback stopped: secretary data exists in pb_groups. Export or migrate those values before dropping the columns.';
  end if;
end $$;

alter table public.pb_groups
  drop column if exists secretary_phone,
  drop column if exists secretary_name;

commit;
