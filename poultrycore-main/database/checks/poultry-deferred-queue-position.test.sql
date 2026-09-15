-- Behavioural checks for migration 289: the consumption-queue indicator.
--
--   psql ... -X -c "BEGIN;" -f poultry-deferred-queue-position.test.sql -c "ROLLBACK;"
--
-- THE CLAIM BEING TESTED
-- ----------------------
-- The indicator is only worth having if it PREDICTS THE ENGINE. So the central
-- check is not "does the arithmetic add up" but:
--
--     consume exactly quantityaheadinqueue, and the deferred lot must be the
--     very next thing drawn.
--
-- If that ever fails, the number is telling owners to feed out a quantity that
-- does not actually reach their deferred cost -- worse than showing nothing.
--
--   A  FIFO: oldest lot is 1st with 0 ahead; the deferred newest lot is last
--   B  the prediction is exact -- consume the stated quantity, deferred lot is next
--   C  a spent lot is NULL, not 0 (not queued at all vs. next in line)
--   D  LIFO reverses the queue, and the deferred lot jumps to the front
--   E  HIFO orders by unit cost, not by date
--   F  the summary's blocked counters agree with the rows

CREATE OR REPLACE FUNCTION pg_temp.zz_makerecord(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $fn$
DECLARE
    v_id integer;
BEGIN
    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (p_farmid, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$fn$;


DO $t$
DECLARE
    v_farm text;
    v_item integer;
    v_old1 integer; v_old2 integer; v_def integer;
    v_r1 integer; v_r2 integer;
    v_ahead numeric;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_CONSUMED', NULL, 'ZZ tester');

    -- The real-world shape: two older expensed lots, then a new deferred one.
    -- The item is created BEFORE the setting matters to it, so lots 1 and 2 are
    -- forced to expense-at-purchase by an override, then the override is lifted.
    v_item := sppoultryrawmaterialitem_insert(
        v_farm, 'ZZ Q Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg',
        'EXPENSE_WHEN_PURCHASED');

    v_old1 := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ', p_purchasedate => ((now() at time zone 'utc') - interval '10 days'),
        p_quantity => 200, p_unitcost => 1, p_totalcost => 200,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 200, p_createdby => 'ZZ tester');
    v_old2 := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ', p_purchasedate => ((now() at time zone 'utc') - interval '5 days'),
        p_quantity => 12, p_unitcost => 2, p_totalcost => 24,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 24, p_createdby => 'ZZ tester');

    -- Lift the override so the NEXT purchase defers, exactly as a farm that
    -- has just switched its setting.
    PERFORM sppoultryrawmaterialitem_update(
        p_poultryrawmaterialitemid => v_item, p_farmid => v_farm,
        p_itemname => 'ZZ Q Feed', p_category => 'FinishedFeed', p_unitofmeasure => 'kg',
        p_minimumstockalert => 0, p_isactive => TRUE, p_notes => NULL,
        p_usagemethod => 'FIFO', p_purchaseunitofmeasure => 'kg',
        p_costrecognitionoverride => NULL, p_setcostrecognitionoverride => TRUE);

    v_def := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_item,
        p_suppliername => 'ZZ', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 500, p_unitcost => 10, p_totalcost => 5000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 5000, p_createdby => 'ZZ tester');

    -- =====================================================================
    -- A. FIFO: oldest first, deferred lot last.
    -- =====================================================================
    RAISE NOTICE 'A1. oldest lot is 1st      expect        1  got %',
        (SELECT queueposition FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_old1);
    RAISE NOTICE 'A2.   with nothing ahead   expect     0.00  got %',
        (SELECT quantityaheadinqueue FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_old1);
    RAISE NOTICE 'A3. deferred lot is 3rd    expect        3  got %',
        (SELECT queueposition FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_def);
    -- 200 + 12. THE number the page puts in front of an owner.
    RAISE NOTICE 'A4.   behind 212 kg        expect   212.00  got %',
        (SELECT quantityaheadinqueue FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_def);
    RAISE NOTICE 'A5. costing method shown   expect     FIFO  got %',
        (SELECT costingmethod FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_def);

    -- =====================================================================
    -- B. **THE** check: the prediction is exact.
    --
    -- Consume precisely what the indicator said was in the way. The deferred
    -- lot must then be next -- so one more kilo recognises deferred cost, and
    -- not a pesewa before that.
    -- =====================================================================
    SELECT quantityaheadinqueue INTO v_ahead FROM fnpoultrydeferredpurchase_rows(v_farm)
    WHERE  poultryrawmaterialpurchaseid = v_def;

    v_r1 := pg_temp.zz_makerecord(v_farm);
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r1, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_item::text || ',"qty":' || v_ahead::text || '}]'));

    -- Everything drawn was expensed at purchase, so nothing reached the P&L.
    RAISE NOTICE 'B1. clearing the queue costs 0 expect  0.00  got %',
        (SELECT COALESCE(SUM(e.amount), 0) FROM expense e
          WHERE e.farmid::text = v_farm AND e.sourcetype = 'PoultryFeedConsumption'
            AND e.sourceid = v_r1);
    RAISE NOTICE 'B2. deferred lot untouched expect  5000.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases
          WHERE poultryrawmaterialpurchaseid = v_def);
    -- It is now at the front.
    RAISE NOTICE 'B3. deferred lot now 1st   expect        1  got %',
        (SELECT queueposition FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_def);
    RAISE NOTICE 'B4.   with nothing ahead   expect     0.00  got %',
        (SELECT quantityaheadinqueue FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_def);

    -- One more draw, and now it costs. 50 kg at 10.00.
    v_r2 := pg_temp.zz_makerecord(v_farm);
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r2, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_item::text || ',"qty":50}]'));

    RAISE NOTICE 'B5. next 50 kg costs 500   expect   500.00  got %',
        (SELECT COALESCE(SUM(e.amount), 0) FROM expense e
          WHERE e.farmid::text = v_farm AND e.sourcetype = 'PoultryFeedConsumption'
            AND e.sourceid = v_r2);
    RAISE NOTICE 'B6. deferred left 4500     expect  4500.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases
          WHERE poultryrawmaterialpurchaseid = v_def);

    -- =====================================================================
    -- C. A spent lot is not queued.
    -- =====================================================================
    RAISE NOTICE 'C1. spent lot has no place expect        t  got %',
        (SELECT queueposition IS NULL FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_old1);
    -- NULL, not 0: zero would read as "next to be drawn".
    RAISE NOTICE 'C2.   and nothing ahead    expect        t  got %',
        (SELECT quantityaheadinqueue IS NULL FROM fnpoultrydeferredpurchase_rows(v_farm)
          WHERE poultryrawmaterialpurchaseid = v_old1);

    -- =====================================================================
    -- D/E. The order follows the item's costing method.
    -- =====================================================================
    DECLARE
        v_i2 integer; v_a integer; v_b integer;
    BEGIN
        v_i2 := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Q LIFO', 'FinishedFeed', 'kg', 0, NULL, 'LIFO', 'kg');
        v_a := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_i2,
            p_suppliername => 'ZZ', p_purchasedate => ((now() at time zone 'utc') - interval '3 days'),
            p_quantity => 100, p_unitcost => 4, p_totalcost => 400,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 400, p_createdby => 'ZZ tester');
        v_b := sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_i2,
            p_suppliername => 'ZZ', p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 60, p_unitcost => 9, p_totalcost => 540,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 540, p_createdby => 'ZZ tester');

        -- Under LIFO the NEWEST lot leads, so the deferred one is reachable at once.
        RAISE NOTICE 'D1. LIFO puts newest 1st   expect        1  got %',
            (SELECT queueposition FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_b);
        RAISE NOTICE 'D2.   nothing ahead of it  expect     0.00  got %',
            (SELECT quantityaheadinqueue FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_b);
        RAISE NOTICE 'D3. older lot is 2nd       expect        2  got %',
            (SELECT queueposition FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_a);

        -- HIFO orders by unit cost: 9.00 before 4.00, which here coincides with
        -- newest-first, so flip the costs to make the two orders differ.
        PERFORM sppoultryrawmaterialitem_update(
            p_poultryrawmaterialitemid => v_i2, p_farmid => v_farm,
            p_itemname => 'ZZ Q LIFO', p_category => 'FinishedFeed', p_unitofmeasure => 'kg',
            p_minimumstockalert => 0, p_isactive => TRUE, p_notes => NULL,
            p_usagemethod => 'HIFO', p_purchaseunitofmeasure => 'kg',
            p_costrecognitionoverride => NULL, p_setcostrecognitionoverride => FALSE);
        UPDATE poultryrawmaterialpurchases SET unitcost = 99
        WHERE  poultryrawmaterialpurchaseid = v_a;

        RAISE NOTICE 'E1. HIFO leads on cost    expect        1  got %',
            (SELECT queueposition FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_a);
        RAISE NOTICE 'E2.   method reported     expect     HIFO  got %',
            (SELECT costingmethod FROM fnpoultrydeferredpurchase_rows(v_farm)
              WHERE poultryrawmaterialpurchaseid = v_a);
    END;

    -- =====================================================================
    -- F. The summary's blocked counters agree with the rows.
    -- =====================================================================
    RAISE NOTICE 'F1. blocked count matches  expect        0  got %',
        ((SELECT blockedpurchases FROM sppoultrydeferredpurchase_summary(v_farm, 'DEFERRED'))
         - (SELECT COUNT(*) FROM sppoultrydeferredpurchase_getall(v_farm, 'DEFERRED')
             WHERE COALESCE(quantityaheadinqueue, 0) > 0));
    RAISE NOTICE 'F2. blocked cost matches   expect     0.00  got %',
        ((SELECT blockedcost FROM sppoultrydeferredpurchase_summary(v_farm, 'DEFERRED'))
         - (SELECT COALESCE(SUM(deferredremainingcost), 0)
              FROM sppoultrydeferredpurchase_getall(v_farm, 'DEFERRED')
             WHERE COALESCE(quantityaheadinqueue, 0) > 0));

    RAISE NOTICE '   -- all checks emitted; compare each expect/got pair above --';
END
$t$;
