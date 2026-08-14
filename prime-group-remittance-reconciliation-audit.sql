-- Prime Braidox group-remittance reconciliation audit
-- READ ONLY: no balances, payments, savings, or loans are changed.

with target_codes(code) as (
  values ('3006'), ('1248'), ('9301'), ('2487'), ('8776')
),
target_groups as (
  select
    g.id,
    g.business_id,
    g.name,
    g.group_code
  from public.pb_groups g
  join target_codes c
    on regexp_replace(coalesce(g.group_code, ''), '[^0-9A-Za-z]', '', 'g') = c.code
),
target_transactions as (
  select
    t.id,
    t.business_id,
    t.group_id,
    t.trans_id,
    t.amount,
    t.account_reference,
    t.transaction_type,
    t.status as transaction_status,
    coalesce(
      nullif(to_jsonb(t)->>'transaction_time', ''),
      nullif(to_jsonb(t)->>'trans_time', ''),
      nullif(to_jsonb(t)->>'created_at', '')
    ) as received_at
  from public.pb_mpesa_transactions t
  join target_codes c
    on regexp_replace(coalesce(t.account_reference, ''), '[^0-9A-Za-z]', '', 'g') = c.code
),
reconciliations_json as (
  select
    r.id,
    r.business_id,
    r.group_id,
    r.meeting_date,
    r.status as reconciliation_status,
    r.mpesa_reference,
    r.total_savings,
    r.total_repayments,
    r.grand_total,
    to_jsonb(r) as row_data
  from public.pb_reconciliations r
)
select
  t.received_at,
  g.name as group_name,
  g.group_code,
  t.trans_id as mpesa_receipt,
  t.amount as amount_received,
  t.transaction_status,
  r.id as remittance_record_id,
  r.meeting_date,
  r.reconciliation_status,
  r.total_savings as savings_recorded_for_meeting,
  r.total_repayments as repayments_recorded_for_meeting,
  r.grand_total as expected_group_total,
  nullif(r.row_data->>'actual_amount_received', '')::numeric as amount_admin_confirmed,
  case
    when r.id is null then
      'Payment reached the correct group, but no remittance record is linked using this M-Pesa receipt'
    when r.reconciliation_status <> 'confirmed' then
      'Remittance was logged but still awaits admin confirmation'
    when coalesce(nullif(r.row_data->>'actual_amount_received', '')::numeric, r.grand_total, 0) <> t.amount then
      'Remittance is confirmed, but its confirmed amount differs from the callback amount'
    when coalesce(r.grand_total, 0) <> t.amount then
      'Payment is linked, but meeting savings plus repayments differ from the amount received'
    else
      'Payment is fully linked and reconciled with the meeting records'
  end as finding
from target_transactions t
join target_groups g
  on g.id = t.group_id
 and g.business_id is not distinct from t.business_id
left join reconciliations_json r
  on r.business_id is not distinct from t.business_id
 and r.group_id = t.group_id
 and upper(regexp_replace(coalesce(r.mpesa_reference, ''), '[^0-9A-Za-z]', '', 'g')) =
     upper(regexp_replace(coalesce(t.trans_id, ''), '[^0-9A-Za-z]', '', 'g'))
order by t.received_at desc, g.name;
