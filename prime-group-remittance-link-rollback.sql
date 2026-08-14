-- Prime Braidox rollback for prime-group-remittance-link-setup.sql.
-- Use only if the historical receipt links need to be undone.

begin;

update public.pb_reconciliations r
set
  mpesa_reference = b.old_mpesa_reference,
  actual_amount_received = b.old_actual_amount_received
from public.pb_group_remittance_link_backup_20260814 b
where r.id = b.reconciliation_id;

update public.pb_mpesa_transactions t
set
  status = b.old_transaction_status,
  allocated_table = b.old_allocated_table,
  allocated_id = b.old_allocated_id,
  allocated_at = null
from public.pb_group_remittance_link_backup_20260814 b
where t.id = b.transaction_id;

select
  'Prime Braidox historical remittance links restored' as result,
  count(*) as links_restored,
  false as financial_data_changed
from public.pb_group_remittance_link_backup_20260814;

commit;
