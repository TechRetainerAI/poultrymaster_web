-- =============================================================================
-- 345  Receive Purchase -- one workflow for a supplier invoice that brings
--      stock in (poultry)
-- =============================================================================
--
-- WHAT THIS IS
-- ------------
-- Receiving feed, ingredients, medication or supplies from a supplier is ONE
-- real-world event, but until now it took up to three screens: record the
-- purchase on Raw Materials, then pay it from the purchase row or from Supplier
-- Balances, once per item on the invoice. A Purchase Receipt is that event as
-- one document:
--
--     header   supplier, purchase date, invoice reference, due date, notes,
--              additional costs (transport, offloading ...), amount paid now,
--              cash account
--     lines    item, quantity, unit cost, unit conversion -- one per item
--
-- THIS MIGRATION POSTS NOTHING ITSELF. It ORCHESTRATES the functions that
-- already own each effect, so a receipt is indistinguishable, ledger for
-- ledger, from the same purchase entered the old way:
--
--   stock + cost layer     sppoultryrawmaterialpurchase_insert, once per line.
--                          It creates the lot (the cost layer FIFO/LIFO/HIFO
--                          draws from), raises the item's stock, and STAMPS the
--                          cost-recognition method (262/265) -- this file never
--                          decides how a line is expensed.
--   payment, cash, expense sppoultrysupplierpayment_record, once per receipt,
--                          allocated across the lines. That one call is the
--                          existing authority for: the supplier payment header,
--                          the allocation rows, each lot's amountpaid, the ONE
--                          CashOut on the chosen account (with its overdraft
--                          guard), and -- only for lines whose method is
--                          EXPENSE_WHEN_PURCHASED -- the expense rows (207's
--                          cash-basis rule: a purchase is expensed as it is
--                          paid). A deferred line books no expense here; it
--                          reaches the P&L as a NonCash consumption expense
--                          when it is used (266).
--   payable                fnpoultrypayables, derived live from each lot's
--                          totalcost - amountpaid. Nothing is stored.
--   reversal               sppoultrysupplierpayment_reverse for the payment,
--                          sppoultryrawmaterialitem_adjust for the stock.
--
-- Lines are inserted with amountpaid = 0, so the insert itself books neither
-- an expense nor a cash line; the payment is the ONLY place money moves. That
-- is what makes double counting structurally impossible: there is no second
-- path that could also post it.
--
-- POSTING MATRIX (see the completion report for the worked GHS figures)
-- ----------------------------------------------------------------------
--                  stock/lot   payable          cash        expense now
--   paid, EWP        +total    0                -paid       +paid
--   paid, EWC        +total    0                -paid       none (on use)
--   credit           +total    +total           none        none
--   part, EWP        +total    +(total-paid)    -paid       +paid (rest when paid)
--   part, EWC        +total    +(total-paid)    -paid       none (on use)
--   EWP = EXPENSE_WHEN_PURCHASED, EWC = EXPENSE_WHEN_CONSUMED (stamped per lot).
--
-- ADDITIONAL COSTS
-- ----------------
-- The lot is the only place a landed cost can live: totalcost has always been
-- allowed to differ from quantity x unitcost (the purchase dialog sends both).
-- A receipt's additional costs are spread over its lines in proportion to line
-- value (by quantity when every line is free) and the last line takes the
-- rounding pennies, so SUM(lot.totalcost) = receipt total EXACTLY. The lot's
-- unitcost is the landed unit cost, rounded to the column's 2 dp -- the same
-- precision every draw already uses. Deferred lines recognise their landed
-- cost pro rata of totalcost (264), so the P&L gets the exact pennies.
--
-- APPEND-ONLY REVERSAL
-- --------------------
-- Nothing is deleted. Reversing a receipt:
--   * reverses its own supplier payment through the existing function (which
--     restores amountpaid, marks the payment and allocations Reversed, and
--     removes the expense rows that payment booked -- 207's rule, since a
--     negative expense row would corrupt every SUM(amount));
--   * writes one NEGATIVE poultryrawmaterialadjustments row per line
--     ('PurchaseReceiptReversal') through sppoultryrawmaterialitem_adjust, so
--     purchases - usage + adjustments (sppoultryrawmaterialitem_recalculatestock)
--     still equals stock;
--   * empties the lot (remainingquantity and deferredremainingcost to 0) and
--     stamps poultryrawmaterialpurchases.reversedat. The lot row, its quantity
--     and its totalcost are KEPT, so the purchase history still shows it.
--
-- It is REFUSED (sppoultrypurchasereceipt_reversalblockers says why) when:
--   * any of the stock has been drawn (usage, production, feed production) --
--     the cost layer would no longer be intact, and unwinding someone else's
--     draws is not this function's decision;
--   * the item's physical stock is below what the receipt added (internal use
--     or an adjustment took it without drawing lots);
--   * a supplier payment OTHER than the receipt's own was applied to it --
--     reverse that first from Supplier Payments, where it is visible;
--   * the receipt's payment is in a cash reconciliation (Cleared), because
--     reversing a supplier payment removes its cash line (existing behaviour of
--     sppoultrysupplierpaymentcash_sync) and a reconciled line must not move.
--
-- READERS THAT LEARN ABOUT reversedat
-- -----------------------------------
--   fnpoultrypayables                 a reversed lot owes nothing; receipt due date
--   fnpoultrydeferredpurchase_rows    a reversed lot is not "awaiting P&L"
--   sppoultryrawmaterialpurchase_getall  shows Reversed + receipt number
--   sppoultryclosingreport_get        a reversed lot is not a purchase of the period
-- Every other reader is quantity- or remaining-based and already reads a
-- reversed lot correctly (remaining 0, stock reduced by the adjustment).
--
-- DUPLICATE PREVENTION
-- --------------------
--   * clientrequestid: a double-clicked Save returns the FIRST receipt rather
--     than receiving the goods twice (unique per company).
--   * The same supplier invoice reference cannot be received twice while the
--     first is Posted (partial unique index, case/space-insensitive).
--   * Lots belonging to a receipt cannot be edited or deleted on their own:
--     the FK below refuses the delete, and trg_poultryrmpurchase_receiptlock
--     refuses a change to any column that defines the purchase.
--
-- Idempotent. PostgreSQL. Dry-run with database/apply-receive-purchase.ps1.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- 1. schema --

ALTER TABLE public.poultryrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS reversedat timestamp NULL;

COMMENT ON COLUMN public.poultryrawmaterialpurchases.reversedat IS
    '345. Set when the Purchase Receipt that created this lot was reversed. The '
    'row is kept for history; payables, deferred-cost and period-purchase readers '
    'skip it, and its stock left through a PurchaseReceiptReversal adjustment.';

