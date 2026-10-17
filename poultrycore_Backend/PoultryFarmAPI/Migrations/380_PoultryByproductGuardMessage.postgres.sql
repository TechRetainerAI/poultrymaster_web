-- =============================================================================
-- 380_PoultryByproductGuardMessage.postgres.sql                 (requires 372)
--
-- Purpose
-- -------
-- Clearer wording when deleting / reversing a production record or an egg
-- sorting (or editing one down) would take Broken Eggs / Dead Birds below zero.
-- Was:
--   "This reversal would leave Broken Eggs at -100 -- some of them have since
--    been sold, used or disposed. Reverse those first."
--   (said "reversal" even when the user had pressed Delete)
-- Now, for a delete / reversal:
--   "This can't be deleted or reversed yet: Broken Eggs would drop to -100,
--    because some of them have already been sold, used or disposed. Reverse
--    those first, then try again."
-- and for an edit:
--   "This change would leave Broken Eggs at -100, because some of them have
--    already been sold, used or disposed. Reverse those first, or enter a
--    smaller reduction."
--
-- Same rule, same SQLSTATE (P0001): only the sentence changes.
-- =============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.fnpoultry_byproductguard(p_farmid text, p_role text, p_before numeric, p_what text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_after numeric := fnpoultry_byproductonhand(p_farmid, p_role);
    v_name  text    := fnpoultry_byproductname(p_role);
BEGIN
    IF v_after < 0 AND v_after < p_before THEN
        -- 380: plain words, and the right ones for what the user pressed.
        IF p_what = 'change' THEN
            RAISE EXCEPTION 'This change would leave % at %, because some of them have already been sold, used or disposed. Reverse those first, or enter a smaller reduction.',
                v_name, trunc(v_after) USING ERRCODE = 'P0001';
        ELSE
            RAISE EXCEPTION 'This can''t be deleted or reversed yet: % would drop to %, because some of them have already been sold, used or disposed. Reverse those first, then try again.',
                v_name, trunc(v_after) USING ERRCODE = 'P0001';
        END IF;
    END IF;
END
$function$;

COMMIT;
