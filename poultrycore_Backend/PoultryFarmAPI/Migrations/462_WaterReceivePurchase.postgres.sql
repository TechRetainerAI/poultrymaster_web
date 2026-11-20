-- =============================================================================
-- 462  Water: Receive Purchase -- one document for a supplier invoice that
--      brings raw materials in                  (Water port of poultry 345)
-- =============================================================================
--
-- A Purchase Receipt is the delivery as ONE document: supplier, date, invoice
-- reference, due date, additional costs (transport, offloading ...), amount
-- paid now and from which account -- plus one line per item.
--
-- IT POSTS NOTHING ITSELF. It orchestrates the functions that already own each
-- effect, so a receipt is, ledger for ledger, the same purchases entered the
-- old way:
--   stock + lot        spwaterrawmaterialpurchase_insert, once per line, with
--                      amountpaid 0 (no expense, no cash -- 275 stamps the
--                      cost-recognition method; this file never decides it);
--   payment + cash     spwatersupplierpayment_record, ONE call per receipt,
--                      allocated across the lines ('ReceivePurchase'). It owns
--                      the allocation rows, each lot's amountpaid, the cash
--                      (with its overdraft guard) and -- 429 -- the P&L's
--                      raw-materials cost on the payment date;
--   payable            fnwaterpayables, live from totalcost - amountpaid.
-- The payment is the ONLY place money moves, so nothing can be counted twice.
--
-- ADDITIONAL COSTS are spread over the lines by line value (by quantity when
-- every line is free); the last line takes the rounding pennies, so
-- SUM(lot.totalcost) = receipt total exactly.
--
-- APPEND-ONLY REVERSAL. Nothing is deleted:
--   * the receipt's own payment is reversed by spwatersupplierpayment_reverse
--     (421/W0: the CashOut stays, a reversal CashIn is added, amountpaid and
--     the payable are restored);
--   * one NEGATIVE 'PurchaseReceiptReversal' adjustment per line through
--     spwaterrawmaterialitem_adjust, so purchases - usage + adjustments
--     (spwaterrawmaterialitem_recalculatestock) still equals stock;
--   * the lot is emptied (remaining 0, deferred remaining 0) and stamped
--     waterrawmaterialpurchases.reversedat; its row stays for history.
-- REFUSED (spwaterpurchasereceipt_reversalblockers says why) when stock has
-- been drawn from a lot, the item's stock is below what the receipt added,
-- another supplier payment was applied to it, money is recorded on a lot
-- without a payment behind it, or the receipt's payment is reconciled.
--
-- READERS THAT LEARN ABOUT reversedat
--   fnwaterpayables                 a reversed lot owes nothing; receipt due date
--   fnwaterdeferredpurchase_rows    a reversed lot is not awaiting the P&L
--   spwaterrawmaterialpurchase_getall  + isreversed, receiptnumber
-- Everything else reads quantities or amountpaid, which the reversal sets.
--
-- LOCKS: a receipt's lot cannot be edited (trg_waterrmpurchase_receiptlock)
-- or deleted (FK RESTRICT, and spwaterrawmaterialpurchase_delete says why).
-- Duplicates: clientrequestid (a double-clicked Save returns the first
-- receipt) and one POSTED receipt per supplier invoice reference.
--
-- DEPLOY ORDER: migration, then the Farm API, then the web. Idempotent.
-- Dry-run with database/apply-water-receive-purchase.ps1.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- 1. schema --
ALTER TABLE public.waterrawmaterialpurchases ADD COLUMN IF NOT EXISTS reversedat timestamp NULL;