CREATE TABLE IF NOT EXISTS public.poultrypurchasereceipts (
    poultrypurchasereceiptid  serial PRIMARY KEY,
    farmid                    text          NOT NULL,
    receiptnumber             text          NOT NULL,
    supplierid                integer       NOT NULL,
    suppliername              text          NULL,
    purchasedate              timestamp     NOT NULL,
    referenceno               text          NULL,
    duedate                   date          NULL,
    notes                     text          NULL,
    subtotal                  numeric(14,2) NOT NULL,
    additionalcosts           numeric(14,2) NOT NULL DEFAULT 0,
    additionalcostsnote       text          NULL,
    totalcost                 numeric(14,2) NOT NULL,
    amountpaidatreceipt       numeric(14,2) NOT NULL DEFAULT 0,
    paymentmethod             text          NULL,
    poultrycashaccountid      integer       NULL,
    poultrysupplierpaymentid  integer       NULL,
    status                    text          NOT NULL DEFAULT 'Posted',
    clientrequestid           uuid          NULL,
    createdby                 text          NULL,
    createdat                 timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby                text          NULL,
    reversedat                timestamp     NULL,
    reversalreason            text          NULL,
    CONSTRAINT ck_poultrypurchasereceipts_status   CHECK (status IN ('Posted', 'Reversed')),
    CONSTRAINT ck_poultrypurchasereceipts_amounts  CHECK (subtotal >= 0 AND additionalcosts >= 0
                                                          AND totalcost > 0
                                                          AND totalcost = subtotal + additionalcosts),
    CONSTRAINT ck_poultrypurchasereceipts_paid     CHECK (amountpaidatreceipt >= 0
                                                          AND amountpaidatreceipt <= totalcost)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrypurchasereceipts_number
    ON public.poultrypurchasereceipts (farmid, receiptnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrypurchasereceipts_request
    ON public.poultrypurchasereceipts (farmid, clientrequestid)
    WHERE clientrequestid IS NOT NULL;
-- One POSTED receipt per supplier invoice. Reversed receipts drop out of the
-- index, so a reversed invoice can be received again correctly.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrypurchasereceipts_invoice
    ON public.poultrypurchasereceipts (farmid, supplierid, lower(btrim(referenceno)))
    WHERE status = 'Posted' AND NULLIF(btrim(referenceno), '') IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_poultrypurchasereceipts_date
    ON public.poultrypurchasereceipts (farmid, purchasedate DESC);

CREATE TABLE IF NOT EXISTS public.poultrypurchasereceiptlines (
    poultrypurchasereceiptlineid    serial PRIMARY KEY,
    poultrypurchasereceiptid        integer       NOT NULL
        REFERENCES public.poultrypurchasereceipts (poultrypurchasereceiptid) ON DELETE RESTRICT,
    farmid                          text          NOT NULL,
    lineno                          integer       NOT NULL,
    poultryrawmaterialitemid        integer       NOT NULL
        REFERENCES public.poultryrawmaterialitems (poultryrawmaterialitemid),
    quantity                        numeric(14,3) NOT NULL,
    unitcost                        numeric(14,2) NOT NULL,   -- invoice price per purchase unit
    linesubtotal                    numeric(14,2) NOT NULL,
    allocatedadditionalcost         numeric(14,2) NOT NULL DEFAULT 0,
    linetotal                       numeric(14,2) NOT NULL,
    productionunit                  text          NULL,
    productionunitsperpurchaseunit  numeric(18,8) NULL,
    notes                           text          NULL,
    -- The cost layer this line created. RESTRICT is the delete guard: the
    -- Raw Materials delete function cannot remove a receipt's lot.
    poultryrawmaterialpurchaseid    integer       NOT NULL
        REFERENCES public.poultryrawmaterialpurchases (poultryrawmaterialpurchaseid) ON DELETE RESTRICT,
    reversaladjustmentid            integer       NULL,
    CONSTRAINT ck_poultrypurchasereceiptlines_qty   CHECK (quantity > 0 AND unitcost >= 0),
    CONSTRAINT ck_poultrypurchasereceiptlines_total CHECK (allocatedadditionalcost >= 0
                                                           AND linetotal = linesubtotal + allocatedadditionalcost),
    CONSTRAINT ux_poultrypurchasereceiptlines_lineno UNIQUE (poultrypurchasereceiptid, lineno),
    CONSTRAINT ux_poultrypurchasereceiptlines_lot    UNIQUE (poultryrawmaterialpurchaseid)
);

-- ------------------------------------------------ 2. the lot lock (trigger) --
-- A receipt's lot is defined by the receipt. Draws, payments and the reversal
-- itself only move remainingquantity / deferredremainingcost / amountpaid /
-- reversedat / updatedat / the cash account, so those stay writable; every
-- column that says WHAT was bought, WHEN, from WHOM and for HOW MUCH does not.
CREATE OR REPLACE FUNCTION public.trg_poultryrmpurchase_receiptlock_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE
    v_number text;
BEGIN
    IF  NEW.farmid                         IS NOT DISTINCT FROM OLD.farmid
    AND NEW.poultryrawmaterialitemid       IS NOT DISTINCT FROM OLD.poultryrawmaterialitemid
    AND NEW.supplierid                     IS NOT DISTINCT FROM OLD.supplierid
    AND NEW.purchasedate                   IS NOT DISTINCT FROM OLD.purchasedate
    AND NEW.quantity                       IS NOT DISTINCT FROM OLD.quantity
    AND NEW.unitcost                       IS NOT DISTINCT FROM OLD.unitcost
    AND NEW.totalcost                      IS NOT DISTINCT FROM OLD.totalcost
    AND NEW.productionunitsperpurchaseunit IS NOT DISTINCT FROM OLD.productionunitsperpurchaseunit
    AND NEW.costrecognitionmethod          IS NOT DISTINCT FROM OLD.costrecognitionmethod
    AND NEW.deferredtotalcost              IS NOT DISTINCT FROM OLD.deferredtotalcost THEN
        RETURN NEW;
    END IF;

    SELECT r.receiptnumber INTO v_number
    FROM   public.poultrypurchasereceiptlines l
    JOIN   public.poultrypurchasereceipts r ON r.poultrypurchasereceiptid = l.poultrypurchasereceiptid
    WHERE  l.poultryrawmaterialpurchaseid = OLD.poultryrawmaterialpurchaseid
    LIMIT  1;

    IF v_number IS NOT NULL THEN
        RAISE EXCEPTION 'This stock lot belongs to purchase receipt % and cannot be edited on its own. Reverse the receipt and receive it again instead.', v_number;
    END IF;
    RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS trg_poultryrmpurchase_receiptlock ON public.poultryrawmaterialpurchases;
CREATE TRIGGER trg_poultryrmpurchase_receiptlock
    BEFORE UPDATE ON public.poultryrawmaterialpurchases
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryrmpurchase_receiptlock_fn();

-- ------------------------------------------------------------ 3. post ------
DO $d$ DECLARE r record; BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND p.proname IN ('sppoultrypurchasereceipt_post',
                                 'sppoultrypurchasereceipt_reversalblockers',
                                 'sppoultrypurchasereceipt_reverse',
                                 'sppoultrypurchasereceipt_getall',
                                 'sppoultrypurchasereceipt_getlines')
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig; END LOOP;
END $d$;

CREATE FUNCTION public.sppoultrypurchasereceipt_post(
    p_farmid               text,
    p_supplierid           integer,
    p_suppliername         text,
    p_purchasedate         timestamp,
    p_referenceno          text,
    p_duedate              date,
    p_notes                text,
    p_lines                jsonb,
    p_additionalcosts      numeric DEFAULT 0,
    p_additionalcostsnote  text    DEFAULT NULL,
    p_amountpaid           numeric DEFAULT 0,
    p_paymentmethod        text    DEFAULT NULL,
    p_cashaccountid        integer DEFAULT NULL,
    p_clientrequestid      uuid    DEFAULT NULL,
    p_createdby            text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_type      text;
    v_existing  integer;
    v_supplier  integer := p_supplierid;
    v_supname   text;
    v_date      timestamp;
    v_today     date;
    v_ref       text := NULLIF(btrim(p_referenceno), '');
    v_dup       record;
    v_count     integer;
    v_subtotal  numeric(14,2);
    v_add       numeric(14,2) := round(COALESCE(p_additionalcosts, 0), 2);
    v_total     numeric(14,2);
    v_paid      numeric(14,2) := round(COALESCE(p_amountpaid, 0), 2);
    v_weight    numeric;
    v_alloc     numeric(14,2);
    v_left      numeric(14,2);
    v_id        integer;
    v_number    text;
    v_lot       integer;
    v_method    text;
    v_unit      numeric(14,2);
    v_allocs    jsonb := '[]'::jsonb;
    v_payid     integer;
    v_due       date := p_duedate;
    l           record;
BEGIN
    IF COALESCE(btrim(p_farmid), '') = '' THEN
        RAISE EXCEPTION 'Company is required.';
    END IF;
    IF COALESCE(btrim(p_createdby), '') = '' THEN
        RAISE EXCEPTION 'The user receiving the purchase is required.';
    END IF;

    -- Company isolation: a Water or Generic company has its own purchase
    -- module, and these lots would be invisible to it. Legacy poultry farms
    -- carry a NULL type (see PoultryAdvancedReportsController).
    v_type := spfarm_gettype(p_farmid);
    IF v_type IS NOT NULL AND btrim(v_type) <> '' AND lower(v_type) <> 'poultry' THEN
        RAISE EXCEPTION 'Receive Purchase is only available for Poultry companies (this company is %).', v_type;
    END IF;

    -- One receipt at a time per company: makes the receipt number, the
    -- duplicate-invoice check and the idempotency check race-free.
    PERFORM pg_advisory_xact_lock(hashtext('poultrypurchasereceipt:' || lower(p_farmid)));

    IF p_clientrequestid IS NOT NULL THEN
        SELECT r.poultrypurchasereceiptid INTO v_existing
        FROM   poultrypurchasereceipts r
        WHERE  r.farmid = p_farmid AND r.clientrequestid = p_clientrequestid
        LIMIT  1;
        IF v_existing IS NOT NULL THEN
            RETURN v_existing;   -- the same Save, sent twice
        END IF;
    END IF;

    -- ---- supplier -----------------------------------------------------------
    IF v_supplier IS NULL AND COALESCE(btrim(p_suppliername), '') <> '' THEN
        v_supplier := fnpoultrysupplier_resolve(p_farmid, btrim(p_suppliername), p_createdby);
    END IF;
    IF v_supplier IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier you bought from.';
    END IF;
    SELECT s.name INTO v_supname FROM supplier s
    WHERE  s.supplierid = v_supplier AND s.farmid = p_farmid LIMIT 1;
    IF v_supname IS NULL THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    -- ---- date ---------------------------------------------------------------
    v_today := fncompany_businessdate(p_farmid);
    v_date  := COALESCE(p_purchasedate, v_today::timestamp);
    IF v_date::date > v_today THEN
        RAISE EXCEPTION 'The purchase date (%) is in the future. Goods can only be received on or before today (%).',
              v_date::date, v_today;
    END IF;

    -- ---- duplicate invoice --------------------------------------------------
    IF v_ref IS NOT NULL THEN
        SELECT r.receiptnumber, r.purchasedate INTO v_dup
        FROM   poultrypurchasereceipts r
        WHERE  r.farmid = p_farmid AND r.supplierid = v_supplier AND r.status = 'Posted'
          AND  lower(btrim(r.referenceno)) = lower(v_ref)
        LIMIT  1;
        IF FOUND THEN
            RAISE EXCEPTION 'Invoice "%" from % was already received as % on %. Reverse that receipt first if it was wrong.',
                  v_ref, v_supname, v_dup.receiptnumber, v_dup.purchasedate::date;
        END IF;
    END IF;

    -- ---- lines ----------------------------------------------------------------
    -- Keys are lowercase on purpose: jsonb ->> is case-sensitive, and the C#
    -- side serialises these exact names (postgres-sp-gotchas #1).
    DROP TABLE IF EXISTS tmp_receipt_lines;
    CREATE TEMP TABLE tmp_receipt_lines ON COMMIT DROP AS
    SELECT e.n::integer                                              AS lineno,
           NULLIF(e.v ->> 'itemid', '')::integer                     AS itemid,
           NULLIF(e.v ->> 'quantity', '')::numeric                   AS quantity,
           NULLIF(e.v ->> 'unitcost', '')::numeric                   AS unitcost,
           NULLIF(btrim(e.v ->> 'productionunit'), '')               AS productionunit,
           NULLIF(e.v ->> 'productionunitsperpurchaseunit', '')::numeric AS mult,
           NULLIF(btrim(e.v ->> 'notes'), '')                        AS notes,
           NULL::numeric(14,2)                                       AS subtotal,
           0::numeric(14,2)                                          AS allocated,
           NULL::numeric(14,2)                                       AS linetotal
    FROM   jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) WITH ORDINALITY AS e(v, n);

    SELECT COUNT(*) INTO v_count FROM tmp_receipt_lines;
    IF v_count = 0 THEN
        RAISE EXCEPTION 'Add at least one item to the receipt.';
    END IF;
    IF v_count > 50 THEN
        RAISE EXCEPTION 'A receipt can hold at most 50 lines (this one has %). Split the invoice into two receipts.', v_count;
    END IF;

    FOR l IN SELECT * FROM tmp_receipt_lines ORDER BY lineno LOOP
        IF l.itemid IS NULL THEN
            RAISE EXCEPTION 'Line %: choose an item.', l.lineno;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                       WHERE i.poultryrawmaterialitemid = l.itemid AND i.farmid = p_farmid) THEN
            RAISE EXCEPTION 'Line %: that item does not belong to this company.', l.lineno;
        END IF;
        IF EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                   WHERE i.poultryrawmaterialitemid = l.itemid AND i.farmid = p_farmid
                     AND NOT COALESCE(i.isactive, TRUE)) THEN
            RAISE EXCEPTION 'Line %: % is inactive. Reactivate it on Raw Materials before receiving it.',
                  l.lineno, (SELECT i.itemname FROM poultryrawmaterialitems i WHERE i.poultryrawmaterialitemid = l.itemid);
        END IF;
        IF l.quantity IS NULL OR l.quantity <= 0 THEN
            RAISE EXCEPTION 'Line %: quantity must be greater than 0.', l.lineno;
        END IF;
        IF round(l.quantity, 3) <> l.quantity THEN
            RAISE EXCEPTION 'Line %: quantity can have at most 3 decimal places.', l.lineno;
        END IF;
        IF l.unitcost IS NULL OR l.unitcost < 0 THEN
            RAISE EXCEPTION 'Line %: unit cost cannot be negative.', l.lineno;
        END IF;
        IF l.mult IS NOT NULL AND l.mult <= 0 THEN
            RAISE EXCEPTION 'Line %: units per purchase unit must be greater than 0.', l.lineno;
        END IF;
    END LOOP;

    UPDATE tmp_receipt_lines t SET subtotal = round(t.quantity * t.unitcost, 2);
    SELECT COALESCE(SUM(t.subtotal), 0) INTO v_subtotal FROM tmp_receipt_lines t;

    IF v_add < 0 THEN
        RAISE EXCEPTION 'Additional costs cannot be negative.';
    END IF;
    v_total := v_subtotal + v_add;
    IF v_total <= 0 THEN
        RAISE EXCEPTION 'The receipt total must be greater than 0.';
    END IF;

    -- ---- additional costs, pro rata; the last line takes the pennies ---------
    IF v_add > 0 THEN
        SELECT CASE WHEN v_subtotal > 0 THEN v_subtotal ELSE SUM(t.quantity) END
        INTO   v_weight FROM tmp_receipt_lines t;
        v_left := v_add;
        FOR l IN SELECT * FROM tmp_receipt_lines ORDER BY lineno LOOP
            IF l.lineno = (SELECT MAX(t.lineno) FROM tmp_receipt_lines t) THEN
                v_alloc := v_left;
            ELSE
                v_alloc := round(v_add * (CASE WHEN v_subtotal > 0 THEN l.subtotal ELSE l.quantity END) / v_weight, 2);
                v_alloc := LEAST(v_alloc, v_left);
            END IF;
            UPDATE tmp_receipt_lines t SET allocated = v_alloc WHERE t.lineno = l.lineno;
            v_left := v_left - v_alloc;
        END LOOP;
    END IF;
    UPDATE tmp_receipt_lines t SET linetotal = t.subtotal + t.allocated;

    -- ---- payment ----------------------------------------------------------------
    IF v_paid < 0 THEN
        RAISE EXCEPTION 'Amount paid cannot be negative.';
    END IF;
    IF v_paid > v_total THEN
        RAISE EXCEPTION 'Amount paid (%) is more than the purchase total (%).', v_paid, v_total;
    END IF;
    IF v_paid > 0 AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the payment came from.';
    END IF;
    IF v_paid >= v_total THEN
        v_due := NULL;                       -- nothing left to fall due
    ELSIF v_due IS NOT NULL AND v_due < v_date::date THEN
        RAISE EXCEPTION 'The due date (%) cannot be before the purchase date (%).', v_due, v_date::date;
    END IF;

    -- ---- header -----------------------------------------------------------------
    SELECT 'RCV-' || lpad((COALESCE(MAX(NULLIF(substring(r.receiptnumber FROM '^RCV-(\d+)$'), '')::integer), 0) + 1)::text, 5, '0')
    INTO   v_number
    FROM   poultrypurchasereceipts r WHERE r.farmid = p_farmid;

    INSERT INTO poultrypurchasereceipts
        (farmid, receiptnumber, supplierid, suppliername, purchasedate, referenceno, duedate, notes,
         subtotal, additionalcosts, additionalcostsnote, totalcost, amountpaidatreceipt,
         paymentmethod, poultrycashaccountid, status, clientrequestid, createdby)
    VALUES
        (p_farmid, v_number, v_supplier, v_supname, v_date, v_ref, v_due, NULLIF(btrim(p_notes), ''),
         v_subtotal, v_add, NULLIF(btrim(p_additionalcostsnote), ''), v_total, v_paid,
         CASE WHEN v_paid > 0 THEN COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash') ELSE 'Credit' END,
         CASE WHEN v_paid > 0 THEN p_cashaccountid END, 'Posted', p_clientrequestid, p_createdby)
    RETURNING poultrypurchasereceiptid INTO v_id;

    -- ---- lines -> lots, through the existing purchase insert ------------------
    FOR l IN SELECT * FROM tmp_receipt_lines ORDER BY lineno LOOP
        -- Landed unit cost. Without additional costs it is exactly the invoice
        -- price, so a receipt with none is the old purchase to the penny.
        v_unit := CASE WHEN l.allocated = 0 THEN l.unitcost
                       ELSE round(l.linetotal / l.quantity, 2) END;

        v_lot := sppoultryrawmaterialpurchase_insert(
            p_farmid                         => p_farmid,
            p_poultryrawmaterialitemid       => l.itemid,
            p_suppliername                   => v_supname,
            p_supplierid                     => v_supplier,
            p_purchasedate                   => v_date,
            p_quantity                       => l.quantity,
            p_unitcost                       => v_unit,
            p_totalcost                      => l.linetotal,
            p_productionunit                 => l.productionunit,
            p_productionunitsperpurchaseunit => l.mult,
            p_paymentmethod                  => CASE WHEN v_paid > 0 THEN COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash') ELSE 'Credit' END,
            p_amountpaid                     => 0,      -- money moves ONLY through the payment below
            p_receipturl                     => NULL,
            p_notes                          => left(concat_ws(' | ', 'Receipt ' || v_number,
                                                               CASE WHEN v_ref IS NOT NULL THEN 'Invoice ' || v_ref END,
                                                               l.notes), 500),
            p_createdby                      => p_createdby);

        -- The insert falls back to qty x unitcost for a zero total; keep the
        -- line honest about what the lot actually holds.
        SELECT pu.costrecognitionmethod INTO v_method
        FROM   poultryrawmaterialpurchases pu WHERE pu.poultryrawmaterialpurchaseid = v_lot;

        INSERT INTO poultrypurchasereceiptlines
            (poultrypurchasereceiptid, farmid, lineno, poultryrawmaterialitemid, quantity, unitcost,
             linesubtotal, allocatedadditionalcost, linetotal, productionunit,
             productionunitsperpurchaseunit, notes, poultryrawmaterialpurchaseid)
        VALUES
            (v_id, p_farmid, l.lineno, l.itemid, l.quantity, l.unitcost,
             l.subtotal, l.allocated, l.linetotal, l.productionunit, l.mult, l.notes, v_lot);
    END LOOP;

    -- ---- the payment: one supplier payment, allocated line by line ------------
    IF v_paid > 0 THEN
        v_left := v_paid;
        FOR l IN SELECT rl.poultryrawmaterialpurchaseid AS lot, rl.linetotal
                 FROM   poultrypurchasereceiptlines rl
                 WHERE  rl.poultrypurchasereceiptid = v_id AND rl.linetotal > 0
                 ORDER  BY rl.lineno LOOP
            EXIT WHEN v_left <= 0;
            v_alloc := LEAST(v_left, l.linetotal);
            v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
                'documenttype', 'RawMaterialPurchase',
                'documentid',   l.lot,
                'amount',       v_alloc));
            v_left := v_left - v_alloc;
        END LOOP;

        v_payid := sppoultrysupplierpayment_record(
            p_farmid        => p_farmid,
            p_supplierid    => v_supplier,
            p_amount        => v_paid,
            p_allocations   => v_allocs,
            p_paymentmethod => COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'),
            p_paymentdate   => v_date,
            p_cashaccountid => p_cashaccountid,
            p_reference     => COALESCE(v_ref, v_number),
            p_notes         => 'Paid on purchase receipt ' || v_number,
            p_sourcetype    => 'ReceivePurchase',
            p_createdby     => p_createdby);

        UPDATE poultrypurchasereceipts r SET poultrysupplierpaymentid = v_payid
        WHERE  r.poultrypurchasereceiptid = v_id;
    END IF;

    RETURN v_id;
