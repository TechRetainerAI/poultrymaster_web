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

## The invariant that matters most

`fnbalanceaudit(farmid, 'poultry')` returns **nothing** when healthy. A non-empty
result means a document's `amountpaid` no longer agrees with its allocations, and
the balances on screen can no longer be trusted. Migration 238 added a fourth arm
so expenses are watched alongside sales, purchases and flock batches. It is exposed at
`GET /api/Poultry/balances/audit?farmId=…` and is worth checking after any
migration that touches sales, purchases or payments.
