-- =============================================================================
-- 314_WaterAssetCostComposition.postgres.sql
--
-- Purpose
-- -------
-- 313 for the water register. Same problem, same shape, same three numbers:
--
--     acquisitioncost      the original acquisition, plus any CORRECTION to it
--     additionalcost       everything capitalised into it afterwards
--     originalcost         unchanged, still the total -- now honestly labelled
--
-- Read 313's header for the reasoning; it is not repeated here. What follows is
-- only what water does DIFFERENTLY, because those differences are the whole
-- risk in porting this file.
--
-- THE MONEY LEG IS NOT THE SAME, AND MUST NOT BE MADE THE SAME
-- ============================================================
-- Poultry corrects cash by calling 238's sppoultryexpensecash_resync, which
-- DELETES the expense's cash transactions and re-posts them from the corrected
-- figure. Water has no such function and should not grow one: 283's own
-- reversal says why in as many words -- "the cash is handed back with an
-- opposite transaction rather than by deleting the original, so the cash ledger
-- stays append-only like every other water ledger."
--
-- So a water correction that reduces what was paid appends a CashIn for the
-- difference and increments the account, exactly as spwatercapitalasset_reverse
-- does. Nothing is deleted, and a reader of watercashtransactions can still see
-- the 130,000 that went out and the 117,000 that came back.
--
-- WHAT A CORRECTION CAN AND CANNOT MOVE
-- =====================================
-- It corrects what the asset COST. It does not decide what was PAID. So the
-- paid figure is only ever capped -- nobody can have paid more than the bill is
-- now for -- and the capping is what releases the cash:
--
--     recorded 130,000, paid 130,000, corrected to 13,000
--         -> paid becomes 13,000, CashIn 117,000, payable 0
--
--     recorded 130,000, paid 20,000 on credit, corrected to 13,000
--         -> paid becomes 13,000, CashIn 7,000, payable 0
--
--     recorded 13,000, paid 13,000, corrected UP to 130,000
--         -> paid stays 13,000, no cash moves, payable becomes 117,000
--
-- The last one is the one worth reading twice: correcting a recorded cost
-- upwards must not invent a payment nobody made.
--
-- THE OTHER THREE DIFFERENCES
-- ===========================
--   * the link column is waterexpenseid, not expenseid;
--   * suppliers are watersuppliers.suppliername, keyed by watersupplierid;
--   * waterexpenses has no category TEXT -- it points at
--     waterexpensecategories -- and it is SOFT-deleted, never deleted.
--
-- EFFECT ON TODAY'S NUMBERS: none. Reads gain columns; no existing row is
-- written and no existing value changes.
--
-- Order: 313 (poultry) first, then 314. Each is independent of the other.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. A correction may be negative. Nothing else may.
-- -----------------------------------------------------------------------------
ALTER TABLE watercapitalassetcosts
    DROP CONSTRAINT IF EXISTS ck_watercapitalassetcosts_amount;

ALTER TABLE watercapitalassetcosts
    ADD CONSTRAINT ck_watercapitalassetcosts_amount
    CHECK (amount <> 0 AND (amount > 0 OR sourcetype = 'OriginalCostCorrection'));

COMMENT ON COLUMN watercapitalassetcosts.sourcetype IS
    'Acquisition (the first cost) | AdditionalCost (capitalised later) | '
    'OriginalCostCorrection (a signed adjustment to the acquisition, 314). '
    'Acquisition + OriginalCostCorrection = the original acquisition cost; '
    'everything else = additional capitalised costs.';