END $f$;

-- ------------------------------------------------- 4. reversal blockers ------
-- Every reason a receipt cannot be reversed, in plain words. The UI shows the
-- first; the reverse function raises it. Empty result = safe to reverse.
CREATE FUNCTION public.sppoultrypurchasereceipt_reversalblockers(p_farmid text, p_receiptid integer)
RETURNS TABLE(code text, message text)
LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_r record;
BEGIN
    SELECT r.* INTO v_r FROM poultrypurchasereceipts r
    WHERE  r.poultrypurchasereceiptid = p_receiptid AND r.farmid = p_farmid;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'NotFound'::text, 'Purchase receipt not found for this company.'::text;
        RETURN;
    END IF;
    IF v_r.status = 'Reversed' THEN
        RETURN QUERY SELECT 'AlreadyReversed'::text,
            ('Receipt ' || v_r.receiptnumber || ' was already reversed.')::text;
        RETURN;
    END IF;

    -- Stock drawn from the lot: a cost layer is only reversible while intact.
    RETURN QUERY
    SELECT 'Consumed'::text,
           (i.itemname || ': ' ||
            rtrim(to_char(pu.quantity - pu.remainingquantity, 'FM999999990.###'), '.') || ' of ' ||
            rtrim(to_char(pu.quantity, 'FM999999990.###'), '.') ||
            ' has already been used. Reverse the usage, production or feed production that drew it first.')::text
    FROM   poultrypurchasereceiptlines rl
    JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
    JOIN   poultryrawmaterialitems i      ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    WHERE  rl.poultrypurchasereceiptid = p_receiptid
      AND  (pu.remainingquantity + 0.0005 < pu.quantity
            OR pu.deferredremainingcost + 0.005 < pu.deferredtotalcost)
    ORDER  BY rl.lineno;

    -- Physical stock below what the receipt added (internal use / adjustments
    -- take stock without drawing lots).
    RETURN QUERY
    SELECT 'StockShort'::text,
           (i.itemname || ': only ' || rtrim(to_char(i.currentquantity, 'FM999999990.###'), '.') || ' ' ||
            COALESCE(i.unitofmeasure, '') || ' is in stock, but this receipt added ' ||
            rtrim(to_char(s.qty, 'FM999999990.###'), '.') ||
            '. Stock was taken out by internal use or an adjustment, so reversing would leave it negative.')::text
    FROM  (SELECT pu.poultryrawmaterialitemid AS itemid,
                  SUM(pu.quantity * COALESCE(NULLIF(pu.productionunitsperpurchaseunit, 0), 1)) AS qty
           FROM   poultrypurchasereceiptlines rl
           JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
           WHERE  rl.poultrypurchasereceiptid = p_receiptid
           GROUP  BY pu.poultryrawmaterialitemid) s
    JOIN   poultryrawmaterialitems i ON i.poultryrawmaterialitemid = s.itemid AND i.farmid = p_farmid
    WHERE  i.currentquantity + 0.0005 < s.qty;

    -- A later supplier payment applied to these lines.
    RETURN QUERY
    SELECT DISTINCT 'OtherPayment'::text,
           ('Supplier payment #' || sp.poultrysupplierpaymentid::text || ' (' ||
            trim(to_char(sp.totalamount, 'FM999999990.00')) || ' on ' || to_char(sp.paymentdate, 'YYYY-MM-DD') ||
            ') was applied to this receipt. Reverse it from Supplier Payments first.')::text
    FROM   poultrypurchasereceiptlines rl
    JOIN   supplierpaymentallocation sa
           ON  sa.documentid = rl.poultryrawmaterialpurchaseid AND sa.documenttype = 'RawMaterialPurchase'
           AND sa.module = 'poultry' AND sa.farmid = p_farmid AND sa.status = 'Posted'
    JOIN   poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = p_farmid
    WHERE  rl.poultrypurchasereceiptid = p_receiptid
      AND  sa.paymentid IS DISTINCT FROM v_r.poultrysupplierpaymentid;

    -- Money recorded on a lot without an allocation (should be impossible: the
    -- lot is locked and inserted unpaid -- but if it happened, reversing the
    -- receipt's payment would not bring amountpaid back to zero).
    RETURN QUERY
    SELECT 'UntrackedPayment'::text,
           (i.itemname || ': ' || trim(to_char(pu.amountpaid - COALESCE(a.amt, 0), 'FM999999990.00')) ||
            ' is recorded as paid without a supplier payment behind it. Check the purchase before reversing.')::text
    FROM   poultrypurchasereceiptlines rl
    JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
    JOIN   poultryrawmaterialitems i      ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS amt FROM supplierpaymentallocation sa
               WHERE  sa.documentid = pu.poultryrawmaterialpurchaseid AND sa.documenttype = 'RawMaterialPurchase'
                 AND  sa.module = 'poultry' AND sa.farmid = p_farmid AND sa.status = 'Posted') a ON TRUE
    WHERE  rl.poultrypurchasereceiptid = p_receiptid
      AND  pu.amountpaid > COALESCE(a.amt, 0) + 0.005;

    -- The receipt's own payment already reconciled.
    IF v_r.poultrysupplierpaymentid IS NOT NULL THEN
        RETURN QUERY
        SELECT 'Reconciled'::text,
               ('The payment made on this receipt is part of a cash reconciliation on ' ||
                COALESCE(a.accountname, 'its cash account') ||
                '. Un-clear it on Cash Reconciliation before reversing the receipt.')::text
        FROM   poultrycashtransactions ct
        JOIN   poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = ct.sourceid AND sp.status = 'Posted'
        LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = ct.poultrycashaccountid
        WHERE  ct.farmid = p_farmid AND ct.sourcetype = 'PoultrySupplierPayment'
          AND  ct.sourceid = v_r.poultrysupplierpaymentid
          AND  (ct.clearingstatus = 'Cleared' OR ct.poultrycashreconciliationid IS NOT NULL)
        LIMIT  1;
    END IF;
