-- Behavioural checks for migration 348: the shared Recurring Expense Engine.
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK.
--
--   psql ... -X -f recurring-expense-engine.test.sql
--
-- Dates are relative to each company's business date, so this passes on any
-- day and in any time zone. Companies are fresh uuids per run.
--
--   A  Recurrence: month ends, leap years, weekly/biweekly/quarterly/annual
--   B  Templates: validation, module from the company type, foreign ids refused
--   C  Generation: drafts not posts, idempotency, end date, catch-up
--   D  Pause / resume (pause period not raised)
--   E  End (drafts kept, nothing after)
--   F  Editing a draft (variable amount, date, cash account)
--   G  Skip / restore
--   H  Posting handshake: claim / complete / release / interrupted / link
--   I  Cash and payables through the modules' own writers
--   J  Company isolation
--   K  Time zone
--   L  History is append-only; deletion rules; frozen identity fields

BEGIN;

CREATE FUNCTION pg_temp.chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.chk_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

-- A poultry template with sensible defaults.
CREATE FUNCTION pg_temp.ptpl(p_farm text, p_name text, p_freq text, p_start date, p_amount numeric DEFAULT 1000,
                             p_end date DEFAULT NULL, p_method text DEFAULT 'Cash', p_cash integer DEFAULT NULL,
                             p_sup integer DEFAULT NULL, p_var boolean DEFAULT FALSE)
RETURNS integer LANGUAGE sql AS $c$
    SELECT sprecurringexpense_savetemplate(p_farm, NULL, p_name, NULL, 'Utilities', p_sup, NULL, p_amount, p_var,
                                           p_freq, p_start, p_end, p_method, p_cash, NULL, 'Draft', 'tester');
$c$;

DO $t$
DECLARE
    v_farm   text := gen_random_uuid()::text;   -- poultry (no farms row = legacy poultry)
    v_gen    text := gen_random_uuid()::text;   -- generic
    v_other  text := gen_random_uuid()::text;   -- another poultry company
    v_today  date;
    v_sup    integer;
    v_osup   integer;
    v_acct   integer;
    v_oacct  integer;
    g_cat    integer;
    g_sup    integer;
    g_acct   integer;
    t_rent   integer;
    t_power  integer;
    t_old    integer;
    t_tmp    integer;
    o_id     integer;
    o2       integer;
    v_tok    uuid;
    v_exp    integer;
    v_n      integer;
    v_txt    text;
    v_cash0  numeric;
    f        integer := 0;
