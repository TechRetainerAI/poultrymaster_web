# Balance / payment-allocation checks

Behavioural tests for the Customer Balances and Supplier Balances payment
allocation layer (migrations 222–224, and 238–239 for expenses as payables). They exercise the real stored functions
against real data and then **roll everything back**, so they are safe to run
against dev — and, carefully, against prod.

Each script is a single `DO $t$ ... $t$` block that RAISEs a NOTICE per check in
the form `expect X got Y`, plus a set of negative cases that must each be
blocked. Nothing is asserted by the runner: read the output and look for a line
where `expect` and `got` disagree, or a `<-- BUG` marker on a negative case that
was allowed through.

## Running them

They must run **inside a transaction that is rolled back**, because they create
customers, sales and purchases. Wrap them yourself:

```powershell
$env:PGPASSWORD='<password>'
cd <repo>\poultrycore-main\database\checks
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" `
  -h <host> -p 5432 -U poultryapp -d VisibilityCoreDB -X `
  -c "BEGIN;" -f poultry-customer-balances.test.sql -c "ROLLBACK;"
```

Or, to validate an unapplied migration and its behaviour in one pass, concatenate
the migration files (with their own `BEGIN;`/`COMMIT;` stripped) ahead of the test
body inside a single `BEGIN; … ROLLBACK;`. That is how 222–224 were verified
before they were ever applied: a rolled-back run validates syntax *and* end-to-end
behaviour without touching a single committed row.

**The farm id and cash account id at the top of each file are hardcoded** to a
dev company. Change them before running anywhere else — a farm with no cash
accounts, or with `allownegativebalance` set differently, will fail checks that
are actually fine.

## What they cover

`poultry-customer-balances.test.sql` — 23 checks
- balance rollup equals the sum of open sale balances
- a part payment moves cash (the behaviour migration 223 fixed)
- bulk payment across two sales: per-sale `amountpaid`, the `paid` flag, the
  untouched third sale, one cash movement, two allocations
- statement line count, closing balance, and a windowed opening balance
- reversal restores balances and cash exactly
- `fnbalanceaudit` stays empty throughout
- blocked: under-allocation, over-allocation, unknown customer, another
  company's sale, double reversal, the same sale twice, another farm's cash
  account

`poultry-supplier-balances.test.sql` — 26 checks
- the same shape on the payables side, over both document types
- **no double-counted cash**: the payment's CashOut and the purchase's own
  collapsed line stay disjoint
- migration 207's invariant (linked expense rows sum to `amountpaid`) survives
  both posting and reversal
- a pay-balance from the Purchases page produces an allocation, so both entry
  points agree
- blocked: overdrawing a cash account, over-allocation, an unknown document
  type, double reversal, a purchase belonging to another supplier

`poultry-expense-payables.test.sql` — 31 checks + 6 negative cases
- **the no-op claim**: no existing expense becomes a payable, and cash-flow
  outflow moves by exactly the cash that actually moved
- the generated `paymentstatus` column across all four states
- which expenses are payable and which are deliberately not: no supplier means
  nobody to owe, `NonCash` means no money moved
- an expense's own due date beating the supplier's payment terms
- **no second expense row** when a bill is paid — the double-count migration 238
  exists to prevent
- one payment settling a bill and a purchase together: one header, two
  allocations, one CashOut, and the purchase leg still booking its own expense
  row while the bill leg does not
- the two cash-flow arms summing rather than doubling
- reversal restoring both kinds of payable, keeping every row
- blocked: over-applying, paying a non-cash internal cost, paying a bill with no
  supplier, paying a settled bill, cutting a bill below what has been paid,
  paying more than the total

`generic-subscription-billing.test.sql` — 32 checks + 7 negative cases
Covers migrations 242-244 end to end, on a company the template creates from
scratch:
- applying a business template: the industry is stamped, subscriptions come on,
  stock goes off, and the starter plans arrive with their billing frequency
- **catch-up billing**: a subscription two months behind raises three invoices in
  one run, each with the right period and a due date of start + terms
- generated invoices are DRAFT, so nothing is owed until someone approves —
  the balance stays 0.00 while they sit unapproved
- **pressing generate twice adds nothing**, which is the guarantee the partial
  unique index on (subscription, period) exists to make
- one payment across TWO invoices: one payment header, two allocations, the
  first invoice Paid and the second PartiallyPaid, and exactly ONE cash-in row