END $f$;

-- ------------------------------------------------------------ 5. reverse ------
CREATE FUNCTION public.sppoultrypurchasereceipt_reverse(
    p_farmid     text,
    p_receiptid  integer,
    p_reason     text,
    p_reversedby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_r       record;
    v_block   text;
    v_status  text;
    v_adjid   integer;
    v_count   integer := 0;
    v_left    numeric;
    l         record;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'Give a reason for reversing this receipt.';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultrypurchasereceipt:' || lower(p_farmid)));

    SELECT r.* INTO v_r FROM poultrypurchasereceipts r
    WHERE  r.poultrypurchasereceiptid = p_receiptid AND r.farmid = p_farmid
    FOR UPDATE;

    SELECT b.message INTO v_block
    FROM   sppoultrypurchasereceipt_reversalblockers(p_farmid, p_receiptid) b LIMIT 1;
    IF v_block IS NOT NULL THEN
        RAISE EXCEPTION '%', v_block;
    END IF;

    -- 1. Money: the receipt's own payment, through the existing reversal. It
    --    may already have been reversed from Supplier Payments -- then there is
    --    nothing to undo here.
    IF v_r.poultrysupplierpaymentid IS NOT NULL THEN
        SELECT sp.status INTO v_status FROM poultrysupplierpayments sp
        WHERE  sp.poultrysupplierpaymentid = v_r.poultrysupplierpaymentid AND sp.farmid = p_farmid;
        IF v_status = 'Posted' THEN
            PERFORM sppoultrysupplierpayment_reverse(
                p_farmid, v_r.poultrysupplierpaymentid,
                'Purchase receipt ' || v_r.receiptnumber || ' reversed: ' || btrim(p_reason),
                p_reversedby);
        END IF;
    END IF;

    SELECT COALESCE(SUM(pu.amountpaid), 0) INTO v_left
    FROM   poultrypurchasereceiptlines rl
    JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
    WHERE  rl.poultrypurchasereceiptid = p_receiptid;
    IF v_left > 0.005 THEN
        RAISE EXCEPTION 'Reversing the payment left % still recorded as paid on this receipt. Nothing was changed.', v_left;
    END IF;

    -- 2. Stock: an opposite adjustment per line, then the lot emptied. Rows kept.
    FOR l IN SELECT rl.poultrypurchasereceiptlineid AS lineid, pu.*
             FROM   poultrypurchasereceiptlines rl
             JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
             WHERE  rl.poultrypurchasereceiptid = p_receiptid
             ORDER  BY rl.lineno LOOP
        SELECT a.poultryrawmaterialadjustmentid INTO v_adjid
        FROM   sppoultryrawmaterialitem_adjust(
                   p_farmid, l.poultryrawmaterialitemid,
                   -(l.quantity * COALESCE(NULLIF(l.productionunitsperpurchaseunit, 0), 1)),
                   l.unitcost, 'PurchaseReceiptReversal',
                   left('Reversal of purchase receipt ' || v_r.receiptnumber || ': ' || btrim(p_reason), 500),
                   p_reversedby) a;

        UPDATE poultryrawmaterialpurchases pu
        SET    remainingquantity     = 0,
               deferredremainingcost = 0,   -- never recognised, so never charged
               reversedat            = (now() at time zone 'utc'),
               updatedat             = (now() at time zone 'utc')
        WHERE  pu.poultryrawmaterialpurchaseid = l.poultryrawmaterialpurchaseid;

        UPDATE poultrypurchasereceiptlines rl SET reversaladjustmentid = v_adjid
        WHERE  rl.poultrypurchasereceiptlineid = l.lineid;
        v_count := v_count + 1;
    END LOOP;

    UPDATE poultrypurchasereceipts r
    SET    status = 'Reversed', reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'), reversalreason = btrim(p_reason)
    WHERE  r.poultrypurchasereceiptid = p_receiptid;

    RETURN v_count;
END $f$;

-- ------------------------------------------------------------ 6. readers ------
CREATE FUNCTION public.sppoultrypurchasereceipt_getall(
    p_farmid    text,
    p_fromdate  date    DEFAULT NULL,
    p_todate    date    DEFAULT NULL,
    p_status    text    DEFAULT NULL,
    p_receiptid integer DEFAULT NULL)
RETURNS TABLE(poultrypurchasereceiptid integer, receiptnumber text, supplierid integer, suppliername text,
              purchasedate timestamp, referenceno text, duedate date, notes text,
              subtotal numeric, additionalcosts numeric, additionalcostsnote text, totalcost numeric,
              amountpaidatreceipt numeric, amountpaid numeric, balance numeric, paymentstatus text,
              isoverdue boolean, paymentmethod text, poultrycashaccountid integer, cashaccountname text,
              poultrysupplierpaymentid integer, status text, linecount integer, itemsummary text,
              expensedatpurchasecost numeric, deferredcost numeric,
              createdby text, createdat timestamp, reversedby text, reversedat timestamp, reversalreason text,
              reversalblocker text)
LANGUAGE sql STABLE AS $f$
    SELECT r.poultrypurchasereceiptid, r.receiptnumber, r.supplierid,
           COALESCE(s.name, r.suppliername)::text,
           r.purchasedate, r.referenceno, r.duedate, r.notes,
           r.subtotal, r.additionalcosts, r.additionalcostsnote, r.totalcost,
           r.amountpaidatreceipt,
           -- Live, from the lots: later payments from Supplier Balances count,
           -- and a payment reversed there stops counting.
           (CASE WHEN r.status = 'Reversed' THEN 0 ELSE COALESCE(x.paid, 0) END)::numeric(14,2),
           (CASE WHEN r.status = 'Reversed' THEN 0 ELSE r.totalcost - COALESCE(x.paid, 0) END)::numeric(14,2),
           (CASE WHEN r.status = 'Reversed'                       THEN 'Reversed'
                 WHEN COALESCE(x.paid, 0) >= r.totalcost - 0.005  THEN 'Paid'
                 WHEN COALESCE(x.paid, 0) > 0                     THEN 'Part paid'
                 ELSE 'Unpaid' END)::text,
           (r.status = 'Posted' AND COALESCE(x.paid, 0) < r.totalcost - 0.005
            AND COALESCE(r.duedate, r.purchasedate::date + COALESCE(s.paymenttermsdays, 0))
                < fncompany_businessdate(r.farmid)),
           r.paymentmethod, r.poultrycashaccountid, a.accountname::text,
           r.poultrysupplierpaymentid, r.status,
           COALESCE(x.lines, 0)::integer, x.items,
           COALESCE(x.ewp, 0)::numeric(14,2), COALESCE(x.ewc, 0)::numeric(14,2),
           r.createdby, r.createdat, r.reversedby, r.reversedat, r.reversalreason,
           (CASE WHEN r.status = 'Posted' THEN
                (SELECT b.message FROM sppoultrypurchasereceipt_reversalblockers(r.farmid, r.poultrypurchasereceiptid) b LIMIT 1)
            END)::text
    FROM   poultrypurchasereceipts r
    LEFT   JOIN supplier s ON s.supplierid = r.supplierid AND s.farmid = r.farmid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = r.poultrycashaccountid AND a.farmid = r.farmid
    LEFT   JOIN LATERAL (
               SELECT SUM(pu.amountpaid)                                   AS paid,
                      COUNT(*)                                             AS lines,
                      string_agg(i.itemname, ', ' ORDER BY rl.lineno)     AS items,
                      SUM(rl.linetotal) FILTER (WHERE fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod))     AS ewp,
                      SUM(rl.linetotal) FILTER (WHERE NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)) AS ewc
               FROM   poultrypurchasereceiptlines rl
               JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
               JOIN   poultryrawmaterialitems i      ON i.poultryrawmaterialitemid = rl.poultryrawmaterialitemid
               WHERE  rl.poultrypurchasereceiptid = r.poultrypurchasereceiptid
           ) x ON TRUE
    WHERE  r.farmid = p_farmid
      AND  (p_receiptid IS NULL OR r.poultrypurchasereceiptid = p_receiptid)
      AND  (p_fromdate IS NULL OR r.purchasedate::date >= p_fromdate)
      AND  (p_todate   IS NULL OR r.purchasedate::date <= p_todate)
      AND  (p_status IS NULL OR p_status = '' OR p_status = 'All' OR r.status = p_status)
    ORDER  BY r.purchasedate DESC, r.poultrypurchasereceiptid DESC;