-- -----------------------------------------------------------------------------
-- 2. The partition, defined once. Complementary by construction.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercapitalasset_acquisitioncost(p_assetid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   watercapitalassetcosts c
    WHERE  c.watercapitalassetid = p_assetid
      AND  c.status = 'Posted'
      AND  c.sourcetype IN ('Acquisition', 'OriginalCostCorrection');
$function$;

COMMENT ON FUNCTION public.fnwatercapitalasset_acquisitioncost(integer) IS
    'What the asset was originally acquired for, as corrected. Zero for an asset '
    'that was BUILT cost by cost and never had a single acquisition.';

CREATE OR REPLACE FUNCTION public.fnwatercapitalasset_additionalcost(p_assetid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   watercapitalassetcosts c
    WHERE  c.watercapitalassetid = p_assetid
      AND  c.status = 'Posted'
      AND  c.sourcetype NOT IN ('Acquisition', 'OriginalCostCorrection');
$function$;

COMMENT ON FUNCTION public.fnwatercapitalasset_additionalcost(integer) IS
    'Everything capitalised into the asset after its acquisition.';

COMMENT ON FUNCTION public.fnwatercapitalasset_originalcost(integer) IS
    'TOTAL CAPITALISED COST: acquisition (as corrected) plus every additional '
    'cost. Named originalcost by 283 and kept for compatibility -- see '
    'fnwatercapitalasset_acquisitioncost for the original acquisition alone.';

-- -----------------------------------------------------------------------------
-- 3. Correct the original acquisition cost.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercapitalasset_correctoriginalcost(
    p_farmid        text,
    p_assetid       integer,
    p_newamount     numeric,
    p_effectivedate date    DEFAULT NULL,
    p_reason        text    DEFAULT NULL,
    p_createdby     text    DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status   text;
    v_residual numeric(14,2);
    v_acqcost  numeric(14,2);
    v_addcost  numeric(14,2);
    v_new      numeric(14,2) := ROUND(COALESCE(p_newamount, 0), 2);
    v_diff     numeric(14,2);
    v_costid   integer;
    v_expid    integer;
    v_suppid   integer;
    v_alloc    numeric(14,2);
    v_acct     integer;
    v_paid     numeric(14,2);
    v_newpaid  numeric(14,2);
    v_refund   numeric(14,2);
    v_desc     text;
    v_date     date := COALESCE(p_effectivedate, (now() at time zone 'utc')::date);
    v_newid    integer;
BEGIN
    SELECT a.status, a.residualvalue INTO v_status, v_residual
    FROM   watercapitalassets a
    WHERE  a.watercapitalassetid = p_assetid AND a.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'A reversed asset cannot be corrected.';
    END IF;
    IF v_status = 'Disposed' THEN
        RAISE EXCEPTION 'A disposed asset cannot be corrected.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to correct the original cost.';
    END IF;
    IF v_new <= 0 THEN
        RAISE EXCEPTION 'The corrected original cost must be greater than 0. To undo the acquisition entirely, reverse the asset.';
    END IF;

    v_acqcost := fnwatercapitalasset_acquisitioncost(p_assetid);
    v_addcost := fnwatercapitalasset_additionalcost(p_assetid);
    v_diff    := v_new - v_acqcost;

    IF ABS(v_diff) < 0.005 THEN
        RAISE EXCEPTION 'The original acquisition cost is already %.', v_acqcost;
    END IF;

    SELECT c.watercapitalassetcostid, c.waterexpenseid, c.supplierid
      INTO v_costid, v_expid, v_suppid
    FROM   watercapitalassetcosts c
    WHERE  c.watercapitalassetid = p_assetid AND c.farmid = p_farmid
      AND  c.sourcetype = 'Acquisition' AND c.status = 'Posted'
    ORDER  BY c.watercapitalassetcostid
    LIMIT  1;

    IF v_costid IS NULL THEN
        RAISE EXCEPTION 'This asset has no original acquisition to correct -- its cost was built up with Add cost. Reverse the added cost that is wrong and add it again.';
    END IF;

    -- Book value may never fall below residual value (283), so a correction that
    -- takes the cost under it would leave the asset asserting it is worth more
    -- than it cost.
    IF v_residual > (v_new + v_addcost) THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the corrected cost (%). Lower the residual value first.',
              v_residual, (v_new + v_addcost)::numeric(14,2);
    END IF;

    -- ---- the money leg -----------------------------------------------------
    IF v_expid IS NOT NULL THEN
        SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
        FROM   supplierpaymentallocation sa
        WHERE  lower(sa.farmid) = lower(p_farmid) AND sa.module = 'water'
          AND  sa.status = 'Posted'
          AND  sa.documenttype = 'Expense' AND sa.documentid = v_expid;

        IF COALESCE(v_alloc, 0) > v_new THEN
            RAISE EXCEPTION 'Supplier payments of % have already been recorded against this acquisition, which is more than the corrected cost of %. Reverse the payment on Supplier Payments first.',
                  v_alloc, v_new;
        END IF;

        -- 283's own resolution of "what was actually paid": an explicit
        -- amountpaid, else zero for Credit and the full amount for anything else.
        SELECT e.watercashaccountid,
               COALESCE(e.amountpaid,
                        CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                             THEN 0 ELSE e.amount END),
               e.description
          INTO v_acct, v_paid, v_desc
        FROM   waterexpenses e
        WHERE  e.waterexpenseid = v_expid AND e.farmid = p_farmid;

        IF v_paid IS NOT NULL THEN
            -- Only ever capped. Correcting the cost up must not invent a payment.
            v_newpaid := LEAST(v_paid, v_new);
            v_refund  := ROUND(GREATEST(v_paid - v_newpaid, 0), 2);

            UPDATE waterexpenses e
            SET    amount     = v_new,
                   amountpaid = v_newpaid,
                   updatedat  = (now() at time zone 'utc')
            WHERE  e.waterexpenseid = v_expid AND e.farmid = p_farmid;

            -- Append-only: the money comes back as its own CashIn, it is not
            -- edited out of the transaction that took it.
            IF v_refund > 0 AND v_acct IS NOT NULL THEN
                INSERT INTO watercashtransactions
                    (farmid, watercashaccountid, transactiondate, transactiontype,
                     sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
                VALUES
                    (p_farmid, v_acct, v_date, 'CashIn',
                     'Expense', v_expid, v_refund,
                     'Original cost correction — ' || COALESCE(v_desc, 'capital asset'),
                     p_createdby, p_createdby, (now() at time zone 'utc'));

                UPDATE watercashaccounts a
                SET    currentbalance = a.currentbalance + v_refund,
                       updatedat = (now() at time zone 'utc')
                WHERE  a.watercashaccountid = v_acct AND a.farmid = p_farmid;
            END IF;
        END IF;
    END IF;

    -- ---- the record --------------------------------------------------------
    INSERT INTO watercapitalassetcosts
        (farmid, watercapitalassetid, costdate, description, costcategory,
         amount, sourcetype, waterexpenseid, supplierid, status, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, btrim(p_reason), 'Original Cost Correction',
         v_diff, 'OriginalCostCorrection', v_expid, v_suppid, 'Posted', p_createdby)
    RETURNING watercapitalassetcostid INTO v_newid;

    UPDATE watercapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() at time zone 'utc')
    WHERE  a.watercapitalassetid = p_assetid AND a.farmid = p_farmid;

    -- 284's generator refreshes this at the end of every run. Doing it here too
    -- means an asset a correction has just finished depreciating says so now.
    UPDATE watercapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM  (SELECT x.watercapitalassetid AS id,
                  CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
           FROM   watercapitalassets x
           CROSS  JOIN LATERAL fnwatercapitalasset_financials(x.watercapitalassetid) f
           WHERE  x.watercapitalassetid = p_assetid AND x.farmid = p_farmid
             AND  x.status IN ('Active', 'FullyDepreciated')) s
    WHERE  ca.watercapitalassetid = s.id AND ca.status <> s.newstatus;

    RETURN v_newid;
END;
$function$;

COMMENT ON FUNCTION public.spwatercapitalasset_correctoriginalcost(text, integer, numeric, date, text, text) IS
    'Corrects a data-entry mistake in the original acquisition cost. Writes a '
    'signed OriginalCostCorrection row, amends the acquisition expense (never a '
    'second one) and hands back any over-paid cash as its own CashIn. Posted '
    'depreciation is left exactly as posted; future charges follow the corrected '
    'cost automatically.';

-- -----------------------------------------------------------------------------
-- 4. Reverse ONE capitalised cost.
--
-- The unwind is 283's own, lifted out of the loop inside
-- spwatercapitalasset_reverse so the two cannot drift.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercapitalassetcost_reverse(
    p_farmid    text,
    p_costid    integer,
    p_reason    text,
    p_createdby text    DEFAULT NULL,
    -- The asset the caller believes this cost belongs to. Optional so the SP can
    -- be used on its own, but the API always passes it: the cost id arrives from
    -- a URL, and a URL that says asset 7 must not be able to reverse asset 9's
    -- cost merely because both belong to the same company.
    p_assetid   integer DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_assetid integer;
    v_source  text;
    v_status  text;
    v_expid   integer;
    v_astatus text;
    v_acct    integer;
    v_paid    numeric(14,2);
    v_desc    text;
BEGIN
    SELECT c.watercapitalassetid, c.sourcetype, c.status, c.waterexpenseid
      INTO v_assetid, v_source, v_status, v_expid
    FROM   watercapitalassetcosts c
    WHERE  c.watercapitalassetcostid = p_costid AND c.farmid = p_farmid;

    IF v_assetid IS NULL THEN
        RAISE EXCEPTION 'Cost entry not found for this company.';
    END IF;
    IF p_assetid IS NOT NULL AND p_assetid <> v_assetid THEN
        RAISE EXCEPTION 'That cost entry does not belong to this asset.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cost.';
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'This cost has already been reversed.';
    END IF;
    IF v_source = 'Acquisition' THEN
        RAISE EXCEPTION 'This is the original acquisition. Use Correct original cost to change the amount, or reverse the whole asset.';
    END IF;
    IF v_source = 'OriginalCostCorrection' THEN
        RAISE EXCEPTION 'A correction cannot be reversed. Correct the original cost again to the amount you want.';
    END IF;

    SELECT a.status INTO v_astatus
    FROM   watercapitalassets a
    WHERE  a.watercapitalassetid = v_assetid AND a.farmid = p_farmid;
    IF v_astatus IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot change the costs of a % asset.', lower(v_astatus);
    END IF;

    IF EXISTS (SELECT 1 FROM waterassetdepreciation d
               WHERE d.watercapitalassetid = v_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this asset. Reverse it before changing the asset cost.';
    END IF;

    IF v_expid IS NOT NULL
       AND EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                   WHERE sa.documenttype = 'Expense' AND sa.documentid = v_expid
                     AND lower(sa.farmid) = lower(p_farmid) AND sa.module = 'water'
                     AND sa.status = 'Posted') THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this cost. Reverse the payment on Supplier Payments first.';
    END IF;

    IF v_expid IS NOT NULL THEN
        SELECT e.watercashaccountid,
               COALESCE(e.amountpaid,
                        CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                             THEN 0 ELSE e.amount END),
               e.description
          INTO v_acct, v_paid, v_desc
        FROM   waterexpenses e
        WHERE  e.waterexpenseid = v_expid AND e.farmid = p_farmid;

        IF COALESCE(v_paid, 0) > 0 AND v_acct IS NOT NULL THEN
            INSERT INTO watercashtransactions
                (farmid, watercashaccountid, transactiondate, transactiontype,
                 sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
            VALUES
                (p_farmid, v_acct, (now() at time zone 'utc'), 'CashIn',
                 'Expense', v_expid, v_paid,
                 'Reversal of capital asset cost — ' || COALESCE(v_desc, ''),
                 p_createdby, p_createdby, (now() at time zone 'utc'));

            UPDATE watercashaccounts a
            SET    currentbalance = a.currentbalance + v_paid,
                   updatedat = (now() at time zone 'utc')
            WHERE  a.watercashaccountid = v_acct AND a.farmid = p_farmid;
        END IF;

        -- Soft delete, and zero the paid amount so no reader can treat the row
        -- as a settled bill on its way out.
        UPDATE waterexpenses e
        SET    isdeleted  = TRUE,
               amountpaid = 0,
               updatedat  = (now() at time zone 'utc')
        WHERE  e.waterexpenseid = v_expid AND e.farmid = p_farmid;
    END IF;

    UPDATE watercapitalassetcosts c
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = btrim(p_reason)
    WHERE  c.watercapitalassetcostid = p_costid AND c.farmid = p_farmid;

    UPDATE watercapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() at time zone 'utc')
    WHERE  a.watercapitalassetid = v_assetid AND a.farmid = p_farmid;
END;
$function$;

COMMENT ON FUNCTION public.spwatercapitalassetcost_reverse(text, integer, text, text, integer) IS
    'Reverses ONE additional capitalised cost. The row is kept and marked '
    'Reversed -- never deleted -- and its cash and payable are unwound through '
    'the same append-only path spwatercapitalasset_reverse uses.';

-- -----------------------------------------------------------------------------
-- 5. Reads. Both gain columns, so both are dropped BY NAME and rebuilt.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure::text AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('spwatercapitalasset_getall', 'spwatercapitalassetcost_getall')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
        RAISE NOTICE '314: dropped %', r.sig;
    END LOOP;
END
$drop$;

CREATE OR REPLACE FUNCTION public.spwatercapitalasset_getall(
    p_farmid text, p_status text DEFAULT NULL, p_categoryid integer DEFAULT NULL
) RETURNS TABLE(watercapitalassetid integer, farmid text, assetnumber text, assetname text,
                waterassetcategoryid integer, categoryname text, description text,
                acquisitiondate date, inservicedate date, location text, serialnumber text,
                supplierid integer, suppliername text, status text, notes text,
                originalcost numeric, residualvalue numeric, depreciableamount numeric,
                usefullifemonths integer, monthlydepreciation numeric,
                accumulateddepreciation numeric, currentbookvalue numeric,
                remainingdepreciable numeric, isfullydepreciated boolean,
                costentries integer, depreciationentries integer,
                disposaldate date, disposalproceeds numeric,
                createdby text, createdat timestamp without time zone,
                updatedat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text,
                acquisitioncost numeric, additionalcost numeric, totalcapitalizedcost numeric)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT a.watercapitalassetid, a.farmid::text, a.assetnumber::text, a.assetname::text,
           a.waterassetcategoryid, c.categoryname::text, a.description::text,
           a.acquisitiondate, a.inservicedate, a.location::text, a.serialnumber::text,
           a.supplierid, s.suppliername::text, a.status::text, a.notes::text,
           f.originalcost, f.residualvalue, f.depreciableamount,
           f.usefullifemonths, f.monthlydepreciation,
           f.accumulateddepreciation, f.currentbookvalue,
           f.remainingdepreciable, f.isfullydepreciated,
           (SELECT COUNT(*)::integer FROM watercapitalassetcosts cc
             WHERE cc.watercapitalassetid = a.watercapitalassetid AND cc.status = 'Posted'),
           (SELECT COUNT(*)::integer FROM waterassetdepreciation dd
             WHERE dd.watercapitalassetid = a.watercapitalassetid AND dd.status = 'Posted'),
           a.disposaldate, a.disposalproceeds,
           a.createdby::text, a.createdat, a.updatedat,
           a.reversedby::text, a.reversedat, a.reversalreason::text,
           -- 314.
           fnwatercapitalasset_acquisitioncost(a.watercapitalassetid),
           fnwatercapitalasset_additionalcost(a.watercapitalassetid),
           f.originalcost
    FROM   watercapitalassets a
    LEFT   JOIN waterassetcategories c ON c.waterassetcategoryid = a.waterassetcategoryid
    LEFT   JOIN watersuppliers s ON s.watersupplierid = a.supplierid
    CROSS  JOIN LATERAL fnwatercapitalasset_financials(a.watercapitalassetid) f
    WHERE  a.farmid = p_farmid
      AND  (p_status IS NULL OR a.status = p_status)
      AND  (p_categoryid IS NULL OR a.waterassetcategoryid = p_categoryid)
    ORDER  BY a.acquisitiondate DESC, a.watercapitalassetid DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwatercapitalassetcost_getall(
    p_farmid text, p_assetid integer
) RETURNS TABLE(watercapitalassetcostid integer, watercapitalassetid integer,
                costdate date, description text, costcategory text, amount numeric,
                sourcetype text, waterexpenseid integer, supplierid integer, suppliername text,
                paymentstatus text, amountpaid numeric, balance numeric,
                status text, createdby text, createdat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text,
                paymentmethod text, duedate date, cashaccountname text,
                expenseamount numeric, expensecategory text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT c.watercapitalassetcostid, c.watercapitalassetid,
           c.costdate, c.description::text, c.costcategory::text, c.amount,
           c.sourcetype::text, c.waterexpenseid, c.supplierid, s.suppliername::text,
           e.paymentstatus::text,
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0)
                    - COALESCE(e.amountpaid,
                               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                    THEN 0 ELSE e.amount END), 0)::numeric(14,2),
           c.status::text, c.createdby::text, c.createdat,
           c.reversedby::text, c.reversedat, c.reversalreason::text,
           -- 314.
           e.paymentmethod::text, e.duedate::date, ca.accountname::text,
           e.amount::numeric(14,2), ec.name::text
    FROM   watercapitalassetcosts c
    LEFT   JOIN waterexpenses e ON e.waterexpenseid = c.waterexpenseid
    LEFT   JOIN watersuppliers s ON s.watersupplierid = c.supplierid
    LEFT   JOIN watercashaccounts ca ON ca.watercashaccountid = e.watercashaccountid
    LEFT   JOIN waterexpensecategories ec ON ec.waterexpensecategoryid = e.waterexpensecategoryid
    WHERE  c.farmid = p_farmid AND c.watercapitalassetid = p_assetid
    ORDER  BY c.costdate, c.watercapitalassetcostid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'acquisition + additional = total, every asset' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'BROKEN on ' || COUNT(*) || ' asset(s)' END AS result
FROM   watercapitalassets a
WHERE  ROUND(fnwatercapitalasset_acquisitioncost(a.watercapitalassetid)
           + fnwatercapitalasset_additionalcost(a.watercapitalassetid), 2)
    <> ROUND(fnwatercapitalasset_originalcost(a.watercapitalassetid), 2)

UNION ALL
SELECT 'no correction written by the migration',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WROTE ' || COUNT(*) END
FROM   watercapitalassetcosts c
WHERE  c.sourcetype = 'OriginalCostCorrection'

UNION ALL
SELECT 'the four new routines exist (4 expected)',
       CASE WHEN COUNT(*) = 4 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnwatercapitalasset_acquisitioncost',
                     'fnwatercapitalasset_additionalcost',
                     'spwatercapitalasset_correctoriginalcost',
                     'spwatercapitalassetcost_reverse');
