-- Behavioural checks for migration 251: the Generic module toggles and the
-- company settings.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y", then negative
-- cases that must each be blocked. Run inside a transaction you ROLL BACK; it
-- rewrites one company's settings and applies templates to it.
--
--   psql ... -X -c "BEGIN;" -f generic-business-settings.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 251
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- Two companies are used. Saas has a profile and a template, so it is the one
-- templates are applied to. WinHT has neither a settings row nor a profile,
-- which is what makes it the right company to prove that READING settings does
-- not CREATE them.
--
-- The claims this file tests:
--   1. A company with no settings row reads defaults, and reading does not
--      write one.
--   2. The synthesised defaults are EXACTLY what an inserted row holds --
--      every column, not a sample.
--   3. A partial save leaves every field it did not mention alone, and the
--      nullable ids can still be deliberately cleared.
--   4. Applying a template sets what a template is entitled to set and leaves
--      the owner's other choices standing.
--   5. **autopostinvoices actually changes what a billing run does**, through
--      the same approve path the button uses, and the run stays idempotent.

DO $t$
DECLARE
    -- Saas: has a profile, so templates can be applied to it.
    v_farm  text := '056af97f-2099-481c-b5ac-3af20e3ef2b2';
    -- WinHT: no settings row, no profile. Never written to by this file.
    v_bare  text := '080887bc-a360-4fe7-9679-48eb48a3bf18';

    v_before jsonb; v_after jsonb;
    v_cust integer; v_acct integer; v_plan integer;
    v_sub1 integer; v_sub2 integer;
    v_run  integer; v_bal numeric; v_txt text;
