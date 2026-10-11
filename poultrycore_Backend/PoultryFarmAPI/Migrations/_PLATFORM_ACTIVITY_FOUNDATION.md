# Platform Activity & Usage Foundation (PROMPT 1 OF 7)

Migrations **346** (foundation) + **347** (historical backfill). Applied to
`VisibilityCoreDB` (dev) and `VisibilityCorePROD` on 2026-10-11.

## What already existed (inspection findings)

| Concept | Where it lives |
|---|---|
| Company | `farms` row; `farms.type` = family (`Poultry/Water/Hotel/Restaurant/Generic/System`); `farms.timezoneid` (validated IANA zone, see `CompanyTimeService`) |
| Organization / Business Office | the **owner user**: `farms.owneruserid` = `aspnetusers.id` = `organizationbillingaccounts.owneruserid`; display name in `aspnetusers.businessofficename` |
| Generic business template | `genericcompanyprofiles.genericbusinesstemplate` per company |
| Users / per-company access | `aspnetusers` (shared DB with Login API) + `userfarms (userid, farmid, role)` |
| Audit trail | `auditlogs` table, written by the **global `AuditLogActionFilter`** on every POST/PUT/DELETE (fire-and-forget) — kept untouched as the authoritative action/security trail |
| Business events | none centralized — writes go through per-module services/SPs; the action filter is the only cross-cutting success hook |
| Platform admin gate | JWT roles `SystemAdmin` / `PlatformOwner` (same gate as `PlatformFarms` and the platform audit feed) |
| Background jobs | none (no scheduler) — hence trigger-maintained aggregates, not a nightly job |

## What was added

- **`platformactivityevents`** — the normalized event stream
  (org/company/family/template, user, `activitycategory` + `activitytype`,
  `sourcemodule` + `sourcerecordid` reference to the authoritative row,
  `businessdate` in the *company's* timezone, `ismeaningful`, `source`
  `Runtime|HistoricalBackfill`, optional `correlationid`). Indexed on org,
  company, time, category, type, family, business date + a partial index on
  meaningful events and a partial **unique** index on `correlationid`
  (idempotency: duplicate emission is a silent no-op).
- **`platform_activity_record(...)`** — the single write path. Resolves
  organization, family, template and company-timezone business date so no
  caller duplicates that logic; `ON CONFLICT DO NOTHING` on correlation.
- **`companyusagedaily`** (+ `companyusagedailyusers`) — derived daily cache
  (counts total/meaningful/per-category + distinct active users), maintained by
  an `AFTER INSERT` trigger; `platform_usagedaily_rebuild()` re-derives it from
  the stream at any time (also the archive path: rebuild/retain aggregates
  before pruning old raw events).
- **Login engagement** — `aspnetusers.lastloginatutc` / `logincount`,
  `userlogindays` (ActiveUserDays), `platform_record_login(userid)`; called by
  the Login API only on verified logins (password or OTP success), never on
  token refresh. Login events are `AUTHENTICATION` and never meaningful.

## Event creation strategy (no 200-controller edit)

1. **`AuditLogActionFilter`** (already global on every mutating action) now
   also classifies successful requests through **`ActivityClassifier`**:
   - Tier 1: explicit `(controller, action)` → meaningful milestone map
     (SaleRecorded, ProductionRecorded, BatchProductionPosted, PaymentRecorded,
     ExpenseCreated, BookingCreated, CheckIn/CheckOutCompleted,
     DailyClosingCompleted, PayrollApproved, InventoryReceived, FlockClosed,
     DriverReturnCompleted, CashReconciled, CompanySetupCompleted, …).
   - Tier 2: typed non-meaningful events (EmployeeCreated, CustomerCreated,
     RoomConfigured, ProductionLineConfigured, CheckoutStarted).
   - Tier 3: any other mutating success on a recognized module → generic
     non-meaningful usage event; unknown controllers are skipped.
   Emission happens **only after the action succeeded** (rolled-back
   transactions surface as errors and are never emitted), asynchronously, and
   `RecordAsync` never throws — analytics can never break a business flow.
2. **Service-level emitter** where idempotency matters: `PlatformBillingService`
   emits `BILLING/SubscriptionPaymentRecorded` *after* the payment transaction
   commits, with `correlationid = pay:<provider>:<reference>` — five webhook
   redeliveries still produce one event.
