-- =============================================================================
-- 313_PoultryAssetCostComposition.postgres.sql
--
-- Purpose
-- -------
-- Make the number on the Capital Investments row EXPLAINABLE.
--
-- THE ONE CONFUSION THIS FILE EXISTS TO REMOVE
-- ============================================
-- 270 decided, correctly, that an asset's cost is the SUM of its cost rows
-- rather than a column somebody keeps in step by hand. It named that sum
-- `originalcost`, and every screen since has printed it under the label
-- "Original cost".
--
-- It is not the original cost. It is the TOTAL CAPITALISED cost.
--
--     bought the cages                      100,000
--     installed them later                   20,000
--     added a section                        10,000
--                                          --------
--     originalcost (as 270 named it)        130,000
--
-- An owner reading "Original cost 130,000" concludes the cages were bought for
-- 130,000, and there is nowhere on the screen that says otherwise. Worse, the
-- only offered way to change it is "Add cost", so somebody who typed 130,000
-- when the invoice said 13,000 has no way to fix it that is not a lie.
--
-- So this file splits one number into three, using the data 270 already stores:
--
--     acquisitioncost      the original acquisition, plus any CORRECTION to it
--     additionalcost       everything capitalised into it afterwards
--     originalcost         unchanged, still the total -- now honestly labelled
--
-- The split is a PARTITION of the same posted rows, so
-- acquisitioncost + additionalcost = originalcost holds by construction and
-- cannot drift. No number that exists today changes value.
--
-- WHY A CORRECTION IS A COST ROW AND NOT A COLUMN EDIT
-- ===================================================
-- Because "the invoice was 13,000, not 130,000" is a financial event with a
-- date, an author and a reason, and it changes cash, the supplier balance and
-- every future month's depreciation. Overwriting a number leaves none of that.
--
-- A correction is therefore an ordinary row in poultrycapitalassetcosts with
-- sourcetype 'OriginalCostCorrection' and a SIGNED amount -- the same append-only
-- shape the depreciation ledger already uses, for the same reason: the history
-- stays readable and the total stays a SUM.
--
--     09/10  Original acquisition            130,000
--     09/17  Original cost correction       -117,000   "invoice misread"
--                                          ---------
--            Original acquisition cost        13,000
--
-- WHAT THE CORRECTION DOES TO THE MONEY, AND WHY IT IS NOT A NEW TRANSACTION
-- =========================================================================
-- Nothing is posted twice. The acquisition's EXISTING expense row is amended --
-- the same row that moved the cash and opened the payable -- and 238's
-- sppoultryexpensecash_resync is asked to redo the cash leg from it. Resync
-- reverses what it posted and re-posts the corrected figure, so an overstated
-- 130,000 cash-out becomes a 13,000 cash-out and the account is handed back the
-- 117,000 that never actually left it.
--
-- Creating a second expense for the difference would have been easier and would
-- have been wrong: Supplier Balances would show two documents for one purchase,
-- and the P&L exclusion would have to be reasoned about twice.
--
-- WHAT IT DOES TO DEPRECIATION: NOTHING, BACKWARDS
-- ================================================
-- Every month already posted stays exactly as posted. Nothing is deleted and
-- nothing is rewritten -- an owner who reads September's profit today must read
-- the same figure next year.
--
-- Forwards it needs no code at all, and that is the point of 270's design.
-- fnpoultrycapitalasset_monthly reads the CURRENT cost, so the next month
-- charged is already the corrected month; and `remainingdepreciable` bounds the
-- generator, so an asset whose cost fell below what has already been charged
-- simply has nothing more due. The only thing this file adds is the status
-- refresh 271's generator does at the end of its run, applied immediately so the
-- register does not claim an asset is still depreciating when it is not.
--
-- REVERSING ONE ADDED COST
-- ========================
-- 270 can reverse a whole acquisition and refuses once anything depends on it.
-- It cannot reverse ONE cost, so a mistyped 20,000 installation could only be
-- undone by reversing the entire asset. sppoultrycapitalassetcost_reverse fills
-- that gap with the identical unwind 270's own reversal loop performs, under the
-- identical guards.
--
-- WHAT THIS FILE IS NOT
-- =====================
-- It does not change how depreciation is calculated, generated, posted or
-- reversed. It does not touch the expense rail, the P&L, Cash Flow, Financial
-- Activity or supplier balances -- it USES them. It adds no table, because the
-- cost ledger 270 built is already the right place for every one of these facts.
--
-- EFFECT ON TODAY'S NUMBERS: none. Reads gain columns; no existing row is
-- written and no existing value changes.
--
-- Order: 313 (poultry), then 314 (water). Each is independent of the other.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. A correction may be negative. Nothing else may.
--
-- 270's CHECK (amount > 0) is exactly right for a cost: capitalising minus
-- 5,000 of cement is not a thing. A correction is not a cost, it is an
-- adjustment TO one, so it is the single sourcetype allowed to carry a negative
-- amount -- and zero stays forbidden for every row, because a correction that
-- changes nothing is a mistake, not a record.
-- -----------------------------------------------------------------------------
ALTER TABLE poultrycapitalassetcosts
    DROP CONSTRAINT IF EXISTS ck_poultrycapitalassetcosts_amount;

