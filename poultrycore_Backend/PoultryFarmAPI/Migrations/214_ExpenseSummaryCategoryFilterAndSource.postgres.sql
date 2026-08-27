-- =============================================================================
-- 214_ExpenseSummaryCategoryFilterAndSource.postgres.sql
--
-- Problem
-- -------
-- The Expense Summary report reads thin next to /expenses, and two of its nine
-- columns cannot show anything useful:
--
--   * Status — the expense table has no payment-status column at all. The
--     service hardcodes "Paid" on every row (and files a warning saying so), so
--     the column repeats one constant down the page. The Paid / Unpaid summary
--     cards are the same constant: PaidExpenses = total, UnpaidExpenses = 0.
--   * Flock and Supplier are genuinely populated (72 and 34 of 153 expenses),
--     but blank on the rows most farms look at first.
--
-- Meanwhile the one field that explains where an expense came from —
-- expense.sourcetype, set on 79 of 153 rows — is not returned at all. That is
-- what tells you a row is a raw-material purchase, a flock batch, or a driver
-- return rather than something typed by hand.
--
-- There is also no way to filter by category, which is the first thing anyone
-- asks of an expense report. 'Raw Materials / Inventory Purchase' alone is 70
-- of 153 rows and drowns everything else.
--
-- Fix
-- ---
--   1. Return e.sourcetype so the report can show where each expense came from.
--   2. Add p_category so the report can be filtered to one category. The
--      service computes the summary cards from the returned rows, so filtering
--      here keeps the cards and the table telling the same story — a
--      client-side filter would have left the totals describing everything.
--
-- The category match is case-insensitive and exact-after-trim, so the value
-- picked in the UI matches regardless of stored casing.
--
-- Note on the DROP: adding a parameter and changing the return type both make
-- this a different function to Postgres. CREATE OR REPLACE alone would leave
-- the old five-argument version in place, and the service's named-argument call
-- would then be ambiguous between the two. The old signature is dropped first.
--
-- Idempotent: the DROP is IF EXISTS and the CREATE is OR REPLACE.
-- =============================================================================

\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS public.sppoultryreport_expensesummary(text, date, date, integer, text);

CREATE OR REPLACE FUNCTION public.sppoultryreport_expensesummary(
    p_farmid    text,
    p_startdate date,
    p_enddate   date,
    p_flockid   integer DEFAULT NULL::integer,
    p_supplier  text    DEFAULT NULL::text,
    p_category  text    DEFAULT NULL::text
)
RETURNS TABLE (
    date          date,
    expenseid     integer,
    category      text,
    description   text,
    supplier      text,
    amount        numeric,
    paymentmethod text,
    sourcetype    text,
    flockid       integer,
    flockname     text,
    createdby     text
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    RETURN QUERY
    SELECT
        e.expensedate::date         AS date,
        e.expenseid                 AS expenseid,
        e.category::text            AS category,
        e.description::text         AS description,
        e.supplier::text            AS supplier,
        e.amount                    AS amount,
        e.paymentmethod::text       AS paymentmethod,
        e.sourcetype::text          AS sourcetype,
        e.flockid                   AS flockid,
        f.name::text                AS flockname,
        e.userid::text              AS createdby
    FROM   expense e
    LEFT JOIN flock f ON f.flockid = e.flockid AND f.farmid = p_farmid
    WHERE  e.farmid = v_gid
      AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)
      AND  (p_flockid IS NULL OR e.flockid = p_flockid)
      AND  (p_supplier IS NULL OR e.supplier = p_supplier)
      AND  (NULLIF(btrim(COALESCE(p_category, '')), '') IS NULL
            OR lower(btrim(e.category)) = lower(btrim(p_category)))
    ORDER  BY e.expensedate DESC, e.expenseid DESC;
END
$function$;

DO $grant$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'Techretainer') THEN
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.sppoultryreport_expensesummary(text, date, date, integer, text, text) TO "Techretainer"';
    END IF;
END
$grant$;

-- 214_ExpenseSummaryCategoryFilterAndSource.postgres.sql complete.