CREATE TABLE IF NOT EXISTS public.waterpurchasereceipts (
    waterpurchasereceiptid   serial PRIMARY KEY,
    farmid                   text          NOT NULL,
    receiptnumber            text          NOT NULL,
    supplierid               integer       NOT NULL,
    suppliername             text          NULL,
    purchasedate             timestamp     NOT NULL,
    referenceno              text          NULL,
    duedate                  date          NULL,
    notes                    text          NULL,
    subtotal                 numeric(14,2) NOT NULL,
    additionalcosts          numeric(14,2) NOT NULL DEFAULT 0,
    additionalcostsnote      text          NULL,
    totalcost                numeric(14,2) NOT NULL,
    amountpaidatreceipt      numeric(14,2) NOT NULL DEFAULT 0,
    paymentmethod            text          NULL,
    watercashaccountid       integer       NULL,
    watersupplierpaymentid   integer       NULL,
    status                   text          NOT NULL DEFAULT 'Posted',
    clientrequestid          uuid          NULL,
    createdby                text          NULL,
    createdat                timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby               text          NULL,
    reversedat               timestamp     NULL,
    reversalreason           text          NULL,
    CONSTRAINT ck_waterpurchasereceipts_status  CHECK (status IN ('Posted', 'Reversed')),
    CONSTRAINT ck_waterpurchasereceipts_amounts CHECK (subtotal >= 0 AND additionalcosts >= 0 AND totalcost > 0
                                                       AND totalcost = subtotal + additionalcosts),
    CONSTRAINT ck_waterpurchasereceipts_paid    CHECK (amountpaidatreceipt >= 0 AND amountpaidatreceipt <= totalcost)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterpurchasereceipts_number  ON public.waterpurchasereceipts (farmid, receiptnumber);
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterpurchasereceipts_request ON public.waterpurchasereceipts (farmid, clientrequestid)
    WHERE clientrequestid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterpurchasereceipts_invoice ON public.waterpurchasereceipts (farmid, supplierid, lower(btrim(referenceno)))
    WHERE status = 'Posted' AND NULLIF(btrim(referenceno), '') IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_waterpurchasereceipts_date ON public.waterpurchasereceipts (farmid, purchasedate DESC);

CREATE TABLE IF NOT EXISTS public.waterpurchasereceiptlines (
    waterpurchasereceiptlineid     serial PRIMARY KEY,
    waterpurchasereceiptid         integer       NOT NULL REFERENCES public.waterpurchasereceipts (waterpurchasereceiptid) ON DELETE RESTRICT,
    farmid                         text          NOT NULL,
    lineno                         integer       NOT NULL,
    waterrawmaterialitemid         integer       NOT NULL REFERENCES public.waterrawmaterialitems (waterrawmaterialitemid),
    quantity                       numeric(14,3) NOT NULL,
    unitcost                       numeric(14,2) NOT NULL,
    linesubtotal                   numeric(14,2) NOT NULL,
    allocatedadditionalcost        numeric(14,2) NOT NULL DEFAULT 0,
    linetotal                      numeric(14,2) NOT NULL,
    productionunit                 text          NULL,
    productionunitsperpurchaseunit numeric(18,8) NULL,
    notes                          text          NULL,
    waterrawmaterialpurchaseid     integer       NOT NULL REFERENCES public.waterrawmaterialpurchases (waterrawmaterialpurchaseid) ON DELETE RESTRICT,
    reversaladjustmentid           integer       NULL,
    CONSTRAINT ck_waterpurchasereceiptlines_qty   CHECK (quantity > 0 AND unitcost >= 0),
    CONSTRAINT ck_waterpurchasereceiptlines_total CHECK (allocatedadditionalcost >= 0 AND linetotal = linesubtotal + allocatedadditionalcost),
    CONSTRAINT ux_waterpurchasereceiptlines_lineno UNIQUE (waterpurchasereceiptid, lineno),
    CONSTRAINT ux_waterpurchasereceiptlines_lot    UNIQUE (waterrawmaterialpurchaseid)
);

-- ------------------------------------------------ 2. the lot lock (trigger) --
CREATE OR REPLACE FUNCTION public.trg_waterrmpurchase_receiptlock_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE v_number text;
BEGIN
    IF  NEW.farmid                         IS NOT DISTINCT FROM OLD.farmid
    AND NEW.waterrawmaterialitemid         IS NOT DISTINCT FROM OLD.waterrawmaterialitemid
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
    FROM   public.waterpurchasereceiptlines l
    JOIN   public.waterpurchasereceipts r ON r.waterpurchasereceiptid = l.waterpurchasereceiptid
    WHERE  l.waterrawmaterialpurchaseid = OLD.waterrawmaterialpurchaseid
    LIMIT  1;
    IF v_number IS NOT NULL THEN
        RAISE EXCEPTION 'This stock lot belongs to purchase receipt % and cannot be edited on its own. Reverse the receipt and receive it again instead.', v_number;
    END IF;
    RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS trg_waterrmpurchase_receiptlock ON public.waterrawmaterialpurchases;
CREATE TRIGGER trg_waterrmpurchase_receiptlock
    BEFORE UPDATE ON public.waterrawmaterialpurchases
    FOR EACH ROW EXECUTE FUNCTION public.trg_waterrmpurchase_receiptlock_fn();

-- ------------------------------------------------------------- 3. post -----
DO $d$ DECLARE r record; BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND p.proname IN ('spwaterpurchasereceipt_post', 'spwaterpurchasereceipt_reversalblockers',
                                 'spwaterpurchasereceipt_reverse', 'spwaterpurchasereceipt_getall',
                                 'spwaterpurchasereceipt_getlines', 'spwaterrawmaterialpurchase_getall')
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig; END LOOP;
END $d$;

CREATE FUNCTION public.spwaterpurchasereceipt_post(
    p_farmid text, p_supplierid integer, p_purchasedate timestamp, p_referenceno text, p_duedate date,
    p_notes text, p_lines jsonb, p_additionalcosts numeric DEFAULT 0, p_additionalcostsnote text DEFAULT NULL,
    p_amountpaid numeric DEFAULT 0, p_paymentmethod text DEFAULT NULL, p_cashaccountid integer DEFAULT NULL,
    p_clientrequestid uuid DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_type     text;
    v_existing integer;
    v_supname  text;
    v_date     timestamp;
    v_today    date;
    v_ref      text := NULLIF(btrim(p_referenceno), '');
    v_dup      record;
    v_count    integer;
    v_subtotal numeric(14,2);
    v_add      numeric(14,2) := round(COALESCE(p_additionalcosts, 0), 2);
    v_total    numeric(14,2);
    v_paid     numeric(14,2) := round(COALESCE(p_amountpaid, 0), 2);
    v_weight   numeric;
    v_alloc    numeric(14,2);
    v_left     numeric(14,2);
    v_id       integer;
    v_number   text;
    v_lot      integer;
    v_unit     numeric(14,2);
    v_allocs   jsonb := '[]'::jsonb;
    v_payid    integer;
    v_due      date := p_duedate;
    v_method   text := CASE WHEN round(COALESCE(p_amountpaid, 0), 2) > 0
                            THEN COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash') ELSE 'Credit' END;
    l          record;
BEGIN
    IF COALESCE(btrim(p_farmid), '') = '' THEN RAISE EXCEPTION 'Company is required.'; END IF;
    IF COALESCE(btrim(p_createdby), '') = '' THEN RAISE EXCEPTION 'The user receiving the purchase is required.'; END IF;
    v_type := spfarm_gettype(p_farmid);
    IF lower(COALESCE(v_type, '')) <> 'water' THEN
        RAISE EXCEPTION 'This Receive Purchase is for Water companies (this company is %).', COALESCE(v_type, 'unknown');
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('waterpurchasereceipt:' || lower(p_farmid)));

    IF p_clientrequestid IS NOT NULL THEN
        SELECT r.waterpurchasereceiptid INTO v_existing FROM waterpurchasereceipts r
        WHERE  r.farmid = p_farmid AND r.clientrequestid = p_clientrequestid LIMIT 1;
        IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;   -- the same Save, sent twice
    END IF;

    SELECT s.suppliername INTO v_supname FROM watersuppliers s
    WHERE  s.watersupplierid = p_supplierid AND s.farmid = p_farmid AND NOT COALESCE(s.isdeleted, FALSE);
    IF v_supname IS NULL THEN RAISE EXCEPTION 'Choose the supplier you bought from.'; END IF;

    v_today := fncompany_businessdate(p_farmid);
    v_date  := COALESCE(p_purchasedate, v_today::timestamp);
    IF v_date::date > v_today THEN
        RAISE EXCEPTION 'The purchase date (%) is in the future. Goods can only be received on or before today (%).', v_date::date, v_today;
    END IF;

    IF v_ref IS NOT NULL THEN
        SELECT r.receiptnumber, r.purchasedate INTO v_dup FROM waterpurchasereceipts r
        WHERE  r.farmid = p_farmid AND r.supplierid = p_supplierid AND r.status = 'Posted'
          AND  lower(btrim(r.referenceno)) = lower(v_ref) LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'Invoice "%" from % was already received as % on %. Reverse that receipt first if it was wrong.',
                  v_ref, v_supname, v_dup.receiptnumber, v_dup.purchasedate::date;
        END IF;
    END IF;

    -- Lowercase keys on purpose: jsonb ->> is case-sensitive and the API sends these names.
    DROP TABLE IF EXISTS tmp_wreceipt_lines;
    CREATE TEMP TABLE tmp_wreceipt_lines ON COMMIT DROP AS
    SELECT e.n::integer AS lineno,
           NULLIF(e.v ->> 'itemid', '')::integer AS itemid,
           NULLIF(e.v ->> 'quantity', '')::numeric AS quantity,
           NULLIF(e.v ->> 'unitcost', '')::numeric AS unitcost,
           NULLIF(btrim(e.v ->> 'productionunit'), '') AS productionunit,
           NULLIF(e.v ->> 'productionunitsperpurchaseunit', '')::numeric AS mult,
           NULLIF(btrim(e.v ->> 'notes'), '') AS notes,
           NULL::numeric(14,2) AS subtotal, 0::numeric(14,2) AS allocated, NULL::numeric(14,2) AS linetotal
    FROM   jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) WITH ORDINALITY AS e(v, n);

    SELECT COUNT(*) INTO v_count FROM tmp_wreceipt_lines;
    IF v_count = 0 THEN RAISE EXCEPTION 'Add at least one item to the receipt.'; END IF;
    IF v_count > 50 THEN
        RAISE EXCEPTION 'A receipt can hold at most 50 lines (this one has %). Split the invoice into two receipts.', v_count;
    END IF;

    FOR l IN SELECT * FROM tmp_wreceipt_lines ORDER BY lineno LOOP
        IF l.itemid IS NULL THEN RAISE EXCEPTION 'Line %: choose an item.', l.lineno; END IF;
        IF NOT EXISTS (SELECT 1 FROM waterrawmaterialitems i WHERE i.waterrawmaterialitemid = l.itemid AND i.farmid = p_farmid) THEN
            RAISE EXCEPTION 'Line %: that item does not belong to this company.', l.lineno;
        END IF;
        IF EXISTS (SELECT 1 FROM waterrawmaterialitems i WHERE i.waterrawmaterialitemid = l.itemid AND NOT COALESCE(i.isactive, TRUE)) THEN
            RAISE EXCEPTION 'Line %: % is inactive. Reactivate it before receiving it.',
                  l.lineno, (SELECT i.itemname FROM waterrawmaterialitems i WHERE i.waterrawmaterialitemid = l.itemid);
        END IF;
        IF l.quantity IS NULL OR l.quantity <= 0 THEN RAISE EXCEPTION 'Line %: quantity must be greater than 0.', l.lineno; END IF;
        IF round(l.quantity, 3) <> l.quantity THEN RAISE EXCEPTION 'Line %: quantity can have at most 3 decimal places.', l.lineno; END IF;
        IF l.unitcost IS NULL OR l.unitcost < 0 THEN RAISE EXCEPTION 'Line %: unit cost cannot be negative.', l.lineno; END IF;
        IF l.mult IS NOT NULL AND l.mult <= 0 THEN RAISE EXCEPTION 'Line %: units per purchase unit must be greater than 0.', l.lineno; END IF;
    END LOOP;

    UPDATE tmp_wreceipt_lines t SET subtotal = round(t.quantity * t.unitcost, 2);
    SELECT COALESCE(SUM(t.subtotal), 0) INTO v_subtotal FROM tmp_wreceipt_lines t;
    IF v_add < 0 THEN RAISE EXCEPTION 'Additional costs cannot be negative.'; END IF;
    v_total := v_subtotal + v_add;
    IF v_total <= 0 THEN RAISE EXCEPTION 'The receipt total must be greater than 0.'; END IF;

    IF v_add > 0 THEN
        SELECT CASE WHEN v_subtotal > 0 THEN v_subtotal ELSE SUM(t.quantity) END INTO v_weight FROM tmp_wreceipt_lines t;
        v_left := v_add;
        FOR l IN SELECT * FROM tmp_wreceipt_lines ORDER BY lineno LOOP
            IF l.lineno = (SELECT MAX(t.lineno) FROM tmp_wreceipt_lines t) THEN
                v_alloc := v_left;
            ELSE
                v_alloc := LEAST(round(v_add * (CASE WHEN v_subtotal > 0 THEN l.subtotal ELSE l.quantity END) / v_weight, 2), v_left);
            END IF;
            UPDATE tmp_wreceipt_lines t SET allocated = v_alloc WHERE t.lineno = l.lineno;
            v_left := v_left - v_alloc;
        END LOOP;
    END IF;
    UPDATE tmp_wreceipt_lines t SET linetotal = t.subtotal + t.allocated;

    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > v_total THEN RAISE EXCEPTION 'Amount paid (%) is more than the purchase total (%).', v_paid, v_total; END IF;
    IF v_paid > 0 AND p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Choose the cash account the payment came from.'; END IF;
    IF v_paid >= v_total THEN
        v_due := NULL;
    ELSIF v_due IS NOT NULL AND v_due < v_date::date THEN
        RAISE EXCEPTION 'The due date (%) cannot be before the purchase date (%).', v_due, v_date::date;
    END IF;

    SELECT 'RCV-' || lpad((COALESCE(MAX(NULLIF(substring(r.receiptnumber FROM '^RCV-(\d+)$'), '')::integer), 0) + 1)::text, 5, '0')
    INTO   v_number FROM waterpurchasereceipts r WHERE r.farmid = p_farmid;

    INSERT INTO waterpurchasereceipts
        (farmid, receiptnumber, supplierid, suppliername, purchasedate, referenceno, duedate, notes,
         subtotal, additionalcosts, additionalcostsnote, totalcost, amountpaidatreceipt,
         paymentmethod, watercashaccountid, status, clientrequestid, createdby)
    VALUES
        (p_farmid, v_number, p_supplierid, v_supname, v_date, v_ref, v_due, NULLIF(btrim(p_notes), ''),
         v_subtotal, v_add, NULLIF(btrim(p_additionalcostsnote), ''), v_total, v_paid,
         v_method, CASE WHEN v_paid > 0 THEN p_cashaccountid END, 'Posted', p_clientrequestid, p_createdby)
    RETURNING waterpurchasereceiptid INTO v_id;

    FOR l IN SELECT * FROM tmp_wreceipt_lines ORDER BY lineno LOOP
        v_unit := CASE WHEN l.allocated = 0 THEN l.unitcost ELSE round(l.linetotal / l.quantity, 2) END;
        v_lot := spwaterrawmaterialpurchase_insert(
            p_farmid                         => p_farmid,
            p_waterrawmaterialitemid         => l.itemid,
            p_suppliername                   => v_supname,
            p_purchasedate                   => v_date,
            p_quantity                       => l.quantity,
            p_unitcost                       => v_unit,
            p_paymentmethod                  => v_method,
            p_amountpaid                     => 0,      -- money moves ONLY through the payment below
            p_receipturl                     => NULL,
            p_receivedbystaffid              => NULL,
            p_notes                          => left(concat_ws(' | ', 'Receipt ' || v_number,
                                                               CASE WHEN v_ref IS NOT NULL THEN 'Invoice ' || v_ref END, l.notes), 500),
            p_createdby                      => p_createdby,
            p_supplierid                     => p_supplierid,
            p_totalcost                      => l.linetotal,
            p_watercashaccountid             => NULL,
            p_productionunit                 => l.productionunit,
            p_productionunitsperpurchaseunit => l.mult);

        INSERT INTO waterpurchasereceiptlines
            (waterpurchasereceiptid, farmid, lineno, waterrawmaterialitemid, quantity, unitcost,
             linesubtotal, allocatedadditionalcost, linetotal, productionunit,
             productionunitsperpurchaseunit, notes, waterrawmaterialpurchaseid)
        VALUES
            (v_id, p_farmid, l.lineno, l.itemid, l.quantity, l.unitcost,
             l.subtotal, l.allocated, l.linetotal, l.productionunit, l.mult, l.notes, v_lot);
    END LOOP;

    IF v_paid > 0 THEN
        v_left := v_paid;
        FOR l IN SELECT rl.waterrawmaterialpurchaseid AS lot, rl.linetotal
                 FROM   waterpurchasereceiptlines rl
                 WHERE  rl.waterpurchasereceiptid = v_id AND rl.linetotal > 0
                 ORDER  BY rl.lineno LOOP
            EXIT WHEN v_left <= 0;
            v_alloc := LEAST(v_left, l.linetotal);
            v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
                'documenttype', 'RawMaterialPurchase', 'documentid', l.lot, 'amount', v_alloc));
            v_left := v_left - v_alloc;
        END LOOP;

        v_payid := spwatersupplierpayment_record(
            p_farmid        => p_farmid,
            p_supplierid    => p_supplierid,
            p_amount        => v_paid,
            p_allocations   => v_allocs,
            p_paymentmethod => v_method,
            p_paymentdate   => v_date,
            p_cashaccountid => p_cashaccountid,
            p_reference     => COALESCE(v_ref, v_number),
            p_note          => 'Paid on purchase receipt ' || v_number,
            p_sourcetype    => 'ReceivePurchase',
            p_createdby     => p_createdby);

        UPDATE waterpurchasereceipts r SET watersupplierpaymentid = v_payid WHERE r.waterpurchasereceiptid = v_id;
    END IF;

    RETURN v_id;
