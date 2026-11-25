-- =============================================================================
-- 489_Winchester_GenericCustomerPaymentCrossCheck.postgres.sql
--
-- Fixes found when cross-checking Generic "Record customer payment" (488)
-- against Poultry (367).
--
-- 1. Cash Flow (and Financial Activity, which is built on it) counted a payment
--    recorded on Customer Balances / Customer Payments TWICE: once as the
--    receipt, and again inside the sale's "residual" (money the sale took at
--    the counter = amount paid - payments linked to the sale). Those payments
--    are linked through customerpaymentallocation, not linkedsaleid, so they
--    were not taken off. Now Posted allocations are taken off too. (Seen on dev:
--    2 sales were double counted.) A reversed payment's allocation is Reversed
--    and its amount already left the sale's amountpaid, so nothing changes there.
--
-- 2. Daily Closing: "credit sales" of a day = the sales' balance NOW, so a
--    credit sale paid later through an allocated payment looked like counter
--    cash on its sale day, and the payment was counted again on its own day.
--    The amounts applied by Posted allocations are added back.
--
-- 3. Customer credit left by a payment (genericcustomercredits rows with
--    ReferenceType 'CustomerPayment'): Generic's usable credit is the customer's
--    running balance below zero (sale approve "apply credit", credit refunds).
--    The rows never went down when that credit was used, so the Customer Credit
--    panel kept showing it, and reversing the payment was allowed after its
--    credit was spent. Now:
--      - applying credit on a sale and refunding credit use these rows up,
--        oldest first (fngenericcustomercredit_consume);
--      - reversing a payment is refused when its credit is no longer all there,
--        checked against the rows AND the customer's available credit.
--    Hand-added credits (spgenericcustomercredit_create) are not touched: they
--    never moved the running balance.
--
-- Functions are patched in their LIVE bodies; each patch is checked and skipped
-- when already applied. No BEGIN/COMMIT (RunMigration wraps the file).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fngenericcustomercredit_consume(p_farmid text, p_customerid integer, p_amount numeric)
RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_left numeric(14,2) := GREATEST(round(COALESCE(p_amount, 0), 2), 0);
    v_r    record;
    v_take numeric(14,2);
BEGIN
    FOR v_r IN
        SELECT cr."GenericCustomerCreditId" AS id, cr."RemainingBalance" AS rem
        FROM   genericcustomercredits cr
        WHERE  cr."FarmId" = p_farmid AND cr."GenericCustomerId" = p_customerid
          AND  cr."ReferenceType" = 'CustomerPayment' AND cr."Status" = 'Active'
          AND  cr."RemainingBalance" > 0
        ORDER  BY cr."CreditDate", cr."GenericCustomerCreditId"
        FOR UPDATE
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, v_r.rem);
        UPDATE genericcustomercredits
        SET    "RemainingBalance" = "RemainingBalance" - v_take,
               "Status" = CASE WHEN "RemainingBalance" - v_take <= 0 THEN 'Used' ELSE "Status" END
        WHERE  "GenericCustomerCreditId" = v_r.id;
        v_left := v_left - v_take;
    END LOOP;
    RETURN v_left;   -- what was not covered by payment credit rows
END;
$function$;

DO $patch$
DECLARE
    v_def text;
    v_old text;
BEGIN
    -- 1. Cash Flow: take allocated payments off the sale residual.
    v_def := pg_get_functiondef('public.spgenericcashflow_rows(text,timestamp without time zone,timestamp without time zone)'::regprocedure);
    IF position('489:' IN v_def) = 0 THEN
        v_old := '- COALESCE((SELECT SUM(pp.amount)';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '489: spgenericcashflow_rows is not the expected shape (residual marker).';
        END IF;
        EXECUTE replace(v_def, v_old,
'- COALESCE((SELECT SUM(ca.amountapplied)   -- 489: payments applied through allocations
                             FROM   customerpaymentallocation ca
                             WHERE  ca.module = ''generic'' AND ca.saleid = s.genericsaleid
                               AND  lower(ca.farmid::text) = lower(p_farmid) AND ca.status = ''Posted''), 0)
                 ' || v_old);
    END IF;

    -- 2. Daily Closing: credit portion of the day's sales as it was at the sale.
    v_def := pg_get_functiondef('public.spgenericdailyclosing_submit(integer,text,numeric,text,text,text)'::regprocedure);
    IF position('489:' IN v_def) = 0 THEN
        v_old := 'SELECT SUM(s.balance)';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '489: spgenericdailyclosing_submit is not the expected shape (credit sales marker).';
        END IF;
        EXECUTE replace(v_def, v_old,
'SELECT SUM(s.balance + COALESCE((SELECT SUM(ca.amountapplied)   -- 489: paid later through allocations
                                          FROM   customerpaymentallocation ca
                                          WHERE  ca.module = ''generic'' AND ca.farmid = s.farmid
                                            AND  ca.saleid = s.genericsaleid AND ca.status = ''Posted''), 0))');
    END IF;

    -- 3a. Sale approve: credit applied on the sale uses payment credit rows up.
    v_def := pg_get_functiondef('public.spgenericsale_approve(integer,text,text)'::regprocedure);
    IF position('fngenericcustomercredit_consume' IN v_def) = 0 THEN
        v_old := '-- 5. Explicit credit application (from form, with pessimistic lock above)';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '489: spgenericsale_approve is not the expected shape (credit marker).';
        END IF;
        EXECUTE replace(v_def, v_old,
'-- 489: credit left by customer payments is used up, oldest first.
    IF (v_applycreditamount > 0 AND v_customerid IS NOT NULL) THEN
        PERFORM public.fngenericcustomercredit_consume(p_farmid, v_customerid, v_applycreditamount);
    END IF;

    ' || v_old);
    END IF;

    -- 3b. Credit refund: the same.
    v_def := pg_get_functiondef('public.spgenericcustomercreditrefund_create(text,integer,numeric,text,integer,text,text)'::regprocedure);
    IF position('fngenericcustomercredit_consume' IN v_def) = 0 THEN
        v_old := '-- 1. Insert refund record';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '489: spgenericcustomercreditrefund_create is not the expected shape (refund marker).';
        END IF;
        EXECUTE replace(v_def, v_old,
'-- 489: credit left by customer payments is used up, oldest first.
    PERFORM public.fngenericcustomercredit_consume(p_farmid, p_genericcustomerid, p_amount);
    ' || v_old);
    END IF;

    -- 3c. Payment reverse: refuse when the credit it left is no longer all there.
    v_def := pg_get_functiondef('public.spgenericcustomerpayment_reverse(text,integer,text,text)'::regprocedure);
    IF position('489:' IN v_def) = 0 THEN
        v_old := 'AND cr."RemainingBalance" < cr."Amount") THEN';
        IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
            RAISE EXCEPTION '489: spgenericcustomerpayment_reverse is not the expected shape (488 guard).';
        END IF;
        EXECUTE replace(v_def, v_old,
'AND (cr."RemainingBalance" < cr."Amount"
                      -- 489: also against what the customer can still use
                      OR cr."Amount" > GREATEST(-COALESCE((SELECT c.currentbalance FROM genericcustomers c
                                                          WHERE c.genericcustomerid = v_customer
                                                            AND c.farmid = p_farmid), 0), 0))) THEN');
    END IF;
END
$patch$;
