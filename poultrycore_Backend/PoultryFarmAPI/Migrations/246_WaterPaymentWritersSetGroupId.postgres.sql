-- =============================================================================
-- 246  The water payment writers set the group id themselves
-- =============================================================================
-- 245 put a BEFORE INSERT trigger on waterpayments so a row can never again
-- land without a paymentgroupid. That closes the hole. It does not make the
-- three writers that caused it correct -- they still name their columns
-- explicitly and still leave the group out, and the next person reading them
-- learns the wrong lesson about what a payment row needs.
--
-- This fixes them at the source:
--
--   spwaterpayment_record                 1 insert
--   spwaterdriverreturn_approve           3 inserts
--   spwaterdriverreturn_approvereconcile  9 inserts
--
-- Each insert gains `paymentgroupid` in its column list and gen_random_uuid()
-- in its VALUES. NOTHING ELSE IN THESE FUNCTIONS CHANGES -- the bodies below
-- are pg_get_functiondef output with exactly those 13 pairs of lines edited,
-- so the diff against what is running is 26 lines and no logic.
--
-- THE TRIGGER STAYS. It is not made redundant by this: it is what covers the
-- writer somebody adds next year, and belt-and-braces on a column that three
-- separate authors have already forgotten is proportionate. Where both apply
-- the writer wins -- the trigger only fills a NULL.
--
-- ONE GROUP PER ROW, NOT PER APPROVAL. Approving a driver return can write a
-- cash row, a mobile-money row and a bank row against one sale. Each gets its
-- own group, so they read as three payments -- which is how they read today,
-- and how the rows 227 backfilled already read. Merging them into one payment
-- event per approval is a defensible alternative and a DIFFERENT decision:
-- it would change what the ledger and the statement show, so it is not being
-- smuggled in here.
--
-- NO DATA IS TOUCHED. Function bodies only. Existing rows keep the groups they
-- have; 245 already repaired the ones that had none.
--
-- HOW TO RUN
--   1. Dry run (default):
--        psql "<conn>" -f 246_WaterPaymentWritersSetGroupId.postgres.sql
--   2. For real:
--        psql "<conn>" -v apply=true -f 246_WaterPaymentWritersSetGroupId.postgres.sql
--
--   Requires 245 (the repaired rows and the trigger). Safe to run at any time
--   after it; no API build depends on this one.
-- =============================================================================

\set ON_ERROR_STOP on

\if :{?apply}
\else
  \set apply false
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Which writers are missing it now.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Writers into waterpayments, BEFORE ======================================'
SELECT p.proname,
       array_length(string_to_array(lower(p.prosrc), 'insert into waterpayments'), 1) - 1 AS inserts,
       CASE WHEN lower(p.prosrc) LIKE '%paymentgroupid%' THEN 'sets it' ELSE 'MISSING' END AS groupid
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND lower(p.prosrc) LIKE '%insert into waterpayments%'
ORDER  BY 1;

-- -----------------------------------------------------------------------------
-- 2. The three functions, unchanged but for their inserts.
-- -----------------------------------------------------------------------------

-- ---- spwaterpayment_record ---------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterpayment_record(p_farmid text, p_watersaleid integer DEFAULT NULL::integer, p_amount numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_paymentdate timestamp := p_paymentdate;
    v_paymentid   integer;
BEGIN
    IF v_paymentdate IS NULL THEN
        v_paymentdate := (now() at time zone 'utc');
    END IF;

    -- Sale must belong to farm.
    IF NOT EXISTS (SELECT 1 FROM watersales s
                   WHERE s.watersaleid = p_watersaleid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Sale does not belong to this farm.';
    END IF;

    INSERT INTO waterpayments
        (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, paymentgroupid)
    VALUES (p_farmid, p_watersaleid, p_amount, p_paymentmethod, v_paymentdate, p_reference, p_note, p_createdby, gen_random_uuid())
    RETURNING waterpaymentid INTO v_paymentid;

    -- Recompute AmountPaid and Status on the sale.
    UPDATE watersales s
    SET    amountpaid = COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                                  WHERE w.watersaleid = s.watersaleid), 0),
           status     = CASE
                          WHEN s.status = 'Cancelled' THEN 'Cancelled'
                          WHEN COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                                         WHERE w.watersaleid = s.watersaleid), 0) >= s.totalamount
                               THEN 'Paid'
                          WHEN COALESCE((SELECT SUM(w.amount) FROM waterpayments w
                                         WHERE w.watersaleid = s.watersaleid), 0) > 0
                               THEN 'PartiallyPaid'
                          ELSE 'Pending'
                        END,
           updateddate = (now() at time zone 'utc')
    WHERE  s.watersaleid = p_watersaleid;

    RETURN v_paymentid;
