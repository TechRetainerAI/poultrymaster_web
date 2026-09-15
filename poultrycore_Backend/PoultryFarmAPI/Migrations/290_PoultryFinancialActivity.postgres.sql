-- =============================================================================
-- 290_PoultryFinancialActivity.postgres.sql
--
-- Purpose
-- -------
-- One timeline that answers, for every financial event: did cash move, was
-- revenue recognised, was an expense recognised, what did profit do, and what
-- did the farm's financial position do. It is the bridge between the two views
-- that already exist and it REPLACES NEITHER:
--
--   Cash Flow        where money came from and went          (cash only)
--   Financial Activity  what happened and what each effect was  (this file)
--   Profit & Loss    what was recognised and was there profit (accrual only)
--
-- The whole point is that Money In is not Revenue and Money Out is not Expense.
-- A loan receipt raises cash and not profit; depreciation lowers profit and not
-- cash; a deferred feed purchase spends cash now and becomes an expense later.
--
-- WHY THERE IS NO NEW EVENT TABLE
-- -------------------------------
-- A projection table was considered and rejected. This database already has one
-- authority per leg, and each is a set-returning function:
--
--   sppoultrycashflow_rows      the cash leg, already deduped
--   fnpoultrypl_revenuelines    the revenue leg (accrual, at sale date)
--   fnpoultrypl_expenselines    the expense leg, already classified
--
-- Reading those three is what makes this report agree with Cash Flow and with
-- P&L by construction. A projection table would be a second source of financial
-- truth that could silently drift from all three, and it would have to be
-- rebuilt every time one of the classifiers changed. If volume ever makes this
-- too slow, the fix is a materialised view over these same functions -- not a
-- parallel write path.
--
-- HOW THE THREE LEGS BECOME ONE ROW
-- ---------------------------------
-- Every leg emits an EVENT KEY. Legs that describe the same business event
-- carry the same key and are summed into one row; legs that describe different
-- events must NOT collide. The keys are chosen deliberately:
--
--   Sale:<saleid>              cash-at-counter + revenue   -> one row
--   CustomerPayment:<paymentid>  cash only. Keyed on the PAYMENT, never the
--                              sale: two payments against one sale are two
--                              events, and keying on the sale would also merge
--                              them into the sale's revenue and invent income.
--   Expense:<expenseid>        cash-at-entry + expense     -> one row
--   SupplierPayment:<allocid>  cash only, settling a bill already expensed.
--                              Keyed on the ALLOCATION so it cannot merge with
--                              the Expense row and expense the bill twice.
--   LoanPayment:<paymentid>    the whole payment leaving the account, plus the
--                              interest and fee expense rows it wrote. One row:
--                              Money Out 12,500, Expense 2,500. The principal
--                              never reaches the expense table, so it cannot be
--                              counted as a cost.
--   Loan:<loanid>              money in, no revenue
--   OwnerMoney:<id>            money in or out, never profit
--   CashTransfer:<id>          neither in nor out (see below)
--
-- WHAT IS DELIBERATELY NOT A CASH MOVEMENT
-- ----------------------------------------
-- Internal transfers. Bank -> MoMo is not money entering or leaving the farm,
-- so the row carries no Money In and no Money Out; the two account legs are in
-- the position detail. Cash Flow excludes transfers entirely for the same
-- reason, so the two reports still agree on Net Cash Flow.
--
-- Idempotent: CREATE OR REPLACE only. No table is altered, no data is written.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Wording. Kept in functions so the rows, the filters and any later caller
--    cannot drift apart on what an event is called.
-- -----------------------------------------------------------------------------