$f$;

CREATE FUNCTION public.sppoultrypurchasereceipt_getlines(p_farmid text, p_receiptid integer)
RETURNS TABLE(poultrypurchasereceiptlineid integer, lineno integer, poultryrawmaterialitemid integer,
              itemname text, category text, unitofmeasure text,
              quantity numeric, unitcost numeric, linesubtotal numeric, allocatedadditionalcost numeric,
              linetotal numeric, landedunitcost numeric, productionunit text,
              productionunitsperpurchaseunit numeric, productionquantity numeric, notes text,
              poultryrawmaterialpurchaseid integer, costrecognitionmethod text, recognitionlabel text,
              remainingquantity numeric, consumedquantity numeric, amountpaid numeric, balance numeric,
              deferredremainingcost numeric, reversaladjustmentid integer)
LANGUAGE sql STABLE AS $f$
    SELECT rl.poultrypurchasereceiptlineid, rl.lineno, rl.poultryrawmaterialitemid,
           i.itemname::text, i.category::text, i.unitofmeasure::text,
           rl.quantity, rl.unitcost, rl.linesubtotal, rl.allocatedadditionalcost, rl.linetotal,
           pu.unitcost, rl.productionunit, rl.productionunitsperpurchaseunit,
           (rl.quantity * COALESCE(NULLIF(rl.productionunitsperpurchaseunit, 0), 1))::numeric(18,3),
           rl.notes, rl.poultryrawmaterialpurchaseid, pu.costrecognitionmethod::text,
           (CASE WHEN fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
                 THEN 'Expensed as paid' ELSE 'Expensed when used' END)::text,
           pu.remainingquantity,
           (CASE WHEN pu.reversedat IS NULL THEN pu.quantity - pu.remainingquantity ELSE 0 END)::numeric(14,3),
           pu.amountpaid,
           (CASE WHEN pu.reversedat IS NULL THEN GREATEST(pu.totalcost - pu.amountpaid, 0) ELSE 0 END)::numeric(14,2),
           pu.deferredremainingcost, rl.reversaladjustmentid
    FROM   poultrypurchasereceiptlines rl
    JOIN   poultrypurchasereceipts r      ON r.poultrypurchasereceiptid = rl.poultrypurchasereceiptid
    JOIN   poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = rl.poultryrawmaterialpurchaseid
    JOIN   poultryrawmaterialitems i      ON i.poultryrawmaterialitemid = rl.poultryrawmaterialitemid
    WHERE  r.farmid = p_farmid AND rl.poultrypurchasereceiptid = p_receiptid
    ORDER  BY rl.lineno;
