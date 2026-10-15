-- =============================================================================
-- 364_PoultryDailyClosingPartPaidSales.postgres.sql
--
-- Purpose
-- -------
-- Daily Closing showed the FULL total of a part-paid sale as "Credit sales",
-- while the Sales page showed only what is still owed. A sale of 280 with 200
-- paid at the till read 280 on credit instead of 80.
--
-- Cause: both Daily Closing readers split the day's sales on the binary
-- `paid` flag (paid -> cash, not paid -> credit at the full total). A part
-- payment leaves paid = false, so the whole sale went to credit. The part
-- payment was then ALSO counted in "Payments received", which only came out
-- right in "Customer balances" by accident -- and a fully paid sale that has a
-- payment row was counted twice (cash sale AND payment received), pushing the
-- receivables change below zero.
--
-- THE RULE NOW
-- ------------
--   Credit sales       what the day's sales still owed at the END of that day:
--                      the Sales page balance (fnpoultrysalebalance) plus any
--                      payment dated after the day, so a past day does not
--                      change when the customer pays later.
--   Cash sales         the day's revenue - credit sales.
--   Payments received  payments dated that day, EXCEPT those on a sale made
--                      that same day (already in Cash sales). So it is money
--                      collected on earlier sales, plus deposits.
--
-- Patched in place from pg_get_functiondef (anchor must match exactly once):
--   sppoultrydailyclosing_workspace_core   the Daily Closing page
--   fnpoultrydailyclosing_livetotals       the closings list / legacy totals
-- An Approved closing keeps its frozen snapshot and is not recomputed.
-- =============================================================================
BEGIN;

-- ------------------------------------------------ 1. owed at end of a day --
CREATE OR REPLACE FUNCTION public.fnpoultrysale_owedasof(p_farmid text, p_saleid integer, p_asof date)
RETURNS numeric LANGUAGE sql STABLE AS $f$
    -- The Sales page balance, plus what was paid on the sale AFTER p_asof.
    -- Payments are dated by poultrypayments.paymentdate; an allocation of
    -- credit counts on the date of the payment that created the credit.
    SELECT LEAST(COALESCE(s.totalamount, 0),
                 public.fnpoultrysalebalance(s.paid, s.totalamount, s.amountpaid)
                 + COALESCE((
                     SELECT SUM(ca.amountapplied)
                     FROM   customerpaymentallocation ca
                     JOIN   poultrypayments pp ON pp.poultrypaymentid = ca.paymentid AND pp.farmid = ca.farmid
                     WHERE  ca.module = 'poultry' AND ca.saleid = s.saleid AND ca.farmid = p_farmid
                       AND  ca.status = 'Posted' AND pp.paymentdate::date > p_asof), 0)
                 + COALESCE((
                     SELECT SUM(pp.amount)
                     FROM   poultrypayments pp
                     WHERE  pp.saleid = s.saleid AND pp.farmid = p_farmid
                       AND  COALESCE(pp.status, 'Posted') = 'Posted'
                       AND  pp.paymentdate::date > p_asof
                       AND  NOT EXISTS (SELECT 1 FROM customerpaymentallocation ca
                                        WHERE ca.module = 'poultry' AND ca.paymentid = pp.poultrypaymentid
                                          AND ca.farmid = pp.farmid)), 0))::numeric(14,2)
    FROM   sale s
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;
$f$;

-- ------------------------------------------------------- 2. patch helper --
CREATE FUNCTION pg_temp.m364_patch(p_fn text, p_marker text, p_old text, p_new text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_oid oid;
    v_n   integer;
    v_def text;
    v_old text := replace(p_old, chr(13), '');
    v_new text := replace(p_new, chr(13), '');
BEGIN
    SELECT count(*), min(p.oid) INTO v_n, v_oid
    FROM   pg_proc p WHERE p.proname = p_fn AND p.pronamespace = 'public'::regnamespace;
    IF v_n <> 1 THEN
        RAISE EXCEPTION '364: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '364: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '364: anchor for % (%) found % times, expected 1', p_fn, p_marker, v_n;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '364: patched % (%)', p_fn, p_marker;
END
$f$;

-- ------------------------------------------------ 3. Daily Closing page --
SELECT pg_temp.m364_patch('sppoultrydailyclosing_workspace_core', '364: owed at the end of the day',
$o$           COALESCE(sum(s.totalamount) FILTER (WHERE COALESCE(s.paid, TRUE)), 0)    AS cash,
           COALESCE(sum(s.totalamount) FILTER (WHERE NOT COALESCE(s.paid, TRUE)), 0) AS credit$o$,
$n$           -- 364: owed at the end of the day, not the full total of a part-paid sale.
           COALESCE(sum(s.totalamount - public.fnpoultrysale_owedasof(p_farmid, s.saleid, v_date)), 0) AS cash,
           COALESCE(sum(public.fnpoultrysale_owedasof(p_farmid, s.saleid, v_date)), 0)                 AS credit$n$);

SELECT pg_temp.m364_patch('sppoultrydailyclosing_workspace_core', '364: paid at the sale itself',
$o$      AND COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote') -- 363: payments received that day
      AND pp.paymentdate::date = v_date;$o$,
$n$      AND COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote') -- 363: payments received that day
      AND pp.paymentdate::date = v_date
      -- 364: paid at the sale itself is already in Cash sales.
      AND NOT EXISTS (SELECT 1 FROM sale s2
                      WHERE s2.saleid = pp.saleid AND s2.farmid = p_farmid
                        AND s2.status = 'Posted' AND s2.saledate::date = v_date);$n$);

-- ----------------------------------------- 4. closings list / legacy totals --
SELECT pg_temp.m364_patch('fnpoultrydailyclosing_livetotals', '364: owed at the end of the day',
$o$               COALESCE(SUM(CASE WHEN COALESCE(s.paid,FALSE) = FALSE THEN s.totalamount ELSE 0 END),0) AS creditsales,
               COALESCE(SUM(CASE WHEN s.paid = TRUE THEN s.totalamount ELSE 0 END),0)           AS cashcoll$o$,
$n$               -- 364: owed at the end of the day, not the full total of a part-paid sale.
               COALESCE(SUM(public.fnpoultrysale_owedasof(p_farmid, s.saleid, p_closingdate)),0)                 AS creditsales,
               COALESCE(SUM(s.totalamount - public.fnpoultrysale_owedasof(p_farmid, s.saleid, p_closingdate)),0) AS cashcoll$n$);

SELECT pg_temp.m364_patch('fnpoultrydailyclosing_livetotals', '364: paid at the sale itself',
$o$          AND  COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
    ),$o$,
$n$          AND  COALESCE(pp.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
          -- 364: paid at the sale itself is already in cash collected.
          AND  NOT EXISTS (SELECT 1 FROM public.sale s2
                           WHERE s2.saleid = pp.saleid AND s2.farmid = p_farmid
                             AND s2.status = 'Posted' AND s2.saledate::date = p_closingdate)
    ),$n$);

COMMIT;