-- The business-friendly name of the event.
CREATE OR REPLACE FUNCTION public.fnpoultryfa_type(p_source text, p_costtype text DEFAULT NULL)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_source
        WHEN 'Sale'                          THEN 'Sale'
        WHEN 'CustomerPayment'               THEN 'Customer Payment'
        WHEN 'SupplierPayment'               THEN 'Supplier Payment'
        WHEN 'LoanReceived'                  THEN 'Loan Received'
        WHEN 'LoanPayment'                   THEN 'Loan Repayment'
        WHEN 'OwnerContribution'             THEN 'Owner Contribution'
        WHEN 'OwnerDraw'                     THEN 'Owner Draw'
        WHEN 'CashTransfer'                  THEN 'Cash Transfer'
        WHEN 'AssetDepreciation'             THEN 'Depreciation'
        WHEN 'CapitalAsset'                  THEN 'Capital Investment'
        WHEN 'CapitalAssetCost'              THEN 'Capital Investment'
        WHEN 'PoultryFeedConsumption'        THEN 'Feed Consumption'
        WHEN 'PoultryMedicationConsumption'  THEN 'Medication Consumption'
        WHEN 'PoultryInternalUsage'          THEN 'Internal Use'
        WHEN 'PoultryRawMaterialPurchase'    THEN 'Inventory Purchase'
        WHEN 'MainFlockBatch'                THEN 'Flock Purchase'
        WHEN 'Payroll'                       THEN 'Payroll'
        WHEN 'Adjustment'                    THEN 'Cash Adjustment'
        ELSE CASE WHEN COALESCE(p_costtype,'') = 'CapitalAsset' THEN 'Capital Investment'
                  ELSE 'Expense' END
    END;
$$;

-- The bucket an owner would file it under. Structured metadata only -- never a
-- keyword scan of the description, which would reclassify a row the day someone
-- edits its wording.
CREATE OR REPLACE FUNCTION public.fnpoultryfa_category(p_source text, p_costtype text DEFAULT NULL)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_source
        WHEN 'Sale'                          THEN 'Sales'
        WHEN 'CustomerPayment'               THEN 'Customer Collections'
        WHEN 'SupplierPayment'               THEN 'Supplier Payment'
        WHEN 'LoanReceived'                  THEN 'Financing'
        WHEN 'LoanPayment'                   THEN 'Financing Cost'
        WHEN 'OwnerContribution'             THEN 'Owner Capital'
        WHEN 'OwnerDraw'                     THEN 'Owner Capital'
        WHEN 'CashTransfer'                  THEN 'Internal Transfer'
        WHEN 'AssetDepreciation'             THEN 'Depreciation'
        WHEN 'CapitalAsset'                  THEN 'Capital Investment'
        WHEN 'CapitalAssetCost'              THEN 'Capital Investment'
        WHEN 'PoultryFeedConsumption'        THEN 'Cost Recognition'
        WHEN 'PoultryMedicationConsumption'  THEN 'Cost Recognition'
        WHEN 'PoultryInternalUsage'          THEN 'Internal Use'
        WHEN 'PoultryRawMaterialPurchase'    THEN 'Inventory Purchase'
        WHEN 'MainFlockBatch'                THEN 'Inventory Purchase'
        WHEN 'Payroll'                       THEN 'Payroll'
        WHEN 'Adjustment'                    THEN 'Adjustment'
        ELSE CASE WHEN COALESCE(p_costtype,'') = 'CapitalAsset' THEN 'Capital Investment'
                  ELSE 'Operating Expense' END
    END;
$$;

-- The coarse filter on the page: All | Operating | Financing | Owner | Capital |
-- Inventory | Transfer.
CREATE OR REPLACE FUNCTION public.fnpoultryfa_activitytype(p_source text, p_costtype text DEFAULT NULL)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_source IN ('LoanReceived', 'LoanPayment', 'Adjustment')        THEN 'Financing'
        WHEN p_source IN ('OwnerContribution', 'OwnerDraw')                   THEN 'Owner'
        WHEN p_source IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDepreciation')
             OR COALESCE(p_costtype,'') = 'CapitalAsset'                      THEN 'Capital'
        WHEN p_source IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                          'PoultryInternalUsage', 'PoultryRawMaterialPurchase',
                          'MainFlockBatch')                                   THEN 'Inventory'
        WHEN p_source = 'CashTransfer'                                        THEN 'Transfer'
        ELSE 'Operating'
    END;
$$;