END $f$;

-- ------------------------------------------------- 4. reversal blockers ------
CREATE FUNCTION public.spwaterpurchasereceipt_reversalblockers(p_farmid text, p_receiptid integer)
RETURNS TABLE(code text, message text)
LANGUAGE plpgsql STABLE AS $f$
DECLARE v_r record;
BEGIN
    SELECT r.* INTO v_r FROM waterpurchasereceipts r
    WHERE  r.waterpurchasereceiptid = p_receiptid AND r.farmid = p_farmid;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'NotFound'::text, 'Purchase receipt not found for this company.'::text;
        RETURN;
    END IF;
    IF v_r.status = 'Reversed' THEN
        RETURN QUERY SELECT 'AlreadyReversed'::text, ('Receipt ' || v_r.receiptnumber || ' was already reversed.')::text;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT 'Consumed'::text,
           (i.itemname || ': ' || rtrim(to_char(pu.quantity - pu.remainingquantity, 'FM999999990.###'), '.') || ' of ' ||
            rtrim(to_char(pu.quantity, 'FM999999990.###'), '.') ||
            ' has already been used. Reverse the production batch or usage that drew it first.')::text
    FROM   waterpurchasereceiptlines rl
    JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
    JOIN   waterrawmaterialitems i      ON i.waterrawmaterialitemid = pu.waterrawmaterialitemid
    WHERE  rl.waterpurchasereceiptid = p_receiptid
      AND  (pu.remainingquantity + 0.0005 < pu.quantity
            OR COALESCE(pu.deferredremainingcost, 0) + 0.005 < COALESCE(pu.deferredtotalcost, 0))
    ORDER  BY rl.lineno;

    RETURN QUERY
    SELECT 'StockShort'::text,
           (i.itemname || ': only ' || rtrim(to_char(i.currentquantity, 'FM999999990.###'), '.') || ' ' ||
            COALESCE(i.unitofmeasure, '') || ' is in stock, but this receipt added ' ||
            rtrim(to_char(s.qty, 'FM999999990.###'), '.') ||
            '. Stock was taken out by internal use or an adjustment, so reversing would leave it negative.')::text
    FROM  (SELECT pu.waterrawmaterialitemid AS itemid,
                  SUM(pu.quantity * COALESCE(NULLIF(pu.productionunitsperpurchaseunit, 0), 1)) AS qty
           FROM   waterpurchasereceiptlines rl
           JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
           WHERE  rl.waterpurchasereceiptid = p_receiptid
           GROUP  BY pu.waterrawmaterialitemid) s
    JOIN   waterrawmaterialitems i ON i.waterrawmaterialitemid = s.itemid AND i.farmid = p_farmid
    WHERE  i.currentquantity + 0.0005 < s.qty;

    RETURN QUERY
    SELECT DISTINCT 'OtherPayment'::text,
           ('Supplier payment #' || sp.watersupplierpaymentid::text || ' (' ||
            trim(to_char(sp.totalamount, 'FM999999990.00')) || ' on ' || to_char(sp.paymentdate, 'YYYY-MM-DD') ||
            ') was applied to this receipt. Reverse it from Supplier Payments first.')::text
    FROM   waterpurchasereceiptlines rl
    JOIN   supplierpaymentallocation sa
           ON  sa.documentid = rl.waterrawmaterialpurchaseid AND sa.documenttype = 'RawMaterialPurchase'
           AND sa.module = 'water' AND sa.farmid = p_farmid AND sa.status = 'Posted'
    JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid AND sp.farmid = p_farmid
    WHERE  rl.waterpurchasereceiptid = p_receiptid
      AND  sa.paymentid IS DISTINCT FROM v_r.watersupplierpaymentid;

    RETURN QUERY
    SELECT 'UntrackedPayment'::text,
           (i.itemname || ': ' || trim(to_char(pu.amountpaid - COALESCE(a.amt, 0), 'FM999999990.00')) ||
            ' is recorded as paid without a supplier payment behind it. Check the purchase before reversing.')::text
    FROM   waterpurchasereceiptlines rl
    JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
    JOIN   waterrawmaterialitems i      ON i.waterrawmaterialitemid = pu.waterrawmaterialitemid
    LEFT   JOIN LATERAL (
               SELECT SUM(sa.amountapplied) AS amt FROM supplierpaymentallocation sa
               WHERE  sa.documentid = pu.waterrawmaterialpurchaseid AND sa.documenttype = 'RawMaterialPurchase'
                 AND  sa.module = 'water' AND sa.farmid = p_farmid AND sa.status = 'Posted') a ON TRUE
    WHERE  rl.waterpurchasereceiptid = p_receiptid
      AND  pu.amountpaid > COALESCE(a.amt, 0) + 0.005;

    IF v_r.watersupplierpaymentid IS NOT NULL THEN
        RETURN QUERY
        SELECT 'Reconciled'::text,
               ('The payment made on this receipt is part of a cash reconciliation on ' ||
                COALESCE(a.accountname, 'its cash account') ||
                '. Un-clear it on Cash Reconciliation before reversing the receipt.')::text
        FROM   watercashtransactions ct
        LEFT   JOIN watercashaccounts a ON a.watercashaccountid = ct.watercashaccountid
        WHERE  ct.farmid = p_farmid
          AND  (ct.clearingstatus = 'Cleared' OR ct.watercashreconciliationid IS NOT NULL)
          AND  (   (ct.sourcetype = 'WaterSupplierPayment' AND ct.sourceid = v_r.watersupplierpaymentid)
                OR (ct.sourcetype = 'Expense' AND ct.sourceid IN (
                        SELECT e.waterexpenseid FROM waterexpenses e
                        WHERE  e.farmid = p_farmid AND e.sourcetype = 'WaterSupplierPayment'
                          AND  e.sourceid = v_r.watersupplierpaymentid)))
          AND  EXISTS (SELECT 1 FROM watersupplierpayments sp
                       WHERE sp.watersupplierpaymentid = v_r.watersupplierpaymentid AND sp.status = 'Posted')
        LIMIT  1;
    END IF;
