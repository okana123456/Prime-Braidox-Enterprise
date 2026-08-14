-- Prime Braidox group-code payment audit
-- READ ONLY: this script does not insert, update, or delete any data.
-- Codes read from the client's note: 3006, 1248, 9301, 2487, 8776.

with target_codes(code) as (
  values ('3006'), ('1248'), ('9301'), ('2487'), ('8776')
),
groups_json as (
  select
    g.id,
    g.business_id,
    to_jsonb(g) as row_data,
    regexp_replace(coalesce(to_jsonb(g)->>'group_code', ''), '[^0-9A-Za-z]', '', 'g') as clean_code
  from public.pb_groups g
),
target_groups as (
  select g.*
  from groups_json g
  join target_codes c on upper(g.clean_code) = upper(c.code)
),
transactions_json as (
  select
    t.id,
    t.business_id,
    to_jsonb(t) as row_data,
    regexp_replace(coalesce(to_jsonb(t)->>'account_reference', ''), '[^0-9A-Za-z]', '', 'g') as clean_reference,
    coalesce(
      nullif(to_jsonb(t)->>'transaction_time', ''),
      nullif(to_jsonb(t)->>'trans_time', ''),
      nullif(to_jsonb(t)->>'created_at', '')
    ) as received_at
  from public.pb_mpesa_transactions t
),
target_transactions as (
  select
    t.*,
    c.code as expected_code,
    g.id as matched_group_by_code,
    g.row_data->>'name' as matched_group_name_by_code
  from transactions_json t
  join target_codes c on upper(t.clean_reference) = upper(c.code)
  left join groups_json g
    on g.business_id is not distinct from t.business_id
   and upper(g.clean_code) = upper(c.code)
),
sections as (
  select
    1 as section_order,
    '01_target_group_codes'::text as section,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'code', c.code,
          'group_found', g.id is not null,
          'business_id', g.business_id,
          'group_id', g.id,
          'group_name', g.row_data->>'name',
          'stored_group_code', g.row_data->>'group_code',
          'officer_id', g.row_data->>'officer_id',
          'status', coalesce(g.row_data->>'status', g.row_data->>'is_active')
        ) order by c.code, g.row_data->>'name'
      ),
      '[]'::jsonb
    ) as result
  from target_codes c
  left join target_groups g on upper(g.clean_code) = upper(c.code)

  union all

  select
    2,
    '02_duplicate_group_codes',
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'business_id', d.business_id,
          'code', d.clean_code,
          'number_of_groups', d.group_count,
          'groups', d.groups
        ) order by d.business_id, d.clean_code
      ),
      '[]'::jsonb
    )
  from (
    select
      business_id,
      clean_code,
      count(*) as group_count,
      jsonb_agg(jsonb_build_object('id', id, 'name', row_data->>'name')) as groups
    from groups_json
    where clean_code <> ''
    group by business_id, clean_code
    having count(*) > 1
  ) d

  union all

  select
    3,
    '03_transactions_received_for_target_codes',
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'received_at', tt.received_at,
          'business_id', tt.business_id,
          'receipt', coalesce(tt.row_data->>'trans_id', tt.row_data->>'receipt_number'),
          'amount', tt.row_data->>'amount',
          'account_reference_received', tt.row_data->>'account_reference',
          'expected_code', tt.expected_code,
          'stored_group_id', tt.row_data->>'group_id',
          'group_found_by_code', tt.matched_group_name_by_code,
          'transaction_type', tt.row_data->>'transaction_type',
          'status', tt.row_data->>'status',
          'finding', case
            when tt.matched_group_by_code is null then 'Payment arrived, but no group in this business has this code'
            when nullif(tt.row_data->>'group_id', '') is null then 'Payment arrived but callback left it unmatched'
            when tt.row_data->>'group_id' <> tt.matched_group_by_code::text then 'Payment was linked to a different group'
            else 'Payment arrived and matched the expected group'
          end
        ) order by tt.received_at desc nulls last
      ),
      '[]'::jsonb
    )
  from target_transactions tt

  union all

  select
    4,
    '04_summary_by_code',
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'code', c.code,
          'groups_found', coalesce(g.group_count, 0),
          'payments_received', coalesce(t.payment_count, 0),
          'latest_payment_received_at', t.latest_received_at,
          'matched_payments', coalesce(t.matched_count, 0),
          'unmatched_payments', coalesce(t.unmatched_count, 0),
          'diagnosis', case
            when coalesce(g.group_count, 0) = 0 then 'Code is not assigned to a group in pb_groups'
            when g.group_count > 1 then 'Code is duplicated and cannot identify one group safely'
            when coalesce(t.payment_count, 0) = 0 then 'No callback transaction for this code is stored in this Supabase project'
            when coalesce(t.unmatched_count, 0) > 0 then 'Callback received payment, but matching failed'
            else 'Stored callback transactions match this group code'
          end
        ) order by c.code
      ),
      '[]'::jsonb
    )
  from target_codes c
  left join (
    select clean_code, count(*) as group_count
    from groups_json
    group by clean_code
  ) g on upper(g.clean_code) = upper(c.code)
  left join (
    select
      expected_code,
      count(*) as payment_count,
      max(received_at) as latest_received_at,
      count(*) filter (
        where nullif(row_data->>'group_id', '') is not null
          and row_data->>'group_id' = matched_group_by_code::text
      ) as matched_count,
      count(*) filter (
        where nullif(row_data->>'group_id', '') is null
           or matched_group_by_code is null
           or row_data->>'group_id' <> matched_group_by_code::text
      ) as unmatched_count
    from target_transactions
    group by expected_code
  ) t on upper(t.expected_code) = upper(c.code)

  union all

  select
    5,
    '05_recent_unmatched_account_references',
    coalesce(
      jsonb_agg(u.item order by u.received_at desc nulls last),
      '[]'::jsonb
    )
  from (
    select
      t.received_at,
      jsonb_build_object(
        'received_at', t.received_at,
        'business_id', t.business_id,
        'receipt', coalesce(t.row_data->>'trans_id', t.row_data->>'receipt_number'),
        'amount', t.row_data->>'amount',
        'account_reference_received', t.row_data->>'account_reference',
        'cleaned_reference', t.clean_reference,
        'transaction_type', t.row_data->>'transaction_type',
        'status', t.row_data->>'status'
      ) as item
    from transactions_json t
    where nullif(t.row_data->>'group_id', '') is null
       or coalesce(t.row_data->>'transaction_type', 'unmatched') = 'unmatched'
    order by t.received_at desc nulls last
    limit 100
  ) u

)
select section_order, section, result
from sections
order by section_order;