-- -----------------------------------------------------------------------------
-- 2. The events. Three legs in, one row per business event out.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_events(
    p_farmid text, p_from date, p_to date)
RETURNS TABLE (
    eventkey        text,
    businessdate    date,
    occurredat      timestamp,
    activitytype    text,
    type            text,
    category        text,
    description     text,
    sourcetype      text,
    sourceid        integer,
    sourcenumber    text,
    moneyin         numeric,
    moneyout        numeric,
    revenue         numeric,
    expense         numeric,
    profitimpact    numeric,
    iscash          boolean,
    isnoncash       boolean,
    istransfer      boolean,
    cashaccountid   integer,
    partyname       text,
    plline          text,
    status          text
)
LANGUAGE sql
STABLE
AS $$
    WITH legs AS (
        -- ---- leg A: cash -----------------------------------------------------
        -- sppoultrycashflow_rows is the authority. It already resolves receipts
        -- against sale residuals, expense-at-entry against later supplier
        -- payments, drops reversed rows and excludes NonCash. Re-deriving any of
        -- that here is how the two reports would start disagreeing.
        SELECT CASE r.sourcetype
                   WHEN 'CustomerPayment'   THEN 'CustomerPayment:' || r.sourcerowid
                   WHEN 'Sale'              THEN 'Sale:'            || r.sourceid
                   WHEN 'Expense'           THEN 'Expense:'         || r.sourceid
                   WHEN 'ExpensePayment'    THEN 'SupplierPayment:' || r.sourcerowid
                   WHEN 'OwnerContribution' THEN 'OwnerMoney:'      || r.sourcerowid
                   WHEN 'OwnerDraw'         THEN 'OwnerMoney:'      || r.sourcerowid
                   WHEN 'LoanReceived'      THEN 'Loan:'            || r.sourceid
                   WHEN 'LoanRepayment'     THEN 'LoanPayment:'     || r.sourcerowid
                   ELSE 'Cash:' || r.rowsource || ':' || r.sourcerowid
               END                                        AS eventkey,
               2                                          AS metapri,
               r.transactiondate::date                    AS businessdate,
               r.transactiondate                          AS occurredat,
               CASE r.sourcetype
                   WHEN 'ExpensePayment' THEN 'SupplierPayment'
                   WHEN 'LoanRepayment'  THEN 'LoanPayment'
                   ELSE r.sourcetype
               END                                        AS src,
               NULL::text                                 AS costtype,
               r.description                              AS description,
               r.sourceid                                 AS sourceid,
               NULL::text                                 AS sourcenumber,
               GREATEST(r.amount, 0)                      AS moneyin,
               GREATEST(-r.amount, 0)                     AS moneyout,
               0::numeric                                 AS revenue,
               0::numeric                                 AS expense,
               FALSE                                      AS istransfer,
               r.cashaccountid                            AS cashaccountid,
               NULL::text                                 AS partyname,
               NULL::text                                 AS plline,
               'Posted'::text                             AS status
        FROM   public.sppoultrycashflow_rows(
                   p_farmid,
                   p_from::timestamp,
                   ((p_to + 1)::timestamp - interval '1 microsecond')) r
        WHERE  r.amount <> 0

        UNION ALL

        -- ---- leg B: revenue --------------------------------------------------
        -- Recognised when the SALE happened, not when it was paid. A credit sale
        -- is revenue today with no cash; a collection months later is cash with
        -- no revenue. Both are the point of this report.
        SELECT 'Sale:' || v.saleid,
               1,
               v.saledate::date,
               v.saledate,
               'Sale',
               NULL::text,
               ('Sale #' || v.saleid ||
                COALESCE(' - ' || NULLIF(btrim(v.customername), ''), '') ||
                COALESCE(' (' || NULLIF(btrim(v.product), '') || ')', '')),
               v.saleid,
               ('#' || v.saleid)::text,
               0::numeric,
               0::numeric,
               COALESCE(v.totalamount, 0),
               0::numeric,
               FALSE,
               NULL::integer,
               NULLIF(btrim(v.customername), ''),
               v.revenueline,
               'Posted'::text
        FROM   public.fnpoultrypl_revenuelines(p_farmid, p_from, p_to) v

        UNION ALL

        -- ---- leg C: expense --------------------------------------------------
        -- The expense table is this database's single P&L expense ledger:
        -- consumption recognition, depreciation, loan interest, payroll and
        -- internal use all post there, already classified by 272's functions.
        --
        -- EXCLUDED rows are still emitted, at zero. A capital asset and a
        -- deferred inventory purchase move cash and must appear as events, and
        -- this leg is the only one that knows what kind of event they are -- but
        -- neither is an expense, so the amount is zeroed rather than the row
        -- dropped. That is exactly the "cash moved, profit did not" case.
        SELECT CASE WHEN e.sourcetype = 'LoanPayment'
                    THEN 'LoanPayment:' || e.sourceid
                    ELSE 'Expense:'     || e.expenseid
               END,
               -- The cash leg names a loan repayment better than its interest
               -- line does, so it wins the wording for that one event only.
               CASE WHEN e.sourcetype = 'LoanPayment' THEN 3 ELSE 1 END,
               e.expensedate::date,
               e.expensedate,
               COALESCE(NULLIF(btrim(e.sourcetype), ''), 'Expense'),
               e.costtype,
               COALESCE(NULLIF(btrim(e.description), ''), e.category),
               e.expenseid,
               NULL::text,
               0::numeric,
               0::numeric,
               0::numeric,
               CASE WHEN e.plsection = 'Excluded' THEN 0::numeric ELSE COALESCE(e.amount, 0) END,
               FALSE,
               NULL::integer,
               NULLIF(btrim(e.suppliername), ''),
               e.plline,
               'Posted'::text
        FROM   public.fnpoultrypl_expenselines(p_farmid, p_from, p_to) e

        UNION ALL

        -- ---- leg D: internal transfers --------------------------------------
        -- Neither in nor out at company level: the farm's own money changed
        -- pocket. Carried so the timeline is complete and so the account legs
        -- can be shown in the position detail, with both cash columns at zero so
        -- it cannot inflate Money In / Money Out. Cash Flow omits transfers for
        -- the same reason, which is what keeps the two Net Cash Flows equal.
        SELECT 'CashTransfer:' || t.poultrycashtransferid,
               1,
               t.transferdate::date,
               t.transferdate,
               'CashTransfer',
               NULL::text,
               COALESCE(NULLIF(btrim(t.notes), ''),
                        'Transfer ' || COALESCE(fa.accountname, 'account') ||
                        ' to ' || COALESCE(ta.accountname, 'account')),
               t.poultrycashtransferid,
               NULLIF(btrim(t.transfernumber), ''),
               0::numeric,
               0::numeric,
               0::numeric,
               0::numeric,
               TRUE,
               t.frompoultrycashaccountid,
               NULL::text,
               NULL::text,
               t.status::text
        FROM   poultrycashtransfers t
        LEFT   JOIN poultrycashaccounts fa ON fa.poultrycashaccountid = t.frompoultrycashaccountid
        LEFT   JOIN poultrycashaccounts ta ON ta.poultrycashaccountid = t.topoultrycashaccountid
        WHERE  t.farmid = p_farmid
          -- 'Approved' is the only status in which the money has actually moved.
          -- The workflow is Draft -> Approved -> Reversed (252); a Draft has not
          -- moved anything and a Reversed one has been put back.
          AND  t.status = 'Approved'
          AND  t.transferdate >= p_from::timestamp
          AND  t.transferdate <  (p_to + 1)::timestamp
    ),
    merged AS (
        SELECT l.eventkey,
               -- Metadata comes from ONE leg, the one that knows most about this
               -- kind of event, rather than being coalesced field by field from
               -- several -- which is how a row ends up with one leg's date and
               -- another leg's description.
               (array_agg(l.businessdate ORDER BY l.metapri, l.occurredat))[1] AS businessdate,
               (array_agg(l.occurredat   ORDER BY l.metapri, l.occurredat))[1] AS occurredat,
               (array_agg(l.src          ORDER BY l.metapri, l.occurredat))[1] AS src,
               (array_agg(l.costtype     ORDER BY l.metapri, l.occurredat))[1] AS costtype,
               (array_agg(l.description  ORDER BY l.metapri, l.occurredat))[1] AS description,
               (array_agg(l.sourceid     ORDER BY l.metapri, l.occurredat))[1] AS sourceid,
               (array_agg(l.sourcenumber ORDER BY l.metapri, l.occurredat))[1] AS sourcenumber,
               (array_agg(l.plline       ORDER BY l.metapri, l.occurredat))[1] AS plline,
               (array_agg(l.status       ORDER BY l.metapri, l.occurredat))[1] AS status,
               MAX(l.cashaccountid)                                            AS cashaccountid,
               MAX(l.partyname)                                                AS partyname,
               BOOL_OR(l.istransfer)                                           AS istransfer,
               ROUND(SUM(l.moneyin),  2)                                       AS moneyin,
               ROUND(SUM(l.moneyout), 2)                                       AS moneyout,
               ROUND(SUM(l.revenue),  2)                                       AS revenue,
               ROUND(SUM(l.expense),  2)                                       AS expense
        FROM   legs l
        GROUP  BY l.eventkey
    )
    SELECT m.eventkey,
           m.businessdate,
           m.occurredat,
           public.fnpoultryfa_activitytype(m.src, m.costtype),
           public.fnpoultryfa_type(m.src, m.costtype),
           public.fnpoultryfa_category(m.src, m.costtype),
           m.description,
           m.src,
           m.sourceid,
           m.sourcenumber,
           m.moneyin,
           m.moneyout,
           m.revenue,
           m.expense,
           -- Profit is what was RECOGNISED, never what moved. Adding money in or
           -- out here is the single mistake this whole report exists to prevent.
           ROUND(m.revenue - m.expense, 2),
           (m.moneyin + m.moneyout) > 0,
           (m.moneyin + m.moneyout) = 0 AND (m.revenue + m.expense) > 0,
           m.istransfer,
           m.cashaccountid,
           m.partyname,
           m.plline,
           m.status
    FROM   merged m
    -- An event with nothing on any leg is not an event.
    WHERE  m.moneyin <> 0 OR m.moneyout <> 0 OR m.revenue <> 0 OR m.expense <> 0
        OR m.istransfer;
