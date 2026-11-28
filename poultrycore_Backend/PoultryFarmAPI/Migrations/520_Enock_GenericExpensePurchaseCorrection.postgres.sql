-- =============================================================================
-- 520_Enock_GenericExpensePurchaseCorrection.postgres.sql
--
-- "Edit & repost" for Generic EXPENSES (504) and INVENTORY PURCHASES (500):
-- the Water 458 / Generic sale 485 model.
--
--   Edit & repost   on a reversed expense/purchase, open the New form filled
--                   in from it; the saved record is LINKED to the reversed one
--
--   genericexpenses.correctsexpenseid    new expense  -> the reversed expense
--   genericpurchases.correctspurchaseid  new purchase -> the reversed purchase
--
-- One live correction per reversed record. "Live" = not deleted and not
-- Cancelled, so if the correcting draft is deleted/cancelled (or itself
-- reversed) the original can be reposted again -- worked out, never stored on
-- the reversal, exactly as 485 does for sales.
--
-- No money or stock moves here: the new record is an ordinary Draft that is
-- approved as usual. Needs 500 + 505 (lists return the reversal id).
-- Live list bodies dumped from dev 2026-11-28 (pg_get_functiondef), + 2 columns.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'spgenericexpense_reversalget') THEN
    RAISE EXCEPTION '520 needs 504_Enock_GenericExpenseReversal first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'spgenericpurchase_reversalget') THEN
    RAISE EXCEPTION '520 needs 500_Enock_GenericPurchaseReversal first.';
  END IF;
END $$;

-- ------------------------------------------------------------------ 1. schema --
ALTER TABLE public.genericexpenses  ADD COLUMN IF NOT EXISTS correctsexpenseid  integer NULL;
ALTER TABLE public.genericpurchases ADD COLUMN IF NOT EXISTS correctspurchaseid integer NULL;
CREATE INDEX IF NOT EXISTS ix_genericexpenses_correctsexpense
    ON public.genericexpenses (correctsexpenseid) WHERE correctsexpenseid IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_genericpurchases_correctspurchase
    ON public.genericpurchases (correctspurchaseid) WHERE correctspurchaseid IS NOT NULL;

-- ------------------------------------------------- 2. the live correction --
CREATE OR REPLACE FUNCTION public.fngenericexpense_correctedby(p_farmid text, p_expenseid integer)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT min(n.genericexpenseid)
    FROM   genericexpenses n
    WHERE  n.farmid = p_farmid AND n.correctsexpenseid = p_expenseid
      AND  n.isdeleted = FALSE AND n.status <> 'Cancelled';
$$;

CREATE OR REPLACE FUNCTION public.fngenericpurchase_correctedby(p_farmid text, p_purchaseid integer)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT min(n.genericpurchaseid)
    FROM   genericpurchases n
    WHERE  n.farmid = p_farmid AND n.correctspurchaseid = p_purchaseid
      AND  n.isdeleted = FALSE AND n.status <> 'Cancelled';
$$;

-- ------------------------------------------------------------ 3. the links --
DROP FUNCTION IF EXISTS public.spgenericexpense_linkcorrection(text, integer, integer, text);
CREATE FUNCTION public.spgenericexpense_linkcorrection(p_farmid text, p_newexpenseid integer, p_correctsexpenseid integer, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_prev integer;
BEGIN
    IF p_newexpenseid = p_correctsexpenseid THEN
        RAISE EXCEPTION 'An expense cannot correct itself.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericexpenses e WHERE e.genericexpenseid = p_newexpenseid AND e.farmid = p_farmid
                   AND e.isdeleted = FALSE AND e.expensereversalid IS NULL AND e.status <> 'Cancelled') THEN
        RAISE EXCEPTION 'The corrected expense was not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericexpenses e WHERE e.genericexpenseid = p_correctsexpenseid AND e.farmid = p_farmid
                   AND e.expensereversalid IS NOT NULL) THEN
        RAISE EXCEPTION 'Expense #% is not a reversed expense of this company, so nothing can be reposted from it.', p_correctsexpenseid
            USING ERRCODE = 'P0001';
    END IF;
    v_prev := fngenericexpense_correctedby(p_farmid, p_correctsexpenseid);
    IF v_prev IS NOT NULL AND v_prev <> p_newexpenseid THEN
        RAISE EXCEPTION 'Expense #% was already reposted as expense #%.', p_correctsexpenseid, v_prev USING ERRCODE = 'P0001';
    END IF;

    UPDATE genericexpenses e SET correctsexpenseid = p_correctsexpenseid, updatedat = (now() AT TIME ZONE 'UTC')
    WHERE  e.farmid = p_farmid AND e.genericexpenseid = p_newexpenseid
      AND  e.correctsexpenseid IS DISTINCT FROM p_correctsexpenseid;
