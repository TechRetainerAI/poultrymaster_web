-- 439: a bird sale must name the flock the birds came from.
--
-- A bird sale saved with "All flocks" (flockid 0 / NULL) wrote its Birds
-- stock row (-qty) but took the birds out of no flock, so Stock Movements Net
-- fell below the birds alive (Flocks page / Recalculate product stock). A
-- batch alone is not enough either: the batch bird counts never read sales.
-- Seen on dev: #2147 Sky Farm (50), #2247 Gyimah Farm (3), #3341 Ali Farm (50).
--
-- The guard checks only a NEW bird sale, or an edit that changes the flock,
-- product or quantity -- so the old flockless sales can still be reversed
-- (that only changes status) or corrected. Eggs, byproducts and the
-- egg-only delivery / driver-return sales are untouched.
-- "Bird sale" = fnpoultrysale_isbirdsale, the same rule that writes the
-- Birds stock row and that the web form mirrors (isLiveBirdProduct).

BEGIN;

CREATE OR REPLACE FUNCTION public.tr_sale_birdneedsflock_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(NEW.flockid, 0) = 0
       AND COALESCE(NEW.quantity, 0) > 0
       AND public.fnpoultrysale_isbirdsale(NEW.product)
       AND (TG_OP = 'INSERT'
            OR NEW.flockid  IS DISTINCT FROM OLD.flockid
            OR NEW.product  IS DISTINCT FROM OLD.product
            OR NEW.quantity IS DISTINCT FROM OLD.quantity) THEN
        RAISE EXCEPTION 'Choose the flock the birds came from. A bird sale must come out of a flock.'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS tr_sale_birdneedsflock ON public.sale;
CREATE TRIGGER tr_sale_birdneedsflock
    BEFORE INSERT OR UPDATE OF flockid, product, quantity ON public.sale
    FOR EACH ROW EXECUTE FUNCTION public.tr_sale_birdneedsflock_fn();

COMMIT;