$$;

-- -----------------------------------------------------------------------------
-- 3. The rows, with a running cash position.
-- -----------------------------------------------------------------------------
-- Running cash is seeded from sppoultrycashflow_summary's opening balance, not
-- recomputed here: the page must not invent a second cash algorithm. Non-cash
-- events carry the balance forward unchanged, which is what makes depreciation
-- visibly not touch cash.
CREATE OR REPLACE FUNCTION public.sppoultryfinancialactivity_get(
    p_farmid text, p_from date, p_to date)
RETURNS TABLE (
    eventkey        text,
    businessdate    date,
    occurredat      timestamp,
    activitytype    text,
    type            text,
    category        text,
    description     text,
    sourcetype      text,
    sourceid        integer,
    sourcenumber    text,
    moneyin         numeric,
    moneyout        numeric,
    revenue         numeric,
    expense         numeric,
    profitimpact    numeric,
    runningcash     numeric,
    iscash          boolean,
    isnoncash       boolean,
    istransfer      boolean,
    cashaccountid   integer,
    cashaccountname text,
    partyname       text,
    plline          text,
    status          text
)
LANGUAGE sql
STABLE
AS $$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
        FROM   public.sppoultrycashflow_summary(
                   p_farmid, p_from::timestamp,
                   ((p_to + 1)::timestamp - interval '1 microsecond')) s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.activitytype, e.type,
           e.category, e.description, e.sourcetype, e.sourceid, e.sourcenumber,
           e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.occurredat, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer,
           e.cashaccountid, a.accountname::text, e.partyname, e.plline, e.status
    FROM   public.fnpoultryfa_events(p_farmid, p_from, p_to) e
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = e.cashaccountid
    ORDER  BY e.businessdate, e.occurredat, e.eventkey;