END $f$;

-- ------------------------------------------------------------ 5. reverse ------
CREATE FUNCTION public.spwaterpurchasereceipt_reverse(p_farmid text, p_receiptid integer, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_r      record;
    v_block  text;
    v_status text;
    v_adjid  integer;
    v_count  integer := 0;
    v_left   numeric;
    l        record;
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Give a reason for reversing this receipt.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('waterpurchasereceipt:' || lower(p_farmid)));
    SELECT r.* INTO v_r FROM waterpurchasereceipts r
    WHERE  r.waterpurchasereceiptid = p_receiptid AND r.farmid = p_farmid
    FOR UPDATE;

    SELECT b.message INTO v_block FROM spwaterpurchasereceipt_reversalblockers(p_farmid, p_receiptid) b LIMIT 1;
    IF v_block IS NOT NULL THEN RAISE EXCEPTION '%', v_block; END IF;

    -- 1. Money: the receipt's own payment (it may already have been reversed
    --    from Supplier Payments -- then there is nothing to undo here).
    IF v_r.watersupplierpaymentid IS NOT NULL THEN
        SELECT sp.status INTO v_status FROM watersupplierpayments sp
        WHERE  sp.watersupplierpaymentid = v_r.watersupplierpaymentid AND sp.farmid = p_farmid;
        IF COALESCE(v_status, 'Posted') = 'Posted' THEN
            PERFORM spwatersupplierpayment_reverse(
                p_farmid, v_r.watersupplierpaymentid,
                'Purchase receipt ' || v_r.receiptnumber || ' reversed: ' || btrim(p_reason), p_reversedby);
        END IF;
    END IF;

    SELECT COALESCE(SUM(pu.amountpaid), 0) INTO v_left
    FROM   waterpurchasereceiptlines rl
    JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
    WHERE  rl.waterpurchasereceiptid = p_receiptid;
    IF v_left > 0.005 THEN
        RAISE EXCEPTION 'Reversing the payment left % still recorded as paid on this receipt. Nothing was changed.', v_left;
    END IF;

    -- 2. Stock: an opposite adjustment per line, then the lot emptied. Rows kept.
    FOR l IN SELECT rl.waterpurchasereceiptlineid AS lineid, pu.*
             FROM   waterpurchasereceiptlines rl
             JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
             WHERE  rl.waterpurchasereceiptid = p_receiptid
             ORDER  BY rl.lineno LOOP
        SELECT a.waterrawmaterialadjustmentid INTO v_adjid
        FROM   spwaterrawmaterialitem_adjust(
                   p_farmid, l.waterrawmaterialitemid,
                   -(l.quantity * COALESCE(NULLIF(l.productionunitsperpurchaseunit, 0), 1)),
                   l.unitcost, 'PurchaseReceiptReversal',
                   left('Reversal of purchase receipt ' || v_r.receiptnumber || ': ' || btrim(p_reason), 500),
                   p_reversedby) a;

        UPDATE waterrawmaterialpurchases pu
        SET    remainingquantity = 0, deferredremainingcost = 0,
               reversedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc')
        WHERE  pu.waterrawmaterialpurchaseid = l.waterrawmaterialpurchaseid;

        UPDATE waterpurchasereceiptlines rl SET reversaladjustmentid = v_adjid WHERE rl.waterpurchasereceiptlineid = l.lineid;
        v_count := v_count + 1;
    END LOOP;

    UPDATE waterpurchasereceipts r
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() at time zone 'utc'), reversalreason = btrim(p_reason)
    WHERE  r.waterpurchasereceiptid = p_receiptid;
    RETURN v_count;
