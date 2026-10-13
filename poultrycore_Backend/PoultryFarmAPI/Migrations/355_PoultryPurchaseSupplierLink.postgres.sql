-- 355. Record Purchase: the supplier is a real supplier, enforced here.
--
-- Supplier Balances (fnpoultrypayables) reads a raw-material purchase by its
-- supplierid. Record Purchase used to save only a typed supplier name, so
-- those purchases -- and what was still owed on them -- never reached
-- Supplier Balances. The form now picks from the supplier list (like
-- Expenses), but the rule lives here so no caller can get around it:
--
--   * a supplierid must belong to this company, and the purchase takes that
--     supplier's own name (the name can no longer disagree with the id);
--   * a typed name with no id is matched to the company's supplier of that
--     name, or added as a new supplier -- the same rule Receive Invoice (345)
--     already applies through fnpoultrysupplier_resolve;
--   * no supplier at all stays allowed (a cash purchase from a market stall).
--
-- The linked cash expense keeps its supplier TEXT only. Giving it a
-- supplierid would put the same purchase into Supplier Balances twice (once as
-- the purchase, once through fnpoultrypayables' Expense arm).
--
-- Idempotent: the two patches check for their own marker first.

-- 1. The one place the rule is written --------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrypurchase_supplier(
    p_farmid text, p_supplierid integer, p_suppliername text, p_userid text DEFAULT NULL,
    OUT o_supplierid integer, OUT o_suppliername text)
LANGUAGE plpgsql
AS $function$
BEGIN
    o_supplierid := p_supplierid;
    IF o_supplierid IS NULL THEN
        o_supplierid := public.fnpoultrysupplier_resolve(p_farmid, p_suppliername, p_userid);
    END IF;
    IF o_supplierid IS NULL THEN
        o_suppliername := NULL;           -- no supplier: allowed
        RETURN;
    END IF;

    SELECT s.name INTO o_suppliername
    FROM   supplier s
    WHERE  s.supplierid = o_supplierid AND s.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;
END;
$function$;

-- 2. Insert and update resolve the supplier before anything else -------------
-- The parameters are reassigned at the top of the body, so every later use of
-- p_supplierid / p_suppliername (the purchase row, the linked expense's text)
-- sees the resolved supplier.
DO $patch$
DECLARE
    v_sig  text;
    v_def  text;
    v_call text;
    v_n    int;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY['insert', 'update'] LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = 'sppoultryrawmaterialpurchase_' || v_sig;
        IF v_def IS NULL THEN
            RAISE EXCEPTION '355: sppoultryrawmaterialpurchase_% not found.', v_sig;
        END IF;
        CONTINUE WHEN position('fnpoultrypurchase_supplier' IN v_def) > 0;

        -- Exactly one top-level BEGIN, or the shape has changed under us.
        v_n := (length(v_def) - length(replace(v_def, E'\nBEGIN\n', ''))) / length(E'\nBEGIN\n');
        IF v_n <> 1 THEN
            RAISE EXCEPTION '355: sppoultryrawmaterialpurchase_% has % top-level BEGINs; patch it by hand.', v_sig, v_n;
        END IF;

        v_call := CASE v_sig
            WHEN 'insert' THEN 'fnpoultrypurchase_supplier(p_farmid, p_supplierid, p_suppliername, p_createdby)'
            ELSE               'fnpoultrypurchase_supplier(p_farmid, p_supplierid, p_suppliername, NULL)'
        END;

        EXECUTE replace(v_def, E'\nBEGIN\n',
            E'\nBEGIN\n'
            || E'    -- 355. A real supplier of this company, or none.\n'
            || E'    SELECT r.o_supplierid, r.o_suppliername INTO p_supplierid, p_suppliername\n'
            || E'    FROM   public.' || v_call || E' r;\n');
    END LOOP;
END;
$patch$;

-- 3. Backfill: link older name-only purchases to an existing supplier --------
-- Match only; old typed names are NOT turned into new suppliers here (they
-- may be typos). Editing such a purchase and saving it links it then.
-- Receipt-made lots always carry a supplierid, so the receipt lock never fires.
UPDATE poultryrawmaterialpurchases pu
SET    supplierid   = m.supplierid,
       suppliername = m.name
FROM  (SELECT DISTINCT ON (s.farmid, lower(btrim(s.name)))
              s.farmid, lower(btrim(s.name)) AS k, s.supplierid, s.name
       FROM   supplier s
       ORDER  BY s.farmid, lower(btrim(s.name)), s.supplierid) m
WHERE  pu.supplierid IS NULL
  AND  COALESCE(btrim(pu.suppliername), '') <> ''
  AND  m.farmid = pu.farmid
  AND  m.k = lower(btrim(pu.suppliername));