$$;

-- -----------------------------------------------------------------------------
-- 4. Period totals.
-- -----------------------------------------------------------------------------
-- Cash figures come from the Cash Flow summary so the two pages cannot report
-- different Net Cash Flow for the same period. Revenue and expense are summed
-- from the events, which are the P&L's own lines.
CREATE OR REPLACE FUNCTION public.sppoultryfinancialactivity_summary(
    p_farmid text, p_from date, p_to date)
RETURNS TABLE (
    moneyin        numeric,
    moneyout       numeric,
    netcashflow    numeric,
    openingcash    numeric,
    closingcash    numeric,
    revenue        numeric,
    expense        numeric,
    netprofit      numeric,
    eventcount     integer,
    cashevents     integer,
    noncashevents  integer
)
LANGUAGE sql
STABLE
AS $$
    WITH cf AS (
        SELECT * FROM public.sppoultrycashflow_summary(
            p_farmid, p_from::timestamp, ((p_to + 1)::timestamp - interval '1 microsecond'))
    ),
    ev AS (
        SELECT COALESCE(SUM(e.revenue), 0)                       AS rev,
               COALESCE(SUM(e.expense), 0)                       AS exp,
               COUNT(*)                                          AS n,
               COUNT(*) FILTER (WHERE e.iscash)                   AS ncash,
               COUNT(*) FILTER (WHERE e.isnoncash)                AS nnoncash
        FROM   public.fnpoultryfa_events(p_farmid, p_from, p_to) e
    )
    SELECT ROUND(cf.moneyin, 2),
           ROUND(cf.moneyout, 2),
           ROUND(cf.netcashflow, 2),
           ROUND(cf.openingbalance, 2),
           ROUND(cf.cashathand, 2),
           ROUND(ev.rev, 2),
           ROUND(ev.exp, 2),
           ROUND(ev.rev - ev.exp, 2),
           ev.n::integer,
           ev.ncash::integer,
           ev.nnoncash::integer
    FROM   cf CROSS JOIN ev;