END $f$;

-- ------------------------------------------------------------ 6. readers ------
CREATE FUNCTION public.spwaterpurchasereceipt_getall(
    p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL,
    p_status text DEFAULT NULL, p_receiptid integer DEFAULT NULL)
RETURNS TABLE(waterpurchasereceiptid integer, receiptnumber text, supplierid integer, suppliername text,
              purchasedate timestamp, referenceno text, duedate date, notes text,
              subtotal numeric, additionalcosts numeric, additionalcostsnote text, totalcost numeric,
              amountpaidatreceipt numeric, amountpaid numeric, balance numeric, paymentstatus text,
              isoverdue boolean, paymentmethod text, watercashaccountid integer, cashaccountname text,
              watersupplierpaymentid integer, status text, linecount integer, itemsummary text,
              expensedatpurchasecost numeric, deferredcost numeric,
              createdby text, createdat timestamp, reversedby text, reversedat timestamp, reversalreason text,
              reversalblocker text)
LANGUAGE sql STABLE AS $f$
    SELECT r.waterpurchasereceiptid, r.receiptnumber, r.supplierid,
           COALESCE(s.suppliername, r.suppliername)::text,
           r.purchasedate, r.referenceno, r.duedate, r.notes,
           r.subtotal, r.additionalcosts, r.additionalcostsnote, r.totalcost,
           r.amountpaidatreceipt,
           (CASE WHEN r.status = 'Reversed' THEN 0 ELSE COALESCE(x.paid, 0) END)::numeric(14,2),
           (CASE WHEN r.status = 'Reversed' THEN 0 ELSE r.totalcost - COALESCE(x.paid, 0) END)::numeric(14,2),
           (CASE WHEN r.status = 'Reversed'                      THEN 'Reversed'
                 WHEN COALESCE(x.paid, 0) >= r.totalcost - 0.005 THEN 'Paid'
                 WHEN COALESCE(x.paid, 0) > 0                    THEN 'Part paid'
                 ELSE 'Unpaid' END)::text,
           (r.status = 'Posted' AND COALESCE(x.paid, 0) < r.totalcost - 0.005
            AND COALESCE(r.duedate, r.purchasedate::date + COALESCE(s.paymenttermsdays, 0)) < fncompany_businessdate(r.farmid)),
           r.paymentmethod, r.watercashaccountid, a.accountname::text,
           r.watersupplierpaymentid, r.status,
           COALESCE(x.lines, 0)::integer, x.items,
           COALESCE(x.ewp, 0)::numeric(14,2), COALESCE(x.ewc, 0)::numeric(14,2),
           r.createdby, r.createdat, r.reversedby, r.reversedat, r.reversalreason,
           (CASE WHEN r.status = 'Posted' THEN
                (SELECT b.message FROM spwaterpurchasereceipt_reversalblockers(r.farmid, r.waterpurchasereceiptid) b LIMIT 1)
            END)::text
    FROM   waterpurchasereceipts r
    LEFT   JOIN watersuppliers s ON s.watersupplierid = r.supplierid AND s.farmid = r.farmid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = r.watercashaccountid AND a.farmid = r.farmid
    LEFT   JOIN LATERAL (
               SELECT SUM(pu.amountpaid) AS paid, COUNT(*) AS lines,
                      string_agg(i.itemname, ', ' ORDER BY rl.lineno) AS items,
                      SUM(rl.linetotal) FILTER (WHERE fnwatercostrecognition_expenseatpurchase(pu.costrecognitionmethod))     AS ewp,
                      SUM(rl.linetotal) FILTER (WHERE NOT fnwatercostrecognition_expenseatpurchase(pu.costrecognitionmethod)) AS ewc
               FROM   waterpurchasereceiptlines rl
               JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
               JOIN   waterrawmaterialitems i      ON i.waterrawmaterialitemid = rl.waterrawmaterialitemid
               WHERE  rl.waterpurchasereceiptid = r.waterpurchasereceiptid) x ON TRUE
    WHERE  r.farmid = p_farmid
      AND  (p_receiptid IS NULL OR r.waterpurchasereceiptid = p_receiptid)
      AND  (p_fromdate IS NULL OR r.purchasedate::date >= p_fromdate)
      AND  (p_todate   IS NULL OR r.purchasedate::date <= p_todate)
      AND  (p_status IS NULL OR p_status = '' OR p_status = 'All' OR r.status = p_status)
    ORDER  BY r.purchasedate DESC, r.waterpurchasereceiptid DESC;
$f$;

CREATE FUNCTION public.spwaterpurchasereceipt_getlines(p_farmid text, p_receiptid integer)
RETURNS TABLE(waterpurchasereceiptlineid integer, lineno integer, waterrawmaterialitemid integer,
              itemname text, category text, unitofmeasure text,
              quantity numeric, unitcost numeric, linesubtotal numeric, allocatedadditionalcost numeric,
              linetotal numeric, landedunitcost numeric, productionunit text,
              productionunitsperpurchaseunit numeric, productionquantity numeric, notes text,
              waterrawmaterialpurchaseid integer, costrecognitionmethod text, recognitionlabel text,
              remainingquantity numeric, consumedquantity numeric, amountpaid numeric, balance numeric,
              deferredremainingcost numeric, reversaladjustmentid integer)
