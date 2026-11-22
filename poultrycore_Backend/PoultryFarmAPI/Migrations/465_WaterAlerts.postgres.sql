-- =============================================================================
-- 465  Water: Alerts -- everything that needs attention, on one page
--                       (the Water counterpart of poultry's Farm Alerts)
-- =============================================================================
--
-- Poultry's Farm Alerts is built from poultry things (missing production
-- records, unsorted eggs, flock anomalies, vaccinations). Water's attention
-- points are its own, so this is a Water design on the same principles:
--
--   DERIVED, NEVER STORED. Nothing is written; reading the page can never spam
--   anyone, and an alert disappears the moment its cause is fixed.
--   ONE ROW PER KIND OF PROBLEM, with how many and (for money) how much, a
--   severity (Critical / Warning / Info) and the page that fixes it.
--
--   Daily closing  days with activity but no closing (last 14 days), closings
--                  left in Draft, Rejected closings not yet redone
--   Production     batches waiting for approval
--   Deliveries     loadings still out from an earlier day, driver returns in Draft
--   Stock          raw materials Negative / Out of stock / Critical / Warning
--                  (464's days of supply -- the Restock Forecast's own figures)
--   Equipment      machines and boreholes due or overdue for maintenance,
--                  borehole quality tests due, repair logs still open
--   Money          customers overdue, supplier bills past their due date
--                  (receipt due date, else the supplier's payment terms),
--                  cash accounts below zero
--
-- Read-only. Idempotent.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.spwateralerts_get(text);

CREATE FUNCTION public.spwateralerts_get(p_farmid text)
RETURNS TABLE(section text, code text, severity text, title text, detail text,
              itemcount integer, amount numeric, href text, sortorder integer)
LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_today date := fncompany_businessdate(p_farmid);
    v_n     integer;
    v_amt   numeric;
    v_old   date;
BEGIN
    -- ---------------------------------------------------------- daily closing
    SELECT COUNT(*), MIN(d) INTO v_n, v_old
    FROM  (SELECT DISTINCT x.d FROM (
               SELECT s.saledate::date AS d FROM watersales s
               WHERE s.farmid = p_farmid AND s.status <> 'Cancelled'
               UNION SELECT pb.productiondate FROM waterproductionbatches pb
               WHERE pb.farmid = p_farmid AND NOT COALESCE(pb.isdeleted, FALSE) AND pb.status = 'Approved'
               UNION SELECT dr.returndate::date FROM waterdriverreturns dr
               WHERE dr.farmid = p_farmid AND dr.status = 'Approved') x
           WHERE x.d BETWEEN v_today - 14 AND v_today - 1) days(d)
    WHERE NOT EXISTS (SELECT 1 FROM waterdailyclosings c
                      WHERE c.farmid = p_farmid AND c.closingdate = days.d AND COALESCE(c.isactive, TRUE));
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Daily closing', 'MissingClosing', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' day has' ELSE ' days have' END || ' sales or production but no closing')::text,
            ('Last 14 days, earliest ' || to_char(v_old, 'DD Mon') || '.')::text, v_n, NULL::numeric, '/water-daily-closing', 10;
    END IF;

    SELECT COUNT(*) INTO v_n FROM waterdailyclosings c
    WHERE c.farmid = p_farmid AND COALESCE(c.isactive, TRUE) AND c.status = 'Draft' AND c.closingdate < v_today;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Daily closing', 'DraftClosing', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' closing is' ELSE ' closings are' END || ' still in Draft')::text,
            'Submit and approve them so the day is final.'::text, v_n, NULL::numeric, '/water-daily-closing', 11;
    END IF;

    SELECT COUNT(*) INTO v_n FROM waterdailyclosings c
    WHERE c.farmid = p_farmid AND COALESCE(c.isactive, TRUE) AND c.status = 'Rejected';
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Daily closing', 'RejectedClosing', 'Critical',
            (v_n || CASE WHEN v_n = 1 THEN ' closing was' ELSE ' closings were' END || ' rejected')::text,
            'Correct and resubmit them.'::text, v_n, NULL::numeric, '/water-daily-closing', 12;
    END IF;

    -- ------------------------------------------------------------- production
    SELECT COUNT(*), MIN(pb.productiondate) INTO v_n, v_old FROM waterproductionbatches pb
    WHERE pb.farmid = p_farmid AND NOT COALESCE(pb.isdeleted, FALSE) AND pb.status = 'Draft';
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Production', 'DraftBatches',
            (CASE WHEN v_old < v_today THEN 'Warning' ELSE 'Info' END)::text,
            (v_n || CASE WHEN v_n = 1 THEN ' production batch is' ELSE ' production batches are' END || ' waiting for approval')::text,
            'Stock and cost are only counted once a batch is approved.'::text, v_n, NULL::numeric, '/water-production-batches', 20;
    END IF;

    -- ------------------------------------------------------------- deliveries
    SELECT COUNT(*) INTO v_n FROM watervehicleloadings l
    WHERE l.farmid = p_farmid AND NOT COALESCE(l.isdeleted, FALSE) AND l.status = 'Loaded' AND l.loaddate::date < v_today;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Deliveries', 'LoadingsOut', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' vehicle loading is' ELSE ' vehicle loadings are' END || ' still out from an earlier day')::text,
            'Record the driver return so the bags and cash are accounted for.'::text, v_n, NULL::numeric, '/water-driver-returns', 30;
    END IF;

    SELECT COUNT(*), COALESCE(SUM(COALESCE(dr.cashcollected, 0) + COALESCE(dr.momocollected, 0) + COALESCE(dr.bankcollected, 0)), 0)
    INTO v_n, v_amt FROM waterdriverreturns dr
    WHERE dr.farmid = p_farmid AND dr.status = 'Draft';
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Deliveries', 'DraftReturns', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' driver return is' ELSE ' driver returns are' END || ' waiting for approval')::text,
            'Their sales and collections are not counted until approved.'::text, v_n, v_amt, '/water-driver-returns', 31;
    END IF;

    -- ------------------------------------------------------------------ stock
    RETURN QUERY
    SELECT 'Stock'::text, ('Stock' || s.status)::text,
           (CASE WHEN s.status IN ('Negative', 'OutOfStock', 'Critical') THEN 'Critical' ELSE 'Warning' END)::text,
           (COUNT(*) || ' raw material' || CASE WHEN COUNT(*) = 1 THEN ' ' ELSE 's ' END ||
            CASE s.status WHEN 'Negative' THEN 'below zero (a count is owed)'
                          WHEN 'OutOfStock' THEN 'out of stock and still in use'
                          WHEN 'Critical' THEN 'running out within the critical window'
                          ELSE 'running low' END)::text,
           string_agg(s.itemname, ', ' ORDER BY s.daysofsupply NULLS FIRST, s.itemname)::text,
           COUNT(*)::integer, NULL::numeric, '/water-restock-forecast'::text,
           (40 + MIN(s.severityrank))::integer
    FROM   public.spwaterstocksupply(p_farmid) s
    WHERE  s.status IN ('Negative', 'OutOfStock', 'Critical', 'Warning')
    GROUP  BY s.status;

    -- -------------------------------------------------------------- equipment
    SELECT COUNT(*), COUNT(*) FILTER (WHERE m.nextmaintenancedate < v_today) INTO v_n, v_amt FROM watermachines m
    WHERE m.farmid = p_farmid AND COALESCE(m.status, 'Active') <> 'Retired' AND m.nextmaintenancedate <= v_today;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Equipment', 'MachineMaintenance',
            (CASE WHEN v_amt > 0 THEN 'Warning' ELSE 'Info' END)::text,
            (v_n || CASE WHEN v_n = 1 THEN ' machine is' ELSE ' machines are' END || ' due for maintenance')::text,
            (CASE WHEN v_amt > 0 THEN v_amt || ' overdue.' ELSE 'Due today.' END)::text, v_n, NULL::numeric, '/water-machines', 50;
    END IF;

    SELECT COUNT(*) INTO v_n FROM waterboreholes b
    WHERE b.farmid = p_farmid AND COALESCE(b.status, 'Active') NOT IN ('Retired', 'Inactive') AND b.nextmaintenancedate <= v_today;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Equipment', 'BoreholeMaintenance', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' borehole is' ELSE ' boreholes are' END || ' due for maintenance')::text,
            NULL::text, v_n, NULL::numeric, '/water-boreholes', 51;
    END IF;

    SELECT COUNT(*) INTO v_n FROM waterboreholes b
    WHERE b.farmid = p_farmid AND COALESCE(b.status, 'Active') NOT IN ('Retired', 'Inactive') AND b.waterqualitytestduedate <= v_today;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Equipment', 'QualityTestDue', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' borehole needs' ELSE ' boreholes need' END || ' a water quality test')::text,
            NULL::text, v_n, NULL::numeric, '/water-boreholes', 52;
    END IF;

    SELECT COUNT(*), COALESCE(SUM(ml.repaircost), 0) INTO v_n, v_amt FROM watermaintenancelogs ml
    WHERE ml.farmid = p_farmid AND NOT COALESCE(ml.isdeleted, FALSE)
      AND COALESCE(ml.status, 'Open') NOT IN ('Completed', 'Resolved', 'Closed', 'Cancelled');
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Equipment', 'OpenRepairs', 'Info',
            (v_n || CASE WHEN v_n = 1 THEN ' repair is' ELSE ' repairs are' END || ' still open')::text,
            NULL::text, v_n, NULL::numeric, '/water-maintenance', 53;
    END IF;

    -- ------------------------------------------------------------------ money
    SELECT COUNT(*), COALESCE(SUM(b.overdueamount), 0) INTO v_n, v_amt
    FROM public.spwatercustomerbalances(p_farmid) b WHERE b.overdueamount > 0;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Money', 'CustomersOverdue', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' customer is' ELSE ' customers are' END || ' overdue')::text,
            'Past their payment terms.'::text, v_n, v_amt, '/water-customer-balances', 60;
    END IF;

    SELECT COUNT(*), COALESCE(SUM(x.balance), 0) INTO v_n, v_amt
    FROM public.fnwaterpayables(p_farmid) x
    LEFT JOIN watersuppliers s ON s.watersupplierid = x.supplierid AND s.farmid = p_farmid
    WHERE x.balance > 0.005
      AND COALESCE(x.duedate, x.docdate + COALESCE(s.paymenttermsdays, 0)) < v_today;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Money', 'SuppliersOverdue', 'Warning',
            (v_n || CASE WHEN v_n = 1 THEN ' supplier bill is' ELSE ' supplier bills are' END || ' past due')::text,
            'Due date, else the supplier''s payment terms.'::text, v_n, v_amt, '/water-supplier-balances', 61;
    END IF;

    SELECT COUNT(*), COALESCE(SUM(a.currentbalance), 0) INTO v_n, v_amt FROM watercashaccounts a
    WHERE a.farmid = p_farmid AND COALESCE(a.isactive, TRUE) AND a.currentbalance < 0;
    IF v_n > 0 THEN
        RETURN QUERY SELECT 'Money', 'NegativeCash', 'Critical',
            (v_n || CASE WHEN v_n = 1 THEN ' cash account is' ELSE ' cash accounts are' END || ' below zero')::text,
            'Usually a missing receipt or a payment recorded twice.'::text, v_n, v_amt, '/water-cash-accounts', 62;
    END IF;
END $f$;

COMMIT;