END;
$function$

;

-- ---- spwaterdriverreturn_approve ---------------------------------
CREATE OR REPLACE FUNCTION public.spwaterdriverreturn_approve(p_waterdriverreturnid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status            text;
    v_loadingid         integer;
    v_bagssold          integer;
    v_bagsreturned      integer;
    v_bagsdamaged       integer;
    v_cashcollected     numeric;
    v_momocollected     numeric;
    v_bankcollected     numeric;
    v_creditsalesamount numeric;
    v_productid         integer;
    v_expectedpriceperbag numeric;
    v_driverid          integer;
    v_vehicleid         integer;
    v_routeid           integer;
    v_expectedcash      numeric;
    v_totalaccounted    numeric;
    v_shortage          numeric;
    v_overage           numeric;
    v_cs                record;
    v_paid              numeric;
    v_balance           numeric;
    v_salestatus        text;
    v_saleid            integer;
BEGIN
    IF EXISTS (SELECT 1 FROM waterdriverreturns dr
               WHERE dr.waterdriverreturnid = p_waterdriverreturnid
                 AND dr.farmid = p_farmid AND dr.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT dr.status, dr.watervehicleloadingid,
           dr.bagssold, dr.bagsreturned, dr.bagsdamaged,
           dr.cashcollected, dr.momocollected, dr.bankcollected, dr.creditsalesamount
      INTO v_status, v_loadingid,
           v_bagssold, v_bagsreturned, v_bagsdamaged,
           v_cashcollected, v_momocollected, v_bankcollected, v_creditsalesamount
    FROM   waterdriverreturns dr
    WHERE  dr.waterdriverreturnid = p_waterdriverreturnid AND dr.farmid = p_farmid
    LIMIT  1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Driver return % not found.', p_waterdriverreturnid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Driver return cannot be approved from status %.', v_status;
    END IF;

    SELECT l.waterproductid, l.expectedsellingpriceperbag,
           l.waterdriverid, l.watervehicleid, l.waterrouteid
      INTO v_productid, v_expectedpriceperbag, v_driverid, v_vehicleid, v_routeid
    FROM   watervehicleloadings l
    WHERE  l.watervehicleloadingid = v_loadingid AND l.farmid = p_farmid
    LIMIT  1;

    -- Expected cash: prefer per-item rows when present (multi-product), else
    -- fall back to legacy bagsSold * headerPrice.
    SELECT COALESCE(SUM(ri.expectedsales), 0) INTO v_expectedcash
    FROM   waterdriverreturnitems ri
    WHERE  ri.waterdriverreturnid = p_waterdriverreturnid;

    IF v_expectedcash = 0 THEN
        v_expectedcash := (v_bagssold::numeric(14,2)) * v_expectedpriceperbag;
    END IF;

    v_totalaccounted := v_cashcollected + v_momocollected + v_bankcollected + v_creditsalesamount;
    v_shortage := CASE WHEN v_expectedcash > v_totalaccounted THEN v_expectedcash - v_totalaccounted ELSE 0 END;
    v_overage  := CASE WHEN v_totalaccounted > v_expectedcash THEN v_totalaccounted - v_expectedcash ELSE 0 END;

    UPDATE waterdriverreturns dr
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc'),
           shortageamount = v_shortage, overageamount = v_overage
    WHERE  dr.waterdriverreturnid = p_waterdriverreturnid AND dr.farmid = p_farmid;

    UPDATE watervehicleloadings l
    SET    status = 'Reconciled', updatedat = (now() at time zone 'utc')
    WHERE  l.watervehicleloadingid = v_loadingid AND l.farmid = p_farmid;

    -- Per-product LoadReturnIn movements. Multi-item branch when present, else
    -- fall back to the legacy single-product return.
    IF EXISTS (SELECT 1 FROM waterdriverreturnitems ri
               WHERE ri.waterdriverreturnid = p_waterdriverreturnid) THEN
        INSERT INTO waterstocktransactions
            (farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
        SELECT p_farmid, ri.waterproductid, 'LoadReturnIn', ri.bagsreturned, NULL, NULL,
               concat('Driver return #', p_waterdriverreturnid, ' for loading #', v_loadingid),
               p_approvedby
        FROM   waterdriverreturnitems ri
        WHERE  ri.waterdriverreturnid = p_waterdriverreturnid
          AND  ri.bagsreturned > 0;
    ELSIF v_bagsreturned > 0 THEN
        INSERT INTO waterstocktransactions
            (farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
        VALUES (p_farmid, v_productid, 'LoadReturnIn', v_bagsreturned, NULL, NULL,
                concat('Driver return #', p_waterdriverreturnid, ' for loading #', v_loadingid),
                p_approvedby);
    END IF;

    -- Materialize customer breakdown into WaterSales/Items/Payments.
    -- Stock has ALREADY moved on LoadOut, so we don't write Sale stock txns
    -- here (avoiding double-decrement).
    FOR v_cs IN
        SELECT cs.waterdriverreturncustomersaleid AS csid,
               cs.watercustomerid AS custid, cs.totalamount AS tot,
               cs.cashpaid AS cash, cs.momopaid AS momo, cs.bankpaid AS bank,
               cs.creditamount AS credit, cs.notes AS csnotes
        FROM   waterdriverreturncustomersales cs
        WHERE  cs.waterdriverreturnid = p_waterdriverreturnid
    LOOP
        v_paid    := v_cs.cash + v_cs.momo + v_cs.bank;
        v_balance := v_cs.tot - v_paid;
        v_salestatus := CASE WHEN v_balance <= 0 THEN 'Paid'
                             WHEN v_paid > 0     THEN 'PartiallyPaid'
                             ELSE 'Pending' END;

        INSERT INTO watersales
            (farmid, watercustomerid, saledate, totalamount, amountpaid, status, notes,
             createdby, sourcetype, sourceid, waterdriverid, watervehicleid, waterrouteid)
        VALUES
            (p_farmid, v_cs.custid, (now() at time zone 'utc'), v_cs.tot, v_paid, v_salestatus, v_cs.csnotes,
             p_approvedby, 'DeliveryRun', p_waterdriverreturnid, v_driverid, v_vehicleid, v_routeid)
        RETURNING watersaleid INTO v_saleid;

        INSERT INTO watersaleitems (watersaleid, waterproductid, quantity, unitprice)
        SELECT v_saleid, csi.waterproductid, csi.quantity, csi.unitprice
        FROM   waterdriverreturncustomersaleitems csi
        WHERE  csi.waterdriverreturncustomersaleid = v_cs.csid;

        -- One payment row per non-zero method.
        IF v_cs.cash > 0 THEN
            INSERT INTO waterpayments
                (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note,
                 createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
            VALUES (p_farmid, v_saleid, v_cs.cash, 'Cash', (now() at time zone 'utc'),
                    concat('DR#', p_waterdriverreturnid), NULL,
                    p_approvedby, v_cs.custid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
        END IF;

        IF v_cs.momo > 0 THEN
            INSERT INTO waterpayments
                (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note,
                 createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
            VALUES (p_farmid, v_saleid, v_cs.momo, 'Mobile Money', (now() at time zone 'utc'),
                    concat('DR#', p_waterdriverreturnid), NULL,
                    p_approvedby, v_cs.custid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
        END IF;

        IF v_cs.bank > 0 THEN
            INSERT INTO waterpayments
                (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note,
                 createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
            VALUES (p_farmid, v_saleid, v_cs.bank, 'Bank', (now() at time zone 'utc'),
                    concat('DR#', p_waterdriverreturnid), NULL,
                    p_approvedby, v_cs.custid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
        END IF;

        UPDATE waterdriverreturncustomersales cs
        SET    generatedwatersaleid = v_saleid, updatedat = (now() at time zone 'utc')
        WHERE  cs.waterdriverreturncustomersaleid = v_cs.csid;
    END LOOP;

    -- Shortage row (legacy behaviour).
    IF v_shortage > 0 THEN
        INSERT INTO waterdrivershortages (
            farmid, waterdriverid, watervehicleloadingid, waterdriverreturnid,
            shortagedate, expectedamount, actualamount, shortageamount,
            reason, status, notes
        )
        VALUES (
            p_farmid, v_driverid, v_loadingid, p_waterdriverreturnid,
            (now() at time zone 'utc'), v_expectedcash, v_totalaccounted, v_shortage,
            NULL, 'Pending', NULL
        );
    END IF;
END;
$function$

;

-- ---- spwaterdriverreturn_approvereconcile ------------------------
CREATE OR REPLACE FUNCTION public.spwaterdriverreturn_approvereconcile(p_waterdriverreturnid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status              text;
    v_loadingid           integer;
    v_bagssold            integer;
    v_bagsreturned        integer;
    v_bagsdamaged         integer;
    v_missingbags         integer;
    v_cashcollected       numeric;
    v_momocollected       numeric;
    v_bankcollected       numeric;
    v_creditsalesamount   numeric;
    v_postingmode         text;
    v_primarycustomerid   integer;
    v_loadingbagstotal    integer;
    v_custtotalsum        numeric;
    v_collectedsum        numeric;
    v_productid           integer;
    v_expectedpriceperbag numeric;
    v_driverid            integer;
    v_vehicleid           integer;
    v_routeid             integer;
    v_expectedcash        numeric;
    v_totalaccounted      numeric;
    v_shortage            numeric;
    v_overage             numeric;
    v_creditcustomerid    integer;
    v_cs                  record;
    v_paid                numeric;
    v_balance             numeric;
    v_salestatus          text;
    v_saleid              integer;
    v_saletotal           numeric;
    v_salepaid            numeric;
    v_salestatusone       text;
    v_sid1                integer;
    v_sid                 integer;
BEGIN
    SELECT dr.status, dr.watervehicleloadingid,
           dr.bagssold, dr.bagsreturned, dr.bagsdamaged, dr.missingbags,
           dr.cashcollected, dr.momocollected, dr.bankcollected, dr.creditsalesamount,
           COALESCE(dr.salespostingmode, 'Detailed'), dr.primarycustomerid
      INTO v_status, v_loadingid,
           v_bagssold, v_bagsreturned, v_bagsdamaged, v_missingbags,
           v_cashcollected, v_momocollected, v_bankcollected, v_creditsalesamount,
           v_postingmode, v_primarycustomerid
    FROM   waterdriverreturns dr
    WHERE  dr.waterdriverreturnid = p_waterdriverreturnid AND dr.farmid = p_farmid
    LIMIT  1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Driver return % not found.', p_waterdriverreturnid;
    END IF;
    IF v_status = 'Approved' THEN
        RETURN;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Driver return cannot be approved from status %.', v_status;
    END IF;

    -- -------- Validation ------------------------------------------------
    -- 1. Bag accounting must balance against the loading.
    SELECT l.bagsloaded INTO v_loadingbagstotal
    FROM   watervehicleloadings l
    WHERE  l.watervehicleloadingid = v_loadingid AND l.farmid = p_farmid
    LIMIT  1;

    IF v_loadingbagstotal IS NULL THEN
        RAISE EXCEPTION 'Loading % not found.', v_loadingid;
    END IF;

    -- Prefer per-item totals when present (multi-product); else header totals.
    IF EXISTS (SELECT 1 FROM waterdriverreturnitems ri
               WHERE ri.waterdriverreturnid = p_waterdriverreturnid) THEN
        IF EXISTS (
            SELECT 1
            FROM   waterdriverreturnitems ri
            WHERE  ri.waterdriverreturnid = p_waterdriverreturnid
              AND  (ri.bagssold + ri.bagsreturned + ri.bagsdamaged) > ri.bagsloaded
        ) THEN
            RAISE EXCEPTION 'Per-product reconciliation does not balance: sold + returned + damaged exceeds loaded for at least one product.';
        END IF;
    ELSE
        IF (v_bagssold + v_bagsreturned + v_bagsdamaged + v_missingbags) <> v_loadingbagstotal THEN
            RAISE EXCEPTION 'Bag accounting does not balance: % sold + % returned + % damaged + % missing != % loaded.',
                v_bagssold, v_bagsreturned, v_bagsdamaged, v_missingbags, v_loadingbagstotal;
        END IF;
    END IF;

    -- 2. Money fields can't be negative.
    IF (v_cashcollected < 0 OR v_momocollected < 0 OR v_bankcollected < 0 OR v_creditsalesamount < 0) THEN
        RAISE EXCEPTION 'Cash / MoMo / Bank / Credit values cannot be negative.';
    END IF;

    -- 3. Detailed mode: customer breakdown total ~= collected total.
    IF v_postingmode = 'Detailed'
       AND EXISTS (SELECT 1 FROM waterdriverreturncustomersales cs
                   WHERE cs.waterdriverreturnid = p_waterdriverreturnid) THEN
        v_collectedsum := v_cashcollected + v_momocollected + v_bankcollected + v_creditsalesamount;

        SELECT SUM(cs.cashpaid + cs.momopaid + cs.bankpaid + cs.creditamount)
          INTO v_custtotalsum
        FROM   waterdriverreturncustomersales cs
        WHERE  cs.waterdriverreturnid = p_waterdriverreturnid;

        IF ABS(COALESCE(v_custtotalsum, 0) - v_collectedsum) > 0.01 THEN
            RAISE EXCEPTION 'Customer-breakdown total (%) does not match collected total (%).',
                COALESCE(v_custtotalsum, 0)::numeric(14,2)::text,
                v_collectedsum::numeric(14,2)::text;
        END IF;
    END IF;

    -- -------- Posting prep ----------------------------------------------
    SELECT l.waterproductid, l.expectedsellingpriceperbag,
           l.waterdriverid, l.watervehicleid, l.waterrouteid
      INTO v_productid, v_expectedpriceperbag, v_driverid, v_vehicleid, v_routeid
    FROM   watervehicleloadings l
    WHERE  l.watervehicleloadingid = v_loadingid AND l.farmid = p_farmid
    LIMIT  1;

    SELECT COALESCE(SUM(ri.expectedsales), 0) INTO v_expectedcash
    FROM   waterdriverreturnitems ri
    WHERE  ri.waterdriverreturnid = p_waterdriverreturnid;

    IF v_expectedcash = 0 THEN
        v_expectedcash := (v_bagssold::numeric(14,2)) * v_expectedpriceperbag;
    END IF;

    v_totalaccounted := v_cashcollected + v_momocollected + v_bankcollected + v_creditsalesamount;
    v_shortage := CASE WHEN v_expectedcash > v_totalaccounted THEN v_expectedcash - v_totalaccounted ELSE 0 END;
    v_overage  := CASE WHEN v_totalaccounted > v_expectedcash THEN v_totalaccounted - v_expectedcash ELSE 0 END;

    -- For OneCustomer / Summary modes we need a customer to attach the sale to.
    IF v_postingmode = 'Summary' THEN
        IF v_primarycustomerid IS NULL THEN
            SELECT c.watercustomerid INTO v_primarycustomerid
            FROM   watercustomers c
            WHERE  c.farmid = p_farmid AND c.defaultcustomertype = 'GeneralDelivery'
            LIMIT  1;

            IF v_primarycustomerid IS NULL THEN
                -- Lazy-seed defaults so Summary never silently fails for older farms.
                PERFORM spwatercustomer_createdefaults(p_farmid := p_farmid);
                SELECT c.watercustomerid INTO v_primarycustomerid
                FROM   watercustomers c
                WHERE  c.farmid = p_farmid AND c.defaultcustomertype = 'GeneralDelivery'
                LIMIT  1;
            END IF;
        END IF;
    ELSIF v_postingmode = 'OneCustomer' THEN
        IF v_primarycustomerid IS NULL THEN
            RAISE EXCEPTION 'OneCustomer posting mode requires PrimaryCustomerId.';
        END IF;
    END IF;

    -- Optional credit-balance target (Summary mode only). Fall back to the
    -- primary customer if no GeneralCredit default exists.
    v_creditcustomerid := v_primarycustomerid;
    IF v_postingmode = 'Summary' AND v_creditsalesamount > 0 THEN
        SELECT c.watercustomerid INTO v_creditcustomerid
        FROM   watercustomers c
        WHERE  c.farmid = p_farmid AND c.defaultcustomertype = 'GeneralCredit'
        LIMIT  1;
        IF v_creditcustomerid IS NULL THEN
            v_creditcustomerid := v_primarycustomerid;
        END IF;
    END IF;

    -- -------- Apply -----------------------------------------------------
    UPDATE waterdriverreturns dr
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc'),
           shortageamount = v_shortage, overageamount = v_overage
    WHERE  dr.waterdriverreturnid = p_waterdriverreturnid AND dr.farmid = p_farmid;

    UPDATE watervehicleloadings l
    SET    status = 'Reconciled', updatedat = (now() at time zone 'utc')
    WHERE  l.watervehicleloadingid = v_loadingid AND l.farmid = p_farmid;

    -- Per-product LoadReturnIn stock movements (returned bags go back to warehouse).
    IF EXISTS (SELECT 1 FROM waterdriverreturnitems ri
               WHERE ri.waterdriverreturnid = p_waterdriverreturnid) THEN
        INSERT INTO waterstocktransactions
            (farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
        SELECT p_farmid, ri.waterproductid, 'LoadReturnIn', ri.bagsreturned, NULL, NULL,
               concat('Driver return #', p_waterdriverreturnid, ' for loading #', v_loadingid),
               p_approvedby
        FROM   waterdriverreturnitems ri
        WHERE  ri.waterdriverreturnid = p_waterdriverreturnid AND ri.bagsreturned > 0;
    ELSIF v_bagsreturned > 0 THEN
        INSERT INTO waterstocktransactions
            (farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
        VALUES (p_farmid, v_productid, 'LoadReturnIn', v_bagsreturned, NULL, NULL,
                concat('Driver return #', p_waterdriverreturnid, ' for loading #', v_loadingid), p_approvedby);
    END IF;

    -- -------- Materialise customer sales --------------------------------
    IF v_postingmode = 'Detailed' THEN
        -- One sale per customer-breakdown row.
        FOR v_cs IN
            SELECT cs.waterdriverreturncustomersaleid AS csid,
                   cs.watercustomerid AS custid, cs.totalamount AS tot,
                   cs.cashpaid AS cash, cs.momopaid AS momo, cs.bankpaid AS bank,
                   cs.creditamount AS credit, cs.notes AS csnotes
            FROM   waterdriverreturncustomersales cs
            WHERE  cs.waterdriverreturnid = p_waterdriverreturnid
        LOOP
            v_paid    := v_cs.cash + v_cs.momo + v_cs.bank;
            v_balance := v_cs.tot - v_paid;
            v_salestatus := CASE WHEN v_balance <= 0 THEN 'Paid'
                                 WHEN v_paid > 0     THEN 'PartiallyPaid'
                                 ELSE 'Pending' END;

            INSERT INTO watersales
                (farmid, watercustomerid, saledate, totalamount, amountpaid, status, notes,
                 createdby, sourcetype, sourceid, waterdriverid, watervehicleid, waterrouteid)
            VALUES
                (p_farmid, v_cs.custid, (now() at time zone 'utc'), v_cs.tot, v_paid, v_salestatus, v_cs.csnotes,
                 p_approvedby, 'DeliveryRun', p_waterdriverreturnid, v_driverid, v_vehicleid, v_routeid)
            RETURNING watersaleid INTO v_saleid;

            INSERT INTO watersaleitems (watersaleid, waterproductid, quantity, unitprice)
            SELECT v_saleid, csi.waterproductid, csi.quantity, csi.unitprice
            FROM   waterdriverreturncustomersaleitems csi
            WHERE  csi.waterdriverreturncustomersaleid = v_cs.csid;

            IF v_cs.cash > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_saleid, v_cs.cash, 'Cash', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_cs.custid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
            IF v_cs.momo > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_saleid, v_cs.momo, 'Mobile Money', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_cs.custid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
            IF v_cs.bank > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_saleid, v_cs.bank, 'Bank', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_cs.custid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;

            UPDATE waterdriverreturncustomersales cs
            SET    generatedwatersaleid = v_saleid, updatedat = (now() at time zone 'utc')
            WHERE  cs.waterdriverreturncustomersaleid = v_cs.csid;
        END LOOP;
    ELSE
        -- Summary / OneCustomer: one virtual sale to v_primarycustomerid, plus
        -- (for Summary with credit) a credit-only sale to v_creditcustomerid
        -- if it's a different customer.
        v_saletotal := v_cashcollected + v_momocollected + v_bankcollected + v_creditsalesamount;
        v_salepaid  := v_cashcollected + v_momocollected + v_bankcollected;
        v_salestatusone := CASE WHEN v_saletotal - v_salepaid <= 0 THEN 'Paid'
                                WHEN v_salepaid > 0               THEN 'PartiallyPaid'
                                ELSE 'Pending' END;

        IF v_postingmode = 'Summary' AND v_creditcustomerid IS NOT NULL
           AND v_creditcustomerid <> v_primarycustomerid AND v_creditsalesamount > 0 THEN
            -- Split: Cash/MoMo/Bank -> primary (paid); Credit -> credit customer (unpaid).
            INSERT INTO watersales
                (farmid, watercustomerid, saledate, totalamount, amountpaid, status, notes,
                 createdby, sourcetype, sourceid, waterdriverid, watervehicleid, waterrouteid)
            VALUES
                (p_farmid, v_primarycustomerid, (now() at time zone 'utc'), v_salepaid, v_salepaid, 'Paid',
                 concat('Summary delivery sale (DR#', p_waterdriverreturnid, ')'),
                 p_approvedby, 'DeliveryRun', p_waterdriverreturnid, v_driverid, v_vehicleid, v_routeid)
            RETURNING watersaleid INTO v_sid1;

            INSERT INTO watersaleitems (watersaleid, waterproductid, quantity, unitprice)
            SELECT v_sid1, ri.waterproductid, ri.bagssold, ri.unitprice
            FROM   waterdriverreturnitems ri
            WHERE  ri.waterdriverreturnid = p_waterdriverreturnid AND ri.bagssold > 0;

            IF v_cashcollected > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_sid1, v_cashcollected, 'Cash', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_primarycustomerid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
            IF v_momocollected > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_sid1, v_momocollected, 'Mobile Money', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_primarycustomerid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
            IF v_bankcollected > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_sid1, v_bankcollected, 'Bank', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_primarycustomerid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;

            -- Credit-only sale to the GeneralCredit customer.
            INSERT INTO watersales
                (farmid, watercustomerid, saledate, totalamount, amountpaid, status, notes,
                 createdby, sourcetype, sourceid, waterdriverid, watervehicleid, waterrouteid)
            VALUES
                (p_farmid, v_creditcustomerid, (now() at time zone 'utc'), v_creditsalesamount, 0, 'Pending',
                 concat('Summary credit sale (DR#', p_waterdriverreturnid, ')'),
                 p_approvedby, 'DeliveryRun', p_waterdriverreturnid, v_driverid, v_vehicleid, v_routeid);

        ELSIF (v_saletotal > 0 AND v_primarycustomerid IS NOT NULL) THEN
            INSERT INTO watersales
                (farmid, watercustomerid, saledate, totalamount, amountpaid, status, notes,
                 createdby, sourcetype, sourceid, waterdriverid, watervehicleid, waterrouteid)
            VALUES
                (p_farmid, v_primarycustomerid, (now() at time zone 'utc'), v_saletotal, v_salepaid, v_salestatusone,
                 concat(CASE WHEN v_postingmode = 'Summary' THEN 'Summary' ELSE 'OneCustomer' END,
                        ' delivery sale (DR#', p_waterdriverreturnid, ')'),
                 p_approvedby, 'DeliveryRun', p_waterdriverreturnid, v_driverid, v_vehicleid, v_routeid)
            RETURNING watersaleid INTO v_sid;

            -- Build line items from the per-product totals on the return.
            IF EXISTS (SELECT 1 FROM waterdriverreturnitems ri
                       WHERE ri.waterdriverreturnid = p_waterdriverreturnid) THEN
                INSERT INTO watersaleitems (watersaleid, waterproductid, quantity, unitprice)
                SELECT v_sid, ri.waterproductid, ri.bagssold, ri.unitprice
                FROM   waterdriverreturnitems ri
                WHERE  ri.waterdriverreturnid = p_waterdriverreturnid AND ri.bagssold > 0;
            ELSIF v_bagssold > 0 THEN
                INSERT INTO watersaleitems (watersaleid, waterproductid, quantity, unitprice)
                VALUES (v_sid, v_productid, v_bagssold, v_expectedpriceperbag);
            END IF;

            IF v_cashcollected > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_sid, v_cashcollected, 'Cash', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_primarycustomerid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
            IF v_momocollected > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_sid, v_momocollected, 'Mobile Money', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_primarycustomerid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
            IF v_bankcollected > 0 THEN
                INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, note, createdby, watercustomerid, sourcetype, sourceid, paymentgroupid)
                VALUES (p_farmid, v_sid, v_bankcollected, 'Bank', (now() at time zone 'utc'), concat('DR#', p_waterdriverreturnid), NULL, p_approvedby, v_primarycustomerid, 'DeliveryRun', p_waterdriverreturnid, gen_random_uuid());
            END IF;
        END IF;
    END IF;

    -- Shortage row (legacy behaviour preserved from 064).
    IF v_shortage > 0 THEN
        INSERT INTO waterdrivershortages
            (farmid, waterdriverid, watervehicleloadingid, waterdriverreturnid,
             shortagedate, expectedamount, actualamount, shortageamount,
             reason, status, notes)
        VALUES
            (p_farmid, v_driverid, v_loadingid, p_waterdriverreturnid,
             (now() at time zone 'utc'), v_expectedcash, v_totalaccounted, v_shortage,
             NULL, 'Pending', NULL);
    END IF;
END;
$function$

;

-- -----------------------------------------------------------------------------
-- 3. Proof: every writer now sets it, and every insert carries it.
--
-- Counted rather than eyeballed -- a function with nine inserts and one
-- mention of paymentgroupid would pass a LIKE test and still be broken.
-- -----------------------------------------------------------------------------
\echo ''
\echo '=== Writers into waterpayments, AFTER ======================================='
SELECT p.proname,
       array_length(string_to_array(lower(p.prosrc), 'insert into waterpayments'), 1) - 1 AS inserts,
       array_length(string_to_array(lower(p.prosrc), 'paymentgroupid'), 1) - 1            AS groupid_mentions,
       CASE WHEN array_length(string_to_array(lower(p.prosrc), 'paymentgroupid'), 1) - 1
                 >= array_length(string_to_array(lower(p.prosrc), 'insert into waterpayments'), 1) - 1
            THEN 'OK' ELSE 'STILL MISSING' END AS verdict
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND lower(p.prosrc) LIKE '%insert into waterpayments%'
ORDER  BY 1;

DO $do$
DECLARE
    v_bad text;
BEGIN
    SELECT string_agg(p.proname, ', ')
    INTO   v_bad
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public'
      AND  lower(p.prosrc) LIKE '%insert into waterpayments%'
      AND  array_length(string_to_array(lower(p.prosrc), 'paymentgroupid'), 1) - 1
           < array_length(string_to_array(lower(p.prosrc), 'insert into waterpayments'), 1) - 1;

    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION '246: these still insert without a group id: %', v_bad;
    END IF;
    RAISE NOTICE 'every waterpayments writer sets paymentgroupid -- OK';
END
$do$;

\echo ''
\echo '--- The trigger from 245 is still there as the backstop ---------------------'
SELECT tgname, tgenabled = 'O' AS enabled
FROM   pg_trigger
WHERE  tgrelid = 'public.waterpayments'::regclass AND NOT tgisinternal
ORDER  BY tgname;

\if :apply
    COMMIT;
    \echo ''
    \echo '>>> COMMITTED. The writers set the group id; the trigger is the backstop.'
\else
    ROLLBACK;
    \echo ''
    \echo '>>> DRY RUN -- rolled back.'
    \echo '>>> Re-run with  -v apply=true  to write it.'
\endif