3. **Login API** calls `platform_record_login` fire-and-forget.

## Aggregation service & API

`PlatformActivityService` (`IPlatformActivityService`) provides
LastMeaningfulActivityAt, LastLoginAt (via aspnetusers), counts today/7d/30d,
ActiveDays, ActiveUsers, ActivityByCategory/CompanyType/BusinessTemplate and
trend — company summaries come from **one** lateral-join query (no N+1), window
counts come from the daily cache. Organization summaries aggregate companies
while preserving per-company rows.

`PlatformActivityController` (`api/PlatformActivity`, **SystemAdmin/
PlatformOwner only**, enforced server-side):
`GET overview | organizations | organizations/{id} | companies/{id} |
timeseries | categories | recent`.

Statuses `ActiveToday / Active7Days / Active30Days / Inactive30Plus /
NoActivity` and trend `NewActivity / Increasing / Stable / Declining /
Inactive` are computed centrally in `ActivityMath` with thresholds from the
`PlatformActivity` appsettings section (7 / 30 days, ±10% stable band) — never
hardcoded in UI. Trend handles previous=0 without Infinity (percent = null,
status = NewActivity).

## Company-type extensibility

Adding a future Generic template (e.g. Pharmacy) requires **no table change**:
`businesstemplatecode` is free-form from `genericcompanyprofiles`, new
`Generic*` controllers classify automatically into the Generic module, and new
meaningful milestones are one dictionary entry in `ActivityClassifier`.

## Privacy / data minimization

Events store identifiers only (`sourcerecordid`, ids, category/type). No
amounts, notes, credentials or financial payloads are copied; `metadatajson`
is unused by default.

## Backfill (347) — sources & limitations

Backfilled with `source = 'HistoricalBackfill'`, `correlationid =
'bf:<table>:<pk>'` (idempotent, safe to re-run): poultry `sale`, `expense`,
`eggproduction`, `productionrecords`, `poultrydailyclosings`,
`poultrypayments`, `inventorytransactions`; water sales/production/driver
returns/expenses/payments/closings; hotel bookings/check-ins/check-outs/
expenses/customer payments/closings; restaurant orders/expenses/customer
payments/closings; generic sales/expenses/customer payments/purchases/
closings; `platformpayments` (org-level billing).

Documented limitations: logins are not backfillable (no history anywhere);
org/family resolved as of today; rows without a creator stay `userid = NULL`
(nothing fabricated); prod's `sale` table predates `correctssaleid` (handled
via a schema-adaptive `to_jsonb` lookup).

## Tests

- `Tests/PlatformActivity.Tests` (xunit, 41 tests): classifier per vertical
  (meaningful sales/production/expenses/closings/payroll/inventory, reversals
  and plumbing excluded, GETs never recorded, future-Generic extensibility),
  trend math (incl. previous=0), status thresholds.
- `PoultryFarmAPI/Tests/PlatformActivity_SmokeTest.sql` (run via
  Tools/RunMigration; passes by raising `SMOKETEST_PASS` so it always rolls
  back): recording + metadata resolution, duplicate-correlation idempotency,
  usage-daily trigger counts + active users, company-timezone business dates,
  company isolation, organization aggregation, unresolvable-company handling,
  login never meaningful, cache rebuild equivalence. Passed on dev AND prod.

## TODOs for prompts 2–7

- Admin UI dashboards on top of `api/PlatformActivity`.
- Promote further milestones into the meaningful map as verticals grow.
- Partitioning of `platformactivityevents` when volume warrants (indexes and
  the rebuildable cache already assume it).
- Customer-health scoring on top of status + trend.

---

# Executive Dashboard & Customer Intelligence (PROMPT 2 OF 7)

No schema changes — everything reads the Prompt 1 foundation (daily snapshots +
aggregates, never raw audit rows, never full event scans).

## New analytics API (api/PlatformActivity, same SystemAdmin/PlatformOwner gate)

- `overview` extended with lifecycle KPIs: NewOrganizationsThisMonth (first
  company created this calendar month), TrialOrganizations / PayingOrganizations
  (organizationbillingaccounts.status), PastDueOrganizations (open invoice with
  balance > 0 past duedate).