LANGUAGE sql STABLE AS $f$
    SELECT rl.waterpurchasereceiptlineid, rl.lineno, rl.waterrawmaterialitemid,
           i.itemname::text, i.category::text, i.unitofmeasure::text,
           rl.quantity, rl.unitcost, rl.linesubtotal, rl.allocatedadditionalcost, rl.linetotal,
           pu.unitcost, rl.productionunit, rl.productionunitsperpurchaseunit,
           (rl.quantity * COALESCE(NULLIF(rl.productionunitsperpurchaseunit, 0), 1))::numeric(18,3),
           rl.notes, rl.waterrawmaterialpurchaseid, pu.costrecognitionmethod::text,
           (CASE WHEN fnwatercostrecognition_expenseatpurchase(pu.costrecognitionmethod)
                 THEN 'Expensed as paid' ELSE 'Expensed when used' END)::text,
           pu.remainingquantity,
           (CASE WHEN pu.reversedat IS NULL THEN pu.quantity - pu.remainingquantity ELSE 0 END)::numeric(14,3),
           pu.amountpaid,
           (CASE WHEN pu.reversedat IS NULL THEN GREATEST(pu.totalcost - pu.amountpaid, 0) ELSE 0 END)::numeric(14,2),
           pu.deferredremainingcost, rl.reversaladjustmentid
    FROM   waterpurchasereceiptlines rl
    JOIN   waterpurchasereceipts r      ON r.waterpurchasereceiptid = rl.waterpurchasereceiptid
    JOIN   waterrawmaterialpurchases pu ON pu.waterrawmaterialpurchaseid = rl.waterrawmaterialpurchaseid
    JOIN   waterrawmaterialitems i      ON i.waterrawmaterialitemid = rl.waterrawmaterialitemid
    WHERE  r.farmid = p_farmid AND rl.waterpurchasereceiptid = p_receiptid
    ORDER  BY rl.lineno;
$f$;

-- ------------------------------------- 7. existing readers learn reversedat --
-- Each is the live body (pg_get_functiondef, 2026-11-20) with only the marked
-- 462 change.

-- 462: payables skip reversed lots.
CREATE OR REPLACE FUNCTION public.fnwaterpayables(p_farmid text)
 RETURNS TABLE(documenttype text, documentid integer, supplierid integer, docdate date, label text, reference text, totalcost numeric, amountpaid numeric, balance numeric, cashaccountid integer, duedate date)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT 'RawMaterialPurchase'::text, pu.waterrawmaterialpurchaseid, pu.supplierid,
           pu.purchasedate::date,
           COALESCE(i.itemname, pu.suppliername, 'Raw material')::text,
           ('P' || pu.waterrawmaterialpurchaseid::text)::text,
           pu.totalcost, pu.amountpaid,
           GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2),
           -- Always NULL: unlike poultryrawmaterialpurchases, the water table
           -- has no cash account column -- WaterRawMaterialPurchaseModel
           -- exposes one, but it is a projection, not storage.
           NULL::integer,
           NULL::date
    FROM   waterrawmaterialpurchases pu
    LEFT   JOIN waterrawmaterialitems i
           ON i.waterrawmaterialitemid = pu.waterrawmaterialitemid
    WHERE  pu.farmid = p_farmid
      AND  COALESCE(pu.lotsource, '') <> 'ManualDeferredCost'   -- 426: nothing is owed on it
      AND  pu.reversedat IS NULL                                -- 462: a reversed receipt's lot owes nothing
    UNION ALL
    SELECT 'Expense'::text, e.waterexpenseid, e.supplierid,
           e.expensedate::date,
           COALESCE(NULLIF(btrim(e.description), ''), c.name, 'Expense')::text,
           ('E' || e.waterexpenseid::text)::text,
           COALESCE(e.amount, 0)::numeric(14,2),
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END)::numeric(14,2),
           GREATEST(COALESCE(e.amount, 0)
                    - COALESCE(e.amountpaid,
                               CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                    THEN 0 ELSE e.amount END), 0)::numeric(14,2),
           e.watercashaccountid,
           e.duedate
    FROM   waterexpenses e
    LEFT   JOIN waterexpensecategories c
           ON c.waterexpensecategoryid = e.waterexpensecategoryid
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  e.supplierid IS NOT NULL
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      -- 047: only an approved expense has been recognised at all. A Draft is
      -- not yet a debt.
      AND  COALESCE(e.status, '') = 'Approved'
      -- 240: only bills a person typed in are payable; anything with a
      -- sourcetype is another document's shadow. 283 adds the one real
      -- exception -- a capital asset bought on credit is a debt to a supplier,
      -- not the shadow of another document, and neither of these two
      -- sourcetypes is ever generated BY a payment, so the recursion 240 was
      -- guarding against cannot return through here.
      AND  (e.sourcetype IS NULL
            OR e.sourcetype IN ('CapitalAsset', 'CapitalAssetCost'))
    UNION ALL
    -- 424: what the business owes a supplier without a purchase here
    SELECT 'SupplierDebt'::text, d.debtid, d.supplierid, d.debtdate,
           ('Debt ' || d.debtnumber || COALESCE(' - ' || NULLIF(btrim(d.description), ''), ''))::text,
           d.debtnumber::text, d.amount, d.amountpaid,
           GREATEST(d.amount - d.amountpaid, 0)::numeric(14,2),
           NULL::integer, NULL::date
    FROM   watersupplierdebts d
    WHERE  d.farmid = p_farmid AND d.status = 'Posted';
$function$;

-- 462: deferred-cost rows skip reversed lots.
CREATE OR REPLACE FUNCTION public.fnwaterdeferredpurchase_rows(p_farmid text)
 RETURNS TABLE(waterrawmaterialpurchaseid integer, purchasedate timestamp without time zone, waterrawmaterialitemid integer, itemname text, category text, unitofmeasure text, productionunit text, supplierid integer, suppliername text, purchasedquantity numeric, consumedquantity numeric, remainingquantity numeric, operationalcost numeric, deferredtotalcost numeric, recognizedcost numeric, deferredremainingcost numeric, recognitionpercent numeric, allocatedrecognizedcost numeric, recognitiondrift numeric, costrecognitionmethod text, recognitionmethodlabel text, status text, exceptionreason text, recognitionevents integer, lastrecognitiondate timestamp without time zone, costingmethod text, queueposition integer, quantityaheadinqueue numeric)
 LANGUAGE sql
 STABLE
