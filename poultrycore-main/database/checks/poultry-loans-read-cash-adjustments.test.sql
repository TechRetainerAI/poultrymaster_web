-- Behavioural checks for migration 290: the Loans page reads cash adjustments.
--
-- One DO block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it writes a cash adjustment and a loan.
--
--   psql ... -X -c "BEGIN;" -f poultry-loans-read-cash-adjustments.test.sql -c "ROLLBACK;"
--
-- THE CLAIMS
--   A. A LoanReceived adjustment appears in the loan list, tagged so the page
--      can tell it apart, with loan id 0 so no action can be aimed at it.
--   B. It counts as DEBT -- the explicit decision behind this migration.
--   C. Only LoanReceived counts. Owner injections, withdrawals, opening
--      balances and corrections must NOT appear: 287 owns the first two, and
--      counting them here would state the same money twice across two pages.
--   D. A NEGATIVE LoanReceived nets off, because that is how a correction to an
--      over-stated borrowing is recorded on the Cash page.
--   E. Real loans are completely unaffected -- every column they returned
--      before, they still return.
--   F. The status filter still behaves, and legacy rows answer to the right
--      values.

DO $t$
DECLARE
    v_farm   text;
    v_user   text;
    v_tbl    text;
    v_adjid  integer;
    v_negid  integer;
    v_before numeric;
    v_after  numeric;
    v_r      record;
    v_n      integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Poultry' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No poultry company to run these checks against.';
    END IF;
    RAISE NOTICE '   using poultry company %', v_farm;

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'No cashadjustment table on this environment -- 290 has nothing to read.';
    END IF;
    RAISE NOTICE '   cash adjustments live in %', v_tbl;

    SELECT outstandingprincipal INTO v_before FROM sppoultryloan_summary(v_farm);
    RAISE NOTICE '   outstanding before: %', v_before;

    -- A user id is required by the table; any existing one will do.
    EXECUTE format('SELECT ca.userid::text FROM %s ca LIMIT 1', v_tbl) INTO v_user;
    v_user := COALESCE(v_user, 'ZZ tester');

    -- =====================================================================
    -- A. A LoanReceived adjustment reaches the loan list.
    -- =====================================================================
    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', 5000, 'ZZ 290 borrowed from uncle', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_adjid USING v_farm, v_user;

    SELECT * INTO v_r FROM sppoultryloan_getall(v_farm, 'All') r
    WHERE r.source = 'CashAdjustment' AND r.sourceid = v_adjid;

    RAISE NOTICE 'A1. the row is in the list    expect        t  got %', (v_r.sourceid IS NOT NULL);
    RAISE NOTICE 'A2. tagged as a cash adjustment expect CashAdjustment  got %', v_r.source;
    RAISE NOTICE 'A3. loan id is 0, not the adj id expect        0  got %', v_r.poultryloanid;
    RAISE NOTICE 'A4. principal is the amount   expect  5000.00  got %', v_r.originalprincipal;
    RAISE NOTICE 'A5. description carried over  expect        t  got %',
        (v_r.notes = 'ZZ 290 borrowed from uncle');
    -- Nothing was invented to fill the loan-only fields.
    RAISE NOTICE 'A6. no lender was invented    expect        t  got %', (v_r.lendername IS NULL);
    RAISE NOTICE 'A7. no interest rate invented expect        t  got %', (v_r.interestrate IS NULL);
    RAISE NOTICE 'A8. not overdue (no due date) expect        f  got %', v_r.isoverdue;
    RAISE NOTICE 'A9. and no repayments         expect        0  got %', v_r.paymentcount;

    -- =====================================================================
    -- B. IT COUNTS AS DEBT. The decision this migration exists to implement.
    -- =====================================================================
    SELECT outstandingprincipal INTO v_after FROM sppoultryloan_summary(v_farm);
    RAISE NOTICE 'B1. outstanding rose by it    expect  5000.00  got %', (v_after - v_before);
    RAISE NOTICE 'B2. borrowed rose too         expect  5000.00  got %',
        ((SELECT totalborrowed FROM sppoultryloan_summary(v_farm)) -
         (SELECT COALESCE(SUM(l.originalprincipal) FILTER (WHERE l.status <> 'Cancelled'), 0)
          FROM poultryloans l WHERE l.farmid = v_farm));
    -- But NOT into the things an adjustment has none of.
    RAISE NOTICE 'B3. nothing repaid            expect        t  got %',
        ((SELECT totalprincipalrepaid FROM sppoultryloan_summary(v_farm)) =
         (SELECT COALESCE(SUM(l.totalprincipalrepaid), 0) FROM poultryloans l WHERE l.farmid = v_farm));
    RAISE NOTICE 'B4. no interest added         expect        t  got %',
        ((SELECT totalinterestpaid FROM sppoultryloan_summary(v_farm)) =
         (SELECT COALESCE(SUM(l.totalinterestpaid), 0) FROM poultryloans l WHERE l.farmid = v_farm));
    RAISE NOTICE 'B5. summary agrees with list  expect        t  got %',
        ((SELECT activeloans FROM sppoultryloan_summary(v_farm)) =
         (SELECT COUNT(*)::int FROM sppoultryloan_getall(v_farm, 'Active')));

    -- =====================================================================
    -- C. ONLY LoanReceived. The other types belong to other pages.
    -- =====================================================================
    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'OwnerInjection', 9999, 'ZZ 290 owner money', now()),
               ($1, $2, CURRENT_DATE, 'Withdrawal',    -8888, 'ZZ 290 drawing',     now()),
               ($1, $2, CURRENT_DATE, 'OpeningBalance', 7777, 'ZZ 290 opening',     now()),
               ($1, $2, CURRENT_DATE, 'Correction',     6666, 'ZZ 290 fix',         now())
    $sql$, v_tbl) USING v_farm, v_user;

    SELECT COUNT(*) INTO v_n FROM sppoultryloan_getall(v_farm, 'All') r
    WHERE r.source = 'CashAdjustment'
      AND r.notes IN ('ZZ 290 owner money', 'ZZ 290 drawing', 'ZZ 290 opening', 'ZZ 290 fix');
    RAISE NOTICE 'C1. other types stay out      expect        0  got %', v_n;
    -- And they did not move the debt either.
    RAISE NOTICE 'C2. outstanding is unmoved    expect  5000.00  got %',
        ((SELECT outstandingprincipal FROM sppoultryloan_summary(v_farm)) - v_before);

    -- =====================================================================
    -- D. A NEGATIVE LoanReceived NETS OFF.
    --
    -- The correction case. Showing it as a positive borrowing would DOUBLE the
    -- debt the correction was entered to remove.
    -- =====================================================================
    EXECUTE format($sql$
        INSERT INTO %s (farmid, userid, adjustmentdate, adjustmenttype, amount, description, createddate)
        VALUES ($1, $2, CURRENT_DATE, 'LoanReceived', -2000, 'ZZ 290 over-stated, corrected', now())
        RETURNING adjustmentid
    $sql$, v_tbl) INTO v_negid USING v_farm, v_user;

    RAISE NOTICE 'D1. net debt is 5000 - 2000   expect  3000.00  got %',
        ((SELECT outstandingprincipal FROM sppoultryloan_summary(v_farm)) - v_before);
    RAISE NOTICE 'D2. the correction is visible expect -2000.00  got %',
        (SELECT r.originalprincipal FROM sppoultryloan_getall(v_farm, 'All') r
         WHERE r.source = 'CashAdjustment' AND r.sourceid = v_negid);

    -- =====================================================================
    -- E. REAL LOANS ARE UNAFFECTED.
    -- =====================================================================
    SELECT COUNT(*) INTO v_n FROM sppoultryloan_getall(v_farm, 'All') r WHERE r.source = 'Loan';
    RAISE NOTICE 'E1. real loans still listed   expect        t  got %',
        (v_n = (SELECT COUNT(*)::int FROM poultryloans l WHERE l.farmid = v_farm));
    RAISE NOTICE 'E2. and each keeps its own id expect        0  got %',
        (SELECT COUNT(*) FROM sppoultryloan_getall(v_farm, 'All') r
         WHERE r.source = 'Loan' AND r.sourceid <> r.poultryloanid);

    -- =====================================================================
    -- F. THE STATUS FILTER.
    -- =====================================================================
    RAISE NOTICE 'F1. legacy rows are Active    expect        2  got %',
        (SELECT COUNT(*) FROM sppoultryloan_getall(v_farm, 'Active') r
         WHERE r.source = 'CashAdjustment');
    RAISE NOTICE 'F2. and absent from PaidOff   expect        0  got %',
        (SELECT COUNT(*) FROM sppoultryloan_getall(v_farm, 'PaidOff') r
         WHERE r.source = 'CashAdjustment');
    RAISE NOTICE 'F3. and absent from Cancelled expect        0  got %',
        (SELECT COUNT(*) FROM sppoultryloan_getall(v_farm, 'Cancelled') r
         WHERE r.source = 'CashAdjustment');

    RAISE NOTICE '--- 290 checks done. ROLL BACK this transaction. ---';
END
$t$;
