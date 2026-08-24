# Prime Braidox Enterprise - Technical Handover

Last reviewed: 24 August 2026

This document covers **Prime Braidox Enterprise only**. Do not reuse assumptions, database scripts, project references, callbacks, or business rules from Wamama, Bripta/Loanflow, PrimeCredit, Radari, or any other system.

## 1. System purpose and users

Prime Braidox Enterprise is a multi-user lending, group savings, inventory, order, repayment, remittance, and reporting system. It supports the full operating cycle from registering groups and members through issuing asset-backed loans, collecting repayments and savings, reconciling group remittances, and reviewing staff performance.

Primary users:

- **Administrator:** full business access, approvals, staff management, settings, reporting, remittance reconciliation, inventory, and subscription payment.
- **Loan officer/officer:** sees assigned groups and portfolio, records repayments and savings through Active Loans, creates permitted orders, and uses an officer-specific dashboard.
- **Other staff:** access is controlled through `pb_permissions` and should remain limited to explicitly assigned duties.

Loan officers do not self-register. The administrator creates their accounts from Staff & Permissions.

## 2. Repository and branch

- GitHub repository: `okana123456/Prime-Braidox-Enterprise`
- Remote: `https://github.com/okana123456/Prime-Braidox-Enterprise.git`
- Branch: `main`
- Verified local repository: `C:\Users\Admin\Documents\Codex\2026-07-01\ho\work\prime-braidox-update`
- Commit reviewed when this handover was prepared: `40090cf`

Before changing anything in a new task:

1. Confirm the current repository path is the one above.
2. Pull `origin/main` and inspect any newer commits.
3. Check `git status` and preserve all user changes.
4. Do not work from an old copy named similarly elsewhere on the Desktop or under another system folder.

## 3. Technology stack

- Single-page application in one large `index.html` file.
- Plain HTML, CSS, and JavaScript; no build step is currently required.
- Supabase JavaScript client v2 loaded from a CDN.
- Supabase Auth for user sessions.
- Supabase PostgreSQL/PostgREST for business data.
- Supabase Realtime for live updates.
- Supabase Edge Functions for Daraja and monthly subscription flows.
- SheetJS/XLSX for Excel import/export.
- Local browser storage for scoped caching and an offline insert queue.
- Inline PWA manifest and icon assets for installable-app behavior.
- GitHub for source control and Vercel for web deployment.

## 4. Important files

### Application

- `index.html` - complete frontend, styling, routing, authentication, data loading, calculations, reports, dialogs, PWA setup, and Supabase calls.

### Database audit and repair scripts

- `prime-deposit-loan-deduction-check.sql` - read-only audit of required deposits, recorded deposits, repayments, and corrected loan outstanding balances.
- `prime-group-code-payment-audit.sql` - read-only group-code and payment audit.
- `prime-group-code-payment-audit-v2.sql` - updated audit that avoids assumptions about `pb_settings` columns.
- `prime-group-remittance-reconciliation-audit.sql` - read-only comparison of group remittances and incoming M-Pesa payments.
- `prime-group-remittance-link-setup.sql` - transactionally creates exact historical remittance links and backup data.
- `prime-group-remittance-link-verification.sql` - read-only verification after linking.
- `prime-group-remittance-link-rollback.sql` - restores the remittance-link fields from the backup created by the setup script.

There is currently **no local `supabase/functions` directory** in this repository. Edge Function source must be downloaded from the Prime Braidox Supabase project or restored into the repository before it is edited. Never invent or copy a similarly named function from another system without comparing table names, callbacks, and business rules.

## 5. Current architecture

### Frontend flow

1. Supabase Auth signs the user in.
2. `pb_staff` maps the authenticated user to a business and role.
3. `pb_permissions` supplies granular permissions.
4. The app loads the current business settings and subscription status.
5. It loads business-scoped records from the operational `pb_*` tables.
6. The page renders the administrator dashboard or the officer dashboard.
7. Writes go to Supabase; short network interruptions can place supported inserts in a local queue for later synchronization.
8. Realtime subscriptions update local state as database rows change.

### Data isolation

Most frontend reads and writes include `business_id`, but frontend filtering is not a security boundary. Row Level Security must restrict every tenant table to the signed-in user's `pb_staff.business_id`.

The application currently uses:

- Supabase project reference: `zkklawvlnhtaokhtjswk`
- A public anon key embedded in `index.html`, which is normal only when strong RLS is active.
- Business-scoped local-storage keys.
- Auth storage key `pb-main-auth`.

