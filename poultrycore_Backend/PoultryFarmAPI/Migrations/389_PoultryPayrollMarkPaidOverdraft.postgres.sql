-- =============================================================================
-- 389_PoultryPayrollMarkPaidOverdraft.postgres.sql
--
-- Purpose
-- -------
-- Poultry payroll "Mark paid" took the net pay out of the run's cash account
-- without looking at the balance, so it could push an account that does not
-- allow a negative balance below zero (found while recording the Payroll
-- tutorial: GHC 95 in the account, GHC 2,200 of wages). Every other poultry
-- money-out (supplier payments 224, expense payables 238, deferred purchases
-- 262) refuses that with the same message; payroll now does too.
--
-- It also dated the cash-out to the moment of the click. The CashOut row's
-- transactiondate is now the run's pay date (the one entered in the dialog),
-- stored as midnight like every back-dated row; createdat keeps the entry time.
--
-- The body is the live dev function (it was never in a migration file),
-- with only those two changes. Same signature, so the API is unchanged.
-- Apply this migration only; no API or web deploy is needed.
-- =============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultrypayrollrun_markpaid(p_poultrypayrollrunid integer, p_farmid text, p_paidby text DEFAULT NULL::text, p_paydate date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status   text;
    v_net      numeric;
    v_acctid   integer;
    v_bal      numeric;
    v_allowneg boolean;
    v_paydate  date;
BEGIN
    SELECT r.status, r.totalnetpay, r.poultrycashaccountid,
           COALESCE(p_paydate, r.paydate, ((now() at time zone 'utc'))::date)
    INTO   v_status, v_net, v_acctid, v_paydate
    FROM   poultrypayrollruns r
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Payroll run is %; only Approved can be marked paid.', v_status;
    END IF;

    -- 389: refuse to overdraw an account that does not allow it, before
    -- anything is written. Locked so two payouts cannot both pass the check.
    IF (v_acctid IS NOT NULL AND v_net > 0) THEN
        SELECT a.allownegativebalance, a.currentbalance INTO v_allowneg, v_bal
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = v_acctid AND a.farmid = p_farmid
        FOR UPDATE;
        IF v_allowneg IS NULL THEN
            RAISE EXCEPTION 'Cash account does not belong to this company.';
        END IF;
        IF NOT v_allowneg AND (v_bal - v_net) < 0 THEN
            RAISE EXCEPTION 'This payment would overdraw the cash account (balance %, payment %).',
                  v_bal, v_net::numeric(14,2);
        END IF;
    END IF;

    UPDATE poultrypayrollruns r
    SET    status = 'Paid', paidby = p_paidby, paidat = (now() at time zone 'utc'),
           paydate = v_paydate,
           updatedat = (now() at time zone 'utc')
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;

    IF (v_acctid IS NOT NULL AND v_net > 0) THEN
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_net, updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acctid AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_bal
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = v_acctid;

        -- 389: dated to the pay date (business date, midnight), not the click.
        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_acctid, v_paydate::timestamp, 'CashOut', 'Payroll', p_poultrypayrollrunid,
             -v_net, v_bal, 'Payroll net pay', p_paidby, p_paidby, (now() at time zone 'utc'));
    END IF;
END;
$function$;

COMMIT;