ALTER TABLE poultrycapitalassetcosts
    ADD CONSTRAINT ck_poultrycapitalassetcosts_amount
    CHECK (amount <> 0 AND (amount > 0 OR sourcetype = 'OriginalCostCorrection'));

COMMENT ON COLUMN poultrycapitalassetcosts.sourcetype IS
    'Acquisition (the first cost) | AdditionalCost (capitalised later) | '
    'OriginalCostCorrection (a signed adjustment to the acquisition, 313). '
    'Acquisition + OriginalCostCorrection = the original acquisition cost; '
    'everything else = additional capitalised costs.';

-- -----------------------------------------------------------------------------
-- 2. The partition, defined once.
--
-- Complementary by construction: one function takes the acquisition family, the
-- other takes its complement, so no sourcetype can ever be counted twice or
-- dropped, whatever vocabulary a later migration adds.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycapitalasset_acquisitioncost(p_assetid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   poultrycapitalassetcosts c
    WHERE  c.poultrycapitalassetid = p_assetid
      AND  c.status = 'Posted'
      AND  c.sourcetype IN ('Acquisition', 'OriginalCostCorrection');
$function$;

COMMENT ON FUNCTION public.fnpoultrycapitalasset_acquisitioncost(integer) IS
    'What the investment was originally acquired for, as corrected. Zero for an '
    'asset that was BUILT cost by cost and never had a single acquisition.';

CREATE OR REPLACE FUNCTION public.fnpoultrycapitalasset_additionalcost(p_assetid integer)
RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(SUM(c.amount), 0)::numeric(14,2)
    FROM   poultrycapitalassetcosts c
    WHERE  c.poultrycapitalassetid = p_assetid
      AND  c.status = 'Posted'
      AND  c.sourcetype NOT IN ('Acquisition', 'OriginalCostCorrection');
$function$;

COMMENT ON FUNCTION public.fnpoultrycapitalasset_additionalcost(integer) IS
    'Everything capitalised into the investment after its acquisition.';

-- The existing function is not touched -- it is still the total, and half the
-- register reads it -- but it is no longer allowed to go on being called
-- "original cost" without a note saying what it actually is.
COMMENT ON FUNCTION public.fnpoultrycapitalasset_originalcost(integer) IS
    'TOTAL CAPITALISED COST: acquisition (as corrected) plus every additional '
    'cost. Named originalcost by 270 and kept for compatibility -- see '
    'fnpoultrycapitalasset_acquisitioncost for the original acquisition alone.';

-- -----------------------------------------------------------------------------
-- 3. Correct the original acquisition cost.
--
-- Deliberately NOT "make originalcost editable". The difference is the whole
-- point of the workflow: this writes a dated, authored, reasoned row and mends
-- the money leg behind it, where an editable box would silently replace a number
-- that cash, a supplier balance and a depreciation schedule all depend on.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_correctoriginalcost(
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
    v_uuid     uuid;
    v_acqcost  numeric(14,2);
    v_addcost  numeric(14,2);
    v_new      numeric(14,2) := ROUND(COALESCE(p_newamount, 0), 2);
    v_diff     numeric(14,2);
    v_costid   integer;
    v_expid    integer;
    v_suppid   integer;
    v_alloc    numeric(14,2);
    v_paid     numeric(14,2);
    v_amount   numeric(14,2);
    v_date     date := COALESCE(p_effectivedate, (now() at time zone 'utc')::date);
    v_newid    integer;
BEGIN
    SELECT a.status, a.residualvalue INTO v_status, v_residual
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'A reversed investment cannot be corrected.';
    END IF;
    IF v_status = 'Disposed' THEN
        RAISE EXCEPTION 'A disposed investment cannot be corrected.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to correct the original cost.';
    END IF;
    IF v_new <= 0 THEN
        RAISE EXCEPTION 'The corrected original cost must be greater than 0. To undo the acquisition entirely, reverse the investment.';
    END IF;

    v_uuid    := p_farmid::uuid;
    v_acqcost := fnpoultrycapitalasset_acquisitioncost(p_assetid);
    v_addcost := fnpoultrycapitalasset_additionalcost(p_assetid);
    v_diff    := v_new - v_acqcost;

    IF ABS(v_diff) < 0.005 THEN
        RAISE EXCEPTION 'The original acquisition cost is already %.', v_acqcost;
    END IF;

    -- The acquisition row is what is being corrected. Without one there is
    -- nothing here to correct -- the asset was built up out of added costs, and
    -- the row to fix is one of those.
    SELECT c.poultrycapitalassetcostid, c.expenseid, c.supplierid
      INTO v_costid, v_expid, v_suppid
    FROM   poultrycapitalassetcosts c
    WHERE  c.poultrycapitalassetid = p_assetid AND c.farmid = p_farmid
      AND  c.sourcetype = 'Acquisition' AND c.status = 'Posted'
    ORDER  BY c.poultrycapitalassetcostid
    LIMIT  1;

    IF v_costid IS NULL THEN
        RAISE EXCEPTION 'This investment has no original acquisition to correct -- its cost was built up with Add cost. Reverse the added cost that is wrong and add it again.';
    END IF;

    -- Book value may never fall below residual value (270 §20), so a correction
    -- that takes the cost under it would leave the asset asserting it is worth
    -- more than it cost.
    IF v_residual > (v_new + v_addcost) THEN
        RAISE EXCEPTION 'Residual value (%) cannot be more than the corrected cost (%). Lower the residual value first.',
              v_residual, (v_new + v_addcost)::numeric(14,2);
    END IF;

    -- ---- the money leg -----------------------------------------------------
    IF v_expid IS NOT NULL THEN
        SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
        FROM   supplierpaymentallocation sa
        -- lower() on both sides, matching 270's own reversal guard: a case
        -- mismatch here would find no allocations and silently SKIP a financial
        -- guard, which is the worst way for this to fail.
        WHERE  lower(sa.farmid) = lower(p_farmid) AND sa.module = 'poultry'
          AND  sa.status = 'Posted'
          AND  sa.documenttype = 'Expense' AND sa.documentid = v_expid;

        -- Settled money cannot be corrected away from underneath a payment that
        -- exists in the supplier ledger. Reversing that payment is a separate,
        -- visible act and it is the right one.
        IF COALESCE(v_alloc, 0) > v_new THEN
            RAISE EXCEPTION 'Supplier payments of % have already been recorded against this acquisition, which is more than the corrected cost of %. Reverse the payment on Supplier Payments first.',
                  v_alloc, v_new;
        END IF;

        SELECT COALESCE(e.amountpaid, e.amount), e.amount INTO v_paid, v_amount
        FROM   expense e
        WHERE  e.expenseid = v_expid AND e.farmid = v_uuid;

        IF v_amount IS NOT NULL THEN
            -- Nobody can have paid more than the bill is now for. LEAST caps it;
            -- the difference is cash the resync below hands back.
            UPDATE expense e
            SET    amount     = v_new,
                   amountpaid = LEAST(COALESCE(v_paid, v_amount), v_new)
            WHERE  e.expenseid = v_expid AND e.farmid = v_uuid;

            -- 238. Reverses the cash this expense posted and re-posts it from the
            -- corrected figure, net of anything a supplier payment already took.
            PERFORM sppoultryexpensecash_resync(p_farmid, v_expid, p_createdby);
        END IF;
    END IF;

    -- ---- the record --------------------------------------------------------
    -- Signed, so the cost history reads as a statement and the total stays a SUM.
    -- It carries the acquisition's own expense id: the correction did not create
    -- a document, it amended one, and this is the link back to it.
    INSERT INTO poultrycapitalassetcosts
        (farmid, poultrycapitalassetid, costdate, description, costcategory,
         amount, sourcetype, expenseid, supplierid, status, createdby)
    VALUES
        (p_farmid, p_assetid, v_date, btrim(p_reason), 'Original Cost Correction',
         v_diff, 'OriginalCostCorrection', v_expid, v_suppid, 'Posted', p_createdby)
    RETURNING poultrycapitalassetcostid INTO v_newid;

    UPDATE poultrycapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;

    -- 271's generator refreshes this at the end of every run. Doing it here too
    -- means an asset that a correction has just finished depreciating says so
    -- immediately, rather than at the next Generate.
    UPDATE poultrycapitalassets ca
    SET    status = s.newstatus, updatedat = (now() at time zone 'utc')
    FROM  (SELECT x.poultrycapitalassetid AS id,
                  CASE WHEN f.isfullydepreciated THEN 'FullyDepreciated' ELSE 'Active' END AS newstatus
           FROM   poultrycapitalassets x
           CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(x.poultrycapitalassetid) f
           WHERE  x.poultrycapitalassetid = p_assetid AND x.farmid = p_farmid
             AND  x.status IN ('Active', 'FullyDepreciated')) s
    WHERE  ca.poultrycapitalassetid = s.id AND ca.status <> s.newstatus;

    RETURN v_newid;
END;
$function$;

COMMENT ON FUNCTION public.sppoultrycapitalasset_correctoriginalcost(text, integer, numeric, date, text, text) IS
    'Corrects a data-entry mistake in the original acquisition cost. Writes a '
    'signed OriginalCostCorrection row, amends the acquisition expense (never a '
    'second one) and resyncs its cash. Posted depreciation is left exactly as '
    'posted; future charges follow the corrected cost automatically.';

-- -----------------------------------------------------------------------------
-- 4. Reverse ONE capitalised cost.
--
-- The unwind is 270's own, lifted from the loop inside
-- sppoultrycapitalasset_reverse so the two cannot drift: zero what was paid,
-- resync (which hands the cash back and closes the payable), drop the expense,
-- keep the cost row and mark it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalassetcost_reverse(
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
    v_uuid    uuid := p_farmid::uuid;
BEGIN
    SELECT c.poultrycapitalassetid, c.sourcetype, c.status, c.expenseid
      INTO v_assetid, v_source, v_status, v_expid
    FROM   poultrycapitalassetcosts c
    WHERE  c.poultrycapitalassetcostid = p_costid AND c.farmid = p_farmid;

    IF v_assetid IS NULL THEN
        RAISE EXCEPTION 'Cost entry not found for this company.';
    END IF;
    IF p_assetid IS NOT NULL AND p_assetid <> v_assetid THEN
        RAISE EXCEPTION 'That cost entry does not belong to this investment.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a cost.';
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'This cost has already been reversed.';
    END IF;

    -- The acquisition is not an "additional cost" and undoing it is not this
    -- operation: correcting it keeps the asset, reversing it removes the asset.
    IF v_source = 'Acquisition' THEN
        RAISE EXCEPTION 'This is the original acquisition. Use Correct original cost to change the amount, or reverse the whole investment.';
    END IF;
    IF v_source = 'OriginalCostCorrection' THEN
        RAISE EXCEPTION 'A correction cannot be reversed. Correct the original cost again to the amount you want.';
    END IF;

    SELECT a.status INTO v_astatus
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = v_assetid AND a.farmid = p_farmid;
    IF v_astatus IN ('Reversed', 'Disposed') THEN
        RAISE EXCEPTION 'Cannot change the costs of a % investment.', lower(v_astatus);
    END IF;

    -- Same refusal sppoultrycapitalassetcost_add makes, for the same reason:
    -- removing cost under months that are already charged would make every one
    -- of them wrong.
    IF EXISTS (SELECT 1 FROM poultryassetdepreciation d
               WHERE d.poultrycapitalassetid = v_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has already been posted for this investment. Reverse it before changing the investment cost.';
    END IF;

    IF v_expid IS NOT NULL
       AND EXISTS (SELECT 1 FROM supplierpaymentallocation sa
                   WHERE sa.documenttype = 'Expense' AND sa.documentid = v_expid
                     AND lower(sa.farmid) = lower(p_farmid) AND sa.module = 'poultry'
                     AND sa.status = 'Posted') THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this cost. Reverse the payment on Supplier Payments first.';
    END IF;

    IF v_expid IS NOT NULL THEN
        UPDATE expense e SET amountpaid = 0
        WHERE  e.expenseid = v_expid AND e.farmid = v_uuid;
        PERFORM sppoultryexpensecash_resync(p_farmid, v_expid, p_createdby);
        DELETE FROM expense e WHERE e.expenseid = v_expid AND e.farmid = v_uuid;
    END IF;

    UPDATE poultrycapitalassetcosts c
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = btrim(p_reason)
    WHERE  c.poultrycapitalassetcostid = p_costid AND c.farmid = p_farmid;

    UPDATE poultrycapitalassets a
    SET    updatedby = p_createdby, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycapitalassetid = v_assetid AND a.farmid = p_farmid;
END;
$function$;

COMMENT ON FUNCTION public.sppoultrycapitalassetcost_reverse(text, integer, text, text, integer) IS
    'Reverses ONE additional capitalised cost. The row is kept and marked '
    'Reversed -- never deleted -- and its cash and payable are unwound through '
    'the same path sppoultrycapitalasset_reverse uses.';

-- -----------------------------------------------------------------------------
-- 5. 270's whole-asset reversal, made safe against a shared expense.
--
-- A correction row carries the acquisition's expense id, so the loop below can
-- now meet the same expense twice. Only the first visit has anything to undo and
-- the second would be harmless -- but "harmless because the row is already gone"
-- is the kind of reasoning that stops being true. DISTINCT makes it explicit.
--
-- Nothing else about the function changes.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_reverse(
    p_farmid    text,
    p_assetid   integer,
    p_reason    text,
    p_createdby text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_uuid   uuid := p_farmid::uuid;
    r        record;
BEGIN
    SELECT a.status INTO v_status
    FROM   poultrycapitalassets a
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Asset not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'This asset has already been reversed.';
    END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse an asset.';
    END IF;
    IF v_status = 'Disposed' THEN
        RAISE EXCEPTION 'A disposed asset cannot be reversed.';
    END IF;

    IF EXISTS (SELECT 1 FROM poultryassetdepreciation d
               WHERE d.poultrycapitalassetid = p_assetid AND d.status = 'Posted') THEN
        RAISE EXCEPTION 'Depreciation has been posted for this asset. Reverse the depreciation first.';
    END IF;

    IF EXISTS (SELECT 1
               FROM   poultrycapitalassetcosts c
               JOIN   supplierpaymentallocation sa
                 ON   sa.documenttype = 'Expense' AND sa.documentid = c.expenseid
                AND   lower(sa.farmid) = lower(p_farmid) AND sa.module = 'poultry'
                AND   sa.status = 'Posted'
               WHERE  c.poultrycapitalassetid = p_assetid AND c.status = 'Posted') THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this asset. Reverse the payment on Supplier Payments first.';
    END IF;

    -- Unwind each cost's money leg, then remove it. Zeroing amountpaid before
    -- the resync is what hands the cash back: resync reverses whatever it posted
    -- and re-posts nothing.
    FOR r IN SELECT DISTINCT c.expenseid
             FROM   poultrycapitalassetcosts c
             WHERE  c.poultrycapitalassetid = p_assetid AND c.status = 'Posted'
               AND  c.expenseid IS NOT NULL
    LOOP
        UPDATE expense e SET amountpaid = 0
        WHERE  e.expenseid = r.expenseid AND e.farmid = v_uuid;
        PERFORM sppoultryexpensecash_resync(p_farmid, r.expenseid, p_createdby);
        DELETE FROM expense e WHERE e.expenseid = r.expenseid AND e.farmid = v_uuid;
    END LOOP;

    UPDATE poultrycapitalassetcosts c
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason
    WHERE  c.poultrycapitalassetid = p_assetid AND c.status = 'Posted';

    UPDATE poultrycapitalassets a
    SET    status = 'Reversed', reversedby = p_createdby,
           reversedat = (now() at time zone 'utc'), reversalreason = p_reason,
           updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycapitalassetid = p_assetid AND a.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Reads.
--
-- Both gain columns, so both are dropped BY NAME and rebuilt: a RETURNS TABLE
-- cannot be widened by CREATE OR REPLACE, and dropping by a guessed signature
-- drops nothing and leaves an ambiguous overload behind it.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure::text AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('sppoultrycapitalasset_getall', 'sppoultrycapitalassetcost_getall')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
        RAISE NOTICE '313: dropped %', r.sig;
    END LOOP;
END
$drop$;

-- The register. Three new columns at the END, so no existing ordinal moves and
-- the C# readers -- which map by NAME -- pick them up without being reordered.
--
-- totalcapitalizedcost is deliberately the same number as originalcost. The
-- duplication is the point: `originalcost` keeps every caller written against
-- 270 working, and `totalcapitalizedcost` is what the screens are allowed to
-- print, so no label can ever again call the total an original cost.
CREATE OR REPLACE FUNCTION public.sppoultrycapitalasset_getall(
    p_farmid text, p_status text DEFAULT NULL, p_categoryid integer DEFAULT NULL
) RETURNS TABLE(poultrycapitalassetid integer, farmid text, assetnumber text, assetname text,
                poultryassetcategoryid integer, categoryname text, description text,
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
    SELECT a.poultrycapitalassetid, a.farmid::text, a.assetnumber::text, a.assetname::text,
           a.poultryassetcategoryid, c.categoryname::text, a.description::text,
           a.acquisitiondate, a.inservicedate, a.location::text, a.serialnumber::text,
           a.supplierid, s.name::text, a.status::text, a.notes::text,
           f.originalcost, f.residualvalue, f.depreciableamount,
           f.usefullifemonths, f.monthlydepreciation,
           f.accumulateddepreciation, f.currentbookvalue,
           f.remainingdepreciable, f.isfullydepreciated,
           (SELECT COUNT(*)::integer FROM poultrycapitalassetcosts cc
             WHERE cc.poultrycapitalassetid = a.poultrycapitalassetid AND cc.status = 'Posted'),
           (SELECT COUNT(*)::integer FROM poultryassetdepreciation dd
             WHERE dd.poultrycapitalassetid = a.poultrycapitalassetid AND dd.status = 'Posted'),
           a.disposaldate, a.disposalproceeds,
           a.createdby::text, a.createdat, a.updatedat,
           a.reversedby::text, a.reversedat, a.reversalreason::text,
           -- 313.
           fnpoultrycapitalasset_acquisitioncost(a.poultrycapitalassetid),
           fnpoultrycapitalasset_additionalcost(a.poultrycapitalassetid),
           f.originalcost
    FROM   poultrycapitalassets a
    LEFT   JOIN poultryassetcategories c ON c.poultryassetcategoryid = a.poultryassetcategoryid
    LEFT   JOIN supplier s ON s.supplierid = a.supplierid
    CROSS  JOIN LATERAL fnpoultrycapitalasset_financials(a.poultrycapitalassetid) f
    WHERE  a.farmid = p_farmid
      AND  (p_status IS NULL OR a.status = p_status)
      AND  (p_categoryid IS NULL OR a.poultryassetcategoryid = p_categoryid)
    ORDER  BY a.acquisitiondate DESC, a.poultrycapitalassetid DESC;
END;
$function$;

-- The cost history. Gains what "where did this money go?" actually needs and
-- 270 already stored on the expense behind each row: how it was paid, when the
-- balance falls due, and which cash account it came out of.
--
-- ORDER is by date then id, so the acquisition -- the first cost there can be --
-- leads the list and its correction follows on the day it was made.
CREATE OR REPLACE FUNCTION public.sppoultrycapitalassetcost_getall(
    p_farmid text, p_assetid integer
) RETURNS TABLE(poultrycapitalassetcostid integer, poultrycapitalassetid integer,
                costdate date, description text, costcategory text, amount numeric,
                sourcetype text, expenseid integer, supplierid integer, suppliername text,
                paymentstatus text, amountpaid numeric, balance numeric,
                status text, createdby text, createdat timestamp without time zone,
                reversedby text, reversedat timestamp without time zone, reversalreason text,
                paymentmethod text, duedate date, cashaccountname text,
                expenseamount numeric, expensecategory text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT c.poultrycapitalassetcostid, c.poultrycapitalassetid,
           c.costdate, c.description::text, c.costcategory::text, c.amount,
           c.sourcetype::text, c.expenseid, c.supplierid, s.name::text,
           e.paymentstatus::text,
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           c.status::text, c.createdby::text, c.createdat,
           c.reversedby::text, c.reversedat, c.reversalreason::text,
           -- 313.
           e.paymentmethod::text, e.duedate::date, ca.accountname::text,
           e.amount::numeric(14,2), e.category::text
    FROM   poultrycapitalassetcosts c
    LEFT   JOIN expense e ON e.expenseid = c.expenseid
    LEFT   JOIN supplier s ON s.supplierid = c.supplierid
    -- Joined on the id alone, the way every cash-account lookup in 302 is: the
    -- id came off an expense that is already scoped to this company.
    LEFT   JOIN poultrycashaccounts ca ON ca.poultrycashaccountid = e.poultrycashaccountid
    WHERE  c.farmid = p_farmid AND c.poultrycapitalassetid = p_assetid
    ORDER  BY c.costdate, c.poultrycapitalassetcostid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
--
-- The identity first, because if it ever fails every screen downstream is
-- lying: whatever the vocabulary, the two halves must add to the whole for
-- EVERY asset on the database.
-- -----------------------------------------------------------------------------
SELECT 'acquisition + additional = total, every asset' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'BROKEN on ' || COUNT(*) || ' asset(s)' END AS result
FROM   poultrycapitalassets a
WHERE  ROUND(fnpoultrycapitalasset_acquisitioncost(a.poultrycapitalassetid)
           + fnpoultrycapitalasset_additionalcost(a.poultrycapitalassetid), 2)
    <> ROUND(fnpoultrycapitalasset_originalcost(a.poultrycapitalassetid), 2)

UNION ALL
-- Nothing that existed has changed value.
SELECT 'total capitalised cost unchanged for every asset',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'CHANGED on ' || COUNT(*) END
FROM   sppoultrycapitalasset_getall((SELECT f.farmid FROM farms f WHERE f.type = 'Poultry' ORDER BY f.farmid LIMIT 1)) g
WHERE  ROUND(g.originalcost, 2) <> ROUND(g.totalcapitalizedcost, 2)

UNION ALL
-- No correction exists yet: this file writes none.
SELECT 'no correction written by the migration',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'WROTE ' || COUNT(*) END
FROM   poultrycapitalassetcosts c
WHERE  c.sourcetype = 'OriginalCostCorrection'

UNION ALL
-- And the four new routines are all there.
SELECT 'the four new routines exist (4 expected)',
       CASE WHEN COUNT(*) = 4 THEN 'OK' ELSE 'MISSING (' || COUNT(*) || ')' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnpoultrycapitalasset_acquisitioncost',
                     'fnpoultrycapitalasset_additionalcost',
                     'sppoultrycapitalasset_correctoriginalcost',
                     'sppoultrycapitalassetcost_reverse');
