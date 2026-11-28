-- =============================================================================
-- 512_Emma_StaffPaymentsShowPayroll.postgres.sql
--
-- Bug fix: the Employee Payments page only shows direct (one-off) staff
-- payments. Employees paid through a payroll run never appeared there.
--
-- Fix: replace spgenericstaffpayment_getall with a UNION that merges direct
-- payments from genericstaffpayments AND individual payroll line items from
-- genericpayrollitems (only from Paid runs). The return shape is unchanged so
-- the frontend and C# model need no modification.
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.spgenericstaffpayment_getall(text, integer, date, date);

CREATE OR REPLACE FUNCTION public.spgenericstaffpayment_getall(
    p_farmid  text,
    p_staffid integer DEFAULT NULL::integer,
    p_from    date    DEFAULT NULL::date,
    p_to      date    DEFAULT NULL::date)
RETURNS TABLE(
    genericstaffpaymentid integer, genericstaffid integer, staffname text,
    staffrole text, workertype text, paymentdate timestamp without time zone,
    periodstart date, periodend date, amount numeric, paymentmethod text,
    genericcashaccountid integer, cashaccountname text,
    genericexpenseid integer, categoryname text, description text,
    referenceno text, status text, createdby text,
    reversedby text, reversedat timestamp without time zone, reversalreason text)
LANGUAGE sql
STABLE
AS $function$
    -- 1. Direct (one-off) staff payments — the original query.
    SELECT sp.genericstaffpaymentid, sp.genericstaffid,
           btrim(COALESCE(s.firstname, '') || ' ' || COALESCE(s.lastname, ''))::text,
           s.role::text, COALESCE(s.workertype, 'Employee')::text,
           sp.paymentdate, sp.periodstart, sp.periodend, sp.amount, sp.paymentmethod,
           sp.genericcashaccountid, a.accountname::text,
           sp.genericexpenseid, c.name::text, sp.description, sp.referenceno,
           sp.status, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason
    FROM   genericstaffpayments sp
    LEFT   JOIN genericstaff s          ON s.genericstaffid = sp.genericstaffid
    LEFT   JOIN genericcashaccounts a   ON a.genericcashaccountid = sp.genericcashaccountid
    LEFT   JOIN genericexpensecategories c ON c.genericexpensecategoryid = sp.genericexpensecategoryid
    WHERE  sp.farmid = p_farmid
      AND  (p_staffid IS NULL OR sp.genericstaffid = p_staffid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)

    UNION ALL

    -- 2. Payroll line items — one row per employee per Paid run (512).
    SELECT -(pi2.genericpayrollitemid)::integer,          -- negative id to avoid PK collision
           pi2.genericstaffid,
           btrim(COALESCE(s2.firstname, '') || ' ' || COALESCE(s2.lastname, ''))::text,
           s2.role::text, COALESCE(s2.workertype, 'Employee')::text,
           COALESCE(r2.paydate::timestamp, r2.paidat, r2.createdat),  -- payment date
           r2.periodstart::date, r2.periodend::date,
           pi2.netpay,                                                 -- amount
           'Payroll'::text,                                            -- paymentmethod
           r2.genericcashaccountid,
           a2.accountname::text,
           NULL::integer,                                              -- no linked expense
           NULL::text,                                                 -- no category
           ('Payroll #' || r2.genericpayrollrunid::text
            || ' (' || to_char(r2.periodstart, 'DD Mon') || ' – '
            || to_char(r2.periodend, 'DD Mon YYYY') || ')')::text,
           NULL::text,                                                 -- no reference
           'Posted'::text,                                             -- status
           r2.paidby::text,
           NULL::text, NULL::timestamp, NULL::text                     -- not reversible from here
    FROM   genericpayrollitems pi2
    INNER  JOIN genericpayrollruns r2
        ON r2.genericpayrollrunid = pi2.genericpayrollrunid
    LEFT   JOIN genericstaff s2        ON s2.genericstaffid = pi2.genericstaffid
    LEFT   JOIN genericcashaccounts a2 ON a2.genericcashaccountid = r2.genericcashaccountid
    WHERE  r2.farmid = p_farmid
      AND  r2.status = 'Paid'
      AND  COALESCE(r2.isdeleted, FALSE) = FALSE
      AND  COALESCE(pi2.netpay, 0) > 0
      AND  (p_staffid IS NULL OR pi2.genericstaffid = p_staffid)
      AND  (p_from IS NULL OR COALESCE(r2.paydate::date, r2.paidat::date, r2.createdat::date) >= p_from)
      AND  (p_to   IS NULL OR COALESCE(r2.paydate::date, r2.paidat::date, r2.createdat::date) <= p_to)

    ORDER  BY paymentdate DESC, genericstaffpaymentid DESC;
$function$;

COMMIT;