BEGIN
    -- =====================================================================
    -- A. A company with no row reads defaults -- and stays without a row.
    -- =====================================================================
    RAISE NOTICE 'A1. no settings row yet     expect        0  got %',
        (SELECT COUNT(*) FROM genericbusinesssettings WHERE farmid = v_bare);
    RAISE NOTICE 'A2. still reads a row       expect        1  got %',
        (SELECT COUNT(*) FROM spgenericbusinesssettings_get(v_bare));
    RAISE NOTICE 'A3. frequency default       expect  Monthly  got %',
        (SELECT defaultbillingfrequency FROM spgenericbusinesssettings_get(v_bare));
    RAISE NOTICE 'A4. auto-post default OFF   expect        f  got %',
        (SELECT autopostinvoices FROM spgenericbusinesssettings_get(v_bare));
    RAISE NOTICE 'A5. MRR card default ON     expect        t  got %',
        (SELECT showmrr FROM spgenericbusinesssettings_get(v_bare));
    RAISE NOTICE 'A6. stock cards default OFF expect        f  got %',
        (SELECT showinventorycards FROM spgenericbusinesssettings_get(v_bare));
    -- Reading must not write. A _get that inserts is how a company acquires
    -- settings it never chose.
    RAISE NOTICE 'A7. reading wrote nothing   expect        0  got %',
        (SELECT COUNT(*) FROM genericbusinesssettings WHERE farmid = v_bare);

    -- The same for the module toggles, including the two 251 adds.
    RAISE NOTICE 'A8. no module row yet       expect        0  got %',
        (SELECT COUNT(*) FROM genericmodulesettings WHERE farmid = v_bare);
    RAISE NOTICE 'A9. classic modules ON      expect        t  got %',
        (SELECT enableproducts FROM spgenericmodulesettings_get(v_bare));
    RAISE NOTICE 'A10. subscriptions OFF      expect        f  got %',
        (SELECT enablesubscriptions FROM spgenericmodulesettings_get(v_bare));
    -- Both new toggles default ON: 249 shipped Recurring Expenses ungated and
    -- 248 showed Supplier Balances to anyone with Purchases. A migration must
    -- not take a menu away.
    RAISE NOTICE 'A11. recurring expenses ON  expect        t  got %',
        (SELECT enablerecurringexpenses FROM spgenericmodulesettings_get(v_bare));
    RAISE NOTICE 'A12. supplier balances ON   expect        t  got %',
        (SELECT enablesupplierbalances FROM spgenericmodulesettings_get(v_bare));

    -- =====================================================================
    -- B. The synthesised row IS the inserted row -- every column of it.
    -- =====================================================================
    SELECT to_jsonb(g) INTO v_before FROM spgenericbusinesssettings_get(v_bare) g;
    PERFORM spgenericbusinesssettings_upsert(p_farmid => v_bare);
    SELECT to_jsonb(g) INTO v_after FROM spgenericbusinesssettings_get(v_bare) g;
    -- If this ever fails, the table's DEFAULT and the function's fallback row
    -- have drifted, and a company would read different settings before and
    -- after its first save.
    RAISE NOTICE 'B1. defaults match the row  expect        t  got %', (v_before = v_after);
    DELETE FROM genericbusinesssettings WHERE farmid = v_bare;

    -- =====================================================================
    -- C. A partial save touches only what it mentions.
    -- =====================================================================
    PERFORM spgenericbusinesssettings_upsert(
        p_farmid                  => v_farm,
        p_defaultbillingfrequency => 'Quarterly',
        p_defaultpaymentduedays   => 21,
        p_autopostinvoices        => TRUE);
    RAISE NOTICE 'C1. frequency saved         expect Quarterly  got %',
        (SELECT defaultbillingfrequency FROM spgenericbusinesssettings_get(v_farm));
    RAISE NOTICE 'C2. due days saved          expect       21  got %',
        (SELECT defaultpaymentduedays FROM spgenericbusinesssettings_get(v_farm));

    -- A page that only edits the dashboard cards must not blank the billing
    -- defaults it never showed.
    PERFORM spgenericbusinesssettings_upsert(p_farmid => v_farm, p_showmrr => FALSE);
    RAISE NOTICE 'C3. card turned off         expect        f  got %',
        (SELECT showmrr FROM spgenericbusinesssettings_get(v_farm));
    RAISE NOTICE 'C4. frequency untouched     expect Quarterly  got %',
        (SELECT defaultbillingfrequency FROM spgenericbusinesssettings_get(v_farm));
    RAISE NOTICE 'C5. auto-post untouched     expect        t  got %',
        (SELECT autopostinvoices FROM spgenericbusinesssettings_get(v_farm));

    -- =====================================================================
    -- D. The nullable ids: NULL cannot mean both "leave it" and "clear it".
    -- =====================================================================
    -- Without its flag, a value is ignored rather than written.
    PERFORM spgenericbusinesssettings_upsert(
        p_farmid                      => v_farm,
        p_defaultcashaccountforpayments => 424242);
    RAISE NOTICE 'D1. no flag, no write       expect             got %',
        COALESCE((SELECT defaultcashaccountforpayments::text FROM spgenericbusinesssettings_get(v_farm)), '');
    -- With the flag, it is written.
    PERFORM spgenericbusinesssettings_upsert(
        p_farmid                        => v_farm,
        p_defaultcashaccountforpayments => 424242,
        p_setpaymentcashaccount         => TRUE);
    RAISE NOTICE 'D2. flag writes it          expect   424242  got %',
        (SELECT defaultcashaccountforpayments FROM spgenericbusinesssettings_get(v_farm));
    -- And with the flag it can be deliberately cleared, which is the whole
    -- reason the flag exists.
    PERFORM spgenericbusinesssettings_upsert(
        p_farmid                        => v_farm,
        p_defaultcashaccountforpayments => NULL,
        p_setpaymentcashaccount         => TRUE);
    RAISE NOTICE 'D3. flag clears it          expect             got %',
        COALESCE((SELECT defaultcashaccountforpayments::text FROM spgenericbusinesssettings_get(v_farm)), '');

    -- =====================================================================
    -- E. Module toggles round-trip, and the old ten-argument call still works.
    -- =====================================================================
    PERFORM spgenericmodulesettings_upsert(
        v_farm, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE,
        FALSE, FALSE);
    RAISE NOTICE 'E1. recurring turned off    expect        f  got %',
        (SELECT enablerecurringexpenses FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'E2. supplier bal turned off expect        f  got %',
        (SELECT enablesupplierbalances FROM spgenericmodulesettings_get(v_farm));
    -- The ten-argument form is what an older caller sends. It must still work,
    -- and it must not silently turn the two new modules off.
    PERFORM spgenericmodulesettings_upsert(
        v_farm, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE);
    RAISE NOTICE 'E3. old call defaults ON    expect        t  got %',
        (SELECT enablerecurringexpenses FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'E4. and products came back  expect        t  got %',
        (SELECT enableproducts FROM spgenericmodulesettings_get(v_farm));

    -- =====================================================================
    -- F. Applying a template.
    -- =====================================================================
    PERFORM spgenericbusinesstemplate_apply(v_farm, 'SubscriptionServiceBusiness', 'SaaS', 'ZZ test');
    RAISE NOTICE 'F1. stock hidden            expect        f  got %',
        (SELECT enableproducts FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'F2. subscriptions shown     expect        t  got %',
        (SELECT enablesubscriptions FROM spgenericmodulesettings_get(v_farm));
    -- Supplier Balances WITHOUT Purchases: the case 248 supports and the old
    -- enablePurchases gate got wrong.
    RAISE NOTICE 'F3. purchases hidden        expect        f  got %',
        (SELECT enablepurchases FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'F4. supplier balances shown expect        t  got %',
        (SELECT enablesupplierbalances FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'F5. recurring shown         expect        t  got %',
        (SELECT enablerecurringexpenses FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'F6. SaaS bills monthly      expect  Monthly  got %',
        (SELECT defaultbillingfrequency FROM spgenericbusinesssettings_get(v_farm));
    RAISE NOTICE 'F7. no stock cards          expect        f  got %',
        (SELECT showinventorycards FROM spgenericbusinesssettings_get(v_farm));
    -- The owner's OTHER choices survive a re-apply. Only the fields the
    -- template passes are the template's to decide.
    RAISE NOTICE 'F8. auto-post survived      expect        t  got %',
        (SELECT autopostinvoices FROM spgenericbusinesssettings_get(v_farm));
    RAISE NOTICE 'F9. card choice survived    expect        f  got %',
        (SELECT showmrr FROM spgenericbusinesssettings_get(v_farm));

    PERFORM spgenericbusinesstemplate_apply(v_farm, 'SubscriptionServiceBusiness', 'School', 'ZZ test');
    RAISE NOTICE 'F10. a school bills a term  expect   Termly  got %',
        (SELECT defaultbillingfrequency FROM spgenericbusinesssettings_get(v_farm));

    PERFORM spgenericbusinesstemplate_apply(v_farm, 'SubscriptionServiceBusiness', 'Agency', 'ZZ test');
    RAISE NOTICE 'F11. an agency gives terms  expect       14  got %',
        (SELECT defaultpaymentduedays FROM spgenericbusinesssettings_get(v_farm));

    PERFORM spgenericbusinesstemplate_apply(v_farm, 'RetailBusiness', 'Retail', 'ZZ test');
    RAISE NOTICE 'F12. a shop has stock       expect        t  got %',
        (SELECT enableproducts FROM spgenericmodulesettings_get(v_farm));
    RAISE NOTICE 'F13. and stock cards        expect        t  got %',
        (SELECT showinventorycards FROM spgenericbusinesssettings_get(v_farm));
    RAISE NOTICE 'F14. and does not recur     expect  OneTime  got %',
        (SELECT defaultbillingfrequency FROM spgenericbusinesssettings_get(v_farm));

    -- =====================================================================
    -- G. Auto-posting: the setting that actually moves money.
    -- =====================================================================
    INSERT INTO genericcustomers (farmid, customername, paymenttermsdays, isactive, isdeleted)
    VALUES (v_farm, 'ZZ Autopost Ltd', 0, TRUE, FALSE) RETURNING genericcustomerid INTO v_cust;

    INSERT INTO genericcashaccounts (farmid, accountname, accounttype, openingbalance,
                                     currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, 'ZZ Autopost Bank', 'Bank', 0, 0, FALSE, TRUE)
    RETURNING genericcashaccountid INTO v_acct;

    INSERT INTO genericservices (farmid, servicename, defaultprice, isactive, isdeleted,
                                 plantype, billingfrequency)
    VALUES (v_farm, 'ZZ Autopost Plan', 500, TRUE, FALSE, 'Subscription', 'Monthly')
    RETURNING genericserviceid INTO v_plan;

    -- Sub 1 bills while auto-post is OFF.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      billingfrequency, billingamount, nextbillingdate,
                                      autogenerateinvoice, status)
    VALUES (v_farm, v_cust, v_plan, CURRENT_DATE - 40, 'Monthly', 500, CURRENT_DATE - 1, TRUE, 'Active')
    RETURNING genericsubscriptionid INTO v_sub1;

    PERFORM spgenericbusinesssettings_upsert(p_farmid => v_farm, p_autopostinvoices => FALSE);
    v_run := spgenericbillingrun_generate(v_farm, CURRENT_DATE, 'ZZ test');

    RAISE NOTICE 'G1. one invoice raised      expect        1  got %',
        (SELECT totalinvoicesgenerated FROM genericbillingruns WHERE genericbillingrunid = v_run);
    RAISE NOTICE 'G2. and it is a DRAFT       expect    Draft  got %',
        (SELECT status FROM genericsales WHERE genericsubscriptionid = v_sub1 LIMIT 1);
    -- A draft owes nothing: this is the guarantee 243 exists to give.
    RAISE NOTICE 'G3. customer owes nothing   expect     0.00  got %',
        COALESCE((SELECT SUM(d.balance) FROM fngenericopeninvoices(v_farm) d
                   WHERE d.genericcustomerid = v_cust AND d.balance > 0), 0);

    -- Sub 2 bills while auto-post is ON.
    INSERT INTO genericsubscriptions (farmid, genericcustomerid, genericserviceid, startdate,
                                      billingfrequency, billingamount, nextbillingdate,
                                      autogenerateinvoice, status)
    VALUES (v_farm, v_cust, v_plan, CURRENT_DATE - 40, 'Monthly', 700, CURRENT_DATE - 1, TRUE, 'Active')
    RETURNING genericsubscriptionid INTO v_sub2;

    PERFORM spgenericbusinesssettings_upsert(p_farmid => v_farm, p_autopostinvoices => TRUE);
    v_run := spgenericbillingrun_generate(v_farm, CURRENT_DATE, 'ZZ test');

    RAISE NOTICE 'G4. one more raised         expect        1  got %',
        (SELECT totalinvoicesgenerated FROM genericbillingruns WHERE genericbillingrunid = v_run);
    RAISE NOTICE 'G5. this one is APPROVED    expect Approved  got %',
        (SELECT status FROM genericsales WHERE genericsubscriptionid = v_sub2 LIMIT 1);
    -- Approved through the same function the button calls, so the ledger moved.
    RAISE NOTICE 'G6. and it IS a receivable  expect   700.00  got %',
        COALESCE((SELECT SUM(d.balance) FROM fngenericopeninvoices(v_farm) d
                   WHERE d.genericcustomerid = v_cust AND d.balance > 0), 0);
    RAISE NOTICE 'G7. customer balance moved  expect   700.00  got %',
        (SELECT currentbalance FROM genericcustomers WHERE genericcustomerid = v_cust);
    RAISE NOTICE 'G8. a ledger line was cut   expect        1  got %',
        (SELECT COUNT(*) FROM genericcustomerledger
          WHERE farmid = v_farm AND genericcustomerid = v_cust);
    -- The draft from the first run is untouched: auto-post applies to what a
    -- run raises, not to everything already sitting there.
    RAISE NOTICE 'G9. the old draft is a draft expect   Draft  got %',
        (SELECT status FROM genericsales WHERE genericsubscriptionid = v_sub1 LIMIT 1);

    -- Pressing generate again raises nothing: both subscriptions have moved on
    -- a month. Auto-posting does not weaken the duplicate guard.
    v_run := spgenericbillingrun_generate(v_farm, CURRENT_DATE, 'ZZ test');
    RAISE NOTICE 'G10. second run raises none expect        0  got %',
        (SELECT totalinvoicesgenerated FROM genericbillingruns WHERE genericbillingrunid = v_run);
    RAISE NOTICE 'G11. still one receivable   expect   700.00  got %',
        COALESCE((SELECT SUM(d.balance) FROM fngenericopeninvoices(v_farm) d
                   WHERE d.genericcustomerid = v_cust AND d.balance > 0), 0);
    -- The audit invariant still holds after a batch job posted to a customer.
    RAISE NOTICE 'G12. balance audit is clean expect        0  got %',
        (SELECT COUNT(*) FROM fngenericbalanceaudit(v_farm));
END
$t$;

-- =============================================================================
-- Negative cases. Each must be BLOCKED.
-- =============================================================================
DO $n$
DECLARE
    v_farm text := '056af97f-2099-481c-b5ac-3af20e3ef2b2';
BEGIN
    -- A frequency the billing run cannot advance would produce a subscription
    -- that raises one invoice and then stops forever.
    BEGIN
        PERFORM spgenericbusinesssettings_upsert(
            p_farmid => v_farm, p_defaultbillingfrequency => 'Fortnightly');
        RAISE NOTICE 'N1. unknown frequency       <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N1. unknown frequency       blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericbusinesssettings_upsert(
            p_farmid => v_farm, p_reconciliationreminderfrequency => 'Fortnightly');
        RAISE NOTICE 'N2. unknown reconciliation  <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N2. unknown reconciliation  blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericbusinesssettings_upsert(p_farmid => '');
        RAISE NOTICE 'N3. blank company id        <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N3. blank company id        blocked: %', SQLERRM;
    END;

    BEGIN
        PERFORM spgenericbusinesssettings_upsert(
            p_farmid => v_farm, p_defaultpaymentduedays => -5);
        RAISE NOTICE 'N4. negative due days       <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'N4. negative due days       blocked: %', SQLERRM;
    END;
END
$n$;
