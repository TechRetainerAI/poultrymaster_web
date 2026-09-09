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

`water-cash-transfer-reversal.test.sql` — 30 checks + 6 negative cases
Covers migration 257, the water twin of 252. Same claims, same order: a transfer
carrying a number, a reference and its two leg ids; the reversal restoring both
accounts with all four ledger rows standing; neither the transfer nor its
reversal moving company-wide cash flow, asserted against the live
`spwatercashflow_summary`; the four legs summing to zero; the negative-balance
guard flipping to the destination. Blocked: another company's cash account, the
same account at both ends, a zero amount, reversing a draft, reversing twice, a
reversal with no reason.

The farm is looked up rather than hard-coded, and the lookup insists on
`farms.type = 'Water'`. That is not fussiness: `watercashaccounts` also holds
rows for a Generic company built on the water rail, and the OLDEST account in
the table is one of those, so an unfiltered pick quietly tests the wrong rail.

`water-owner-money.test.sql` — 33 checks + 8 negative cases
Covers migration 258, the water twin of 253 — and the migration that closes a
gap 236 wrote down and left:

> "Water records owner injections through adjustWaterCashAccount, which writes
> to the cash LEDGER. This report does not read the ledger, so those movements
> will NOT appear in Water's financing section. … Giving Water its own capital
> record is a separate decision."

Same claims as the poultry file, plus one more: **no supplier payment either**,
because water has its own supplier-payment table that a capital record must not
touch. Blocked: an invented type, zero and negative amounts, another company's
cash account, drawing more than is held, reversing spent money, a reversal with
no reason, reversing twice.

`water-loans.test.sql` — 47 checks + 10 negative cases
Covers migration 259 on the same worked example as the poultry file: 100,000
borrowed, 2,000 withheld, 98,000 received, then 10,000 principal + 2,000
interest + 500 fee. Every poultry claim, and three the water rail needs on its
own account:
- **the NonCash clause 259 adds to the cash-flow expense arm actually works.**
  Water's expense arm was rewritten by 241 to gate on `paidatentry > 0` rather
  than on payment method, so unlike poultry it had no NonCash clause to inherit.
  Without the one 259 adds, money out would read 15,000 against 12,500 that
  left the bank
- **the expense categories are created on demand.**
  `waterexpenses.waterexpensecategoryid` is NOT NULL and categories are
  per-company, so a repayment cannot write its cost without one
- **a back-dated loan still reports midnight.** 256 had to go back and fix this
  on poultry; 259 bakes the rule in from the start, so water never needs the
  follow-up migration

The interest and fee rows carry FOUR sourcetypes where poultry uses two —
`LoanPaymentInterest` / `LoanPaymentFee` and their two reversals. That is not
decoration: `waterexpenses` has a unique index on
`(farmid, sourcetype, sourceid)` that poultry has no equivalent of, saying a
source document gets at most one auto-written expense. Sharing one sourcetype
fails on the second row. The checks count them by name so the split is pinned,
not just the total.

`water-money-permissions.test.sql` — 11 checks
Covers migration 260, the water twin of 255. It touches no money — 16 IAM keys
and copies of existing grants — so the claims are about access:
- **nobody lost any.** Every role that could see water cash can still see all
  four new pages, and every role that could create can still create
- **nobody gained any either.** Reversal went only to holders of
  `water.cash.delete`, not to everyone who can create — widening is as much a
  bug as losing
- per-user grants keeping their effect, so a Deny stays a Deny
- the dangerous flag on `approve` and only on `approve`, and no export key
  invented for pages that cannot export

One difference from 255 worth knowing about: 260 stores the BARE resource in
`iampermissions.resource` (`cash-transfers`), matching the other hundred-odd
rows and the IAM matrix's grouping key. 255 stored the prefixed key
(`poultry.cash-transfers`) on the poultry side. Nothing is broken by it — each
value still groups to itself — but the four poultry rows read differently from
their neighbours, and correcting them belongs in a poultry migration rather than
in a file named WaterMoneyPermissions.