Do not place a service-role key, Daraja secret, consumer secret, or passkey in `index.html`.

### Loading and caching

The current loader requests up to 5,000 rows from each operational table in parallel and caches results locally. This makes offline recovery possible but will become an egress and performance risk as the business grows. Realtime currently listens broadly to public-schema changes. Recommended improvements are documented below.

## 6. Authentication, roles, and permissions

- Supabase email/password authentication is used.
- Sessions persist and auto-refresh.
- Inactivity timeout is currently four hours.
- A keepalive attempts a session refresh every 30 minutes.
- Business registration calls the `pb_register_business_admin` database RPC.
- Staff deletion may call `pb_delete_staff_auth`.
- Staff records must be active and linked to the Supabase Auth user through `auth_user_id`.
- Administrators receive the monthly subscription reminder/lock; ordinary officers are not the billing account owner.

The business registration key is currently present in frontend code. That is not secure because every browser can inspect it. A future security pass should move registration-key validation into an Edge Function or security-definer RPC and rotate the key.

## 7. Database structure

Important tables confirmed in the frontend:

| Table | Purpose |
|---|---|
| `pb_staff` | Auth user, business, role, name, contact, and status |
| `pb_permissions` | Per-staff permission flags |
| `pb_settings` | Business settings, rates, thresholds, name, and collection configuration |
| `pb_groups` | Groups, meeting details, assigned officer, and M-Pesa/group code |
| `pb_members` | Member/client identity, phone, ID number, group, and status |
| `pb_guarantors` | Loan guarantor information |
| `pb_inventory` | Assets/products, prices, quantities, and stock state |
| `pb_orders` | Member asset orders and approval workflow |
| `pb_loans` | Loan principal, total payable, term, dates, member, group, officer, asset, and status |
| `pb_savings` | Ordinary savings, registration instalments, and asset-deposit instalments |
| `pb_repayments` | Loan repayment entries, principal/interest allocation, approval status, and source |
| `pb_meetings` | Group meeting records |
| `pb_reconciliations` | Chairman/group remittance records and linked M-Pesa references |
| `pb_mpesa_transactions` | Daraja C2B callback transactions, matching, and allocation status |
| `pb_suppliers` | Supplier directory |
| `pb_purchases` | Inventory purchase headers |
| `pb_purchase_lines` | Purchase line items |
| `pb_expenses` | Business expenses |
| `pb_audit_log` | User and operational audit events |
| `pb_billing_cycles` | Monthly subscription state per business |

Core relationships:

- Auth user -> `pb_staff.auth_user_id`
- Staff -> `business_id`
- Group -> assigned officer
- Member -> group
- Loan -> member, group, and officer
- Savings -> member, group, meeting, and recorder
- Repayment -> loan, member, group, meeting, and recorder
- Reconciliation -> group and optional M-Pesa transaction/reference
- Operational rows -> `business_id`

Do not rename columns or change types without checking all inline queries in `index.html`, RPC functions, RLS policies, and Edge Functions.

## 8. Important business rules

### Members and groups

- A member belongs to a group and has a searchable name, phone, and ID number.
- Groups have short numeric M-Pesa account codes.
- Group search fields should filter while typing and must not lose focus after each character.
- Member ID number is editable from member details.

### Savings and eligibility

- Ordinary savings use `type = 'savings'`.
- Registration payments use `type = 'registration'`.
- Asset/loan deposits use `type = 'deposit'`.
- Ordinary savings totals must not include registration or deposit rows.
- Default settings currently include a KES 900 savings eligibility threshold and KES 200 registration fee, but administrators can change settings.

### Loans and deposits

- Loans over KES 20,000 require a 25% deposit.
- The deposit is not automatically deducted at issue time.
- It can be collected once or in instalments through Active Loans > Record Saving.
- Recorded deposit instalments reduce the effective outstanding amount for eligible loans.
- When a member has more than one qualifying active loan, deposits are allocated oldest loan first.
- Loan repayment history and client performance information are available from the member profile.
- A 14-day demand letter can be downloaded for collection follow-up.
- The former rule that doubled the next instalment after a missed payment was removed. Do not reintroduce it.

### Officer workflow

- Officers no longer use Meeting Recorder.
- Officers record repayment and saving/deposit entries from Active Loans.
- Officer dashboards are restricted to their assigned portfolio.
- Each officer sees the amount expected from their portfolio on the selected day.
- The administrator dashboard can review expected daily collections by officer and officer portfolio performance.
- Loan officers should see only appropriate inventory item and loan-price information.