$f$;

-- ------------------------------------- 7. existing readers learn reversedat --

-- 7a. Payables: a reversed lot owes nothing; a receipt lot falls due on the
--     receipt's due date and is referenced by its receipt number. Body is the
--     LIVE 238 definition with those two changes only.
CREATE OR REPLACE FUNCTION public.fnpoultrypayables(p_farmid text)
 RETURNS TABLE(documenttype text, documentid integer, supplierid integer, docdate date, label text, reference text, totalcost numeric, amountpaid numeric, balance numeric, cashaccountid integer, duedate date)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT 'RawMaterialPurchase'::text, pu.poultryrawmaterialpurchaseid, pu.supplierid,
           pu.purchasedate::date, COALESCE(i.itemname, 'Raw material')::text,
           -- 345: a receipt's lines are referenced by the receipt.
           COALESCE(rc.receiptnumber, 'P' || pu.poultryrawmaterialpurchaseid::text)::text,
           pu.totalcost, pu.amountpaid,
           GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2),
           pu.poultrycashaccountid,
           rc.duedate                                  -- 345: was NULL::date
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    LEFT   JOIN poultrypurchasereceiptlines rl
           ON rl.poultryrawmaterialpurchaseid = pu.poultryrawmaterialpurchaseid
    LEFT   JOIN poultrypurchasereceipts rc
           ON rc.poultrypurchasereceiptid = rl.poultrypurchasereceiptid
    WHERE  pu.farmid = p_farmid
      AND  pu.reversedat IS NULL                       -- 345
    UNION ALL
    SELECT 'FlockBatch'::text, b.batchid, b.supplierid,
           b.startdate::date, COALESCE(b.batchname, 'Flock batch')::text,
           COALESCE(NULLIF(btrim(b.batchcode), ''), 'B' || b.batchid::text)::text,
           b.totalcost, b.amountpaid,
           GREATEST(b.totalcost - b.amountpaid, 0)::numeric(14,2),
           NULL::integer,
           NULL::date
    FROM   mainflockbatch b
    WHERE  b.farmid = p_farmid
    UNION ALL
    SELECT 'Expense'::text, e.expenseid, e.supplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,
           ('E' || e.expenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid, e.amount)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0)::numeric(14,2),
           e.poultrycashaccountid,
           e.duedate
    FROM   expense e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  e.supplierid IS NOT NULL
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash';
$function$;

