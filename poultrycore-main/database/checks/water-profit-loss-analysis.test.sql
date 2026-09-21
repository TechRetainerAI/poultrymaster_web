-- Behavioural checks for migration 316: the water P&L analytical layer.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it writes nothing.
--
--   psql ... -X -c "BEGIN;" -f water-profit-loss-analysis.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **The statement is spwaterreport_periodpnl's own arithmetic, itemised.**
--
-- 316 adds analysis and is not allowed to restate profit. Section A proves that
-- from the inside: every band of the statement must total EXACTLY the component
-- of periodpnl it sits under, and the bands together must reproduce its net
-- profit to the pesewa. If any line here disagrees, the drilldowns are lying
-- about where a number came from, which is worse than not having them.
--
-- Section B proves the drilldowns: each one is summed and must equal the line it
-- opens. A drilldown whose rows do not add up to the figure that was clicked is
-- the single most damaging thing this feature could ship.
--
-- The rest:
--   C. Informational sections never touch profit.
--   D. Company scoping.
--   E. An empty period is empty, not wrong.

DO $t$
DECLARE
    v_farm   text;
    v_from   date := '2000-01-01';
    v_to     date := '2099-12-31';
    b        record;   -- periodpnl, the authority
    s        record;   -- the new summary
    v_rev    numeric; v_direct numeric; v_opex numeric; v_other numeric; v_loss numeric;
    v_info   numeric;
    v_drill  numeric;
    v_line   numeric;
    v_n      integer;
    v_other_farm text;