END $f$;

DROP FUNCTION IF EXISTS public.spgenericpurchase_linkcorrection(text, integer, integer, text);
CREATE FUNCTION public.spgenericpurchase_linkcorrection(p_farmid text, p_newpurchaseid integer, p_correctspurchaseid integer, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_prev integer;
BEGIN
    IF p_newpurchaseid = p_correctspurchaseid THEN
        RAISE EXCEPTION 'A purchase cannot correct itself.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericpurchases p WHERE p.genericpurchaseid = p_newpurchaseid AND p.farmid = p_farmid
                   AND p.isdeleted = FALSE AND p.purchasereversalid IS NULL AND p.status <> 'Cancelled') THEN
        RAISE EXCEPTION 'The corrected purchase was not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericpurchases p WHERE p.genericpurchaseid = p_correctspurchaseid AND p.farmid = p_farmid
                   AND p.purchasereversalid IS NOT NULL) THEN
        RAISE EXCEPTION 'Purchase #% is not a reversed purchase of this company, so nothing can be reposted from it.', p_correctspurchaseid
            USING ERRCODE = 'P0001';
    END IF;
    v_prev := fngenericpurchase_correctedby(p_farmid, p_correctspurchaseid);
    IF v_prev IS NOT NULL AND v_prev <> p_newpurchaseid THEN
        RAISE EXCEPTION 'Purchase #% was already reposted as purchase #%.', p_correctspurchaseid, v_prev USING ERRCODE = 'P0001';
    END IF;

    UPDATE genericpurchases p SET correctspurchaseid = p_correctspurchaseid, updatedat = (now() AT TIME ZONE 'UTC')
    WHERE  p.farmid = p_farmid AND p.genericpurchaseid = p_newpurchaseid
      AND  p.correctspurchaseid IS DISTINCT FROM p_correctspurchaseid;
END $f$;