AS $function$

    WITH pool AS (

        -- The engine's pool, its order and its unit conversion. A COPY of

        -- spwaterrawmaterialitem_consumebatches, not a parallel idea of how

        -- consumption picks lots. NULLS FIRST / NULLS LAST included, because

        -- water's engine has them.

        SELECT p.waterrawmaterialpurchaseid AS lotid,

               ROW_NUMBER() OVER w AS rn,

               SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))

                   OVER (PARTITION BY p.farmid, p.waterrawmaterialitemid

                         ORDER BY

                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'FIFO' THEN p.purchasedate END ASC NULLS FIRST,

                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.purchasedate END DESC NULLS LAST,

                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'HIFO' THEN p.unitcost END DESC NULLS LAST,

                             CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.waterrawmaterialpurchaseid END DESC NULLS LAST,

                             p.waterrawmaterialpurchaseid ASC

                         ROWS UNBOUNDED PRECEDING)

               - (p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))

                   AS ahead

        FROM   waterrawmaterialpurchases p

        INNER  JOIN waterrawmaterialitems i

               ON i.waterrawmaterialitemid = p.waterrawmaterialitemid

        WHERE  p.farmid = p_farmid AND p.reversedat IS NULL /* 462 */

          AND  p.remainingquantity > 0

        WINDOW w AS (PARTITION BY p.farmid, p.waterrawmaterialitemid

                     ORDER BY

                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'FIFO' THEN p.purchasedate END ASC NULLS FIRST,

                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.purchasedate END DESC NULLS LAST,

                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'HIFO' THEN p.unitcost END DESC NULLS LAST,

                         CASE WHEN COALESCE(i.usagemethod, 'FIFO') = 'LIFO' THEN p.waterrawmaterialpurchaseid END DESC NULLS LAST,

                         p.waterrawmaterialpurchaseid ASC)

    )

    SELECT p.waterrawmaterialpurchaseid,

           p.purchasedate,

           p.waterrawmaterialitemid,

           i.itemname::text,

           i.category::text,

           i.unitofmeasure::text,

           COALESCE(p.productionunit, i.unitofmeasure)::text,

           p.supplierid,

           p.suppliername::text,



           (p.quantity * m.mult)::numeric(18,3),

           ((p.quantity - COALESCE(p.remainingquantity, 0)) * m.mult)::numeric(18,3),

           (COALESCE(p.remainingquantity, 0) * m.mult)::numeric(18,3),



           p.totalcost::numeric(14,2),

           p.deferredtotalcost::numeric(14,2),

           (p.deferredtotalcost - p.deferredremainingcost)::numeric(14,2),

           p.deferredremainingcost::numeric(14,2),

           (CASE WHEN p.deferredtotalcost > 0

                 THEN (p.deferredtotalcost - p.deferredremainingcost) * 100.0 / p.deferredtotalcost

                 ELSE 0 END)::numeric(9,2),



           COALESCE(a.recognized, 0)::numeric(14,2),

           ((p.deferredtotalcost - p.deferredremainingcost)

            - COALESCE(a.recognized, 0))::numeric(14,2),



           p.costrecognitionmethod::text,

           (CASE WHEN fnwatercostrecognition_expenseatpurchase(p.costrecognitionmethod)

                 THEN 'Expense when purchased'

                 ELSE 'Expense when used' END)::text,



           (CASE

                WHEN p.deferredremainingcost > 0 AND COALESCE(p.remainingquantity, 0) <= 0

                     THEN 'Exception'

                WHEN ABS((p.deferredtotalcost - p.deferredremainingcost)

                         - COALESCE(a.recognized, 0)) > 0.05

                     THEN 'Exception'

                WHEN fnwatercostrecognition_expenseatpurchase(p.costrecognitionmethod)

                     OR p.deferredtotalcost = 0

                     THEN 'Expensed at purchase'

                WHEN p.deferredremainingcost >= p.deferredtotalcost THEN 'Not yet expensed'

                WHEN p.deferredremainingcost <= 0                   THEN 'Fully expensed'

                ELSE 'Partly expensed'

            END)::text,



           (CASE

                WHEN p.deferredremainingcost > 0 AND COALESCE(p.remainingquantity, 0) <= 0

                     THEN 'Stock is finished but cost is still held as deferred. It was most '

                       || 'likely removed by an internal-use or stock-adjustment entry, which '

                       || 'does not draw from cost layers.'

                WHEN ABS((p.deferredtotalcost - p.deferredremainingcost)

                         - COALESCE(a.recognized, 0)) > 0.05

                     THEN 'The lot balance and its recorded usages disagree on how much has '

                       || 'been expensed. Neither figure should be quoted until this is checked.'

                ELSE NULL

            END)::text,



           COALESCE(a.events, 0)::int,

           a.lastdate,



           COALESCE(i.usagemethod, 'FIFO')::text,

           q.rn::integer,

           q.ahead::numeric(18,3)

    FROM   waterrawmaterialpurchases p

    INNER  JOIN waterrawmaterialitems i

           ON i.waterrawmaterialitemid = p.waterrawmaterialitemid

    CROSS  JOIN LATERAL (

               SELECT COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS mult

           ) m

    LEFT   JOIN pool q

           ON q.lotid = p.waterrawmaterialpurchaseid

    -- No isreversed filter, unlike poultry: water's reopen DELETEs the

    -- allocations, so anything still here is live by construction.

    LEFT   JOIN LATERAL (

               SELECT SUM(ub.deferredcostdrawn) AS recognized,

                      COUNT(*)                  AS events,

                      MAX(u.useddate)           AS lastdate

               FROM   waterrawmaterialusagebatch ub

               JOIN   waterrawmaterialusage u

                      ON u.waterrawmaterialusageid = ub.waterrawmaterialusageid

               WHERE  ub.waterrawmaterialpurchaseid = p.waterrawmaterialpurchaseid

           ) a ON TRUE

    WHERE  p.farmid = p_farmid AND p.reversedat IS NULL /* 462 */;

$function$;

