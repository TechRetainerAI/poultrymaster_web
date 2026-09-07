-- =============================================================================
-- 237_PoultryCashMovementOnTransactions.postgres.sql
--
-- Purpose
-- -------
-- Point the Cash Movement report at the transaction-sourced cash-flow functions
-- from 235, so it and the Cash Flow page cannot disagree.
--
-- RUN AFTER 235. This file reads sppoultrycashflow_rows / _summary, and depends
-- on the row shape that 235 creates -- specifically the `flowgroup` column and
-- the rowsource values Receipt / SaleResidual / Expense / Adjustment.
--
-- What changes for the reader
-- ---------------------------
-- 232 had already moved this report off dbo.Sale/dbo.Expense and onto the cash
-- ledger. This moves it once more, onto the business transactions themselves.
-- Three things change, on top of what 232 already changed:
--
-- 1. THE ACCOUNT COLUMN IS GONE, replaced by TYPE and CATEGORY. The report no
--    longer reads cash accounts, so printing one would be fiction. What replaces
--    it is more useful anyway: whether a movement was trading or capital, and
--    what the money was actually for.
--
-- 2. RECEIPTS ARE DATED WHEN THE MONEY ARRIVED, not when the sale was made. A
--    January sale part-paid in August now appears in August. Period totals will
--    move for any farm that takes part payments.
--
-- 3. OPENING AND CLOSING ARE MEASURED, NOT DERIVED FROM BALANCES. Opening is
--    everything eligible recorded before the period; closing is opening plus the
--    period's movement. Closing will NOT equal the sum of the cash accounts, and
--    is not meant to -- that comparison is what reconciliation is for.
--
-- DROP + CREATE: rs2's column list changes, and CREATE OR REPLACE cannot alter
-- a function's returned columns. No table is created, altered or written to.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Opening balance.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryreport_cashmovement_rs1(text, date, date);

CREATE OR REPLACE FUNCTION public.sppoultryreport_cashmovement_rs1(
    p_farmid    text,
    p_startdate date,
    p_enddate   date)
RETURNS TABLE (openingcashbalance numeric)
LANGUAGE sql
STABLE
AS $$
    SELECT s.openingbalance
    FROM   public.sppoultrycashflow_summary(
               p_farmid,
               p_startdate::timestamp,
               -- Inclusive of the whole end day. A bare date means midnight and
               -- silently drops everything recorded on the last day of the range.
               (p_enddate + 1)::timestamp - interval '1 microsecond') s;
$$;

-- -----------------------------------------------------------------------------
-- 2. Movement rows.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryreport_cashmovement_rs2(text, date, date);

CREATE OR REPLACE FUNCTION public.sppoultryreport_cashmovement_rs2(
    p_farmid    text,
    p_startdate date,
    p_enddate   date)
RETURNS TABLE (
    "Date"      timestamp,
    flowgroup   text,       -- replaces cashaccount: trading vs capital
    category    text,       -- what the money was for
    sourcetype  text,
    reference   text,
    description text,
    inflow      numeric,
    outflow     numeric,
    createdby   text)
LANGUAGE sql
STABLE
AS $$
    SELECT r.transactiondate,
           r.flowgroup::text,
           r.category::text,
           r.sourcetype::text,
           -- Points at the record this movement came from, so a figure can be
           -- traced back to the sale or expense that produced it.
           CASE r.rowsource
               WHEN 'Receipt'      THEN 'Payment #'    || r.sourcerowid::text
               WHEN 'SaleResidual' THEN 'Sale #'       || r.sourcerowid::text
               WHEN 'Expense'      THEN 'Expense #'    || r.sourcerowid::text
               WHEN 'Adjustment'   THEN 'Adjustment #' || r.sourcerowid::text
               ELSE COALESCE(r.sourcetype, 'Txn') || ' #' || r.sourcerowid::text
           END::text,
           r.description::text,
           CASE WHEN r.amount > 0 THEN  r.amount ELSE 0 END,
           CASE WHEN r.amount < 0 THEN -r.amount ELSE 0 END,
           NULL::text
    FROM   public.sppoultrycashflow_detail(
               p_farmid,
               p_startdate::timestamp,
               (p_enddate + 1)::timestamp - interval '1 microsecond') r
    ORDER  BY r.transactiondate, r.rowsource, r.sourcerowid;
$$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 3. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions (2 expected)' AS check,
       CASE WHEN count(*) = 2 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sppoultryreport_cashmovement_rs1',
                     'sppoultryreport_cashmovement_rs2');

-- The report and the Cash Flow page must now agree exactly -- same functions,
-- same filters. Any non-zero difference means one of them is filtering something
-- the other is not, and this is the query that finds it.
SELECT f.farmid,
       SUM(rs.inflow)  AS report_in,
       SUM(rs.outflow) AS report_out,
       s.moneyin       AS page_in,
       s.moneyout      AS page_out,
       ROUND(SUM(rs.inflow)  - s.moneyin, 2)  AS in_should_be_zero,
       ROUND(SUM(rs.outflow) - s.moneyout, 2) AS out_should_be_zero
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultryreport_cashmovement_rs2(
                        f.farmid, '1900-01-01'::date, '2999-12-31'::date) rs
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
GROUP  BY f.farmid, s.moneyin, s.moneyout
ORDER  BY f.farmid;

-- Opening + in - out = closing, through the report's own two functions.
SELECT f.farmid,
       o.openingcashbalance AS opening,
       SUM(rs.inflow)       AS inflow,
       SUM(rs.outflow)      AS outflow,
       s.cashathand         AS closing,
       ROUND(o.openingcashbalance + SUM(rs.inflow) - SUM(rs.outflow) - s.cashathand, 2)
         AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultryreport_cashmovement_rs1(
                        f.farmid, '2000-01-01'::date, '2999-12-31'::date) o
CROSS  JOIN LATERAL public.sppoultryreport_cashmovement_rs2(
                        f.farmid, '2000-01-01'::date, '2999-12-31'::date) rs
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
GROUP  BY f.farmid, o.openingcashbalance, s.cashathand
ORDER  BY f.farmid;
