-- 516 (Winchester): an expired product can never be sold, from any screen.
--
-- 515 made the Pharmacy till sell only in-date stock, but the batch trigger itself still let a
-- sale from another screen (general Sales, general POS) take stock from an expired batch. Selling
-- an expired medicine is illegal, so the database now refuses it:
-- a 'SaleOut' stock movement may only use stock that is not expired, i.e.
--     stock before this line  -  what is left in expired batches.
-- Stock with no batch recorded (no expiry known) is still sellable, as before.
-- Expired stock leaves the shelf only through a write-off (Batches & expiry -> Write off).
--
-- Changes only 515's own trigger function fngenericstockmovement_batches_trg (same body, plus
-- the guard). Nothing of another developer's is touched. Safe to re-run.

CREATE OR REPLACE FUNCTION fngenericstockmovement_batches_trg()
RETURNS TRIGGER LANGUAGE plpgsql AS $fn$
DECLARE
    v_stock    NUMERIC;
    v_earlier  NUMERIC;
    v_batchid  INT;
    v_expired  NUMERIC;
    v_name     TEXT;
    v_unit     TEXT;
    v_date     DATE;
BEGIN
    IF NEW.quantity IS NULL OR NEW.quantity >= 0 OR NEW.genericproductid IS NULL THEN
        RETURN NEW;
    END IF;

    -- Every writer inserts its movement rows first and updates genericproducts.currentstock
    -- after, so currentstock is still the stock before this document. Earlier rows of the
    -- same document (same statement) have already been taken off the batches.
    SELECT COALESCE(p.currentstock, 0), p.productname, COALESCE(NULLIF(trim(p.unitofmeasure), ''), 'unit') || '(s)'
      INTO v_stock, v_name, v_unit
    FROM genericproducts p
    WHERE p.genericproductid = NEW.genericproductid AND p.farmid = NEW.farmid;
    SELECT COALESCE(SUM(m.quantity), 0) INTO v_earlier FROM genericstockmovements m
    WHERE m.farmid = NEW.farmid AND m.genericproductid = NEW.genericproductid
      AND m.referencetype IS NOT DISTINCT FROM NEW.referencetype
      AND m.referenceid IS NOT DISTINCT FROM NEW.referenceid
      AND m.genericstockmovementid < NEW.genericstockmovementid
      AND m.movementtype = NEW.movementtype;

    -- 516: a sale may not reach expired stock.
    IF NEW.movementtype = 'SaleOut' THEN
        SELECT COALESCE(SUM(b.quantityremaining), 0), MIN(b.expirydate) INTO v_expired, v_date
        FROM genericproductbatches b
        WHERE b.farmid = NEW.farmid AND b.genericproductid = NEW.genericproductid
          AND b.isdeleted = FALSE AND b.quantityremaining > 0
          AND b.expirydate IS NOT NULL AND b.expirydate < CURRENT_DATE;
        IF v_expired > 0 AND -NEW.quantity > (COALESCE(v_stock, 0) + v_earlier) - v_expired THEN
            RAISE EXCEPTION 'Cannot sell % % of %: only % % are in date. % % expired (from %) and must be written off, not sold.',
                trim(to_char(-NEW.quantity, 'FM999999990.###')), v_unit, v_name,
                trim(to_char(GREATEST((COALESCE(v_stock, 0) + v_earlier) - v_expired, 0), 'FM999999990.###')), v_unit,
                trim(to_char(v_expired, 'FM999999990.###')), v_unit, to_char(v_date, 'DD Mon YYYY');
        END IF;
    END IF;

    IF NEW.referencetype = 'Adjustment' THEN
        SELECT w.genericproductbatchid INTO v_batchid FROM genericproductbatchwriteoffs w
        WHERE w.genericstockadjustmentid = NEW.referenceid AND w.farmid = NEW.farmid;
    END IF;

    PERFORM fngenericproductbatch_consume(
        NEW.farmid, NEW.genericproductid, -NEW.quantity, v_stock + v_earlier,
        CASE WHEN NEW.movementtype = 'PurchaseReversal' AND NEW.referencetype = 'Purchase' THEN NEW.referenceid END,
        v_batchid);
    RETURN NEW;
END
$fn$;