- `organizations` rows extended into Customer Intelligence rows: orgCode,
  countryCode (billing market), activeCompanies30d, firstCompany/firstMeaningful
  timestamps, subscriptionStatus (None|Trial|Active|PastDue), trialEndUtc,
  setupPercent (share of companies with ≥1 meaningful event — placeholder until
  the Prompt 3 Health Engine), health (blank, reserved), attention flags
  (PastDue, GoingQuiet, Inactive30Plus, TrialEndingSoon).
- Company rows extended with createdAtUtc, firstMeaningfulActivityAtUtc,
  planCode + billingParticipation (companybillingstates).
- `timeseries` gained a companyFamily filter (per-vertical trend).
- NEW `going-quiet`: deterministic list — baseline window (30d before the recent
  14d) had ≥ 10 meaningful events AND recent 14d ≤ 2. Configurable via
  PlatformActivity appsettings (QuietBaselineDays/QuietRecentDays/
  QuietBaselineMin/QuietRecentMax). Explicitly labeled "Going Quiet", not churn.
- NEW `new-customers`: organizations whose first company was created in the
  window, with first company, first meaningful activity, setup proxy, trial.
- NEW `module-adoption`: meaningful activity per category per vertical.

## Admin portal (farm-registry-portal)

- Rebranded: "VisibilityCore — Platform Admin"; Farms→Companies nav;
  "PoultryMaster activity" → "Platform Activity Audit" (raw audit semantics
  kept as the deep-investigation tool).
