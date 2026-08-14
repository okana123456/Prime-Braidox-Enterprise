-- Prime Braidox remittance-link verification. READ ONLY.

with target_codes(code) as (
  values ('3006'), ('1248'), ('9301'), ('2487'), ('8776')
),
target_transactions as (
  select t.*
  from public.pb_mpesa_transactions t
  join target_codes c
    on regexp_replace(coalesce(t.account_reference, ''), '[^0-9A-Za-z]', '', 'g') = c.code
),
checks as (
  select
    count(*) as payments_received,
    count(*) filter (where r.id is not null) as payments_linked_to_remittances,
    count(*) filter (where r.status = 'confirmed') as payments_fully_reconciled,
    count(*) filter (where r.id is null) as payments_awaiting_remittance_log,
    count(*) filter (where r.id is not null and r.status <> 'confirmed') as payments_awaiting_admin_confirmation
  from target_transactions t
  left join public.pb_reconciliations r
    on r.business_id is not distinct from t.business_id
   and r.group_id = t.group_id
   and upper(regexp_replace(coalesce(r.mpesa_reference, ''), '[^0-9A-Za-z]', '', 'g')) =
       upper(regexp_replace(coalesce(t.trans_id, ''), '[^0-9A-Za-z]', '', 'g'))
)
select
  payments_received,
  payments_linked_to_remittances,
  payments_fully_reconciled,
  payments_awaiting_remittance_log,
  payments_awaiting_admin_confirmation,
  false as financial_data_changed
from checks;
