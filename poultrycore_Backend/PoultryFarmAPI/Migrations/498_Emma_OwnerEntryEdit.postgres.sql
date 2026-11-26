-- Migration 498 — Allow editing non-financial fields on owner entries.
--
-- Financial fields (amount, cashAccountId, entryDate, entryType) stay locked.
-- Only ownerName, paymentMethod, reference, notes can be changed on a Posted entry.
-- Reversed entries cannot be edited.

-- 1. Add updatedat column if not present
ALTER TABLE genericownercontributiondraws ADD COLUMN IF NOT EXISTS updatedat timestamp NULL;

-- 2. Create the update SP
CREATE OR REPLACE FUNCTION public.spgenericownerentry_update(
    p_entryid       integer,
    p_farmid        text,
    p_ownername     text        DEFAULT NULL,
    p_paymentmethod text        DEFAULT NULL,
    p_reference     text        DEFAULT NULL,
    p_notes         text        DEFAULT NULL,
    p_updatedby     text        DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT status INTO v_status
    FROM   genericownercontributiondraws
    WHERE  genericownerentryid = p_entryid AND farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Entry not found for this company.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'Cannot edit a reversed entry.';
    END IF;

    UPDATE genericownercontributiondraws
    SET    ownername      = COALESCE(p_ownername, ownername),
           paymentmethod  = COALESCE(p_paymentmethod, paymentmethod),
           referenceno    = COALESCE(p_reference, referenceno),
           notes          = COALESCE(p_notes, notes),
           updatedat      = now() AT TIME ZONE 'utc'
    WHERE  genericownerentryid = p_entryid AND farmid = p_farmid;

    RETURN p_entryid;
END;
$function$;
