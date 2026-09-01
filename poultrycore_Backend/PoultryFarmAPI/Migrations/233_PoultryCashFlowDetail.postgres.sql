-- =============================================================================
-- 233_PoultryCashFlowDetail.postgres.sql
--
-- Purpose
-- -------
-- One function: sppoultrycashflow_detail. It is sppoultrycashflow_rows (231)
-- with a `category` column bolted on.
--
-- Why a category column is the whole point
-- ----------------------------------------
-- The ledger records WHAT KIND of thing moved money -- sourcetype is 'Sale',
-- 'Expense', 'Adjustment' -- but never WHAT THE MONEY WAS FOR. Every expense in
-- the company, feed and wages and vet bills alike, arrives as the single
-- undifferentiated bucket 'Expense'.
--
-- That is why the Cash Movement report cannot answer "where did it go": it can
-- only say "expenses". The category lives one join away on expense.category and
-- has all along; nothing was reading it.
--
-- The join is safe because sourceid IS expenseid on both legs that can carry an
-- expense -- 231:125 for a ledger row, 231:149 for an unlinked one -- so one
-- join covers both without caring which leg a row came from.
--
-- Everything else is delegated
-- ----------------------------
-- The rows, the date filtering, the transfer detection, the three exclusions
-- and the legacy-adjustment leg all stay in 231. This function adds a column
-- and nothing else, so the detail report and the Cash Flow page can never drift
-- apart -- they are reading the same rows through the same filters.
--
-- NEW FUNCTION ONLY, ZERO DROPS. Nothing existing changes behaviour.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultrycashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    category        text)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource,
           r.offledger,
           r.sourcerowid,
           r.cashaccountid,
           r.accountname,
           r.transactiondate,
           r.transactiontype,
           r.sourcetype,
           r.sourceid,
           r.istransfer,
           r.amount,
           r.description,
           CASE
               -- A transfer is not a use of money, it is the same money in a
               -- different box. Its own bucket, so a caller that shows it cannot
               -- accidentally file it under spending.
               WHEN r.istransfer THEN 'Internal transfer'

               -- The reason this function exists.
               WHEN r.sourcetype = 'Expense'
                   THEN COALESCE(NULLIF(btrim(e.category), ''), 'Uncategorised')

               WHEN r.sourcetype = 'Sale'            THEN 'Sales'
               WHEN r.sourcetype = 'SupplierPayment' THEN 'Supplier payments'

               -- Ledger adjustments store the REASON verbatim in description
               -- (129_AddPoultryCashStoredProcedures.sql:148), and the Add
               -- Adjustment dialog writes "Owner injection - bought feed cash".
               -- Group on the part before the dash, or every adjustment with a
               -- note becomes a bucket of one.
               WHEN r.sourcetype = 'Adjustment'
                   THEN COALESCE(NULLIF(btrim(split_part(r.description, ' - ', 1)), ''),
                                 'Adjustment')

               -- Legacy rows put the adjustment TYPE in sourcetype already.
               WHEN r.rowsource = 'LegacyAdjustment'
                   THEN COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Adjustment')

               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text
    FROM   public.sppoultrycashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- LEFT, deliberately: an expense deleted after its cash row was written must
    -- still appear in the report as 'Uncategorised' rather than vanish from the
    -- totals. farmid is uuid on expense and text on the ledger, hence the cast.
    LEFT   JOIN expense e
           ON  r.sourcetype = 'Expense'
           AND e.expenseid  = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'function created' AS check,
       CASE WHEN count(*) = 1 THEN 'OK' ELSE 'MISSING' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'sppoultrycashflow_detail';

-- Row count must match 231 exactly. A LEFT JOIN that accidentally multiplied
-- rows would silently double money, so this is the check that matters.
SELECT f.farmid,
       (SELECT count(*) FROM public.sppoultrycashflow_rows(f.farmid, NULL, NULL))   AS rows_231,
       (SELECT count(*) FROM public.sppoultrycashflow_detail(f.farmid, NULL, NULL)) AS rows_233,
       (SELECT count(*) FROM public.sppoultrycashflow_detail(f.farmid, NULL, NULL))
     - (SELECT count(*) FROM public.sppoultrycashflow_rows(f.farmid, NULL, NULL))   AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
ORDER  BY f.farmid;

-- What the new column actually yields, per farm. Expect real expense categories
-- (Feed, Labor, Veterinary...) rather than a wall of 'Uncategorised'.
SELECT d.category,
       count(*)                                              AS movements,
       ROUND(SUM(d.amount) FILTER (WHERE d.amount > 0), 2)   AS money_in,
       ROUND(-SUM(d.amount) FILTER (WHERE d.amount < 0), 2)  AS money_out
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultrycashflow_detail(f.farmid, NULL, NULL) d
GROUP  BY d.category
ORDER  BY COALESCE(SUM(ABS(d.amount)), 0) DESC;