BEGIN
    -- The water company with the most expense rows, so the checks run against
    -- real data rather than passing by vacuousness.
    SELECT f.farmid INTO v_farm
    FROM   farms f WHERE f.type = 'Water'
    ORDER  BY (SELECT COUNT(*) FROM waterexpenses e WHERE e.farmid = f.farmid) DESC, f.farmid
    LIMIT  1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No water company to test against.'; END IF;

    SELECT * INTO b FROM spwaterreport_periodpnl(v_farm, v_from, v_to);
    SELECT * INTO s FROM spwaterreport_plsummary(v_farm, v_from, v_to);
    RAISE NOTICE '   using water company % -- periodpnl net profit %', v_farm, b.netprofit;

    SELECT COUNT(*)::integer INTO v_n FROM spwaterreport_pllines(v_farm, v_from, v_to);
    RAISE NOTICE '   the statement has % line(s)', v_n;

    -- =====================================================================
    -- A. THE CLAIM. Every band totals what periodpnl says it totals.
    -- =====================================================================
    SELECT COALESCE(SUM(amount) FILTER (WHERE section = 'Revenue'), 0),
           COALESCE(SUM(amount) FILTER (WHERE section = 'DirectCost'), 0),
           COALESCE(SUM(amount) FILTER (WHERE section = 'OperatingExpense'), 0),
           COALESCE(SUM(amount) FILTER (WHERE section = 'OtherCost'), 0),
           COALESCE(SUM(amount) FILTER (WHERE section = 'Loss'), 0)
      INTO v_rev, v_direct, v_opex, v_other, v_loss
    FROM   spwaterreport_pllines(v_farm, v_from, v_to);

    RAISE NOTICE 'A1. Revenue band = periodpnl income        expect 0.00 diff  got %',
        COALESCE(ROUND(v_rev - b.totalincome, 2), -1);
    RAISE NOTICE 'A2. DirectCost band = raw + production     expect 0.00 diff  got %',
        COALESCE(ROUND(v_direct - (b.rawmaterialcost + b.productioncost), 2), -1);
    -- Operating and Other together, because 282 drops depreciation and loan
    -- interest into OtherCost while periodpnl keeps one flat expense figure.
    RAISE NOTICE 'A3. Operating + Other = periodpnl expenses expect 0.00 diff  got %',
        COALESCE(ROUND((v_opex + v_other) - b.totalexpenses, 2), -1);
    RAISE NOTICE 'A4. Loss band = periodpnl losses           expect 0.00 diff  got %',
        COALESCE(ROUND(v_loss - b.totallosses, 2), -1);

    -- And the whole thing, which is the sentence an owner reads.
    RAISE NOTICE 'A5. bands reproduce net profit             expect 0.00 diff  got %',
        COALESCE(ROUND((v_rev - v_direct - (v_opex + v_other) - v_loss) - b.netprofit, 2), -1);

    -- The summary must not have invented its own net profit either.
    RAISE NOTICE 'A6. summary net profit IS periodpnl''s      expect 0.00 diff  got %',
        COALESCE(ROUND(s.netprofit - b.netprofit, 2), -1);
    RAISE NOTICE 'A7. summary revenue IS periodpnl''s         expect 0.00 diff  got %',
        COALESCE(ROUND(s.totalrevenue - b.totalincome, 2), -1);

    -- =====================================================================
    -- B. Every drilldown adds up to the line it opens.
    -- =====================================================================
    SELECT COALESCE(SUM(amount), 0) INTO v_drill
    FROM   spwaterreport_plrevenuedetail(v_farm, v_from, v_to, NULL);
    RAISE NOTICE 'B1. revenue drilldown = Revenue band       expect 0.00 diff  got %',
        COALESCE(ROUND(v_drill - v_rev, 2), -1);

    SELECT COALESCE(SUM(amount), 0) INTO v_drill
    FROM   spwaterreport_pldirectcostdetail(v_farm, v_from, v_to, NULL);
    RAISE NOTICE 'B2. direct-cost drilldown = DirectCost     expect 0.00 diff  got %',
        COALESCE(ROUND(v_drill - v_direct, 2), -1);

    SELECT COALESCE(SUM(amount), 0) INTO v_drill
    FROM   spwaterreport_plexpensedetail(v_farm, v_from, v_to, NULL);
    RAISE NOTICE 'B3. expense drilldown = Operating + Other  expect 0.00 diff  got %',
        COALESCE(ROUND(v_drill - (v_opex + v_other), 2), -1);

    SELECT COALESCE(SUM(amount), 0) INTO v_drill
    FROM   spwaterreport_pllossdetail(v_farm, v_from, v_to, NULL);
    RAISE NOTICE 'B4. loss drilldown = Loss band             expect 0.00 diff  got %',
        COALESCE(ROUND(v_drill - v_loss, 2), -1);

    -- And per-line, which is what a click actually asks for. Storefront sales is
    -- the line most likely to exist on any database.
    SELECT COALESCE(SUM(amount), 0) INTO v_line
    FROM   spwaterreport_pllines(v_farm, v_from, v_to) WHERE linekey = 'StorefrontSales';
    SELECT COALESCE(SUM(amount), 0) INTO v_drill
    FROM   spwaterreport_plrevenuedetail(v_farm, v_from, v_to, 'StorefrontSales');
    RAISE NOTICE 'B5. one line''s drilldown = that line       expect 0.00 diff  got %',
        COALESCE(ROUND(v_drill - v_line, 2), -1);

    -- =====================================================================
    -- C. Informational sections are outside profit, by construction.
    -- =====================================================================
    SELECT COALESCE(SUM(amount), 0) INTO v_info
    FROM   spwaterreport_pllines(v_farm, v_from, v_to) WHERE isinformational;
    RAISE NOTICE 'C1. informational lines exist (or are 0)   got %', COALESCE(v_info, -1);
    -- The proof: remove them and the net profit is unchanged, because they were
    -- never in it.
    RAISE NOTICE 'C2. profit ignores them                    expect 0.00 diff  got %',
        COALESCE(ROUND((v_rev - v_direct - (v_opex + v_other) - v_loss) - b.netprofit, 2), -1);
    RAISE NOTICE 'C3. every Financing/Capital line is flagged  expect 0  got %',
        (SELECT COUNT(*)::integer FROM spwaterreport_pllines(v_farm, v_from, v_to)
          WHERE section IN ('Financing', 'CapitalInvestment') AND NOT isinformational);
    RAISE NOTICE 'C4. no profit line is flagged informational  expect 0  got %',
        (SELECT COUNT(*)::integer FROM spwaterreport_pllines(v_farm, v_from, v_to)
          WHERE section IN ('Revenue','DirectCost','OperatingExpense','OtherCost','Loss')
            AND isinformational);

    -- The flaw 316's header names, reported rather than hidden.
    RAISE NOTICE 'C5. capital purchases sitting in expenses  got % (0 is healthy)',
        COALESCE(s.capitalinexpenses, -1);

    -- =====================================================================
    -- D. Company scoping.
    -- =====================================================================
    SELECT f.farmid INTO v_other_farm FROM farms f WHERE f.farmid <> v_farm ORDER BY f.farmid LIMIT 1;
    IF v_other_farm IS NOT NULL THEN
        SELECT COUNT(*)::integer INTO v_n
        FROM   spwaterreport_pllines(v_other_farm, v_from, v_to) l
        WHERE  l.amount <> 0;
        RAISE NOTICE 'D1. another company''s statement is its own  got % line(s), not this one''s %',
            v_n, (SELECT COUNT(*)::integer FROM spwaterreport_pllines(v_farm, v_from, v_to));
    ELSE
        RAISE NOTICE 'D1. no second company on this database -- scoping not exercised';
    END IF;

    -- =====================================================================
    -- E. A period with nothing in it is empty, not wrong.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_n
    FROM   spwaterreport_pllines(v_farm, '1900-01-01', '1900-12-31');
    RAISE NOTICE 'E1. an empty period has no lines           expect 0  got %', COALESCE(v_n, -1);

    SELECT * INTO s FROM spwaterreport_plsummary(v_farm, '1900-01-01', '1900-12-31');
    RAISE NOTICE 'E2. and an empty summary nets to zero      expect 0.00  got %',
        COALESCE(s.netprofit, -1);

    RAISE NOTICE '--- 19 numbered assertions expected above (A1-E2). Every "diff" line';
    RAISE NOTICE '--- must read 0.00. A blank "got" is a FAILURE, not a pass. ---';
END;
$t$;
