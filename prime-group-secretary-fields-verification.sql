select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='pb_groups'
  and column_name in ('secretary_name','secretary_phone')
order by column_name;

select
  count(*) as total_groups,
  count(*) filter (where coalesce(secretary_name,'') <> '') as groups_with_secretary_name,
  count(*) filter (where coalesce(secretary_phone,'') <> '') as groups_with_secretary_phone
from public.pb_groups;