### Orders

- Authorized officers can create client orders.
- Pending orders can be reviewed and edited by administrators before approval.
- Administrators can add or remove assets before approval.
- Order member/group search supports typed filtering.

### Remittances and M-Pesa collections

- A chairman or treasurer pays the business Paybill using the group's code as the account reference.
- Individual or late member payments may use the registered phone and relevant group code.
- Incoming C2B callbacks are stored in `pb_mpesa_transactions`.
- The system attempts to match transactions to the group and reconciliation record.
- Unmatched or ambiguous payments require administrator review; do not force-match uncertain records.
- Historical remittance linking scripts only change reconciliation/allocation metadata. They must not alter savings, repayments, or loan balances.
- M-Pesa timestamps displayed to users must use Kenya time.

### Monthly system subscription

- Current Prime Braidox subscription: KES 3,000 per month.
- The administrator sees a reminder before the lock date.
- If the current month remains unpaid, administrator access locks on day 3.
- Successful payment updates `pb_billing_cycles` and reopens the administrator account.
- The frontend invokes `start-billing-payment` for the STK prompt.

## 9. Completed functionality

- Business registration and email/password authentication.
- Business-scoped staff registry and permissions.
- Administrator and officer dashboards.
- Working manual refresh that preserves the current screen.
- Groups and members with typed search and filtering.
- Member ID-number editing.
- Member profile, loan history, repayment history, and performance rating.
- Client performance indicators for previous delays/default behavior.
- Savings, registration instalments, and loan-deposit instalments.
- Deposit-aware effective loan balances.
- Active Loans repayment and savings recording.
- Daily expected collection totals for admin and individual officers.
- Officer portfolio visibility on the main system.
- All-time savings dashboard information.
- Due and arrears monitoring.
- Downloadable 14-day demand letter.
- Inventory, suppliers, purchases, and expenses.
- Order creation, review, editing, approval, and rejection.
- Administrator editing of order assets before approval.
- Remittance logging, typed group search, reconciliation, and M-Pesa matching.
- Repayment and M-Pesa times displayed in Kenya time.
- Reports, accounting summaries, and Excel exports.
- Mobile-responsive layout, dark mode, and installable PWA behavior.
- Offline cache and queued inserts for supported operations.

## 10. Supabase Edge Functions and secrets

### Functions used by the current design

- `start-billing-payment` - starts the KES 3,000 monthly subscription STK prompt.
- `billing-payment-callback` - receives the subscription STK result and updates billing tables.
- `collections-register-urls` - registers the business collection callback URLs with Daraja.
- `collections-callback` - receives client/group C2B payment callbacks and records them for matching.
- A Daraja credential diagnostic/check function may exist in the Supabase project; confirm its exact deployed name before relying on it.

The deployed function list and source must be verified in Supabase because the current Git repository does not contain those files.

### Required secret names

Store values in Supabase Edge Function Secrets, not Git:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `DARAJA_CONSUMER_KEY`
- `DARAJA_CONSUMER_SECRET`
- `DARAJA_PASSKEY`
- `DARAJA_SHORTCODE`
- `DARAJA_TRANSACTION_TYPE`
- `BILLING_AMOUNT`
- `BILLING_ACCOUNT_REFERENCE`
- `BILLING_DESCRIPTION`

For a Paybill STK request, `DARAJA_TRANSACTION_TYPE` is normally `CustomerPayBillOnline`.

Never write secret values into this handover. Rotate any credential that was previously pasted into chat, screenshots, source code, or public Git history.

### Daraja callback rule

A Safaricom shortcode normally has one active C2B confirmation/validation destination. If the same shortcode serves multiple systems, use a deliberate routing gateway that inspects the account reference and forwards the transaction to the correct system. Otherwise, use separate shortcodes. Do not register one system's callback over another system's live callback.

## 11. Deployment information

### GitHub and Vercel

1. Make edits only in the verified local repository.
2. Review the GitHub Desktop diff.
3. Commit to `main` with a descriptive message.
4. Push `origin/main`.
5. Confirm Vercel deploys the latest commit.
6. Test both desktop and phone views after deployment.

The exact production Vercel/custom-domain URL is not stored in this repository handover. Confirm it from the Vercel project before changing Supabase Auth redirect URLs.