$$;

-- -----------------------------------------------------------------------------
-- 5. What each event did to the farm's financial position.
-- -----------------------------------------------------------------------------
-- Returned for the whole period in one call, keyed by event, so the page can
-- expand any row without a request per row.
--
-- This is NOT a general ledger. There are no debits, no credits and no chart of
-- accounts -- only the handful of positions a farm owner already understands and
-- that this database actually tracks.
CREATE OR REPLACE FUNCTION public.fnpoultryfa_positions(
    p_farmid text, p_from date, p_to date)
RETURNS TABLE (
    eventkey      text,
    positiontype  text,
    positionname  text,
    increaseamount numeric,
    decreaseamount numeric,
    explanation   text
)
LANGUAGE sql
STABLE
AS $$
    -- Loan received: the debt the farm took on. The LIABILITY is the principal;
    -- the CASH was amountreceived, which is smaller when the lender withheld a
    -- fee. Two different numbers on purpose.
    SELECT 'Loan:' || l.poultryloanid,
           'LoanLiability',
           l.lendername::text,
           l.originalprincipal::numeric, 0::numeric,
           'Outstanding loan increased'
    FROM   poultryloans l
    WHERE  l.farmid = p_farmid
      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')
      AND  l.loandate >= p_from AND l.loandate <= p_to

    UNION ALL
    -- Loan repayment: only the PRINCIPAL reduces the debt. Interest and fees are
    -- the cost of borrowing and are already the expense leg of the same row.
    SELECT 'LoanPayment:' || p.poultryloanpaymentid,
           'LoanLiability',
           l.lendername::text,
           0::numeric, p.principalamount::numeric,
           'Outstanding loan reduced'
    FROM   poultryloanpayments p
    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid
    WHERE  p.farmid = p_farmid AND p.status = 'Posted'
      AND  p.principalamount > 0
      AND  p.paymentdate >= p_from::timestamp AND p.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    SELECT 'OwnerMoney:' || o.poultryownermoneyid,
           'OwnerCapital',
           COALESCE(NULLIF(btrim(o.ownername), ''), 'Owner'),
           CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE 0 END::numeric,
           CASE WHEN o.transactiontype = 'Contribution' THEN 0 ELSE o.amount END::numeric,
           CASE WHEN o.transactiontype = 'Contribution'
                THEN 'Owner funding increased' ELSE 'Owner funding reduced' END
    FROM   poultryownermoney o
    WHERE  o.farmid = p_farmid AND o.status = 'Posted'
      AND  o.transactiondate >= p_from::timestamp AND o.transactiondate < (p_to + 1)::timestamp

    UNION ALL
    -- A collection settles a debt the customer already owed. No revenue: that
    -- was recognised when the sale happened.
    SELECT 'CustomerPayment:' || pp.poultrypaymentid,
           'CustomerReceivable',
           COALESCE(NULLIF(btrim(s.customername), ''), 'Customer'),
           0::numeric, pp.amount::numeric,
           'Customer debt reduced'
    FROM   poultrypayments pp
    LEFT   JOIN sale s ON s.saleid = pp.saleid
    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- The unpaid part of a sale is money the customer now owes.
    SELECT 'Sale:' || s.saleid,
           'CustomerReceivable',
           COALESCE(NULLIF(btrim(s.customername), ''), 'Customer'),
           v.owed, 0::numeric,
           'Customer now owes this amount'
    FROM   sale s
    CROSS  JOIN LATERAL (
        SELECT ROUND(COALESCE(s.totalamount, 0)
                     - CASE WHEN COALESCE(s.paid, false) THEN COALESCE(s.totalamount, 0)
                            ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                       COALESCE(s.totalamount, 0)) END, 2) AS owed
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  v.owed > 0
      AND  s.saledate >= p_from AND s.saledate <= p_to

    UNION ALL
    -- The unpaid part of a bill is money the farm now owes its supplier.
    SELECT 'Expense:' || e.expenseid,
           'SupplierPayable',
           COALESCE(NULLIF(btrim(s.name), ''), 'Supplier'),
           v.owed, 0::numeric,
           'Supplier is owed this amount'
    FROM   expense e
    LEFT   JOIN supplier s ON s.supplierid = e.supplierid
    CROSS  JOIN LATERAL (
        SELECT ROUND(GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0), 2) AS owed
    ) v
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  v.owed > 0
      AND  e.expensedate >= p_from AND e.expensedate < (p_to + 1)

    UNION ALL
    -- Paying a supplier settles that debt. It is not a second expense.
    SELECT 'SupplierPayment:' || sa.allocationid,
           'SupplierPayable',
           COALESCE(NULLIF(btrim(s.name), ''), 'Supplier'),
           0::numeric, sa.amountapplied::numeric,
           'Supplier debt reduced'
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry'
      AND  sa.status = 'Posted' AND sp.status = 'Posted' AND sa.amountapplied <> 0
      AND  sp.paymentdate >= p_from::timestamp AND sp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- Stock bought, and stock consumed. Which of the two an item does at
    -- purchase is the farm's cost-recognition setting (261-268); this reads the
    -- classification rather than re-deciding it.
    SELECT 'Expense:' || e.expenseid,
           CASE WHEN e.costtype = 'CapitalAsset' THEN 'CapitalAsset'
                WHEN e.sourcetype = 'AssetDepreciation' THEN 'AccumulatedDepreciation'
                ELSE 'Inventory' END,
           CASE WHEN e.costtype = 'CapitalAsset' THEN COALESCE(NULLIF(btrim(e.description),''), 'Capital asset')
                WHEN e.sourcetype = 'AssetDepreciation' THEN COALESCE(NULLIF(btrim(e.description),''), 'Depreciation')
                ELSE COALESCE(NULLIF(btrim(e.category), ''), 'Inventory') END,
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                                      'PoultryInternalUsage')
                THEN 0 ELSE COALESCE(e.amount, 0) END::numeric,
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                                      'PoultryInternalUsage')
                THEN COALESCE(e.amount, 0) ELSE 0 END::numeric,
           CASE WHEN e.costtype = 'CapitalAsset'            THEN 'Capital asset acquired'
                WHEN e.sourcetype = 'AssetDepreciation'     THEN 'Asset book value reduced'
                WHEN e.sourcetype = 'PoultryFeedConsumption' THEN 'Feed stock consumed'
                WHEN e.sourcetype = 'PoultryMedicationConsumption' THEN 'Medication stock consumed'
                WHEN e.sourcetype = 'PoultryInternalUsage'  THEN 'Stock taken for internal use'
                ELSE 'Inventory value increased' END
    FROM   public.fnpoultrypl_expenselines(p_farmid, p_from, p_to) e
    WHERE  e.costtype = 'CapitalAsset'
       OR  e.sourcetype IN ('AssetDepreciation', 'PoultryFeedConsumption',
                            'PoultryMedicationConsumption', 'PoultryInternalUsage',
                            'PoultryRawMaterialPurchase', 'MainFlockBatch')

    UNION ALL
    -- Both legs of a transfer, which is the whole explanation of why the event
    -- shows no Money In and no Money Out: the money is still the farm's.
    SELECT 'CashTransfer:' || t.poultrycashtransferid,
           'Cash', COALESCE(fa.accountname::text, 'From account'),
           0::numeric, t.amount::numeric, 'Money left this account'
    FROM   poultrycashtransfers t
    LEFT   JOIN poultrycashaccounts fa ON fa.poultrycashaccountid = t.frompoultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.status = 'Approved'
      AND  t.transferdate >= p_from::timestamp AND t.transferdate < (p_to + 1)::timestamp

    UNION ALL
    SELECT 'CashTransfer:' || t.poultrycashtransferid,
           'Cash', COALESCE(ta.accountname::text, 'To account'),
           t.amount::numeric, 0::numeric, 'Money arrived in this account'
    FROM   poultrycashtransfers t
    LEFT   JOIN poultrycashaccounts ta ON ta.poultrycashaccountid = t.topoultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.status = 'Approved'
      AND  t.transferdate >= p_from::timestamp AND t.transferdate < (p_to + 1)::timestamp;
