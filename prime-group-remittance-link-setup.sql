-- Prime Braidox: safely link exact historical group remittances to M-Pesa receipts.
-- This does not insert or alter savings, repayments, loans, or balances.

begin;

create table if not exists public.pb_group_remittance_link_backup_20260814 (
  reconciliation_id uuid primary key,
  old_mpesa_reference text,
  old_actual_amount_received numeric,
  transaction_id uuid,
  old_transaction_status text,
  old_allocated_table text,
  old_allocated_id uuid,
  backed_up_at timestamptz not null default now()
);

create table if not exists public.pb_group_remittance_exact_links_20260814 as
with transaction_rows as (
  select
    t.*,
    coalesce(
      nullif(to_jsonb(t)->>'transaction_time', ''),
      nullif(to_jsonb(t)->>'trans_time', ''),
      nullif(to_jsonb(t)->>'created_at', '')
    ) as raw_received_at
  from public.pb_mpesa_transactions t
  where t.transaction_type = 'group_remittance'
),
dated_transactions as (
  select
    t.*,
    case
      when t.raw_received_at ~ '^[0-9]{14}$'
        then to_date(substr(t.raw_received_at, 1, 8), 'YYYYMMDD')
      when t.raw_received_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
        then (t.raw_received_at::timestamptz at time zone 'Africa/Nairobi')::date
      else null
    end as kenya_payment_date
  from transaction_rows t
),
candidates as (
  select
    r.id as reconciliation_id,
    t.id as transaction_id,
    t.trans_id,
    t.amount,
    count(*) over (partition by r.id) as transactions_for_remittance,
    count(*) over (partition by t.id) as remittances_for_transaction
  from public.pb_reconciliations r
  join dated_transactions t
    on t.business_id is not distinct from r.business_id
   and t.group_id = r.group_id
   and t.kenya_payment_date = r.meeting_date
   and abs(t.amount - coalesce(r.actual_amount_received, r.grand_total, 0)) < 0.01
  where nullif(btrim(r.mpesa_reference), '') is null
)
select reconciliation_id, transaction_id, trans_id, amount
from candidates
where transactions_for_remittance = 1
  and remittances_for_transaction = 1;

insert into public.pb_group_remittance_link_backup_20260814 (
  reconciliation_id,
  old_mpesa_reference,
  old_actual_amount_received,
  transaction_id,
  old_transaction_status,
  old_allocated_table,
  old_allocated_id
)
select
  r.id,
  r.mpesa_reference,
  r.actual_amount_received,
  t.id,
  t.status,
  t.allocated_table,
  t.allocated_id
from public.pb_group_remittance_exact_links_20260814 x
join public.pb_reconciliations r on r.id = x.reconciliation_id
join public.pb_mpesa_transactions t on t.id = x.transaction_id
on conflict (reconciliation_id) do nothing;

update public.pb_reconciliations r
set
  mpesa_reference = x.trans_id,
  actual_amount_received = x.amount
from public.pb_group_remittance_exact_links_20260814 x
where r.id = x.reconciliation_id;

update public.pb_mpesa_transactions t
set
  status = 'allocated',
  allocated_table = 'pb_reconciliations',
  allocated_id = x.reconciliation_id,
  allocated_at = now()
from public.pb_group_remittance_exact_links_20260814 x
where t.id = x.transaction_id;

select
  'Prime Braidox remittance linking is ready' as result,
  count(*) as exact_historical_links_created,
  false as savings_changed,
  false as repayments_changed,
  false as loan_balances_changed
from public.pb_group_remittance_exact_links_20260814;

commit;
