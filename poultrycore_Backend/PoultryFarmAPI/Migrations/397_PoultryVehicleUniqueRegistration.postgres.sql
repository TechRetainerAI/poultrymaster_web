-- 397: one vehicle per registration number, per farm.
--
-- A tester registered three vehicles as "12345" (2026-11-03). The Vehicles
-- form now refuses that, but the form only knows the list it loaded, so the
-- database has to be the rule's real home.
--
-- Why a trigger, not a unique index: the dev database already holds those
-- three rows, and CREATE UNIQUE INDEX would fail on them. The trigger stops
-- every NEW clash while leaving existing rows editable, so the duplicates can
-- be renamed (or removed) at the farm's own pace. Once none are left a unique
-- index can replace it.
--
-- "Same number" ignores case, spaces and punctuation: GR 1234-20, gr1234 20
-- and GR-1234-20 are one plate. Blank registrations are not compared.
--
-- Idempotent. Safe to re-run.

CREATE OR REPLACE FUNCTION public.fn_poultryvehicle_regkey(p_reg text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
    SELECT NULLIF(upper(regexp_replace(coalesce(p_reg, ''), '[^A-Za-z0-9]', '', 'g')), '')
$$;

CREATE OR REPLACE FUNCTION public.trg_poultryvehicle_unique_registration()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_key   text := public.fn_poultryvehicle_regkey(NEW.registrationnumber);
    v_other text;
BEGIN
    IF v_key IS NULL THEN
        RETURN NEW;
    END IF;

    -- An edit that leaves the plate as it was is not a new clash (this is what
    -- keeps the pre-existing duplicates editable).
    IF TG_OP = 'UPDATE'
       AND public.fn_poultryvehicle_regkey(OLD.registrationnumber) IS NOT DISTINCT FROM v_key
       AND OLD.farmid = NEW.farmid THEN
        RETURN NEW;
    END IF;

    -- Two saves of the same plate at once would each see no clash; serialise
    -- them per farm + plate.
    PERFORM pg_advisory_xact_lock(hashtext('poultryvehicle-reg:' || NEW.farmid || ':' || v_key));

    SELECT v.vehiclename INTO v_other
    FROM   poultryvehicles v
    WHERE  v.farmid = NEW.farmid
      AND  v.poultryvehicleid IS DISTINCT FROM NEW.poultryvehicleid
      AND  public.fn_poultryvehicle_regkey(v.registrationnumber) = v_key
    LIMIT  1;

    IF v_other IS NOT NULL THEN
        RAISE EXCEPTION 'Registration number % is already used by %.', trim(NEW.registrationnumber), v_other
              USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_poultryvehicle_unique_registration ON poultryvehicles;
CREATE TRIGGER trg_poultryvehicle_unique_registration
    BEFORE INSERT OR UPDATE OF registrationnumber, farmid ON poultryvehicles
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryvehicle_unique_registration();

-- The lookup above, without a scan of the farm's whole fleet.
CREATE INDEX IF NOT EXISTS ix_poultryvehicles_farm_regkey
    ON poultryvehicles (farmid, public.fn_poultryvehicle_regkey(registrationnumber));
