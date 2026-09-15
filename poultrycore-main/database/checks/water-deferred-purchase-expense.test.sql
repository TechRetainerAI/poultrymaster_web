-- Behavioural checks for migration 275: the water deferred purchase expense.
--
-- One DO $t$ block per theme, a NOTICE per check reading "expect X got Y". Run
-- inside a transaction you ROLL BACK; it writes items, suppliers, purchases,
-- expenses, cash transactions and a supplier payment.
--
--   psql ... -X -c "BEGIN;" -f water-deferred-purchase-expense.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 275
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Nothing changes for anybody today.** 275 only ever takes its new branch for
-- a purchase snapshotted EXPENSE_WHEN_CONSUMED, and the interlock means no
-- company can produce one. Section 0 asserts the interlock is still shut AFTER
-- the migration -- if a future edit to 275 flips it there instead of in 279,
-- this is what catches it.
--
-- Everything after section 0 lifts the interlock for this transaction only, to
-- exercise a branch that is otherwise unreachable. That lift is discarded with
-- the ROLLBACK.
--
-- The rest:
--   A. A normal purchase is byte-for-byte what it was: expense for amountpaid,
--      cash out, linked expense id set, stock up.
--   B. A deferred purchase writes NO expense and NO linked expense id -- but
--      stock, supplier balance, totalcost and remainingquantity are identical.
--   C. The method is SNAPSHOTTED. Changing the setting afterwards does not move
--      a purchase that has already been entered.
--   D. A supplier payment against a deferred purchase writes no expense, and
--      still moves the cash. Paying is not expensing.
--   E. The mixed payment -- one deferred purchase and one normal one settled by
--      the SAME payment. The expense is the normal portion only; the cash is the
--      whole amount. This is the case water has and poultry does not, because
--      water aggregates a payment's purchase allocations into one expense row.

-- =============================================================================
-- 0. THE INTERLOCK IS STILL SHUT AFTER 275.
--
-- 275 gates the expense but does NOT enable deferral -- 279 does, once there is
-- a consumption side to recognise the held cost. A deferred purchase created
-- now would hold its cost and never expense it.
-- =============================================================================
DO $lock$
BEGIN
    RAISE NOTICE '0a. interlock still shut  expect        f  got %',
        fnwatercostrecognition_deferralready();

    IF fnwatercostrecognition_deferralready() THEN
        RAISE EXCEPTION
          '275 opened the deferral interlock. Only 279 may do that -- the '
          'consumption side must exist before any company can defer a cost.';
    END IF;
END
$lock$;

-- Lift the interlock FOR THIS TRANSACTION ONLY so the deferred branch can be
-- exercised at all. This is what 279 will do permanently; here it is discarded
-- with the ROLLBACK.
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_deferralready()
RETURNS boolean LANGUAGE sql IMMUTABLE AS $ready$ SELECT TRUE $ready$;