`poultry-cost-recognition-foundation.test.sql` — 47 checks + 7 negative cases
Covers migration 261, the configuration layer for when inventory costs reach
Profit & Loss. The claim that matters most is that **nothing changes for a farm
that does not touch the settings** — 261 is inert until somebody chooses
otherwise, and that is asserted for a farm with no settings row, a category
nobody configured, an item with no override, and a purchase that predates the
feature.
- resolution order: item override beats the farm default beats
  EXPENSE_WHEN_PURCHASED
- the feed and medication settings are INDEPENDENT, asserted in both directions
  so neither is secretly driving the other
- **unconfigured categories are unreachable from the settings.** With BOTH
  settings deferred, Packaging, Supplement, Equipment and a category nobody has
  invented yet must still expense on purchase. Otherwise switching the feature
  on would silently defer a farm's sacks and its premix
- an explicit override survives a category change (the user chose a method, not
  a category's method), while an inherited one follows the new category
- a forward-dated setting is not in force before its date, and an item override
  ignores the schedule entirely
- **the two predicates are exhaustive and mutually exclusive** for every input
  including NULL and nonsense, which is what stops a cost being expensed twice
  or never. Garbage reads as today's behaviour, never as deferred
- blocked: an invented method on either setting, a backdated effective date, an
  invented override on insert or update, and direct writes that try to get round
  the SPs

Two judgement calls are pinned here rather than left implicit. **Grain follows
the Feed default** — the spec's worked example is maize, and farms file maize
under either name. **Supplement does NOT follow Medication** — a supplement is
closer to a feed additive than a drug, and guessing would move a real category
on a farm that only asked about drugs. Both are reversible per item.

`poultry-deferred-purchase-expense.test.sql` — 33 checks
Covers migration 262, which is the file that acts on the decision. It tells the
same story twice against one farm — buy 100 bags at 1,000 paying 40,000, pay a
further 25,000, then edit — once per method, and compares.
- **section A exists to prove nothing changed.** The expense still follows the
  MONEY: 40,000 at entry, 25,000 on the later payment, an edit rebalancing
  rather than duplicating, and 207's invariant (linked rows sum to amountpaid)
  intact
- **section B proves the cost is withheld from the P&L and from nowhere else.**
  No expense at entry, none on the later supplier payment, none when the
  purchase is edited — while stock, unit cost, the FIFO layer, the supplier
  balance and the cash movement are all identical to section A
- the snapshot decides, not the setting: flipping the farm back afterwards
  changes neither purchase, and paying a deferred purchase after the switch
  still books nothing
- a medication purchase is unaffected while feed is deferred, and an item
  override reaches the purchase and is snapshotted

Why the same claim is tested at the payment as well as the purchase: poultry
raw-material recognition is CASH-BASIS. The purchase writes an expense for
amountpaid, and every supplier payment writes another. Suppressing only the
first would let a credit purchase expense itself in instalments — the deferral
would appear to work on the day it was entered and quietly fail for the rest of
its life.

`poultry-financial-settings-permissions.test.sql` — 11 checks
Covers migration 263. Two keys, view and edit.
- **everyone who can read the P&L can see the setting.** It is the explanation
  for a number in that report; hiding it would leave the report unexplainable
  without making anything safer
- **editing is strictly narrower than viewing** — 8 roles read reports, 6 export
  them, and edit rides export. Granting it to all 8 would hand a P&L-shaping
  decision to everyone who can open a report
- edit is flagged dangerous, view is not, and the resource is stored bare
- the item override rides `poultry.raw-materials.edit` rather than a key of its
  own: a separate key would have to be granted to somebody before anyone could
  use the control, and on day one that somebody is nobody

`poultry-deferred-cost-layers.test.sql` — 25 checks
Covers migration 264. Phase 2 did NOT build a costing engine: one already
existed. `poultryrawmaterialpurchases` IS the cost-layer table,
`poultryrawmaterialusagebatch` IS the consumption-allocation table, and
`sppoultryrawmaterialitem_consumebatches` IS the FIFO/LIFO/HIFO engine, unit
normalisation and all. 264 gives them a second number: how much of a lot's cost
has never reached the P&L.
- **the engine's behaviour is unchanged**, which is the whole of section A: FIFO
  660, LIFO 900, HIFO 1,350, the shortfall guard and the allocation rows, all
  asserted at today's answers because 264 rewrites the function every
  consumption path depends on
- deferred cost is drawn PRO RATA and a drained lot lands on **exactly** zero —
  quantity times unit cost would leave a rounding crumb that could never be
  recognised
- **a lot expensed at purchase contributes nothing deferred**, stated as a total
- mixed layers: one draw across an expensed lot and a deferred one consumes both
  physically and defers only the second
- 20 bags of 50 kg defers per KG, not per bag

`poultry-deferred-cost-transfer.test.sql` — 21 checks
Covers migration 265: purchases open deferred cost, and feed production carries
it. The claim that matters is the brief's own mixed example — maize deferred
5,000, premix already expensed 2,000:
- **operational cost 7,000, deferred cost 5,000.** Expensing 7,000 when that feed
  is eaten would charge the premix twice. `totalcost` keeps its existing meaning
  and everything reading it (cost per kg, formula analysis, the production
  reports) is untouched
- deferred cost is CONSERVED through mixing: what the ingredients give up is
  exactly what the finished feed receives
- a batch mixed entirely from expensed stock produces a lot that says it has
  nothing left to expense, whatever the farm setting says
- additional costs (milling, labour) are **not** deferred — they are already
  expenses where they were entered
- a deferred purchase opens with its whole COST deferred, not its amount paid

`poultry-consumption-recognition.test.sql` — 40 checks
Covers migration 266, the brief's worked examples section by section. Feed usage
and medication usage both run through `sppoultryproductionrawmaterialsync`, so
recognition needed ONE hook, not one per screen.
- **59** expensed feed: use 20 kg -> **no further expense**, stock still falls
- **60** deferred feed: purchase expenses 0; use 20 kg -> +200, 800 left
- **62** medication: 50 ml of a 500 ml / 50,000 lot -> +5,000
- **66** mixed layers: 150 kg across an expensed and a deferred lot -> only 500
- **20** no cash, no supplier payment, no cash transaction; invisible to Cash
  Flow AND to payables, while still counting in the P&L
- **69** reversal: expense -200 with **both rows kept**, deferred cost and stock
  back on the exact lot
- **73** credit purchase -> P&L 0; pay 40,000 -> cash moves, P&L still 0;
  consume -> +10,000; pay more -> no change
- reversing one record leaves another record's recognition alone
- three edits (10 -> 30 -> 5 kg) net to 50, not 45: compensation works off the
  CURRENT SUM, so it cannot drift however many times a record is edited

`poultry-cost-layer-guards.test.sql` — 24 checks
Covers migration 267: two inventory values, and the audit that says when they
can be trusted. `fnpoultrycostlayeraudit` returns **nothing** when healthy, like
`fnbalanceaudit`.
- **operational value and deferred value are different numbers.** Stock bought
  under expense-on-purchase is worth 4,000 and has nothing left to expense;
  reporting only the second would call it worthless
- Corrupt = the numbers contradict themselves. Stranded = deferred cost that can
  no longer reach the P&L. Drift = stock and lots disagree
- the same drift is **Stranded** on a deferring item and merely **Drift** where
  nothing is deferred — the distinction Phase 3 needs to prioritise
- the two unsafe-reversal guards still refuse, exercised end to end

`poultry-cost-recognition-reads.test.sql` — 43 checks
Covers migration 268, the read surface sections 43 to 47 are shown through. It
adds no behaviour: three existing reads gain columns at the END of their
RETURNS TABLE, and two set-returning functions from 267 get stored-procedure
wrappers so the .NET layer can reach them at all.
- **a usage that recognises nothing is not a usage that cost nothing.** 800
  cedis of premix, expensed when it was bought, reports operational cost 800 and
  recognised cost 0. A screen showing only the second would tell an
  expense-at-purchase farm — the default, and today every farm on the system —
  that all its feed is free
- a lot reports its OWN snapshot, not today's farm setting
- deferred cost per unit is per PRODUCTION unit, so it is comparable with the
  production unit cost printed beside it; an emptied lot reports **NULL**, a
  full lot with nothing deferred reports **zero**, and those are different facts
- a draw across two lots reports two cost layers and the sum of both
- feed production shows **3,300 total production cost** and **2,000 carried
  forward** — the premix was expensed three days earlier and the milling is an
  expense of its own; charging either again would be the double charge Phase 2
  exists to prevent
- a batch mixed entirely from expensed stock carries **nothing**, and says so
- a reversed usage still reads back with what it drew, flagged `Reversed`
- every column that existed before 268 still returns the same value, asserted
  row by row rather than assumed

Those two guards were FOUND, not written — they predate this work:
`..._purchase_delete` already refuses a lot that has been drawn from (section
29), and `...feedproduction_reverse` already refuses a batch whose feed has been
eaten (sections 30 and 72). Both now also restore deferred cost, which was the
only thing they lacked.

### The drift 267 reports and does not fix

Seven items across two farms already disagree between physical stock and their
cost layers, one of them by 4.7 million units. Internal use and stock adjustments
move `currentquantity` without drawing lots, and always have.

That is reported rather than repaired, deliberately. The drift has several causes
with different correct answers — a loss, a correction, a count fix, a real
consumption — rewriting lots would destroy the evidence needed to tell them
apart, and inventing a recognition for stock nobody costed would be the
double-expensing the whole phase exists to prevent. Wiring those two paths into
the costing engine is Phase 3, and it needs a business answer first.

## Phase 3 — capital assets, classification and the P&L rewrite

`poultry-financial-cost-type.test.sql` — 41 checks
Covers migration 269. Two questions, two answers: Phase 1's
`costrecognitionmethod` says WHEN an inventory cost reaches Profit & Loss;
`financialcosttype` says WHAT KIND of cost it is. Neither replaces the other.
- **a feed purchase is reported as Feed Cost.** Section B buys maize, an
  antibiotic and egg crates — all three land in `expense` with the SAME category
  words, and the item tells them apart. Today all 73 raw-material purchases fall
  into "Other" because the words cannot
- structure first, keyword LAST: stored classification beats the source, the
  source beats the item, the item beats the text. The keyword arm is kept, not
  deleted — three years of hand-typed categories depend on it
- loan interest and fees are FINANCING, below Operating Profit, not in it
- Phase 2's consumption recognition is an OPERATING cost, not a `NonCashExpense`.
  Both are non-cash; only one belongs beside depreciation
- the expense form REFUSES to create a capital cost: one with no asset behind it
  would leave profit and never be depreciated, so the money would vanish from
  both sides of the report

`poultry-capital-assets.test.sql` — 47 checks
Covers migration 270, the Asset Register.
- **a poultry house does not make the farm look bankrupt.** Section C buys one
  for 600,000 on credit, pays 100,000, and asserts all four numbers at once: the
  asset is worth 600,000, cash fell 100,000, the supplier is owed 500,000, and
  the amount charged against profit is ZERO
- paying the supplier later adds NO new cost — one cost row, one expense row,
  before and after
- an asset is BUILT: cement + wood + labour + roofing + electrical = one 500,000
  asset, not five expenses, and not one cedi of it reaches profit
- the guards refuse rather than corrupt: no reversal once a supplier has been
  paid, no cost added once depreciation has run, no residual above the cost, no
  in-service date before acquisition
- reversal with nothing downstream hands the cash back and KEEPS the row with
  its reason
- disposal proceeds are CASH IN and are not a sale

`poultry-asset-depreciation.test.sql` — 57 checks
Covers migration 271.
- **depreciation is an expense that moves no money.** Section B charges 2,000 and
  asserts, in one breath, that the cash account did not move, no cash transaction
  was written, no supplier exists, nothing is owed — and that the 2,000 IS in
  Profit & Loss
- 120,000 over 60 months is 2,000 a month and book value goes to 118,000 (§81)
- generating twice charges nothing the second time
- **1,000 over 3 months is 333.33, 333.33, 333.34** — the last month takes what
  is LEFT, so accumulated lands exactly on the depreciable amount and the asset
  can actually finish. Three months, not four
- book value floors at the residual value: a 10,000 truck with a 4,000 residual
  stops at 4,000, not zero
- a reversal keeps the original, appends the opposite row, restores book value,
  and does NOT reopen the month to the generator — otherwise the next "Generate"
  would silently put the charge back and the reverse button would do nothing

`poultry-profit-loss-redesign.test.sql` — 62 checks
Covers migration 272, the report rewrite. Everything is dated 2015, the window is
2015, and section A asserts the farm has no 2015 history — which is what lets
every figure below be an exact number rather than a delta.
- **a 500,000 poultry house does not turn a 35,000 profit into a 465,000 loss.**
  §90 end to end: revenue 100,000, operating costs 60,000, an asset at 500,000,
  one month of depreciation at 5,000. Net Profit reads 32,500 and Capital
  Investments reads 500,000
- 250,000 of owner money and borrowing reaches the bank in one month and NONE of
  it is revenue
- a loan repayment charges interest 2,000 and fee 500 to profit, and the 10,000
  of principal to nothing — the single most common way a P&L is read wrongly
- a bill on credit is a cost the day it is incurred, and paying it later adds
  nothing
- §84: consumption-based feed reports the 30,000 EATEN, not the 90,000 bought
- §85: a period holding an expense-at-purchase medication layer AND an
  expense-at-consumption one reports 15,000, once
- every drilldown totals to the line above it — asserted for all eight

`poultry-asset-permissions.test.sql` — 17 checks
Covers migration 273. **Nobody gained a right they did not already have**, and
the file asserts both directions: nothing lost, nothing widened. Charging
depreciation to Profit & Loss is deliberately narrower than reading the report.

### The Phase 2 defect Phase 3 made visible

`sppoultryproductionrawmaterialsync` dated its consumption recognition `now()`
rather than the production record's date. Nothing before 272 could see it — the
old report grouped by category, not by anything that cared which month a cost
belonged to. It matters now: a farm entering Friday's records on Monday would
have Friday's feed cost land in the wrong month. 272 reproduces both that
function and `sppoultryconsumption_unrecognise` from their LIVE definitions with
the date, and only the date, changed.

## Water — the same architecture, ported

Migrations 274-286 mirror 261-273 onto the water module. Five check files so far,
covering the stages that could be written; the rest are blocked, and the reason
is worth stating because it shapes the whole port.

**Poultry could rewrite its stored procedures because migration 207 had restored
their Postgres bodies into this repo first.** Water's live bodies were ported
outside version control: the repo holds `spWaterRawMaterialPurchase_*` and
`spwaterreport_periodpnl` only as pre-migration T-SQL. Six stages — 275, 277,
278, 279, 281 and 285 — rewrite one of those, and rewriting from the T-SQL would
silently drop whatever the live port actually does. They are blocked on a dump of
the live definitions, not on design. `apply-water-cost-recognition.ps1` and
`apply-water-phase3.ps1` throw with that explanation rather than half-applying.

The stages that ARE written are the purely additive ones. Where 261 folded the
item override into `sppoultryrawmaterialitem_update`, 274 adds a separate setter
instead — the same shape migration 240 chose for `spwaterexpense_setpayment`, and
for the same reason.

`water-cost-recognition-foundation.test.sql` — 61 checks, 7 negative cases
Covers migration 274. Same claim as its poultry twin: **nothing changes for a
company that does not touch the settings.** Packaging and Chemical are the two
configurable groups; Filter and UVLamp are deliberately outside them, for the
reason 261 left Supplement out of Medication. Section 0 is water-only and is the
important one — see below.

`water-financial-cost-type.test.sql` — 45 checks, 4 negative cases
Covers migration 282. Water classifies in its own `waterexpenses` table, not the
shared `expense` table 269 uses, so the column, the resolvers and the writers are
its own. Asserts that no legacy row changes meaning, that structure beats
keywords, and that electricity stays an operating expense unless the category
names it as production power.

`water-capital-assets.test.sql` — 48 checks, 11 negative cases
Covers migration 283. Same headline claim as poultry: **a borehole does not make
the company look bankrupt.** Section B2 is water-only and asserts the payable fix
described below.

`water-asset-depreciation.test.sql` — 45 checks, 9 negative cases
Covers migration 284. **Depreciation changes profit and moves no money** — the
P&L cost rose, the cash account did not move, no cash transaction was written,
and nobody is owed anything. Any one of those failing means depreciation has
turned into a bill.

`water-financial-settings-permissions.test.sql` and `water-asset-permissions.test.sql`
Cover 276 and 286. Looser than their poultry twins on purpose: the water IAM
catalog is seeded outside this repo, so the donor keys cannot be assumed to
exist. They assert the invariants that hold whichever donors turned out to be
real — reachable by somebody, narrower where it must be narrower, poultry
untouched.

### Applied to dev on 2026-09-09

All six ran through the four-phase scripts: measure, dry run inside a rolled-back
transaction, apply, measure again. **Every stage printed "No change to any
measured total"**, which is the claim that matters — 24 water companies, 47
purchases and 115 expense rows all read exactly as they did before.

The dry runs earned their keep twice, and both were caught before anything was
committed.

**A bad check.** `water-financial-cost-type` asserted that no P&L line labels as
itself. Six do — "Rent" really is just "Rent" — so `label = key` could not tell a
deliberate one-word label from a line that had fallen through the CASE into the
ELSE. The check now asserts no label is EMPTY, and that the self-labelled set is
exactly the expected six, so a newly added line with no label still fails it.

**A real design bug in 283.** See below.

### The unique index that broke the construction workflow

`waterexpenses` carries an index the poultry table has no equivalent of:

```sql
ux_waterexpenses_farmsource_active (farmid, sourcetype, sourceid)
  WHERE sourcetype IS NOT NULL AND isdeleted = false
```

One live system-generated expense per source document. 283 originally keyed every
capitalised cost on the ASSET id, copying the poultry shape — so the first cost
added to an asset succeeded and the second was rejected:

```
ERROR: duplicate key value violates unique constraint "ux_waterexpenses_farmsource_active"
DETAIL: Key (farmid, sourcetype, sourceid)=(..., CapitalAssetCost, 3) already exists.
```

That is exactly the build-it-up-cost-by-cost workflow the register exists for. The
fix: an acquisition stays keyed on the asset (there is only ever one), while an
additional cost is keyed on its own cost-row id — which is why
`spwatercapitalassetcost_add` now writes the cost row FIRST and links the expense
back onto it. `watercapitalassetid` still points at the asset; `sourceid`
identifies the document.

The index turns out to be a gift: the money leg is now idempotent, and because the
index is partial on `isdeleted = false`, a reversed acquisition frees its key so
the asset can be recorded again. Checks D4b and D4c pin all of it.

### The interlock, and why 274 can ship alone

261 and 262 went out together, so the moment a poultry farm could CHOOSE
`EXPENSE_WHEN_CONSUMED`, the migration suppressing the purchase expense was
already there. Applying 274 alone would open a gap that is quiet and expensive:

> a company defers packaging → 274 stamps each new purchase deferred → but 275 is
> not applied, so the purchase STILL writes its P&L expense → months later 279
> lands, reads those snapshots, and recognises the same cost AGAIN on
> consumption.

The cost would be in Profit & Loss twice, on purchases nobody would think to
re-examine, and the snapshot — which by design is never recomputed — would say
the second charge was correct.

So 274 ships `fnwatercostrecognition_deferralready()` returning FALSE, and both
writers refuse the deferred method while it does. The migration that makes
consumption recognition real replaces it with TRUE, and nothing else may. The
settings page reads that state off the API and explains the locked option rather
than offering a save that would fail.

Section 0 of the foundation check asserts the guard blocks, then lifts it inside
its own rolled-back transaction so the resolver can be tested.

### The payable gap 283 had to close

Migration 240 ends `fnwaterpayables` with `AND e.sourcetype IS NULL` — "only
bills a person typed in are payable; anything with a sourcetype is another
document's shadow". That rule stops a recursion: paying a supplier writes a
`WaterSupplierPayment` expense row, and if that row were payable, paying it would
write another.

But a capital asset bought on credit is a REAL debt to a real supplier. Left
under that filter, the company would owe money the system could not show. 283
widens the filter to admit `CapitalAsset` and `CapitalAssetCost` and nothing
else; neither is ever generated BY a payment, so the recursion cannot return
through that door. `water-capital-assets.test.sql` B2 asserts the debt is
visible, and B7 asserts payment shadows are still hidden.

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