-- 462: the purchase list says which lots came from a receipt and which were reversed.
CREATE FUNCTION public.spwaterrawmaterialpurchase_getall(p_farmid text, p_fromdate date DEFAULT NULL::date, p_todate date DEFAULT NULL::date)
 RETURNS TABLE(waterrawmaterialpurchaseid integer, farmid text, waterrawmaterialitemid integer, suppliername text, purchasedate timestamp without time zone, quantity numeric, unitcost numeric, paymentmethod text, amountpaid numeric, receipturl text, receivedbystaffid integer, notes text, createdby text, createdat timestamp without time zone, updatedat timestamp without time zone, linkedwaterexpenseid integer, supplierid integer, totalcost numeric, productionunit text, productionunitsperpurchaseunit numeric, remainingquantity numeric, itemname text, category text, unitofmeasure text, balance numeric, productionquantity numeric, productionunitcost numeric, isreversed boolean, receiptnumber text, waterpurchasereceiptid integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.waterrawmaterialpurchaseid,
           p.farmid::text,
           p.waterrawmaterialitemid,
           p.suppliername::text,
           p.purchasedate,
           p.quantity,
           p.unitcost,
           p.paymentmethod::text,
           p.amountpaid,
           p.receipturl::text,
           p.receivedbystaffid,
           p.notes::text,
           p.createdby::text,
           p.createdat,
           p.updatedat,
           p.linkedwaterexpenseid,
           p.supplierid,
           p.totalcost,
           p.productionunit::text,
           p.productionunitsperpurchaseunit,
           p.remainingquantity,
           i.itemname::text,
           i.category::text,
           i.unitofmeasure::text,
           (CASE WHEN p.reversedat IS NOT NULL THEN 0 ELSE p.totalcost - p.amountpaid END)::numeric(14,2),   -- 462
           (p.quantity * COALESCE(p.productionunitsperpurchaseunit, 1))::numeric(18,3),
           (CASE WHEN COALESCE(p.productionunitsperpurchaseunit, 0) > 0
                 THEN p.totalcost / NULLIF(p.quantity * p.productionunitsperpurchaseunit, 0)
                 ELSE NULL END)::numeric(18,4),
           (p.reversedat IS NOT NULL),                                            -- 462
           rc.receiptnumber, rc.waterpurchasereceiptid
    FROM   waterrawmaterialpurchases p
    INNER  JOIN waterrawmaterialitems i ON i.waterrawmaterialitemid = p.waterrawmaterialitemid
    LEFT   JOIN waterpurchasereceiptlines rl ON rl.waterrawmaterialpurchaseid = p.waterrawmaterialpurchaseid
    LEFT   JOIN waterpurchasereceipts rc ON rc.waterpurchasereceiptid = rl.waterpurchasereceiptid
    WHERE  p.farmid = p_farmid
      AND  COALESCE(p.lotsource, '') <> 'ManualDeferredCost'   -- 426: shown on Deferred costs, not as a purchase
      AND  (p_fromdate IS NULL OR p.purchasedate::date >= p_fromdate)
      AND  (p_todate   IS NULL OR p.purchasedate::date <= p_todate)
    ORDER  BY p.purchasedate DESC, p.waterrawmaterialpurchaseid DESC;
END;
$function$;

-- 462: delete explains that a receipt's lot is reversed with its receipt.
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_delete(p_waterrawmaterialpurchaseid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_qty             numeric;
    v_itemid          integer;
    v_linkedexpenseid integer;
    v_mult            numeric;
    v_prodqty         numeric;
    v_currentstock    numeric;
    v_msg2            text;
BEGIN
    -- 426: a manual cost is not a purchase -- reverse it on Deferred costs.
    IF EXISTS (SELECT 1 FROM waterrawmaterialpurchases g WHERE g.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid
               AND g.farmid = p_farmid AND g.lotsource = 'ManualDeferredCost') THEN
        RAISE EXCEPTION 'This is a manual deferred cost, not a purchase. Reverse it on Deferred costs.' USING ERRCODE = 'P0001';
    END IF;
    -- 462: a receipt's lot goes with its receipt.
    IF EXISTS (SELECT 1 FROM waterpurchasereceiptlines rl
               JOIN waterpurchasereceipts r ON r.waterpurchasereceiptid = rl.waterpurchasereceiptid
               WHERE rl.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND r.farmid = p_farmid) THEN
        RAISE EXCEPTION 'This purchase was entered on purchase receipt %. Reverse the receipt on Receive Purchase instead.',
              (SELECT r.receiptnumber FROM waterpurchasereceiptlines rl
               JOIN waterpurchasereceipts r ON r.waterpurchasereceiptid = rl.waterpurchasereceiptid
               WHERE rl.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid LIMIT 1) USING ERRCODE = 'P0001';
    END IF;
    -- Deleting a drawn lot would strand its WaterRawMaterialUsageBatch rows
    -- against a purchase that no longer exists.
    IF EXISTS (SELECT 1 FROM waterrawmaterialusagebatch ub
               WHERE ub.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid) THEN
        RAISE EXCEPTION 'This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.';
    END IF;

    SELECT p.quantity, p.waterrawmaterialitemid, p.linkedwaterexpenseid,
           COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)
      INTO v_qty, v_itemid, v_linkedexpenseid, v_mult
    FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;

    IF v_qty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_waterrawmaterialpurchaseid;
    END IF;

    v_prodqty := (v_qty * v_mult)::numeric(18,4);
    SELECT mi.currentquantity::numeric(18,4) INTO v_currentstock
    FROM waterrawmaterialitems mi
    WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

    IF (v_currentstock < v_prodqty) THEN
        -- 428: say what to do (see fnwaterrawmaterial_reducemessage).
        v_msg2 := public.fnwaterrawmaterial_reducemessage(p_farmid, v_itemid, v_currentstock, v_prodqty, 'delete this purchase');
        RAISE EXCEPTION '%', v_msg2 USING ERRCODE = 'P0001';
    END IF;

    IF v_linkedexpenseid IS NOT NULL THEN
        PERFORM spwaterrawmaterialpurchase_cancellinkedexpense(
            p_waterrawmaterialpurchaseid => p_waterrawmaterialpurchaseid,
            p_farmid                     => p_farmid,
            p_cancelledby                => NULL);
    END IF;

    UPDATE waterrawmaterialitems mi
    SET currentquantity = mi.currentquantity - v_prodqty,   -- production-level qty
        updatedat       = (now() at time zone 'utc')
    WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

    DELETE FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;
END;
$function$;

-- 462: pay balance refuses a reversed lot.
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_paybalance(p_waterrawmaterialpurchaseid integer, p_farmid text, p_amount numeric, p_paymentmethod text DEFAULT NULL::text, p_paymentdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_createdby text DEFAULT NULL::text)
 RETURNS TABLE(balance numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_doc    record;
    v_amount numeric(14,2);
BEGIN
    -- 462: a reversed receipt's lot owes nothing.
    IF EXISTS (SELECT 1 FROM waterrawmaterialpurchases g
               WHERE g.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND g.reversedat IS NOT NULL) THEN
        RAISE EXCEPTION 'This purchase was reversed with its receipt, so nothing is owed on it.' USING ERRCODE = 'P0001';
    END IF;
    -- 426: a manual cost is not a purchase -- reverse it on Deferred costs.
    IF EXISTS (SELECT 1 FROM waterrawmaterialpurchases g WHERE g.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid
               AND g.farmid = p_farmid AND g.lotsource = 'ManualDeferredCost') THEN
        RAISE EXCEPTION 'This is a manual deferred cost, not a purchase. Reverse it on Deferred costs.' USING ERRCODE = 'P0001';
    END IF;
    SELECT d.documentid, d.supplierid, d.balance, d.cashaccountid
    INTO   v_doc
    FROM   fnwaterpayables(p_farmid) d
    WHERE  d.documenttype = 'RawMaterialPurchase'
      AND  d.documentid = p_waterrawmaterialpurchaseid;

    IF v_doc.documentid IS NULL THEN
        RAISE EXCEPTION 'Purchase not found for this company.';
    END IF;
    IF v_doc.balance <= 0 THEN
        RAISE EXCEPTION 'This purchase has no outstanding balance.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than 0.';
    END IF;

    -- Never overpay -- 091 clamped rather than erroring, and the Purchases page
    -- relies on that when the user types the full total on a part-paid row.
    v_amount := LEAST(p_amount, v_doc.balance)::numeric(14,2);

    PERFORM spwatersupplierpayment_record(
        p_farmid        => p_farmid,
        p_supplierid    => v_doc.supplierid,
        p_amount        => v_amount,
        p_allocations   => jsonb_build_array(jsonb_build_object(
                               'documenttype', 'RawMaterialPurchase',
                               'documentid',   p_waterrawmaterialpurchaseid,
                               'amount',       v_amount)),
        p_paymentmethod => p_paymentmethod,
        p_paymentdate   => p_paymentdate,
        p_cashaccountid => v_doc.cashaccountid,
        p_reference     => NULL,
        p_note          => NULL,
        p_sourcetype    => 'PurchaseEntry',
        p_createdby     => p_createdby);

    RETURN QUERY
    SELECT GREATEST(pu.totalcost - pu.amountpaid, 0)::numeric(14,2)
    FROM   waterrawmaterialpurchases pu
    WHERE  pu.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid
      AND  pu.farmid = p_farmid;
END;
$function$;

-- 462: FIX -- the adjust function failed on every call (ambiguous RETURNING column).
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialitem_adjust(p_farmid text, p_waterrawmaterialitemid integer, p_quantity numeric, p_unitcost numeric DEFAULT NULL::numeric, p_movementtype text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS TABLE(waterrawmaterialadjustmentid integer, currentquantity numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_newid integer;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM waterrawmaterialitems i
                   WHERE i.waterrawmaterialitemid = p_waterrawmaterialitemid AND i.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Raw material item not found for this company.';
    END IF;

    IF p_quantity = 0 THEN
        RAISE EXCEPTION 'Adjustment quantity cannot be zero.';
    END IF;

    INSERT INTO waterrawmaterialadjustments AS adj   -- 462: alias, see RETURNING
        (farmid, waterrawmaterialitemid, quantity, unitcost, movementtype, note, createdby)
    VALUES
        (p_farmid, p_waterrawmaterialitemid, p_quantity, p_unitcost, p_movementtype, p_note, p_createdby)
    RETURNING adj.waterrawmaterialadjustmentid INTO v_newid;   -- 462: was ambiguous with the OUT column

    UPDATE waterrawmaterialitems i
    SET    currentquantity = CASE WHEN i.currentquantity + p_quantity < 0 THEN 0 ELSE i.currentquantity + p_quantity END,
           updatedat       = (now() at time zone 'utc')
    WHERE  i.waterrawmaterialitemid = p_waterrawmaterialitemid AND i.farmid = p_farmid;

    RETURN QUERY
    SELECT v_newid AS waterrawmaterialadjustmentid,
           (SELECT i.currentquantity FROM waterrawmaterialitems i
            WHERE i.waterrawmaterialitemid = p_waterrawmaterialitemid AND i.farmid = p_farmid) AS currentquantity;
END;
$function$;

COMMIT;
