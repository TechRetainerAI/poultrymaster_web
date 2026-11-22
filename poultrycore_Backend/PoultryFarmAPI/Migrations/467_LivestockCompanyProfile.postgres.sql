-- 467: Livestock company profile -- the Company settings page.
--
-- Who the business is and how to reach it: name, owner, contacts, location,
-- address, capacity, operating hours, notes. One row per Livestock company.
-- Currency and time zone are NOT here: they live on the Farms row and are
-- saved by the shared farm-settings and CompanyTime endpoints, exactly as for
-- every other company type.
--
-- Permission: api/Livestock/company -> office.settings (as water/company);
-- writes are owner/admin only (SetupAdminOnly on the controller).
-- Safe to re-run.

BEGIN;

CREATE TABLE IF NOT EXISTS livestockcompanyprofiles (
    farmid          text PRIMARY KEY,
    brandname       text,
    ownername       text,
    phonenumber     text,
    email           text,
    mainlocation    text,
    siteaddress     text,
    totalcapacity   integer CHECK (totalcapacity IS NULL OR totalcapacity >= 0),
    operatinghours  text,
    notes           text,
    createdby       text,
    createdat       timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby       text,
    updatedat       timestamp
);

-- The profile, or an empty one (exists = false) for a company that has not
-- saved it yet. The farm's own name is offered as the brand name.
CREATE OR REPLACE FUNCTION public.splivestockprofile_get(p_farmid text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'exists', p.farmid IS NOT NULL,
        'brandName', COALESCE(p.brandname, (SELECT f.name FROM farms f WHERE f.id = k.farmid OR f.farmid = k.farmid
                                            ORDER BY (f.id = k.farmid) DESC LIMIT 1)),
        'ownerName', p.ownername, 'phoneNumber', p.phonenumber, 'email', p.email,
        'mainLocation', p.mainlocation, 'siteAddress', p.siteaddress,
        'totalCapacity', p.totalcapacity, 'operatingHours', p.operatinghours, 'notes', p.notes,
        'updatedBy', p.updatedby, 'updatedAt', p.updatedat)
    FROM (SELECT p_farmid AS farmid) k
    LEFT JOIN livestockcompanyprofiles p ON p.farmid = k.farmid;
$f$;

CREATE OR REPLACE FUNCTION public.splivestockprofile_save(p_farmid text, p_x jsonb, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_email text := NULLIF(btrim(p_x->>'email'), ''); v_cap integer;
BEGIN
    IF NULLIF(btrim(p_x->>'brandName'), '') IS NULL THEN
        RAISE EXCEPTION 'Give the farm a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
        RAISE EXCEPTION '"%" is not an email address.', v_email USING ERRCODE = 'P0001';
    END IF;
    v_cap := NULLIF(p_x->>'totalCapacity', '')::numeric::integer;
    IF v_cap < 0 THEN
        RAISE EXCEPTION 'Capacity cannot be below zero.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO livestockcompanyprofiles AS p (farmid, brandname, ownername, phonenumber, email, mainlocation, siteaddress,
                                               totalcapacity, operatinghours, notes, createdby)
    VALUES (p_farmid, btrim(p_x->>'brandName'), NULLIF(btrim(p_x->>'ownerName'), ''), NULLIF(btrim(p_x->>'phoneNumber'), ''),
            v_email, NULLIF(btrim(p_x->>'mainLocation'), ''), NULLIF(btrim(p_x->>'siteAddress'), ''),
            v_cap, NULLIF(btrim(p_x->>'operatingHours'), ''), NULLIF(btrim(p_x->>'notes'), ''), p_by)
    ON CONFLICT (farmid) DO UPDATE SET
        brandname = EXCLUDED.brandname, ownername = EXCLUDED.ownername, phonenumber = EXCLUDED.phonenumber,
        email = EXCLUDED.email, mainlocation = EXCLUDED.mainlocation, siteaddress = EXCLUDED.siteaddress,
        totalcapacity = EXCLUDED.totalcapacity, operatinghours = EXCLUDED.operatinghours, notes = EXCLUDED.notes,
        updatedby = p_by, updatedat = (now() at time zone 'utc');
END
$f$;

COMMIT;