### Supabase

The application currently points to project reference `zkklawvlnhtaokhtjswk`. Before moving or cloning the system, update all of the following together:

- Supabase URL and anon key in `index.html`.
- Auth Site URL and allowed redirect URLs.
- Database schema, RPCs, triggers, indexes, and RLS policies.
- Edge Function deployments and secrets.
- Daraja callback URLs registered with Safaricom.
- Any callback URL displayed in Settings.

## 12. Safe database-change procedure

For every financial or relationship correction:

1. Run a read-only audit and record the exact affected rows.
2. Confirm IDs, business scope, dates, and amounts.
3. Create a narrowly scoped backup table when historical rows will change.
4. Run the change inside a transaction.
5. Verify row counts and financial totals immediately.
6. Keep and test a rollback script.
7. Confirm the UI after a fresh login.

Never run a bulk loan, repayment, savings, or remittance update based only on a name. Prefer stable IDs and require exact one-to-one matching.

## 13. Known risks and technical debt

- The business registration key is exposed in frontend source and should move server-side.
- The app loads up to 5,000 rows from many tables on each full refresh. This can become slow and expensive.
- Realtime listens broadly to public-schema changes and should be filtered to the active business where Supabase supports the required filter.
- Full datasets are cached in local storage; large businesses may exceed browser storage limits.
- Offline writes are queued as inserts only. Complex updates, approvals, and financial actions still require reliable online confirmation.
- The application is a very large single HTML file, which increases regression risk.
- Edge Function source is not versioned in this repository.
- RLS is essential but cannot be proven from frontend source alone. Audit it in Supabase before onboarding another business.
- Several business rules are calculated in JavaScript. Critical balance and approval rules should progressively move into tested database functions.
- `todayISO()` uses UTC in several places. Kenya-date behavior must be tested around midnight even though M-Pesa display formatting has been corrected.
- The frontend contains hard-coded billing display values. If the fee changes, update the frontend, `BILLING_AMOUNT`, Edge Functions, and database defaults together.

## 14. Unfinished work and recommended next tasks

Priority order:

1. Download all deployed Prime Braidox Edge Function source and commit it under `supabase/functions`.
2. Export and version the canonical Supabase schema, RPCs, triggers, indexes, and RLS policies as migrations.
3. Move business registration authorization server-side and rotate the registration key.
4. Audit RLS for every `pb_*` table using two test businesses to prove isolation.
5. Replace full-table loading with paginated or date-bounded queries and compact dashboard RPCs.
6. Filter Realtime by business and subscribe only to tables required by the current screen.
7. Add automated tests for deposit allocation, outstanding balance, arrears, expected collection, remittance matching, and billing unlock.
8. Split `index.html` into maintainable modules after test coverage exists.
9. Add a deployment checklist that verifies Auth redirects, callbacks, PWA install, phone layout, and Kenya time.
10. Confirm database constraints prevent duplicate group codes within one business.

## 15. Regression checklist

After any substantial change, verify:

- Admin and officer login.
- Officer cannot see another officer's unauthorized portfolio.
- A second business cannot read Prime Braidox data.
- Dashboard totals match database totals.
- Group/member search works without losing focus.
- Member ID is viewable and editable.
- Officer records repayment and saving from Active Loans.
- Deposit instalments reduce only the intended loan's effective balance.
- Missed instalments do not double the next instalment.
- Expected collection totals are correct for admin and officer.
- Orders can be edited before approval without changing unrelated inventory.
- Remittances match the correct group code and date.
- Unmatched C2B payments remain reviewable.
- M-Pesa time is correct in Africa/Nairobi.
- Subscription STK prompt, callback, reminder, lock, and unlock all work.
- Demand letters and Excel exports open correctly.
- Mobile navigation and PWA installation still work.

## 16. Starting a new Codex task

Use this opening message:

> Work only on Prime Braidox Enterprise. Read `PRIME_BRAIDOX_HANDOVER.md` first, then inspect the current `main` branch at `C:\Users\Admin\Documents\Codex\2026-07-01\ho\work\prime-braidox-update`. Confirm the Git remote and current changes before editing. Do not use code, database assumptions, callbacks, or business rules from Wamama, Bripta/Loanflow, PrimeCredit, Radari, or any other system. Preserve existing financial data and use audit-first, backup, verification, and rollback steps for database changes.

The new task must still inspect the current code. This handover is context, not a substitute for verifying the latest implementation.
