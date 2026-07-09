-- Prime Braidox deposit deduction diagnostic
-- Shows active loans that require a 25% deposit and whether recorded deposit
-- installments reduce the client's effective outstanding balance.

with deposit_totals as (
  select
    member_id,
    sum(coalesce(amount, 0)) as total_deposit_paid
  from public.pb_savings
  where type = 'deposit'
    and coalesce(status, '') <> 'rejected'
  group by member_id
),
repayment_totals as (
  select
    loan_id,
    sum(coalesce(amount, 0)) as repayment_paid
  from public.pb_repayments
  where coalesce(status, '') <> 'pending'
  group by loan_id
),
deposit_loans as (
  select
    l.*,
    row_number() over (
      partition by l.member_id
      order by l.start_date nulls last, l.id
    ) as deposit_loan_order
  from public.pb_loans l
  where l.status = 'active'
    and coalesce(l.loan_value, 0) > 20000
),
allocated as (
  select
    dl.id as loan_id,
    dl.member_id,
    dl.group_id,
    dl.asset_name,
    dl.start_date,
    coalesce(dl.loan_value, 0) as loan_value,
    coalesce(dl.total_payable, 0) as total_payable,
    round(coalesce(dl.loan_value, 0) * 0.25, 2) as required_deposit,
    coalesce(dt.total_deposit_paid, 0) as member_total_deposit_paid,
    coalesce(rt.repayment_paid, 0) as repayment_paid,
    least(
      round(coalesce(dl.loan_value, 0) * 0.25, 2),
      greatest(
        0,
        coalesce(dt.total_deposit_paid, 0)
        - coalesce(sum(round(coalesce(dl.loan_value, 0) * 0.25, 2)) over (
            partition by dl.member_id
            order by dl.start_date nulls last, dl.id
            rows between unbounded preceding and 1 preceding
          ), 0)
      )
    ) as deposit_applied_to_this_loan
  from deposit_loans dl
  left join deposit_totals dt on dt.member_id = dl.member_id
  left join repayment_totals rt on rt.loan_id = dl.id
)
select
  a.loan_id,
  m.full_name as client_name,
  g.name as group_name,
  a.asset_name,
  a.loan_value,
  a.total_payable,
  a.required_deposit,
  a.member_total_deposit_paid,
  a.deposit_applied_to_this_loan,
  a.repayment_paid,
  round(a.total_payable - a.repayment_paid, 2) as old_outstanding_without_deposit,
  round(a.total_payable - a.repayment_paid - a.deposit_applied_to_this_loan, 2) as corrected_outstanding_after_deposit
from allocated a
left join public.pb_members m on m.id = a.member_id
left join public.pb_groups g on g.id = a.group_id
where a.member_total_deposit_paid > 0
order by a.start_date desc, client_name;