-- 7b/7c. Patched in place from the LIVE body, whitespace-tolerant, and loud
--        when the anchor is missing (postgres-sp-gotchas: never silently skip).
DO $p$
DECLARE
    v_def text;
    v_new text;
BEGIN
    -- 7b. Deferred cost: a reversed lot is not awaiting the P&L.
    v_def := pg_get_functiondef('public.fnpoultrydeferredpurchase_rows(text)'::regprocedure);
    IF v_def !~ 'reversedat IS NULL' THEN
        v_new := regexp_replace(v_def,
                    '(\)\s*a\s+ON\s+TRUE\s+WHERE\s+p\.farmid\s*=\s*p_farmid)\s*;',
                    E'\\1\n      AND  p.reversedat IS NULL   -- 345: a reversed receipt''s lot\n;');
        IF v_new = v_def THEN
            RAISE EXCEPTION '345: anchor not found in fnpoultrydeferredpurchase_rows -- the live body has drifted.';
        END IF;
        EXECUTE v_new;
    END IF;

    -- 7c. Closing report: a reversed lot is not a purchase of the period.
    v_def := pg_get_functiondef('public.sppoultryclosingreport_get(text,date,date)'::regprocedure);
    IF v_def !~ 'reversedat IS NULL' THEN
        v_new := regexp_replace(v_def,
                    '(FROM\s+poultryrawmaterialpurchases\s+pu\s+WHERE\s+pu\.farmid\s*=\s*p_farmid\s+AND\s+pu\.purchasedate::date\s+BETWEEN\s+p_fromdate\s+AND\s+p_todate)',
                    E'\\1 AND pu.reversedat IS NULL');
        IF v_new = v_def THEN
            RAISE EXCEPTION '345: anchor not found in sppoultryclosingreport_get -- the live body has drifted.';
        END IF;
        EXECUTE v_new;
    END IF;