- Dashboard replaced with Platform Operations: grouped KPI rows (Customers:
  orgs/companies/new/trial/paying/past-due; Usage: active today/7d/30d/
  inactive-30+/active users), companies-by-type cards (Generic expands by
  template), meaningful-activity trend (7/30/90d × vertical filter, SVG, from
  daily snapshots), module-adoption matrix, Recently Active ("Production posted
  · 18 mins ago", click → filtered audit), Going Quiet widget, New
  Organizations table. All widgets have explicit empty states.
- NEW Customer Intelligence page: organization view (Organization, Country,
  Companies, Last Meaningful, Active Companies, 30d, Trend, Setup %,
  Subscription, Health (blank until Prompt 3), Attention) and company view
  (Company, Organization, Type, Template, Last Activity, Active Users, 30d,
  Plan, Subscription). Filters: type, template, country/market, subscription,
  activity window (today/7d/30d/inactive/new-month), plan. Global search over
  org name/orgCode/company/owner email/type/template. Row click opens
  Organization 360 / Company 360 placeholder panels (full versions in Prompt
  5); "Audit" drills into the filtered audit page.
- Deep links: hash routes (#/intel?view=companies&org=…, #/audit?farm=…)
  survive reload and are shareable.
- Audit page gained Organization and Company-type filters (resolved through the
  activity directory) on top of the existing company/user/action/resource/
  status/date filters.
- Responsive: KPI grid collapses 6→3→2 columns; report grids stack; filter rows
  wrap at laptop/narrow widths.

## Tests

ActivityMath.IsGoingQuiet rule covered by unit tests (46 total in
PlatformActivity.Tests). Directory/trend/KPI SQL exercises the same
trigger-maintained snapshots validated by PlatformActivity_SmokeTest.sql.
Dashboard filters/search/empty states are client-side view logic over the
tested API data (the portal has no JS test harness; noted as a TODO).

---

# Customer Health Engine & Needs Attention Queue (PROMPT 3 OF 7)

Migration **348** (customerattentionitems + customerattentionnotes +
customerhealthhistory + upsert/auto-resolve/history SQL functions), applied to
both databases and covered by CustomerHealth_SmokeTest.sql (8 assertions,
self-rolling-back, passed on dev AND prod).

## Health model

Deterministic levels: **New** (insufficient history) / **Healthy** /
**Needs Attention** / **At Risk** / **Inactive** — no numeric score shown,
every verdict carries data-backed reasons ("No meaningful activity for 17
days", "Trial ends in 4 days"). Computed by the pure `HealthEngine`
(Business/CustomerHealthEngine.cs) so every rule is unit-tested.

Signals: days since meaningful activity, active days 30d, trend vs previous
period, first meaningful transaction (onboarding), billing status, trial
expiry, failed payments (7d), past-due invoices, repeated failed requests
(auditlogs, 7d), active users. Thresholds live in the `PlatformHealth`
appsettings section (NewAccountDays 14, AtRiskDaysSince 14, InactiveDaysSince
30, TrialEndingSoonDays 5, HighEngagementMin30d 20, UsageDropPercent 50,
RepeatedErrorsMin7d 20, NoActivityAfterSignupDays 7).

Organization health rolls up company verdicts (mixed healthy + struggling →
Needs Attention, never a blind average) and overlays billing signals that can
only escalate. Health and reasons are embedded in the Prompt 2 directory
responses (`api/PlatformActivity/organizations`).

## Attention queue

Rules emitted by the sweep: PastDue, PaymentFailed,
TrialEndingSoonHighEngagement ("Highly engaged trial ends in N days" — sales
opportunity), TrialEndingSoonLowEngagement, NoActivityAfterSignup,
SetupIncomplete, PreviouslyActiveNowInactive, UsageDownSignificantly,
RepeatedErrors, NoActiveUsers. (BillingPricingProblem is intentionally absent —
no supported signal exists yet.) `revenueatrisk` column reserved for Prompt 6.

Duplicate suppression: a partial unique index keeps ONE live item per
(org, company, rule); re-detection refreshes reason/severity/lastdetectedatutc.
Resolved/dismissed items stay as history and the condition can re-open fresh.
Reactivation: the sweep auto-resolves inactivity items with "Auto Resolved —
Customer Reactivated" (other cleared rules: "condition no longer detected").
Health history: one row per subject per day, rewritten only on level change.

No scheduler exists on this platform, so the sweep runs on demand: opening the
queue (GET api/PlatformHealth/queue?refresh=true) or POST /evaluate. (Cron is a
known TODO.)

## API + portal

`api/PlatformHealth` (SystemAdmin/PlatformOwner): evaluate, queue, and item
actions assign / contacted / notes / follow-up / resolve / dismiss(reason) —
all captured by the audit filter and mirrored as append-only internal notes.

Portal: new **Customer Success → Needs Attention** page (Customer, Company,
Health, Reason, Last Activity, Subscription, Assignee, Follow-up, Status +
actions, expandable rule/notes detail); dashboard gained a Customer-health KPI
row, health-split donut and Top Attention Items; Customer Intelligence health
column/filter and the 360 panels now show the explained health badge.

## Tests

66 unit tests total — HealthEngine: new account, never-active, healthy,
17-day decline (At Risk), 35-day silence (Inactive), usage drop, repeated
errors, multi-signal reason accumulation, org aggregation (mixed → Needs
Attention; all-inactive → Inactive; all-new → New), past-due/payment-failed/
trial overlays (escalate-only), custom-threshold configuration, every verdict
has reasons. SQL smoke test: dedupe, scope separation, auto-resolve +
reactivation note, reopen-after-resolve, no-op resolve, history-on-change,
note cascade.

---

# Onboarding, Activation, Feature Adoption & Cohorts (PROMPT 4 OF 7)

Migration **349** (applied to both DBs; Onboarding_SmokeTest.sql — 5 assertions
— passed on dev AND prod).

## Milestone framework

- `onboardingmilestones` — configurable catalog per CompanyFamily, optionally
  overridden per Generic BusinessTemplate (an override set REPLACES the family
  defaults; unknown/new templates fall back automatically). Weight + required +
  order per milestone. Seeded from REAL workflows only:
  Poultry (CompanyCreated, FarmSetupCompleted, House, Flock*, Batch, CashAccount,
  FirstProduction, FirstSale, FirstPayment, FirstDailyClosing), Water (Product*,
  ProductionLine, FirstProduction/Sale/DriverReturn/Payment/Closing), Hotel
  (RoomTypes*, Rooms*, Booking, CheckIn, Payment, Closing), Restaurant (Menu*,
  Floors/Tables, Order, Payment, Closing), Generic (Profile*, CashAccount,
  Customer, Sale, Payment, Closing) + School/Gym template overrides
  ("First student setup", "First member", "First subscription payment").
  (* = required/essential setup.)
- Detection is set-based: `platform_milestone_facts` view unions existence
  probes on the authoritative tables with normalized events (so history
  predating Prompt 1 counts), `platform_company_milestones` applies the
  template-aware catalog per company, `platform_setup_summary()` returns
  weighted setup %, required-complete counts and MISSING MILESTONE TITLES for
  every company in one scan.

## Setup % & activation (health integration)

The directory (api/PlatformActivity/organizations) now carries the
milestone-based SetupPercent, missing list, Activated flag (essential setup
complete + first meaningful transaction) and TimeToActivationDays per company;
organization SetupPercent is the mean of its companies. The Prompt 3 Health
Engine and attention rules consume these same fields — one centralized
definition, nothing recalculated elsewhere.

## API (api/PlatformAnalytics, SystemAdmin/PlatformOwner)

- `onboarding` (+family/template/country filters) — per-company setup rows
- `milestones/{companyId}` — full checklist
- `funnel` (+signup month/family/template/country) — Registered → First Company
  → Essential Setup → First Meaningful Activity → Active on 3 Days → Paid, with
  per-stage and top-of-funnel conversion (sequential stages, so "paid but never
  used" never inflates the funnel). No acquisition source exists, so none is shown.
- `feature-adoption?days=` — matrix % per feature per APPLICABLE vertical
  (FeatureCatalog maps normalized ActivityTypes → features; never page views)
- `feature-usage[?companyId=]` — FirstUsedAt / LastUsedAt / UsageCount /
  ActiveDaysUsingFeature
- `retention?scope=org|company&cohortBy=signupMonth|signupWeek|activationMonth`
  — retained at Day N = meaningful activity in D1 [1,7) D7 [7,30) D30 [30,60)
  D60 [60,90) D90 [90,120); unreached windows report null; org and company
  retention are kept separate; product inactivity is never labeled
  subscription churn (billing status stays its own field).

## Portal

New **Analytics** nav section with three tabs: Onboarding & Activation (funnel
bars + setup table with missing milestones and expandable per-company
checklist), Feature Adoption (color-coded matrix + depth table), Retention
(cohort grid with scope/cohort/vertical selectors and documented definition).

## Tests

82 unit tests total; new coverage: FeatureCatalog mapping + applicability +
unknown types, RetentionMath windows (D7/D30, signup-day exclusion, unreached
windows, cohort keys), FunnelMath (sequential conversion, empty funnel,
paid-without-usage). SQL smoke: poultry milestone progression (33% worked
example), School template override, unknown-template fallback, fact detection.

---

# Organization 360, Company 360 & Customer Success CRM (PROMPT 5 OF 7)

Migration **350** (customercrmnotes, customerproductfeedback,
subscriptioncancellationreasons), applied to both DBs;
CustomerCrm_SmokeTest.sql (5 assertions, incl. cross-org isolation and the
attention-item link) passed on dev AND prod.

- **Organization 360** (full page in Customer Intelligence, deep link
  #/intel?org=…): header (name, orgCode, country/market, subscription, health
  + reasons, last meaningful), summary cards (companies, active companies,
  users 30d, setup %, trial/paid, next billing), company list (type, template,
  plan, scale/participation, setup, last activity, trend, health), 7/30/90
  activity rollup with top categories (api/PlatformCrm/organization-activity),
  combined significant-event timeline, notes/contacts/follow-ups, product
  feedback, cancellation reasons. Deep links to Billing (preloaded owner),
  Activity Audit, and each Company 360.
- **Company 360** (deep link #/intel?company=…): header (org, type, template,
  plan, participation, health + reasons, last activity), usage stats,
  setup checklist (milestones), feature adoption depth, recent meaningful
  activity, errors summary (FailedRequests7d; full error analytics = later
  prompt), company-scoped notes, filtered-audit deep link.
- **Vertical summaries** via an adapter REGISTRY (CustomerCrmService
  SummaryProviders — no giant if/else): Poultry (active flocks/birds, last
  production, production days 30d, last sale, closings), Water (lines, last
  production, driver returns, last sale, closings), Hotel (active rooms,
  bookings 30d, check-ins 7d), Restaurant (menu, orders, closings), Generic
  (customers, sales, payments, subscriptions). Unknown families return an
  empty summary — concise support context, not a duplicate dashboard.
- **Timeline** (api/PlatformCrm/timeline): org registered, companies created,
  first meaningful/first sale per company, billing events + invoice paid /
  payment failed, trial end, health TRANSITIONS only (TimelineBuilder dedupe),
  attention items + "Customer reactivated", internal notes/contacts. Low-level
  audit rows are deliberately excluded.
- **CRM**: notes with category (Support/Sales/Onboarding/Billing/Product
  Feedback/General), optional contact type (Called/Emailed/WhatsApp/Meeting/
  Demo/Training — internal record only, no outbound connectors exist), follow-up
  date, assignee, outcome, optional attention-item link (SET NULL on delete);
  structured product feedback (category/module/severity/status); structured
  cancellation reasons (8 codes + note). Author + date always recorded;
  admin-only; mutations also captured in auditlogs by the global filter.
  Queue page gained assignee/health/company-type/follow-up filters.
- **View-as-customer**: write-capable impersonation NOT implemented — the
  customer app cannot currently guarantee the required banner/read-only/
  short-lived-session safeguards, so per the spec fallback the 360 pages are
  the read-only support context. No passwords, tokens, card data or secrets
  are ever queried or displayed.
- **Tests**: 88 unit tests (+TimelineBuilder merge/cap/health-transition
  dedupe + per-subject independence; vertical adapter registry coverage incl.
  unknown-family fallback) and the 5-assertion CRM SQL smoke test on both DBs.

---

# Billing & Revenue Intelligence (PROMPT 6 OF 7)

Migration **351** (revenuemrrsnapshots + platform_mrr_snapshot) on both DBs.
NO second billing source of truth: per-org amounts come from the SAME
evaluation path customers are billed with (PlatformBillingService.GetSummaryAsync
→ EvaluateCompanyAsync), read-time aggregation covers invoices/payments/
discounts/credits, and the only new storage is the monthly MRR snapshot that
powers movement.

- **MRR rules (tested)**: Net MRR = evaluated recurring monthly subtotal minus
  discounts, pre-tax; annual cycle = annual/12; credits are payment instruments,
  never MRR or discounts; paying = Active/PastDue/GracePeriod (Trial shown
  separately as potential); nothing non-recurring exists in this billing system.
- **api/PlatformRevenue/dashboard** (SystemAdmin/PlatformOwner/BillingAdmin):
  per-CURRENCY blocks (GHS/NGN/USD never summed, no FX invented): MRR, gross,
  ARR, paying orgs/companies, ARPO/ARPC, New/Expansion/Contraction/Churned MRR
  (vs last month's snapshot; baseline month shows as New), past-due balances,
  failed payments 30d, invoice discounts this month, outstanding credits, trial
  potential. Plus: vertical split (Generic expands by template; proportional
  discount distribution over companies' MonthlyAmount), per-org rows, Revenue
  At Risk (paying MRR × health At Risk/Inactive, declining trend, payment
  trouble, scheduled cancellation — explicitly "not a churn claim"), trial
  intelligence (ending 7/30d, conversions = first successful payment, rate,
  avg days, high-engagement-not-paid, low-engagement-ending-soon), renewals
  30d (amount/cycle/health/payment state), discount intelligence (invoice
  totals, auto multi-company vs promotional vs customer-specific, largest,
  expiring; credits excluded), credit intelligence (issued/consumed/
  outstanding/by reason), billing exceptions (PricingNotConfigured,
  ScaleSetupRequired, PastDueInvoice, MissingProviderLink,
  MarketChangePending), recovered payments. Each run refreshes this month's
  snapshots and the attention queue's revenueatrisk values (high-value
  prioritization).
- **Portal**: Revenue page (per-currency KPI rows, at-risk table in the spec's
  "ABC Farms" shape, vertical/trials/renewals/discounts/credits/exceptions);
  Customer Intelligence org table gained MRR and At-risk MRR columns (lazy-
  loaded); Needs Attention gained "High MRR at risk first" prioritization.
- **Tests**: 106 at this stage — monthly/annual/discounted MRR normalization,
  never-negative net, paying statuses, movement classification (new/expansion/
  contraction/churn/flat).

---

# Platform Operations, Errors, Security, Flags & Briefs (PROMPT 7 OF 7)

Migration **352** on both DBs (flags + rules + audit, security events with
daily dedupe, releases, briefs, retention function) — PlatformOps_SmokeTest.sql
(5 assertions) passed on dev AND prod.

- **Error intelligence**: NO logging platform rebuilt — customer-impact errors
  derive from the existing auditlogs trail (failed requests already carry
  farmid/userid/resource); GCP Cloud Logging remains the deep log store and is
  linked, not duplicated. Dashboard: errors 24h/72h/7d, affected orgs/companies,
  failed BUSINESS operations (only operations whose success would be meaningful
  activity — ActivityClassifier.IsCriticalResource), top modules/types, trend,
  failures by release. Company 360 now shows real 24h/7d error counts, recent
  failures with correlation handles (audit row ids) and the Cloud Logging hint.
- **Customer attention from errors**: FailedCriticalOperations rule in the
  health sweep ("12 failed Production postings") — ≥5 failed POSTs on one
  critical resource in 7d; harmless validation noise never alerts; auto-resolves.
- **Security monitoring** (deterministic, "flag for review", never a fraud
  claim): RepeatedFailedLogins (Identity lockout counters; ≥5 = Critical),
  PermissionChange (IAM audit rows), PaymentConfigChange (billing-admin audit
  rows), AdminSurfaceDenied (failed requests on platform-admin surfaces),
  BillingMarketChange (pending market changes). Deduped per subject per day
  with occurrence counts. Impersonation events: none, because view-as was
  deliberately not implemented (Prompt 5); exports appear in auditlogs.
- **Feature flags**: platformfeatureflags + scoped rules (Global/Market/
  CompanyFamily/BusinessTemplate/Organization/Company/User; most specific
  wins; master off always wins) resolved by pure FlagMath; rollout without
  redeploy (apps call GET api/PlatformOps/flags/{key}/evaluate — any
  authenticated user, answer is on/off + matched scope only). Full audit
  (created/enabled/disabled/rule set/removed + changedBy + reason). Flags are
  product rollout ONLY — never authorization/payment/financial integrity.
- **Release tracking**: each farm-api instance registers its Cloud Run revision
  (K_REVISION) at startup; impact = failed vs total operations 72h before/after
  first-seen + affected companies. Nothing invented when no version exists.
- **System health**: DB reachability, request/failure counts 24h, failed
  payments, last webhook; honest notes (no scheduler exists; deep metrics in
  GCP; no secrets surfaced).
- **Management briefs**: deterministic Daily/Weekly briefs assembled from the
  prompt 1-6 services (Customers / Trials / Billing-per-currency / Product /
  Operations), stored as structured JSON (platformbriefs) and rendered with
  deep links into Intel/Success/Revenue/Analytics/Audit. NO AI summarizer
  exists, so none is used — the data brief is fully useful alone, and any
  future AI layer must summarize the stored metrics (spec 16). Email delivery
  deliberately not added (no requirement to create new integrations).
- **Role separation**: scoped admin roles honored server-side —
  CustomerSuccess (health/CRM/analytics/briefs), BillingAdmin (revenue/briefs),
  TechnicalSupport (errors/releases/health), SecurityAdmin (security events +
  flag audit); SystemAdmin/PlatformOwner retain everything, flag administration
  and exports stay with them. Roles are ordinary Identity roles.
- **Export**: CSV of high-level analytics (organizations/companies) — explicit
  audit row written per export (GETs bypass the global filter); no secrets or
  raw personal data.
- **Retention**: platform_ops_retention() — security events 730d, briefs 400d,
  flag audit + releases kept; raw error metadata governed by auditlogs/Cloud
  Logging policies. Run manually until a scheduler exists.
- **Tests**: 126 total — FlagMath (master-off, defaults, global, staged
  rollout, org override, company-beats-org, user-most-specific, wrong-value
  no-match, missing context), critical-resource detection (incl. audit aliases
  and harmless surfaces), module mapping; SQL smoke: rule-scope uniqueness,
  flag audit rows, security dedupe + severity refresh + subject separation,
  release idempotency, brief upsert, retention function.
