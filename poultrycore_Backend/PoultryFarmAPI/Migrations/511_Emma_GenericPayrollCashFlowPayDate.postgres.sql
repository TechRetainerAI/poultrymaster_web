-- =============================================================================
-- 511_Emma_GenericPayrollCashFlowPayDate.postgres.sql
--
-- Bug fix: when marking a Generic payroll run as paid, the cash transaction was
-- dated to now() (the moment of the click) instead of the pay date the user
-- selected in the dialog. The Poultry side was already fixed in migration 392;
-- this applies the same correction to Generic.
--
-- Two fixes:
--   1. spgenericpayrollrun_markpaid: cash transaction transactiondate now uses
--      p_paydate (the business date) instead of now().
--   2. spgenericcashflow_rows: payroll rows now show pr.paydate (the business
--      date) instead of pr.paidat (the click timestamp).
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Fix the MarkPaid SP — date the cash-out to the pay date, not the click.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_markpaid(
    p_genericpayrollrunid integer,
    p_farmid text,
    p_paidby text DEFAULT NULL::text,
    p_paydate date DEFAULT NULL::date
)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_cashaccountid integer;
    v_netpay numeric;
    v_notes text;
    v_allowneg boolean;
    v_bal numeric;
    v_newbalance numeric;
    v_paydate date;
BEGIN
    SELECT r.status, r.genericcashaccountid, r.totalnetpay, r.notes
    INTO   v_status, v_cashaccountid, v_netpay, v_notes
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid
       AND r.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Payroll must be Approved before it can be marked Paid (current=%).', v_status;
    END IF;

    -- Resolve the business date: use the dialog selection, fall back to today.
    v_paydate := COALESCE(p_paydate, current_date);

    -- 454 (as on Poultry): no cash account, or nothing left to hand over
    -- (all kept as employee credit), marks the run paid with no cash movement.
    IF v_cashaccountid IS NULL OR COALESCE(v_netpay, 0) <= 0 THEN
        UPDATE genericpayrollruns r
        SET    status = 'Paid', paidby = p_paidby, paidat = (now() at time zone 'utc'),
               paydate = v_paydate, updatedat = (now() at time zone 'utc')
        WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
        RETURN;
    END IF;

    SELECT ca.allownegativebalance, ca.currentbalance
    INTO   v_allowneg, v_bal
    FROM   genericcashaccounts ca
    WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
    LIMIT 1;

    IF v_bal IS NULL THEN
        RAISE EXCEPTION 'GenericCashAccountId not found on this farm.';
    END IF;

    v_newbalance := v_bal - v_netpay;
    IF (v_allowneg = FALSE AND v_newbalance < 0) THEN
        RAISE EXCEPTION 'Cash account would go negative; payroll pay rejected.';
    END IF;

    UPDATE genericpayrollruns r
    SET    status    = 'Paid',
           paidby    = p_paidby,
           paidat    = (now() at time zone 'utc'),
           paydate   = v_paydate,
           updatedat = (now() at time zone 'utc')
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;

    -- 511: dated to the pay date (business date), not the click — same as
    -- Poultry migration 392.
    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, balanceaftertransaction, description,
        createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, v_cashaccountid, v_paydate::timestamp, 'CashOut',
        'Payroll', p_genericpayrollrunid, -v_netpay, v_newbalance,
        COALESCE('Payroll: ' || left(COALESCE(v_notes, ''), 200), 'Payroll'),
        p_paidby, p_paidby, (now() at time zone 'utc')
    );

    UPDATE genericcashaccounts ca
    SET    currentbalance = v_newbalance, updatedat = (now() at time zone 'utc')
    WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
END
$function$;

-- ---------------------------------------------------------------------------
-- 2. Fix the Cash Flow SP — payroll rows should show pr.paydate (the business
--    date the user selected), not pr.paidat (the moment they clicked "Mark Paid").
--    The function is very large and rewritten in many migrations, so we patch
--    the existing function body in-place rather than copy-pasting the whole thing.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_src text;
BEGIN
    -- Get the current function source
    SELECT prosrc INTO v_src
    FROM   pg_proc
    WHERE  proname = 'spgenericcashflow_rows'
      AND  pronamespace = 'public'::regnamespace;

    IF v_src IS NULL THEN
        RAISE NOTICE 'spgenericcashflow_rows not found — skipping cash-flow date patch.';
        RETURN;
    END IF;

    -- Replace the three payroll-date references:
    --   COALESCE(pr.paidat, pr.createdat) → COALESCE(pr.paydate::timestamp, pr.paidat, pr.createdat)
    -- This prefers the business date, falls back to click time, falls back to creation time.
    v_src := replace(
        v_src,
        'COALESCE(pr.paidat, pr.createdat)',
        'COALESCE(pr.paydate::timestamp, pr.paidat, pr.createdat)'
    );

    -- Rebuild the function with the patched body
    EXECUTE format(
        $fn$
        CREATE OR REPLACE FUNCTION public.spgenericcashflow_rows(
            p_farmid text,
            p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone,
            p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone
        )
        RETURNS TABLE(
            rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer,
            accountname text, transactiondate timestamp without time zone, transactiontype text,
            sourcetype text, sourceid integer, istransfer boolean, amount numeric,
            description text, flowgroup text, createdat timestamp without time zone
        )
        LANGUAGE plpgsql STABLE
        AS $function$%s$function$
        $fn$,
        v_src
    );
END
$$;

COMMIT;