- balance-before/after snapshotted on the allocation rather than recomputed
- the payment history translating Approved into the Posted the frontend expects
- reversal restoring both invoice balances and the cash, keeping every row
- blocked: over-applying to an invoice, allocations that do not sum to the
  payment, the same invoice twice in one payment, reversing twice, reversing or
  cancelling without a reason, an unknown billing frequency

`generic-subscription-reporting.test.sql` — 90 checks
Covers migration 250, the read side, on a Generic company seeded from scratch
with subscriptions, invoices, expenses, staff and a payroll run:
- MRR normalised per billing frequency — weekly is 52/12 of a month, not a
  quarter of one — and **OneTime and Draft never counting** as recurring
- **active / new / lost MRR reconciling month to month**: last month's active,
  less what it lost, plus this month's new, IS this month's active
- a subscription counting in the month it was cancelled and not in the next
- the dashboard KPIs agreeing with the reports they summarise: break-even with
  the break-even report, overdue with the balances function, labour cost with
  the staff-cost report
- **burn rate and break-even excluding the current PARTIAL month** — the check
  asserts the averaging window ends on the last day of last month, because a
  part-finished month would halve the answer
- a draft invoice being an alert rather than revenue, in both the dashboard and
  the revenue report
- the income split summing to what `spgenericreport_periodpnl` already reports
- expenses with no supplier keeping their own row instead of vanishing
- hosting categories suggested by name, overridable by hand, and an explicit
  empty selection meaning zero rather than falling back to the suggestion
- labour cost counting staff payments AND paid payroll without double counting

`generic-business-settings.test.sql` — 51 checks + 4 negative cases
Covers migration 251, the module toggles and the company settings:
- a company with NO settings row reading the declared defaults, and **reading
  not creating one** — a _get that inserts is how a company acquires settings
  it never chose
- the synthesised defaults being byte-for-byte the row an insert produces,
  compared as jsonb so every column is covered rather than a sample
- a partial save leaving every field it did not mention alone, and the three
  nullable ids still being deliberately clearable through their own flag
- the ten-argument module upsert still working, and not silently turning the
  two new modules off
- **Supplier Balances shown with Purchases hidden** — the case 248 supports and
  the old enablePurchases gate got wrong
- a template setting what a template is entitled to set (School bills a term,
  an agency gives 14 days) and leaving the owner's other choices standing
- **autopostinvoices actually changing what a billing run does**: off, the
  invoice is a Draft and nothing is owed; on, it is Approved, the ledger moved
  and the customer balance with it — through the same approve function the
  button calls
- the duplicate guard and fngenericbalanceaudit both still clean after a batch
  job posted to a customer's account
- blocked: an unknown billing frequency, an unknown reconciliation frequency, a
  blank company id, negative due days

`poultry-cash-transfer-reversal.test.sql` — 30 checks + 6 negative cases
Covers migration 252, undoing a poultry cash transfer:
- a transfer still moving money exactly as before, now carrying a number, a
  reference and the ids of the two legs approval wrote
- **the reversal restoring both accounts while all four ledger rows stand** —
  the originals are never deleted and no balance is edited directly
- **neither the transfer nor its reversal moving company-wide cash flow**,
  asserted against the live `sppoultrycashflow_summary` rather than against a
  re-implementation of it in the test
- all four legs carrying `sourcetype = 'Transfer'`, which is what keeps the
  reversal internal: written as an ordinary CashIn/CashOut it would invent
  money the business never received and never spent
- the four legs summing to exactly zero
- **the negative-balance guard flipping to the destination on reversal** — the
  money leaves the account it landed in, so that is the account that has to
  afford it
- blocked: another farm's cash account (which went straight through before
  252), the same account at both ends, a zero amount, reversing a draft,
  reversing twice, and a reversal with no reason

`poultry-owner-money.test.sql` — 31 checks + 8 negative cases
Covers migration 253, owner contributions and draws:
- **a contribution is not revenue and a draw is not an expense** — the counts of
  sales, expenses and customer payments are captured before and asserted
  unchanged after both
- **exactly ONE cash row per record.** The classic way to get this wrong is a
  module and a shadow expense both posting cash for the same event
- the amount stored POSITIVE, with the direction living in the type and the
  sign applied once, in SQL
