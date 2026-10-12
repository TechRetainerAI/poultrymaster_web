-- Behavioural checks for migration 339: reopening a flock reverses its
-- closeout sales and the money they brought in.
--
-- Run inside a transaction you ROLL BACK (the apply script does, after 338's
-- checks). Prints "ok"/"FAIL" per check and RAISES at the end on any failure.
--
--   R. Paid in full: cash back out of the account, payment Reversed (kept,
--      with the reason), sale gone, birds back, history keeps the snapshot
--   P. Part paid on credit: same, and the receivable disappears with the sale
--   K. Reopen KEEPING sales: 338's behaviour, nothing money-side moves
--   S. A customer payment that also pays another sale refuses the reopen,
--      and nothing at all has changed when it does

-- SELF-CONTAINED: this file opens its own transaction and ROLLS IT BACK, so it
-- writes nothing even when run on its own. Do not remove these two lines.
BEGIN;

CREATE FUNCTION pg_temp.chk2(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

DO $t$
DECLARE
    v_farm   text := gen_random_uuid()::text;   -- a fresh, invisible company per run
    v_today  date;
    v_start  date;
    v_house  integer;
    v_batch  integer;
    v_flock  integer;
    v_acct   integer;
    v_sale   integer;
    v_other  integer;
    v_cust   integer;
    v_co     integer;
    v_group  uuid;
    v_msg    text;
    v_num    numeric;
    v_n      integer;
    d        jsonb;
    f        integer := 0;
BEGIN
    v_today := fncompany_businessdate(v_farm);
    v_start := v_today - 90;

    INSERT INTO houses (userid, farmid, housename, capacity)
    VALUES ('reopen-test', v_farm, 'Reopen Test House', 500) RETURNING houseid INTO v_house;
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('reopen-test', v_farm, 'RO-339', 'Reopen batch', 'Isa Brown', 100, v_start, 5, 500)
    RETURNING batchid INTO v_batch;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, houseid, hasarrived)
    VALUES ('reopen-test', v_farm, 'RO Flock', 'Isa Brown', v_start, 100, TRUE, v_batch, v_house, TRUE)
    RETURNING flockid INTO v_flock;
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (v_farm, 'Reopen Test Cash', 'Cash', 0, 0) RETURNING poultrycashaccountid INTO v_acct;

    -- =====================================================================
    -- R. Paid in full
    -- =====================================================================
    -- Exactly the C# closeout's order: sale unpaid with the account stamped,
    -- close, then the payment through sppoultrypayment_record.
    v_sale := spsale_insert(p_userid => 'reopen-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                            p_product => 'Birds', p_quantity => 100, p_unitprice => 10, p_totalamount => 1000,
                            p_paymentmethod => 'Cash', p_customername => 'Reopen Test Buyer', p_flockid => v_flock, p_paid => FALSE);
    PERFORM sppoultrysalecash_sync(v_farm, v_sale, v_acct, 1000, FALSE, 'Flock closeout', 'reopen-test');
    v_co := spflock_closeout(v_farm, v_flock, v_today, 'End of lay', NULL, 'reopen-test',
                             jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 100, 'saleId', v_sale)));
    PERFORM sppoultrypayment_record(p_farmid => v_farm, p_saleid => v_sale, p_amount => 1000, p_paymentmethod => 'Cash',
                                    p_paymentdate => v_today::timestamp, p_reference => NULL,
                                    p_note => 'Paid at point of sale (flock closeout)', p_createdby => 'reopen-test');

    SELECT currentbalance INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk2('R0. setup: the sale''s 1,000 reached the cash account', '1000.00', v_num::text);

    PERFORM spflock_reopen(v_farm, v_flock, 'Closed the wrong flock', 'owner-test');

    SELECT currentbalance INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk2('R1. the money is taken back out of the cash account', '0.00', v_num::text);
    SELECT COALESCE(SUM(amount), 0) INTO v_num FROM poultrycashtransactions WHERE farmid = v_farm;
    f := f + pg_temp.chk2('R2. the cash ledger nets to zero', '0', ROUND(v_num)::text);
    SELECT string_agg(status || '|' || COALESCE(reversalreason, ''), ',') INTO v_msg FROM poultrypayments WHERE saleid = v_sale;
    f := f + pg_temp.chk2('R3. the payment is kept, Reversed, with the reason', 'Reversed|Sale reversed: Flock reopened: Closed the wrong flock', v_msg);
    -- 351: the sale is REVERSED, not deleted -- it stays in the history.
    SELECT string_agg(status, ',') INTO v_msg FROM sale WHERE saleid = v_sale;
    f := f + pg_temp.chk2('R4. the sale is kept, Reversed', 'Reversed', v_msg);
    SELECT COALESCE(SUM(quantity), 0) INTO v_num FROM poultrystocktransactions
    WHERE  farmid = v_farm AND txntype = 'Bird Sale' AND relatedid = v_sale;
    f := f + pg_temp.chk2('R5. its Bird Sale ledger row is reversed, not deleted (nets 0)', '0', ROUND(v_num)::text);
    SELECT COUNT(*) INTO v_n FROM poultrystocktransactions
    WHERE  farmid = v_farm AND txntype = 'Bird Sale' AND relatedid = v_sale;
    f := f + pg_temp.chk2('R6. ... over two rows', '2', v_n::text);
    SELECT currentlivebirds INTO v_n FROM fnflock_birdposition(v_farm, v_flock);
    f := f + pg_temp.chk2('R7. the birds are back in the flock', '100', v_n::text);
    SELECT COUNT(*) INTO v_n FROM flock WHERE flockid = v_flock AND active AND closeddate IS NULL;
    f := f + pg_temp.chk2('R8. the flock is running again', '1', v_n::text);

    SELECT h.dispositions -> 0 INTO d FROM spflock_closeouthistory(v_farm, v_flock) h WHERE h.closeoutid = v_co;
    f := f + pg_temp.chk2('R9. history keeps what the sale was', '1000.00|Reopen Test Buyer',
                          (d ->> 'totalAmount') || '|' || (d ->> 'customerName'));
    f := f + pg_temp.chk2('R10. ... and that it was reversed', 'true', ((d ->> 'saleReversedAt') IS NOT NULL)::text);

    -- =====================================================================
    -- P. Part paid on credit
    -- =====================================================================
    v_sale := spsale_insert(p_userid => 'reopen-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                            p_product => 'Birds', p_quantity => 100, p_unitprice => 10, p_totalamount => 1000,
                            p_paymentmethod => 'Cash', p_customername => 'Reopen Test Buyer', p_flockid => v_flock, p_paid => FALSE);
    PERFORM sppoultrysalecash_sync(v_farm, v_sale, v_acct, 1000, FALSE, 'Flock closeout', 'reopen-test');
    v_co := spflock_closeout(v_farm, v_flock, v_today, 'End of lay', NULL, 'reopen-test',
                             jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 100, 'saleId', v_sale)));
    PERFORM sppoultrypayment_record(p_farmid => v_farm, p_saleid => v_sale, p_amount => 400, p_paymentmethod => 'Cash',
                                    p_paymentdate => v_today::timestamp, p_reference => NULL,
                                    p_note => 'Part payment at flock closeout', p_createdby => 'reopen-test');
    SELECT currentbalance INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk2('P0. setup: 400 received, 600 owed', '400.00', v_num::text);

    PERFORM spflock_reopen(v_farm, v_flock, 'Buyer backed out', 'owner-test');

    SELECT currentbalance INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk2('P1. the part payment is taken back out', '0.00', v_num::text);
    SELECT COUNT(*) INTO v_n FROM sppoultrycustomeropensales(v_farm, (SELECT customerid FROM sale WHERE saleid = v_sale)) o WHERE o.saleid = v_sale;
    f := f + pg_temp.chk2('P2. the receivable goes with the sale', '0', v_n::text);
    SELECT COUNT(*) INTO v_n FROM poultrypayments WHERE saleid = v_sale AND COALESCE(status, 'Posted') = 'Posted';
    f := f + pg_temp.chk2('P3. no payment is left Posted against it', '0', v_n::text);

    -- =====================================================================
    -- K. Reopen keeping the sales
    -- =====================================================================
    v_sale := spsale_insert(p_userid => 'reopen-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                            p_product => 'Birds', p_quantity => 100, p_unitprice => 10, p_totalamount => 1000,
                            p_paymentmethod => 'Cash', p_customername => 'Reopen Test Buyer', p_flockid => v_flock, p_paid => FALSE);
    PERFORM sppoultrysalecash_sync(v_farm, v_sale, v_acct, 1000, FALSE, 'Flock closeout', 'reopen-test');
    v_co := spflock_closeout(v_farm, v_flock, v_today, 'End of lay', NULL, 'reopen-test',
                             jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 100, 'saleId', v_sale)));
    PERFORM sppoultrypayment_record(p_farmid => v_farm, p_saleid => v_sale, p_amount => 1000, p_paymentmethod => 'Cash',
                                    p_paymentdate => v_today::timestamp, p_reference => NULL,
                                    p_note => 'Paid', p_createdby => 'reopen-test');

    PERFORM spflock_reopen(v_farm, v_flock, 'Fix a production record', 'owner-test', FALSE);

    SELECT currentbalance INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk2('K1. keeping the sales keeps the money', '1000.00', v_num::text);
    SELECT COUNT(*) INTO v_n FROM sale WHERE saleid = v_sale AND paid;
    f := f + pg_temp.chk2('K2. ... and the sale, still paid', '1', v_n::text);
    SELECT currentlivebirds INTO v_n FROM fnflock_birdposition(v_farm, v_flock);
    f := f + pg_temp.chk2('K3. the birds stay sold', '0', v_n::text);
    UPDATE sale SET quantity = 90 WHERE saleid = v_sale;
    f := f + pg_temp.chk2('K4. the kept sale is unlocked', '1', '1');

    -- Clean slate for S: remove the kept sale the way the Sales page would --
    -- reverse its payment, then delete it.
    SELECT paymentgroupid INTO v_group FROM poultrypayments WHERE saleid = v_sale AND status = 'Posted' LIMIT 1;
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_group, 'test cleanup', 'reopen-test');
    PERFORM sppoultrysalecash_sync(v_farm, v_sale, NULL, 0, FALSE, NULL, 'reopen-test');
    PERFORM spsale_delete(v_farm, 'reopen-test', v_sale);

    -- =====================================================================
    -- S. A shared customer payment refuses, and changes nothing
    -- =====================================================================
    v_sale := spsale_insert(p_userid => 'reopen-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                            p_product => 'Birds', p_quantity => 100, p_unitprice => 10, p_totalamount => 1000,
                            p_customername => 'Reopen Test Buyer', p_flockid => v_flock, p_paid => FALSE);
    PERFORM sppoultrysalecash_sync(v_farm, v_sale, v_acct, 1000, FALSE, 'Flock closeout', 'reopen-test');
    v_co := spflock_closeout(v_farm, v_flock, v_today, 'End of lay', NULL, 'reopen-test',
                             jsonb_build_array(jsonb_build_object('disposition', 'Sale', 'quantity', 100, 'saleId', v_sale)));
    -- An unrelated egg sale to the same customer, and ONE payment covering both.
    v_other := spsale_insert(p_userid => 'reopen-test', p_farmid => v_farm, p_saledate => v_today::timestamp,
                             p_product => 'Eggs', p_quantity => 30, p_unitprice => 2, p_totalamount => 60,
                             p_customername => 'Reopen Test Buyer', p_paid => FALSE);
    SELECT customerid INTO v_cust FROM sale WHERE saleid = v_sale;
    PERFORM sppoultrycustomerpayment_record(p_farmid => v_farm, p_customerid => v_cust, p_amount => 1060,
                                            p_allocations => jsonb_build_array(
                                                jsonb_build_object('saleid', v_sale, 'amount', 1000),
                                                jsonb_build_object('saleid', v_other, 'amount', 60)),
                                            p_paymentmethod => 'Cash', p_paymentdate => v_today::timestamp,
                                            p_cashaccountid => v_acct, p_createdby => 'reopen-test');
    SELECT currentbalance INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;

    BEGIN
        PERFORM spflock_reopen(v_farm, v_flock, 'Try it', 'owner-test');
        v_msg := 'reopened';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    f := f + pg_temp.chk2('S1. a payment that also pays another sale refuses the reopen',
                          'true', (v_msg ILIKE '%also pays other sales%')::text);
    SELECT COUNT(*) INTO v_n FROM flock WHERE flockid = v_flock AND closeddate IS NOT NULL;
    f := f + pg_temp.chk2('S2. ... the flock is still closed', '1', v_n::text);
    SELECT COUNT(*) INTO v_n FROM poultrypayments WHERE saleid IN (v_sale, v_other) AND status = 'Posted';
    f := f + pg_temp.chk2('S3. ... both payments still Posted', '2', v_n::text);
    SELECT currentbalance - v_num INTO v_num FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    f := f + pg_temp.chk2('S4. ... and the cash account did not move', '0.00', v_num::text);

    PERFORM spflock_reopen(v_farm, v_flock, 'Keep the sale this time', 'owner-test', FALSE);
    SELECT COUNT(*) INTO v_n FROM flock WHERE flockid = v_flock AND closeddate IS NULL;
    f := f + pg_temp.chk2('S5. reopening while keeping the sales still works', '1', v_n::text);

    IF f > 0 THEN
        RAISE EXCEPTION 'poultry-flock-reopen-reverses-sales: % check(s) FAILED', f;
    END IF;
    RAISE NOTICE 'poultry-flock-reopen-reverses-sales: all checks passed';
END
$t$;

ROLLBACK;