DO $t$
DECLARE
    v_farm      text;
    v_acct      integer;
    v_supplier  integer;
    v_film      integer;   -- SachetFilm  -> follows the packaging setting
    v_fuel      integer;   -- Fuel        -> hard-wired to purchase, cannot defer
    v_pur_norm  integer;
    v_pur_def   integer;
    v_pur_snap  integer;
    v_paymentid integer;
    v_expcount  integer;
    v_expsum    numeric(14,2);
    v_cashsum   numeric(14,2);
    v_qty       numeric(18,4);
    v_qty2      numeric(18,4);
    v_linked    integer;
    v_method    text;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;
    RAISE NOTICE '   using water company %', v_farm;

    -- Start clean, or "unconfigured behaves like today" is not being tested.
    DELETE FROM waterfinancialsettings WHERE farmid = v_farm;

    SELECT ca.watercashaccountid INTO v_acct
    FROM   watercashaccounts ca
    WHERE  ca.farmid = v_farm AND ca.isactive = TRUE
    ORDER  BY ca.watercashaccountid LIMIT 1;
    IF v_acct IS NULL THEN
        INSERT INTO watercashaccounts (farmid, accountname, accounttype, currentbalance, isactive)
        VALUES (v_farm, 'ZZ Test Till', 'Cash', 0, TRUE)
        RETURNING watercashaccountid INTO v_acct;
    END IF;

    INSERT INTO watersuppliers (farmid, suppliername, isactive)
    VALUES (v_farm, 'ZZ Film Supplier', TRUE)
    RETURNING watersupplierid INTO v_supplier;

    -- Inserted directly rather than through spwaterrawmaterialitem_insert, for
    -- the reason 274's check file gives: this workstream has not reproduced that
    -- function, and coupling the checks to a signature nobody read here is how
    -- a check file starts failing for reasons that have nothing to do with the
    -- migration under test.
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Sachet Film 275', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_film;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Diesel 275', 'Fuel', 'Litre', 'Litre', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_fuel;

    -- =====================================================================
    -- A. A NORMAL PURCHASE IS UNCHANGED.
    --
    -- No settings row, so the resolver says EXPENSE_WHEN_PURCHASED and the
    -- function takes exactly the branch it took yesterday.
    -- =====================================================================
    SELECT COUNT(*) INTO v_expcount FROM waterexpenses WHERE farmid = v_farm;

    v_pur_norm := spwaterrawmaterialpurchase_insert(
        p_farmid                 => v_farm,
        p_waterrawmaterialitemid => v_film,
        p_suppliername           => NULL,
        p_purchasedate           => (now() at time zone 'utc'),
        p_quantity               => 10,
        p_unitcost               => 100,
        p_paymentmethod          => 'Cash',
        p_amountpaid             => 1000,
        p_receipturl             => NULL,
        p_receivedbystaffid      => NULL,
        p_notes                  => 'ZZ 275 normal',
        p_createdby              => 'ZZ tester',
        p_supplierid             => v_supplier,
        p_totalcost              => 1000,
        p_watercashaccountid     => v_acct,
        p_productionunit         => 'Roll',
        p_productionunitsperpurchaseunit => 1);

    SELECT pu.costrecognitionmethod, pu.linkedwaterexpenseid
    INTO   v_method, v_linked
    FROM   waterrawmaterialpurchases pu WHERE pu.waterrawmaterialpurchaseid = v_pur_norm;

    RAISE NOTICE 'A1. normal is stamped purchased expect EXPENSE_WHEN_PURCHASED  got %', v_method;
    RAISE NOTICE 'A2. and has a linked expense    expect        t  got %', (v_linked IS NOT NULL);

    SELECT COALESCE(SUM(e.amount), 0) INTO v_expsum
    FROM   waterexpenses e
    WHERE  e.farmid = v_farm AND e.sourcetype = 'RawMaterialPurchase' AND e.sourceid = v_pur_norm;
    RAISE NOTICE 'A3. expensed for amountpaid     expect  1000.00  got %', v_expsum;

    SELECT COALESCE(SUM(ct.amount), 0) INTO v_cashsum
    FROM   watercashtransactions ct
    WHERE  ct.farmid = v_farm AND ct.sourcetype = 'Expense' AND ct.sourceid = v_linked;
    RAISE NOTICE 'A4. and the cash went out       expect -1000.00  got %', v_cashsum;

    SELECT mi.currentquantity INTO v_qty
    FROM   waterrawmaterialitems mi WHERE mi.waterrawmaterialitemid = v_film;
    RAISE NOTICE 'A5. stock went up               expect  10.0000  got %', v_qty;

    -- =====================================================================
    -- B. A DEFERRED PURCHASE WRITES NO EXPENSE.
    --
    -- Same item, same money, one setting different. Everything that is not the
    -- P&L must be identical to section A.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    SELECT COUNT(*) INTO v_expcount FROM waterexpenses WHERE farmid = v_farm;

    v_pur_def := spwaterrawmaterialpurchase_insert(
        p_farmid                 => v_farm,
        p_waterrawmaterialitemid => v_film,
        p_suppliername           => NULL,
        p_purchasedate           => (now() at time zone 'utc'),
        p_quantity               => 10,
        p_unitcost               => 100,
        p_paymentmethod          => 'Credit',
        p_amountpaid             => 0,
        p_receipturl             => NULL,
        p_receivedbystaffid      => NULL,
        p_notes                  => 'ZZ 275 deferred',
        p_createdby              => 'ZZ tester',
        p_supplierid             => v_supplier,
        p_totalcost              => 1000,
        p_watercashaccountid     => NULL,
        p_productionunit         => 'Roll',
        p_productionunitsperpurchaseunit => 1);

    SELECT pu.costrecognitionmethod, pu.linkedwaterexpenseid
    INTO   v_method, v_linked
    FROM   waterrawmaterialpurchases pu WHERE pu.waterrawmaterialpurchaseid = v_pur_def;

    RAISE NOTICE 'B1. deferred is stamped         expect EXPENSE_WHEN_CONSUMED  got %', v_method;
    RAISE NOTICE 'B2. and has NO linked expense   expect        t  got %', (v_linked IS NULL);

    RAISE NOTICE 'B3. no expense row was written  expect        0  got %',
        (SELECT COUNT(*) FROM waterexpenses e
         WHERE e.farmid = v_farm AND e.sourcetype = 'RawMaterialPurchase' AND e.sourceid = v_pur_def);

    RAISE NOTICE 'B4. and the farm total is flat  expect        t  got %',
        ((SELECT COUNT(*) FROM waterexpenses WHERE farmid = v_farm) = v_expcount);

    -- The half that must NOT change. A deferred purchase is still a purchase.
    SELECT mi.currentquantity INTO v_qty2
    FROM   waterrawmaterialitems mi WHERE mi.waterrawmaterialitemid = v_film;
    RAISE NOTICE 'B5. stock still went up         expect  20.0000  got %', v_qty2;

    RAISE NOTICE 'B6. totalcost is unchanged      expect  1000.00  got %',
        (SELECT pu.totalcost FROM waterrawmaterialpurchases pu WHERE pu.waterrawmaterialpurchaseid = v_pur_def);
    RAISE NOTICE 'B7. the lot is full             expect  10.000   got %',
        (SELECT pu.remainingquantity FROM waterrawmaterialpurchases pu WHERE pu.waterrawmaterialpurchaseid = v_pur_def);
    RAISE NOTICE 'B8. and it is still payable     expect  1000.00  got %',
        (SELECT d.balance FROM fnwaterpayables(v_farm) d
         WHERE d.documenttype = 'RawMaterialPurchase' AND d.documentid = v_pur_def);

    -- An unconfigurable category cannot be dragged along by the setting.
    RAISE NOTICE 'B9. fuel still expenses at purchase expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT r.method FROM fnwatercostrecognition_effective(v_farm, v_fuel, NULL, NULL) r);

    -- =====================================================================
    -- C. THE METHOD IS SNAPSHOTTED, NOT RECOMPUTED.
    --
    -- Turning deferral back off must not retroactively expense a purchase that
    -- was entered while it was on. That is how a closed month's P&L moves.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    RAISE NOTICE 'C1. the old purchase is untouched expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT pu.costrecognitionmethod FROM waterrawmaterialpurchases pu
         WHERE pu.waterrawmaterialpurchaseid = v_pur_def);

    -- And a new one entered now follows the new setting.
    v_pur_snap := spwaterrawmaterialpurchase_insert(
        p_farmid                 => v_farm,
        p_waterrawmaterialitemid => v_film,
        p_suppliername           => NULL,
        p_purchasedate           => (now() at time zone 'utc'),
        p_quantity               => 1,
        p_unitcost               => 100,
        p_paymentmethod          => 'Credit',
        p_amountpaid             => 0,
        p_receipturl             => NULL,
        p_receivedbystaffid      => NULL,
        p_notes                  => 'ZZ 275 after revert',
        p_createdby              => 'ZZ tester',
        p_supplierid             => v_supplier,
        p_totalcost              => 100,
        p_watercashaccountid     => NULL,
        p_productionunit         => 'Roll',
        p_productionunitsperpurchaseunit => 1);

    RAISE NOTICE 'C2. the new one follows today  expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT pu.costrecognitionmethod FROM waterrawmaterialpurchases pu
         WHERE pu.waterrawmaterialpurchaseid = v_pur_snap);

    -- =====================================================================
    -- D. PAYING A DEFERRED PURCHASE EXPENSES NOTHING -- AND STILL MOVES CASH.
    --
    -- The second suppression site. Without it a credit purchase would expense
    -- itself in instalments as the supplier was paid, and the deferral would
    -- appear to work on the day it was entered and fail for the rest of its life.
    -- =====================================================================
    SELECT COUNT(*) INTO v_expcount FROM waterexpenses WHERE farmid = v_farm;
    SELECT ca.currentbalance INTO v_cashsum FROM watercashaccounts ca WHERE ca.watercashaccountid = v_acct;

    v_paymentid := spwatersupplierpayment_record(
        p_farmid        => v_farm,
        p_supplierid    => v_supplier,
        p_amount        => 1000,
        p_allocations   => jsonb_build_array(jsonb_build_object(
                               'documenttype', 'RawMaterialPurchase',
                               'documentid',   v_pur_def,
                               'amount',       1000)),
        p_paymentmethod => 'Cash',
        p_paymentdate   => (now() at time zone 'utc'),
        p_cashaccountid => v_acct,
        p_reference     => NULL,
        p_note          => NULL,
        p_sourcetype    => 'PurchaseEntry',
        p_createdby     => 'ZZ tester');

    RAISE NOTICE 'D1. payment wrote no expense    expect        0  got %',
        (SELECT COUNT(*) FROM waterexpenses e
         WHERE e.farmid = v_farm AND e.sourcetype = 'WaterSupplierPayment' AND e.sourceid = v_paymentid);

    RAISE NOTICE 'D2. and the farm total is flat  expect        t  got %',
        ((SELECT COUNT(*) FROM waterexpenses WHERE farmid = v_farm) = v_expcount);

    -- The point of the whole section: the supplier really was paid.
    RAISE NOTICE 'D3. cash still went out         expect -1000.00  got %',
        ((SELECT ca.currentbalance FROM watercashaccounts ca WHERE ca.watercashaccountid = v_acct) - v_cashsum);

    RAISE NOTICE 'D4. and the balance is settled  expect     0.00  got %',
        COALESCE((SELECT d.balance FROM fnwaterpayables(v_farm) d
                  WHERE d.documenttype = 'RawMaterialPurchase' AND d.documentid = v_pur_def), 0);

    -- =====================================================================
    -- E. THE MIXED PAYMENT.
    --
    -- One payment settling a deferred purchase AND a normal one. Water sums a
    -- payment's purchase allocations into ONE expense row, so an all-or-nothing
    -- gate would be wrong in both directions. The expense must be the normal
    -- portion only; the cash must be the whole payment.
    --
    -- Two fresh credit purchases so the balances are known exactly.
    -- =====================================================================
    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
    v_pur_def := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_film, p_suppliername => NULL,
        p_purchasedate => (now() at time zone 'utc'), p_quantity => 3, p_unitcost => 100,
        p_paymentmethod => 'Credit', p_amountpaid => 0, p_receipturl => NULL,
        p_receivedbystaffid => NULL, p_notes => 'ZZ 275 mixed-deferred', p_createdby => 'ZZ tester',
        p_supplierid => v_supplier, p_totalcost => 300, p_watercashaccountid => NULL,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    PERFORM spwaterfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');
    v_pur_norm := spwaterrawmaterialpurchase_insert(
        p_farmid => v_farm, p_waterrawmaterialitemid => v_film, p_suppliername => NULL,
        p_purchasedate => (now() at time zone 'utc'), p_quantity => 2, p_unitcost => 100,
        p_paymentmethod => 'Credit', p_amountpaid => 0, p_receipturl => NULL,
        p_receivedbystaffid => NULL, p_notes => 'ZZ 275 mixed-normal', p_createdby => 'ZZ tester',
        p_supplierid => v_supplier, p_totalcost => 200, p_watercashaccountid => NULL,
        p_productionunit => 'Roll', p_productionunitsperpurchaseunit => 1);

    SELECT ca.currentbalance INTO v_cashsum FROM watercashaccounts ca WHERE ca.watercashaccountid = v_acct;

    v_paymentid := spwatersupplierpayment_record(
        p_farmid        => v_farm,
        p_supplierid    => v_supplier,
        p_amount        => 500,
        p_allocations   => jsonb_build_array(
                               jsonb_build_object('documenttype', 'RawMaterialPurchase',
                                                  'documentid', v_pur_def,  'amount', 300),
                               jsonb_build_object('documenttype', 'RawMaterialPurchase',
                                                  'documentid', v_pur_norm, 'amount', 200)),
        p_paymentmethod => 'Cash',
        p_paymentdate   => (now() at time zone 'utc'),
        p_cashaccountid => v_acct,
        p_reference     => NULL,
        p_note          => NULL,
        p_sourcetype    => 'SupplierBalances',
        p_createdby     => 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_expsum
    FROM   waterexpenses e
    WHERE  e.farmid = v_farm AND e.sourcetype = 'WaterSupplierPayment' AND e.sourceid = v_paymentid;
    RAISE NOTICE 'E1. expensed the normal part only expect   200.00  got %', v_expsum;

    RAISE NOTICE 'E2. cash out is the WHOLE payment expect  -500.00  got %',
        ((SELECT ca.currentbalance FROM watercashaccounts ca WHERE ca.watercashaccountid = v_acct) - v_cashsum);

    -- The description must not claim to cover a document it excluded.
    RAISE NOTICE 'E3. description names only the expensed doc expect t  got %',
        (SELECT e.description LIKE '%#' || v_pur_norm::text || '%'
            AND e.description NOT LIKE '%#' || v_pur_def::text || '%'
         FROM waterexpenses e
         WHERE e.farmid = v_farm AND e.sourcetype = 'WaterSupplierPayment' AND e.sourceid = v_paymentid);

    -- Both balances are settled either way -- deferral is about the P&L, not
    -- about what is owed.
    RAISE NOTICE 'E4. deferred doc settled        expect     0.00  got %',
        COALESCE((SELECT d.balance FROM fnwaterpayables(v_farm) d
                  WHERE d.documenttype = 'RawMaterialPurchase' AND d.documentid = v_pur_def), 0);
    RAISE NOTICE 'E5. normal doc settled          expect     0.00  got %',
        COALESCE((SELECT d.balance FROM fnwaterpayables(v_farm) d
                  WHERE d.documenttype = 'RawMaterialPurchase' AND d.documentid = v_pur_norm), 0);

    RAISE NOTICE '--- 275 checks done. ROLL BACK this transaction. ---';
END
$t$;