END $p$;

-- 7d. Purchase history: same rows (a reversed lot stays visible), plus whether
--     it was reversed and which receipt it belongs to. RETURNS TABLE is part of
--     the signature, so DROP + CREATE. Body is the LIVE 268 definition.
DROP FUNCTION IF EXISTS public.sppoultryrawmaterialpurchase_getall(text, date, date);
CREATE FUNCTION public.sppoultryrawmaterialpurchase_getall(p_farmid text, p_fromdate date DEFAULT NULL::date, p_todate date DEFAULT NULL::date)
 RETURNS TABLE(poultryrawmaterialpurchaseid integer, farmid text, poultryrawmaterialitemid integer, suppliername text, supplierid integer, purchasedate timestamp without time zone, quantity numeric, unitcost numeric, totalcost numeric, productionunit text, productionunitsperpurchaseunit numeric, paymentmethod text, amountpaid numeric, receipturl text, notes text, createdby text, createdat timestamp without time zone, updatedat timestamp without time zone, poultrycashaccountid integer, remainingquantity numeric, sourcefeedproductionbatchid integer, itemname text, category text, unitofmeasure text, balance numeric, productionquantity numeric, productionunitcost numeric, feedproductionbatchnumber text, feedproductionrole text, costrecognitionmethod text, deferredtotalcost numeric, deferredremainingcost numeric, deferredunitcost numeric, costrecognitionstatus text,
               isreversed boolean, reversedat timestamp without time zone, poultrypurchasereceiptid integer, receiptnumber text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.poultryrawmaterialpurchaseid, p.farmid::text, p.poultryrawmaterialitemid, p.suppliername::text,
           p.supplierid, p.purchasedate, p.quantity, p.unitcost, p.totalcost, p.productionunit::text,
           p.productionunitsperpurchaseunit, p.paymentmethod::text, p.amountpaid, p.receipturl::text,
           p.notes::text, p.createdby::text, p.createdat, p.updatedat, p.poultrycashaccountid,
           p.remainingquantity, p.sourcefeedproductionbatchid,
           i.itemname::text, i.category::text, i.unitofmeasure::text,
           -- 345: a reversed lot owes nothing.
           (CASE WHEN p.reversedat IS NOT NULL THEN 0
                 ELSE p.totalcost - p.amountpaid END)::numeric(14,2) AS balance,
           (p.quantity * COALESCE(p.productionunitsperpurchaseunit, 1))::numeric(18,3) AS productionquantity,
           (CASE WHEN COALESCE(p.productionunitsperpurchaseunit, 0) > 0
                 THEN p.totalcost / NULLIF(p.quantity * p.productionunitsperpurchaseunit, 0)
                 ELSE NULL END)::numeric(18,4) AS productionunitcost,
           b.batchnumber::text AS feedproductionbatchnumber,
           (CASE WHEN b.poultryfeedproductionbatchid IS NULL THEN NULL
                 WHEN b.finishedfeeditemid = p.poultryrawmaterialitemid THEN 'Produced'
                 ELSE 'Purchased' END)::text AS feedproductionrole,
           -- 268. The snapshot taken when the lot was created (261/265). It is
           -- deliberately the lot's own value and not today's setting: changing
           -- the farm default must not restate a lot that has already been
           -- expensed.
           p.costrecognitionmethod::text,
           p.deferredtotalcost,
           p.deferredremainingcost,
           fnpoultrylot_deferredunitcost(p.deferredremainingcost, p.remainingquantity,
                                         p.productionunitsperpurchaseunit)::numeric(18,4)
               AS deferredunitcost,
           (CASE
                WHEN p.reversedat IS NOT NULL
                     THEN 'Reversed'                                  -- 345
                WHEN fnpoultrycostrecognition_expenseatpurchase(p.costrecognitionmethod)
                     THEN 'Expensed at purchase'
                WHEN COALESCE(p.deferredremainingcost, 0) > 0
                     THEN 'Deferred - not yet expensed'
                ELSE 'Deferred - fully expensed'
            END)::text AS costrecognitionstatus,
           (p.reversedat IS NOT NULL)                AS isreversed,          -- 345
           p.reversedat,                                                     -- 345
           rl.poultrypurchasereceiptid,                                      -- 345
           rc.receiptnumber::text                                            -- 345
    FROM   poultryrawmaterialpurchases p
    INNER  JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = p.poultryrawmaterialitemid
    LEFT   JOIN poultryfeedproductionbatches b
           ON b.poultryfeedproductionbatchid = p.sourcefeedproductionbatchid
    LEFT   JOIN poultrypurchasereceiptlines rl
           ON rl.poultryrawmaterialpurchaseid = p.poultryrawmaterialpurchaseid
    LEFT   JOIN poultrypurchasereceipts rc
           ON rc.poultrypurchasereceiptid = rl.poultrypurchasereceiptid
    WHERE  p.farmid = p_farmid
       AND (p_fromdate IS NULL OR p.purchasedate::date >= p_fromdate)
       AND (p_todate   IS NULL OR p.purchasedate::date <= p_todate)
    ORDER  BY p.purchasedate DESC, p.poultryrawmaterialpurchaseid DESC;
END;
$function$;

-- ---------------------------------------------------------- 8. permissions ----
-- Its own resource, seeded from the raw-materials grants people already hold
-- (view->view, create->create, delete->approve), the 338 pattern. Reversal is
-- `approve` because ResolveAction maps the /reverse segment there.
DO $iam$
DECLARE
    v_keys  integer := 0;
    v_roles integer := 0;
    v_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '345: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.purchase-receipts.' || a.action, 'poultry', 'purchase-receipts', a.action,
           'Inventory', 'Purchase Receipts',
           'Receiving a supplier invoice in one step: the stock, the payable and any payment '
           || 'made on the spot. Approve covers reversing a receipt.',
           'Poultry', a.action = 'approve', 12
    FROM (VALUES ('view'), ('create'), ('approve')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_keys = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, m.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES
                  ('poultry.raw-materials.view',   'poultry.purchase-receipts.view'),
                  ('poultry.raw-materials.create', 'poultry.purchase-receipts.create'),
                  ('poultry.raw-materials.delete', 'poultry.purchase-receipts.approve')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_roles = ROW_COUNT;
    END IF;

    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 345',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('poultry.raw-materials.view',   'poultry.purchase-receipts.view'),
                  ('poultry.raw-materials.create', 'poultry.purchase-receipts.create'),
                  ('poultry.raw-materials.delete', 'poultry.purchase-receipts.approve')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '345: % catalog key(s), % role grant(s), % user grant(s) added.', v_keys, v_roles, v_users;
END
$iam$;

COMMIT;