-- ------------------------------------- 4. expense list (live 505 + 2 columns) --
DROP FUNCTION IF EXISTS public.spgenericexpense_getall(text, text, timestamp without time zone, timestamp without time zone);
CREATE FUNCTION public.spgenericexpense_getall(p_farmid text, p_status text DEFAULT NULL::text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(genericexpenseid integer, farmid text, expensedate timestamp without time zone, genericexpensecategoryid integer, categoryname text, genericsupplierid integer, suppliername text, description text, amount numeric, paidto text, paymentmethod text, genericcashaccountid integer, cashaccountname text, receipturl text, branchid integer, staffid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, rejectionreason text, createdat timestamp without time zone, updatedat timestamp without time zone, amountpaid numeric, duedate date, paymentstatus text, sourcetype text, paymentsapplied numeric, expensereversalid integer, reversalnumber text,
                 correctsexpenseid integer, correctedbyexpenseid integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.genericexpenseid, e.farmid::text, e.expensedate,
           e.genericexpensecategoryid, c.name::text,
           e.genericsupplierid, s.suppliername::text,
           e.description::text, e.amount, e.paidto::text, e.paymentmethod::text,
           e.genericcashaccountid, ca.accountname::text, e.receipturl::text, e.branchid, e.staffid,
           e.status::text, e.notes::text, e.createdby::text, e.approvedby::text, e.approvedat,
           e.rejectionreason::text, e.createdat, e.updatedat,
           -- resolved: NULL means paid in full (248)
           COALESCE(e.amountpaid, e.amount), e.duedate, e.paymentstatus, e.sourcetype,
           -- what supplier payments have applied (money is locked while > 0)
           COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                     WHERE sa.farmid = e.farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                       AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted'), 0)::numeric
           , e.expensereversalid, er.reversalnumber::text   -- 505
           , e.correctsexpenseid                             -- 520
           , CASE WHEN e.expensereversalid IS NOT NULL THEN fngenericexpense_correctedby(e.farmid, e.genericexpenseid) END
    FROM   genericexpenses e
    INNER  JOIN genericexpensecategories c ON c.genericexpensecategoryid = e.genericexpensecategoryid
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = e.genericsupplierid
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = e.genericcashaccountid
    LEFT   JOIN genericexpensereversals er ON er.expensereversalid = e.expensereversalid   -- 505
    WHERE  e.farmid = p_farmid AND e.isdeleted = FALSE
       AND (p_status   IS NULL OR e.status = p_status)
       AND (p_fromdate IS NULL OR e.expensedate >= p_fromdate)
       AND (p_todate   IS NULL OR e.expensedate <= p_todate)
    ORDER  BY e.expensedate DESC, e.genericexpenseid DESC;
END
$function$;

-- ------------------------------------ 5. purchase list (live 500 + 2 columns) --
DROP FUNCTION IF EXISTS public.spgenericpurchase_getall(text, text);
CREATE FUNCTION public.spgenericpurchase_getall(p_farmid text, p_status text DEFAULT NULL::text)
 RETURNS TABLE(genericpurchaseid integer, farmid text, genericsupplierid integer, suppliername text, purchasedate timestamp without time zone, branchid integer, subtotalamount numeric, discountamount numeric, taxamount numeric, totalamount numeric, amountpaid numeric, balance numeric, paymentstatus text, paymentmethod text, genericcashaccountid integer, invoicenumber text, receipturl text, receivedbystaffid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, cancelledby text, cancelledat timestamp without time zone, cancellationreason text, createdat timestamp without time zone, updatedat timestamp without time zone, purchasereversalid integer, reversalnumber text,
                 correctspurchaseid integer, correctedbypurchaseid integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.genericpurchaseid, p.farmid::text, p.genericsupplierid, s.suppliername::text,
           p.purchasedate, p.branchid,
           p.subtotalamount, p.discountamount, p.taxamount, p.totalamount,
           p.amountpaid, p.balance, p.paymentstatus::text, p.paymentmethod::text,
           p.genericcashaccountid, p.invoicenumber::text, p.receipturl::text, p.receivedbystaffid,
           p.status::text, p.notes::text, p.createdby::text, p.approvedby::text, p.approvedat,
           p.cancelledby::text, p.cancelledat, p.cancellationreason::text,
           p.createdat, p.updatedat,
           p.purchasereversalid, r.reversalnumber,
           p.correctspurchaseid,                                                    -- 520
           CASE WHEN p.purchasereversalid IS NOT NULL THEN fngenericpurchase_correctedby(p.farmid, p.genericpurchaseid) END
    FROM   genericpurchases p
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = p.genericsupplierid
    LEFT   JOIN genericpurchasereversals r ON r.purchasereversalid = p.purchasereversalid
    WHERE  p.farmid = p_farmid AND p.isdeleted = FALSE
       AND (p_status IS NULL OR p.status = p_status)
    ORDER  BY p.purchasedate DESC, p.genericpurchaseid DESC;
END;
$function$;

-- ------------------------- 6. expense by id (reads getall's g.*, so must follow) --
-- 518 lesson: this is "SELECT g.* FROM spgenericexpense_getall(...)" with a fixed
-- RETURNS TABLE, so every new getall column must be added here too.
DROP FUNCTION IF EXISTS public.spgenericexpense_getbyid(integer, text);
CREATE FUNCTION public.spgenericexpense_getbyid(p_genericexpenseid integer, p_farmid text)
 RETURNS TABLE(genericexpenseid integer, farmid text, expensedate timestamp without time zone, genericexpensecategoryid integer, categoryname text, genericsupplierid integer, suppliername text, description text, amount numeric, paidto text, paymentmethod text, genericcashaccountid integer, cashaccountname text, receipturl text, branchid integer, staffid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, rejectionreason text, createdat timestamp without time zone, updatedat timestamp without time zone, amountpaid numeric, duedate date, paymentstatus text, sourcetype text, paymentsapplied numeric, expensereversalid integer, reversalnumber text,
                 correctsexpenseid integer, correctedbyexpenseid integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT g.* FROM public.spgenericexpense_getall(p_farmid) g
    WHERE  g.genericexpenseid = p_genericexpenseid;
$function$;