BEGIN
    v_today := fncompany_businessdate(v_farm);

    -- ================================================================ A. dates
    f := f + pg_temp.chk('A1. monthly from 31 Jan keeps month ends (no drift)', '2027-01-31,2027-02-28,2027-03-31,2027-04-30,2027-05-31',
            (SELECT string_agg(fnrecurringexpense_occurrencedate('2027-01-31', 'Monthly', n)::text, ',' ORDER BY n) FROM generate_series(0, 4) n));
    f := f + pg_temp.chk('A2. ... and 29 Feb in a leap year', '2028-02-29',
            fnrecurringexpense_occurrencedate('2028-01-31', 'Monthly', 1)::text);
    f := f + pg_temp.chk('A3. annual from 29 Feb lands on 28 Feb, back to 29th in leap years', '2028-02-29,2029-02-28,2030-02-28,2031-02-28,2032-02-29',
            (SELECT string_agg(scheduleddate::text, ',' ORDER BY occurrenceno) FROM fnrecurringexpense_series('2028-02-29', 'Annual', NULL, '2028-01-01', '2032-12-31')));
    f := f + pg_temp.chk('A4. quarterly from 30 Nov', '2026-11-30,2027-02-28,2027-05-30,2027-08-30',
            (SELECT string_agg(fnrecurringexpense_occurrencedate('2026-11-30', 'Quarterly', n)::text, ',' ORDER BY n) FROM generate_series(0, 3) n));
    f := f + pg_temp.chk('A5. weekly and biweekly', '2026-10-08|2026-10-15',
            fnrecurringexpense_occurrencedate('2026-10-01', 'Weekly', 1)::text || '|' || fnrecurringexpense_occurrencedate('2026-10-01', 'Biweekly', 1)::text);
    f := f + pg_temp.chk('A6. series window honours the end date', '3',
            (SELECT COUNT(*)::text FROM fnrecurringexpense_series('2026-01-15', 'Monthly', '2026-03-20', '2025-01-01', '2027-01-01')));
    f := f + pg_temp.chk('A7. series window starting mid-way keeps the right numbers', '10|2026-11-15',
            (SELECT occurrenceno || '|' || scheduleddate FROM fnrecurringexpense_series('2026-01-15', 'Monthly', NULL, '2026-11-01', '2026-11-30')));

    -- ============================================================= fixtures
    INSERT INTO supplier (userid, farmid, name, createddate, paymenttermsdays) VALUES ('tester', v_farm, 'ZZ Landlord', now(), 0) RETURNING supplierid INTO v_sup;
    INSERT INTO supplier (userid, farmid, name, createddate, paymenttermsdays) VALUES ('tester', v_other, 'ZZ Theirs', now(), 0) RETURNING supplierid INTO v_osup;
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance)
    VALUES (v_farm, 'ZZ Cash', 'Cash', 100000, 100000, false) RETURNING poultrycashaccountid INTO v_acct;
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance)
    VALUES (v_other, 'ZZ Their cash', 'Cash', 100, 100, false) RETURNING poultrycashaccountid INTO v_oacct;
    INSERT INTO farms (id, farmid, name, email, type) VALUES (gen_random_uuid()::text, v_gen, 'ZZ Generic Co', 'g@example.com', 'Generic');
    INSERT INTO genericexpensecategories (farmid, name) VALUES (v_gen, 'Rent') RETURNING genericexpensecategoryid INTO g_cat;
    INSERT INTO genericsuppliers (farmid, suppliername) VALUES (v_gen, 'ZZ Generic Landlord') RETURNING genericsupplierid INTO g_sup;
    INSERT INTO genericcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (v_gen, 'ZZ Generic Cash', 'Cash', 50000, 50000) RETURNING genericcashaccountid INTO g_acct;

    -- ============================================================= B. templates
    t_rent := pg_temp.ptpl(v_farm, 'Office rent', 'Monthly', v_today - 75, 3000, NULL, 'Cash', v_acct);
    f := f + pg_temp.chk('B1. module comes from the company type (no farms row = poultry)', 'poultry',
            (SELECT module FROM recurringexpensetemplates WHERE templateid = t_rent));
    t_tmp := sprecurringexpense_savetemplate(v_gen, NULL, 'Shop rent', g_cat, 'Rent', g_sup, NULL, 1500, FALSE,
                 'Monthly', v_today, NULL, 'Cash', g_acct, NULL, 'Draft', 'tester');
    f := f + pg_temp.chk('B2. a Generic company gets a generic template', 'generic',
            (SELECT module FROM recurringexpensetemplates WHERE templateid = t_tmp));
    f := f + pg_temp.chk('B3. default approval is Draft (review before posting)', 'Draft',
            (SELECT approvalmode FROM recurringexpensetemplates WHERE templateid = t_rent));
    BEGIN
        PERFORM sprecurringexpense_savetemplate(v_gen, NULL, 'No cat', NULL, NULL, NULL, NULL, 10, FALSE, 'Monthly', v_today, NULL, 'Cash', g_acct, NULL, 'Draft', 'tester');
        f := f + pg_temp.chk('B4. module category required', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B4. module category required', '%category%', SQLERRM); END;
    BEGIN
        PERFORM pg_temp.ptpl(v_farm, 'Zero', 'Monthly', v_today, 0);
        f := f + pg_temp.chk('B5. zero amount refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B5. zero amount refused', '%greater than 0%', SQLERRM); END;
    BEGIN
        PERFORM pg_temp.ptpl(v_farm, 'Daily?', 'Daily', v_today);
        f := f + pg_temp.chk('B6. unknown frequency refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B6. unknown frequency refused', '%how often%', SQLERRM); END;
    BEGIN
        PERFORM pg_temp.ptpl(v_farm, 'Ends early', 'Monthly', v_today, 10, v_today - 1);
        f := f + pg_temp.chk('B7. end before start refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B7. end before start refused', '%before the start date%', SQLERRM); END;
    BEGIN
        PERFORM pg_temp.ptpl(v_farm, 'Credit no supplier', 'Monthly', v_today, 10, NULL, 'Credit');
        f := f + pg_temp.chk('B8. credit without a supplier refused (nobody to owe)', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B8. credit without a supplier refused (nobody to owe)', '%needs a supplier%', SQLERRM); END;
    BEGIN
        PERFORM pg_temp.ptpl(v_farm, 'Foreign sup', 'Monthly', v_today, 10, NULL, 'Cash', NULL, v_osup);
        f := f + pg_temp.chk('B9. another company''s supplier refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B9. another company''s supplier refused', '%supplier does not belong%', SQLERRM); END;
    BEGIN
        PERFORM pg_temp.ptpl(v_farm, 'Foreign cash', 'Monthly', v_today, 10, NULL, 'Cash', v_oacct);
        f := f + pg_temp.chk('B10. another company''s cash account refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B10. another company''s cash account refused', '%cash account does not belong%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_savetemplate(v_gen, NULL, 'Poultry acct', g_cat, NULL, NULL, NULL, 10, FALSE, 'Monthly', v_today, NULL, 'Cash', v_acct, NULL, 'Draft', 'tester');
        f := f + pg_temp.chk('B11. a poultry cash account is not a generic one', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B11. a poultry cash account is not a generic one', '%cash account does not belong%', SQLERRM); END;

    -- ============================================================= C. generation
    -- Rent started 75 days ago monthly: occurrences at -75, -45ish, -14ish (3 due).
    SELECT COUNT(*) INTO v_n FROM fnrecurringexpense_series(v_today - 75, 'Monthly', NULL, v_today - 75, v_today);
    f := f + pg_temp.chk('C1. generation raises every due occurrence', v_n::text,
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_rent));
    f := f + pg_temp.chk('C2. ... as DRAFTS: nothing posted, no expense row', 'Draft|0',
            (SELECT string_agg(DISTINCT status, ',') || '|' || COUNT(expenseid) FROM recurringexpenseoccurrences WHERE templateid = t_rent));
    f := f + pg_temp.chk('C3. ... and no cash moved', '100000.00',
            (SELECT currentbalance::text FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct));
    f := f + pg_temp.chk('C4. ... no poultry expense written', '0',
            (SELECT COUNT(*)::text FROM expense WHERE farmid = v_farm::uuid));
    f := f + pg_temp.chk('C5. running generation again creates nothing (idempotent)', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm)));
    f := f + pg_temp.chk('C6. ... and again, from a later date in the same period', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm, v_today)));
    BEGIN
        INSERT INTO recurringexpenseoccurrences (templateid, farmid, module, occurrenceno, scheduleddate, amount, expensedate, paymentmethod)
        VALUES (t_rent, v_farm, 'poultry', 0, v_today - 75, 3000, v_today - 75, 'Cash');
        f := f + pg_temp.chk('C7. the database itself refuses a second September', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN unique_violation THEN f := f + pg_temp.chk('C7. the database itself refuses a second September', 'BLOCK', 'BLOCK'); END;
    t_tmp := pg_temp.ptpl(v_farm, 'Future thing', 'Monthly', v_today + 10);
    f := f + pg_temp.chk('C8. nothing raised before its first due date', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_tmp));
    t_tmp := pg_temp.ptpl(v_farm, 'Ended plan', 'Weekly', v_today - 30, 50, v_today - 16);
    f := f + pg_temp.chk('C9. no occurrence after the end date', '3',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_tmp));   -- -30, -23, -16
    t_old := pg_temp.ptpl(v_farm, 'Long overdue', 'Weekly', v_today - 7 * 100, 5);
    f := f + pg_temp.chk('C10. a long backlog catches up 60 at a time', '60',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_old));
    f := f + pg_temp.chk('C11. ... and finishes on the next call', '41',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_old));
    f := f + pg_temp.chk('C12. upcoming lists the next 30 days, not raised yet', 'true',
            (SELECT bool_and(daysaway BETWEEN 1 AND 30) FROM sprecurringexpense_upcoming(v_farm, 30))::text);
    f := f + pg_temp.chk('C13. upcoming 7 is a subset of upcoming 30', 'true',
            ((SELECT COUNT(*) FROM sprecurringexpense_upcoming(v_farm, 7)) <= (SELECT COUNT(*) FROM sprecurringexpense_upcoming(v_farm, 30)))::text);
    f := f + pg_temp.chk('C14. the template reports its next due date', (SELECT MIN(scheduleddate)::text FROM sprecurringexpense_upcoming(v_farm, 60) WHERE templateid = t_rent),
            (SELECT nextduedate::text FROM sprecurringexpense_gettemplates(v_farm) WHERE templateid = t_rent));

    -- ============================================================= D. pause / resume
    t_power := pg_temp.ptpl(v_farm, 'Electricity', 'Weekly', v_today - 20, 2000, NULL, 'Cash', v_acct, NULL, TRUE);
    PERFORM sprecurringexpense_setstatus(v_farm, t_power, 'Pause', NULL, 'tester');
    f := f + pg_temp.chk('D1. a paused template raises nothing', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_power));
    f := f + pg_temp.chk('D2. ... and shows nothing upcoming', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_upcoming(v_farm, 30) WHERE templateid = t_power));
    PERFORM sprecurringexpense_setstatus(v_farm, t_power, 'Resume', NULL, 'tester');
    f := f + pg_temp.chk('D3. resume continues from today', v_today::text,
            (SELECT generatefrom::text FROM recurringexpensetemplates WHERE templateid = t_power));
    f := f + pg_temp.chk('D4. what fell due during the pause is not raised', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_power));   -- -20, -13, -6 skipped
    BEGIN
        PERFORM sprecurringexpense_setstatus(v_farm, t_power, 'Resume', NULL, 'tester');
        f := f + pg_temp.chk('D5. resuming an active template refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('D5. resuming an active template refused', '%not paused%', SQLERRM); END;

    -- ============================================================= F. edit a draft
    SELECT occurrenceid INTO o_id FROM recurringexpenseoccurrences WHERE templateid = t_rent ORDER BY occurrenceno DESC LIMIT 1;
    PERFORM sprecurringexpense_editoccurrence(v_farm, o_id, 3437.50, v_today - 1, 'Cash', v_acct, NULL, NULL, 'Rent went up', 'tester');
    f := f + pg_temp.chk('F1. draft amount, date and note edited', '3437.50|' || (v_today - 1)::text || '|Rent went up',
            (SELECT amount || '|' || expensedate || '|' || note FROM recurringexpenseoccurrences WHERE occurrenceid = o_id));
    f := f + pg_temp.chk('F2. the template amount is unchanged (variable expense)', '3000.00',
            (SELECT amount::text FROM recurringexpensetemplates WHERE templateid = t_rent));
    f := f + pg_temp.chk('F3. the edit is in the history', 'Edited',
            (SELECT eventtype FROM recurringexpenseevents WHERE occurrenceid = o_id ORDER BY eventid DESC LIMIT 1));
    BEGIN
        PERFORM sprecurringexpense_editoccurrence(v_farm, o_id, 10, v_today + 3, 'Cash', v_acct, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('F4. future expense date refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('F4. future expense date refused', '%future%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_editoccurrence(v_farm, o_id, 10, v_today, 'Credit', NULL, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('F5. switching to credit needs a supplier', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('F5. switching to credit needs a supplier', '%needs a supplier%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_editoccurrence(v_farm, o_id, 10, v_today, 'Cash', v_oacct, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('F6. another company''s cash account refused on a draft', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('F6. another company''s cash account refused on a draft', '%does not belong%', SQLERRM); END;

    -- ============================================================= G. skip / restore
    SELECT occurrenceid INTO o2 FROM recurringexpenseoccurrences WHERE templateid = t_rent ORDER BY occurrenceno LIMIT 1;
    BEGIN
        PERFORM sprecurringexpense_skip(v_farm, o2, ' ', 'tester');
        f := f + pg_temp.chk('G1. skipping needs a reason', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('G1. skipping needs a reason', '%why%', SQLERRM); END;
    PERFORM sprecurringexpense_skip(v_farm, o2, 'Paid by the landlord deal', 'tester');
    f := f + pg_temp.chk('G2. skipped', 'Skipped', (SELECT status FROM recurringexpenseoccurrences WHERE occurrenceid = o2));
    f := f + pg_temp.chk('G3. a skipped period is never raised again', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm) WHERE templateid = t_rent));
    PERFORM sprecurringexpense_restore(v_farm, o2, 'tester');
    f := f + pg_temp.chk('G4. restore brings it back as a draft, same period', 'Draft|0',
            (SELECT status || '|' || occurrenceno FROM recurringexpenseoccurrences WHERE occurrenceid = o2));

    -- ============================================================= H. posting handshake
    SELECT claimtoken INTO v_tok FROM sprecurringexpense_claim(v_farm, o_id, 'tester');
    f := f + pg_temp.chk('H1. claim moves the draft to Posting', 'Posting', (SELECT status FROM recurringexpenseoccurrences WHERE occurrenceid = o_id));
    BEGIN
        PERFORM sprecurringexpense_claim(v_farm, o_id, 'tester2');
        f := f + pg_temp.chk('H2. a second Post is refused (double click / two browsers)', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('H2. a second Post is refused (double click / two browsers)', '%already being posted by tester%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_editoccurrence(v_farm, o_id, 10, v_today, 'Cash', v_acct, NULL, NULL, NULL, 'tester');
        f := f + pg_temp.chk('H3. a claimed draft cannot be edited', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('H3. a claimed draft cannot be edited', '%only a draft%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_releaseclaim(v_farm, o_id, NULL, 'manual', 'tester');
        f := f + pg_temp.chk('H4. a fresh claim cannot be released by hand', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('H4. a fresh claim cannot be released by hand', '%less than 10 minutes%', SQLERRM); END;
    PERFORM sprecurringexpense_releaseclaim(v_farm, o_id, v_tok, 'module refused', 'tester');
    f := f + pg_temp.chk('H5. the module refused -> back to Draft', 'Draft', (SELECT status FROM recurringexpenseoccurrences WHERE occurrenceid = o_id));
    SELECT claimtoken INTO v_tok FROM sprecurringexpense_claim(v_farm, o_id, 'tester');
    BEGIN
        PERFORM sprecurringexpense_completepost(v_farm, o_id, gen_random_uuid(), 999, 'tester');
        f := f + pg_temp.chk('H6. completing with someone else''s claim refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('H6. completing with someone else''s claim refused', '%no longer valid%', SQLERRM); END;

    -- ============================================================= I. cash and payable
    -- The API's PoultryRecurringExpensePoster calls IExpenseService.Insert, i.e.
    -- spexpense_insert then sppoultryexpensecash_sync. Do exactly that here.
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_exp := spexpense_insert(p_expensedate => (v_today - 1)::timestamp, p_category => 'Utilities', p_description => 'Office rent',
                              p_amount => 3437.50, p_paymentmethod => 'Cash', p_supplier => NULL, p_flockid => NULL,
                              p_userid => 'tester', p_farmid => v_farm::uuid, p_cashaccountid => v_acct);
    PERFORM sppoultryexpensecash_sync(v_farm, v_exp, v_acct, 3437.50, 'Office rent', 'tester');
    PERFORM sprecurringexpense_completepost(v_farm, o_id, v_tok, v_exp, 'tester');
    f := f + pg_temp.chk('I1. posted with the module''s expense id', 'Posted|' || v_exp,
            (SELECT status || '|' || expenseid FROM recurringexpenseoccurrences WHERE occurrenceid = o_id));
    f := f + pg_temp.chk('I2. a PAID post moves cash once, by the edited amount', '3437.50',
            (v_cash0 - (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct))::text);
    BEGIN
        PERFORM sprecurringexpense_claim(v_farm, o_id, 'tester');
        f := f + pg_temp.chk('I3. posting a posted occurrence again refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('I3. posting a posted occurrence again refused', '%already posted%', SQLERRM); END;
    BEGIN
        UPDATE recurringexpenseoccurrences SET status = 'Posted', expenseid = v_exp WHERE occurrenceid = o2;
        f := f + pg_temp.chk('I4. one expense cannot back two occurrences', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN unique_violation THEN f := f + pg_temp.chk('I4. one expense cannot back two occurrences', 'BLOCK', 'BLOCK'); END;

    -- CREDIT: the poster sends amountpaid = 0 and no cash account.
    PERFORM sprecurringexpense_editoccurrence(v_farm, o2, 3000, v_today - 75, 'Credit', NULL, v_sup, NULL, NULL, 'tester');
    SELECT claimtoken INTO v_tok FROM sprecurringexpense_claim(v_farm, o2, 'tester');
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_exp := spexpense_insert(p_expensedate => (v_today - 75)::timestamp, p_category => 'Utilities', p_description => 'Office rent (credit)',
                              p_amount => 3000, p_paymentmethod => 'Credit', p_supplier => 'ZZ Landlord', p_flockid => NULL,
                              p_userid => 'tester', p_farmid => v_farm::uuid, p_supplierid => v_sup, p_amountpaid => 0);
    PERFORM sppoultryexpensecash_sync(v_farm, v_exp, NULL, 3000, 'Office rent (credit)', 'tester');
    PERFORM sprecurringexpense_completepost(v_farm, o2, v_tok, v_exp, 'tester');
    f := f + pg_temp.chk('I5. a CREDIT post is a payable to the supplier', '3000.00',
            (SELECT balance::text FROM fnpoultrypayables(v_farm) WHERE documenttype = 'Expense' AND documentid = v_exp));
    f := f + pg_temp.chk('I6. ... and moves no cash', v_cash0::text,
            (SELECT currentbalance::text FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct));

    -- Generic: the poster creates the expense in its normal pending state. No
    -- cash until Generic's own approval.
    SELECT occurrenceid INTO o_id FROM sprecurringexpense_generate(v_gen) LIMIT 1;
    SELECT claimtoken INTO v_tok FROM sprecurringexpense_claim(v_gen, o_id, 'tester');
    v_exp := spgenericexpense_insert(p_farmid => v_gen, p_expensedate => v_today::timestamp, p_genericexpensecategoryid => g_cat,
                                     p_genericsupplierid => g_sup, p_description => 'Shop rent', p_amount => 1500, p_paymentmethod => 'Cash',
                                     p_genericcashaccountid => g_acct, p_createdby => 'tester');
    PERFORM sprecurringexpense_completepost(v_gen, o_id, v_tok, v_exp, 'tester');
    f := f + pg_temp.chk('I7. generic: posted occurrence waits for Generic''s approval, no cash yet', '50000.00',
            (SELECT currentbalance::text FROM genericcashaccounts WHERE genericcashaccountid = g_acct));
    PERFORM spgenericexpense_approve(v_exp, v_gen, 'approver');
    f := f + pg_temp.chk('I8. generic: cash moves when Generic approves it', '48500.00',
            (SELECT currentbalance::text FROM genericcashaccounts WHERE genericcashaccountid = g_acct));

    -- ============================================================= E. end
    PERFORM sprecurringexpense_setstatus(v_farm, t_old, 'End', 'Contract over', 'tester');
    f := f + pg_temp.chk('E1. ended', 'Ended', (SELECT status FROM recurringexpensetemplates WHERE templateid = t_old));
    f := f + pg_temp.chk('E2. its drafts stay for review', '101',
            (SELECT COUNT(*)::text FROM recurringexpenseoccurrences WHERE templateid = t_old AND status = 'Draft'));
    f := f + pg_temp.chk('E3. nothing more is raised', '0',
            (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_farm, v_today + 60) WHERE templateid = t_old));
    BEGIN
        PERFORM sprecurringexpense_savetemplate(v_farm, t_old, 'Long overdue', NULL, 'Utilities', NULL, NULL, 9, FALSE, 'Weekly', v_today - 700, NULL, 'Cash', NULL, NULL, 'Draft', 'tester');
        f := f + pg_temp.chk('E4. an ended template cannot be edited', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('E4. an ended template cannot be edited', '%has ended%', SQLERRM); END;
    PERFORM sprecurringexpense_setstatus(v_farm, t_rent, 'End', NULL, 'tester');
    f := f + pg_temp.chk('E5. ending never touches posted expenses', '2',
            (SELECT COUNT(*)::text FROM expense e JOIN recurringexpenseoccurrences o ON o.expenseid = e.expenseid
             WHERE o.templateid = t_rent AND e.farmid = v_farm::uuid));

    -- ============================================================= J. isolation
    f := f + pg_temp.chk('J1. another company sees no templates', '0', (SELECT COUNT(*)::text FROM sprecurringexpense_gettemplates(v_other)));
    f := f + pg_temp.chk('J2. ... no occurrences', '0', (SELECT COUNT(*)::text FROM sprecurringexpense_getoccurrences(v_other)));
    f := f + pg_temp.chk('J3. ... and generates nothing for us', '0', (SELECT COUNT(*)::text FROM sprecurringexpense_generate(v_other)));
    SELECT occurrenceid INTO o_id FROM recurringexpenseoccurrences WHERE farmid = v_farm AND status = 'Draft' LIMIT 1;
    BEGIN
        PERFORM sprecurringexpense_claim(v_other, o_id, 'intruder');
        f := f + pg_temp.chk('J4. cannot post another company''s draft', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('J4. cannot post another company''s draft', '%not found for this company%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_skip(v_other, o_id, 'nope', 'intruder');
        f := f + pg_temp.chk('J5. cannot skip another company''s draft', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('J5. cannot skip another company''s draft', '%not found for this company%', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_setstatus(v_other, t_power, 'Pause', NULL, 'intruder');
        f := f + pg_temp.chk('J6. cannot pause another company''s template', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('J6. cannot pause another company''s template', '%not found for this company%', SQLERRM); END;

    -- ============================================================= K. time zone
    DECLARE
        z_east text := gen_random_uuid()::text; z_west text := gen_random_uuid()::text;
        d_east date; d_west date; te integer; tw integer;
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid) VALUES
            (gen_random_uuid()::text, z_east, 'ZZ East', 'e@example.com', 'Poultry', 'Pacific/Kiritimati'),
            (gen_random_uuid()::text, z_west, 'ZZ West', 'w@example.com', 'Poultry', 'Pacific/Pago_Pago');
        d_east := fncompany_businessdate(z_east); d_west := fncompany_businessdate(z_west);
        f := f + pg_temp.chk('K1. the two companies are on different dates now', 'true', (d_east <> d_west)::text);
        te := pg_temp.ptpl(z_east, 'Rent', 'Monthly', d_east);
        tw := pg_temp.ptpl(z_west, 'Rent', 'Monthly', d_east);   -- same calendar date: still tomorrow in the west
        f := f + pg_temp.chk('K2. east: due today, raised', '1', (SELECT COUNT(*)::text FROM sprecurringexpense_generate(z_east)));
        f := f + pg_temp.chk('K3. west: not due yet in its own time zone', '0', (SELECT COUNT(*)::text FROM sprecurringexpense_generate(z_west)));
        f := f + pg_temp.chk('K4. west: it is upcoming tomorrow', '1',
                (SELECT daysaway::text FROM sprecurringexpense_upcoming(z_west, 7) WHERE templateid = tw));
    END;

    -- ============================================================= L. rules
    BEGIN
        UPDATE recurringexpenseevents SET actor = 'x' WHERE farmid = v_farm;
        f := f + pg_temp.chk('L1. history cannot be edited', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('L1. history cannot be edited', '%append-only%', SQLERRM); END;
    BEGIN
        t_tmp := pg_temp.ptpl(v_farm, 'Never used', 'Monthly', v_today + 200);
        PERFORM sprecurringexpense_deletetemplate(v_farm, t_tmp, 'tester');   -- no occurrences: allowed
        f := f + pg_temp.chk('L2. a template that never produced anything can be deleted', 'ok', 'ok');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk('L2. a template that never produced anything can be deleted', 'ok', SQLERRM); END;
    BEGIN
        PERFORM sprecurringexpense_deletetemplate(v_farm, t_rent, 'tester');
        f := f + pg_temp.chk('L3. a template with history cannot be deleted', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('L3. a template with history cannot be deleted', '%End it instead%', SQLERRM); END;
    t_tmp := pg_temp.ptpl(v_farm, 'Internet', 'Monthly', v_today - 5, 300);
    PERFORM sprecurringexpense_generate(v_farm);
    BEGIN
        PERFORM sprecurringexpense_savetemplate(v_farm, t_tmp, 'Internet', NULL, 'Utilities', NULL, NULL, 300, FALSE, 'Weekly', v_today - 5, NULL, 'Cash', NULL, NULL, 'Draft', 'tester');
        f := f + pg_temp.chk('L4. frequency is frozen once an occurrence exists', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('L4. frequency is frozen once an occurrence exists', '%cannot change once an occurrence exists%', SQLERRM); END;
    PERFORM sprecurringexpense_savetemplate(v_farm, t_tmp, 'Internet (fibre)', NULL, 'Utilities', NULL, NULL, 350, FALSE, 'Monthly', v_today - 5, NULL, 'Cash', NULL, NULL, 'Draft', 'tester');
    f := f + pg_temp.chk('L5. amount/name can change; the existing draft keeps its amount', '350.00|300.00',
            (SELECT t.amount || '|' || o.amount FROM recurringexpensetemplates t JOIN recurringexpenseoccurrences o ON o.templateid = t.templateid WHERE t.templateid = t_tmp));

    IF f > 0 THEN
        RAISE EXCEPTION 'recurring-expense-engine: % check(s) FAILED', f;
    END IF;
    RAISE NOTICE 'recurring-expense-engine: all checks passed';
END $t$;

ROLLBACK;
