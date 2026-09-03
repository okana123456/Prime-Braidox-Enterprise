begin;

select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='pb_groups'
  and column_name in ('secretary_name','secretary_phone')
order by column_name;

create table if not exists public.pb_group_secretary_fields_backup as
select
  id,
  business_id,
  name,
  now() as backed_up_at
from public.pb_groups
where false;

alter table public.pb_groups
  add column if not exists secretary_name text,
  add column if not exists secretary_phone text;

commit;