- **Cash Flow actually seeing it** — money in for a contribution, money out for
  a draw, both filed as financing. Poultry's Cash Flow ignores the cash ledger
  entirely, so without the arm 253 adds, the money would move and the page that
  explains where money came from would say nothing
- a reversal restoring the account, keeping both rows, and removing the record
  from cash flow altogether rather than showing two legs that cancel
- the overdraw guard on a draw, and the same guard flipping to the reversal of
  a contribution the account has since spent
- blocked: an invented type, zero and negative amounts, another farm's cash
  account, drawing more than is held, reversing spent money, a reversal with no
  reason, and reversing twice

`poultry-loans.test.sql` — 43 checks + 10 negative cases
Covers migration 254 on the spec's own worked example: 100,000 borrowed, 2,000
withheld, 98,000 received, then a repayment of 10,000 principal + 2,000 interest
+ 500 fee.
- **cash moves ONCE, for the total.** 12,500 leaves the account -- asserted as
  the row count, as the number of new ledger rows in the whole farm, and as the
  balance. The expense rows add none
- **principal repayment is not an expense.** The P&L's own expense total is read
  before and after and must rise by 2,500, not 12,500
- **cash flow shows the full 12,500 out while the P&L shows 2,500 of cost** --
  both from one event, which is the point of the NonCash marker on the interest
  and fee rows
- the NonCash rows never appearing in cash flow's expense arm as well
- **a lender is not a supplier**: no supplier payment, no allocation, and the
  interest never turning the lender into a creditor on payables
- cash in is what ARRIVED while the debt is what was BORROWED, and the withheld
  fee is not silently expensed on the owner's behalf
- payoff decided by outstanding principal reaching zero, never by comparing
  total paid against the original -- those differ by every cedi of interest
- reversal restoring the debt, reactivating a paid-off loan, clearing the
  paid-off date, keeping both expense rows and adding two cancelling ones
- blocked: receiving more than was borrowed, a loan with no lender, another
  farm's account, principal above the outstanding, a repayment of nothing, a
  negative part, repaying a draft loan, a reversal with no reason, cancelling a
  loan with posted repayments, and repaying more than the account holds

`255_PoultryMoneyPermissions.postgres.sql` — no check file; verification is inline
The only migration in the 252-255 set with no behavioural checks, because it
touches no money: it seeds 16 IAM keys and copies existing grants onto them.
Its three verification queries run at the end of the file instead:
- the 16 catalogue keys exist
- **no role that could see cash lost sight of transfers**
- **no role that could see cash lost sight of loans**

Those last two are the point. Cash Transfers, Owner Money and Loans all rode on
`poultry.cash` until 255, so re-pointing them without copying the 25 role and 26
user grants would have left every one of those grants covering nothing, and the
first person to open the page after a deploy refused.

`poultry-cashflow-loan-time.test.sql` — 14 checks
Covers migration 256: a loan received today sorted below everything else
received today, because `poultryloans.loandate` is a DATE and 254 cast it
straight to midnight while every other cash-flow arm carries a real moment.
- a loan dated TODAY reporting the moment it was recorded, and still filed on
  today's date
- **a BACK-DATED loan still reporting midnight.** Using the recording time
  unconditionally would drag last Tuesday's loan into today, above rows that
  really did happen after it -- the date the money moved is what a cash flow is
  about, and the recording time only breaks ties inside that day
- newest-first actually working: today's loan sorting above the back-dated one
  and above today's own midnight
- **only the clock moved** -- amount, sign, flow group, row count, money in,
  money out and net all unchanged

## The invariant that matters most

`fnbalanceaudit(farmid, 'poultry')` returns **nothing** when healthy. A non-empty
result means a document's `amountpaid` no longer agrees with its allocations, and
the balances on screen can no longer be trusted. Migration 238 added a fourth arm
so expenses are watched alongside sales, purchases and flock batches. It is exposed at
`GET /api/Poultry/balances/audit?farmId=…` and is worth checking after any
migration that touches sales, purchases or payments.

The Generic module has the same invariant in its own function,
`fngenericbalanceaudit(farmid)`, exposed at
`GET /api/generic-company/{farmId}/balances/audit?farmId=…`. It is customer-side
only for now: GenericExpenses has no `amountpaid`/`balance` columns at all, so
there is no Generic payable to watch until that migration is written.