$$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'financial activity functions (7 expected)' AS check,
       CASE WHEN count(*) = 7 THEN 'OK' ELSE 'MISSING (' || count(*) || ')' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnpoultryfa_type', 'fnpoultryfa_category', 'fnpoultryfa_activitytype',
                     'fnpoultryfa_events', 'fnpoultryfa_positions',
                     'sppoultryfinancialactivity_get', 'sppoultryfinancialactivity_summary');

-- Net Cash Flow here MUST equal Cash Flow's for the same period, or the two
-- pages will disagree in front of the owner. Expect zero drift on every farm.
SELECT f.farmid,
       ROUND(a.moneyin - a.moneyout, 2)   AS activity_net,
       ROUND(c.netcashflow, 2)            AS cashflow_net,
       ROUND((a.moneyin - a.moneyout) - c.netcashflow, 2) AS drift
FROM   (SELECT DISTINCT farmid FROM sale) f
CROSS  JOIN LATERAL public.sppoultryfinancialactivity_summary(f.farmid, '2000-01-01', '2100-01-01') a
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, '2000-01-01'::timestamp, '2100-01-01'::timestamp) c
WHERE  ROUND((a.moneyin - a.moneyout) - c.netcashflow, 2) <> 0;

-- Every event must balance: profit impact is revenue less expense and nothing
-- else. Expect zero rows.
SELECT e.eventkey, e.revenue, e.expense, e.profitimpact
FROM   (SELECT DISTINCT farmid FROM sale) f
CROSS  JOIN LATERAL public.fnpoultryfa_events(f.farmid, '2000-01-01', '2100-01-01') e
WHERE  ROUND(e.profitimpact - (e.revenue - e.expense), 2) <> 0;
