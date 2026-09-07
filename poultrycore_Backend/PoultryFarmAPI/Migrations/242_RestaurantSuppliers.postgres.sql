-- =============================================================================
-- Migration 242: Restaurant Suppliers Setup Entity  (PostgreSQL)
-- =============================================================================
-- Suppliers are per-farm (each restaurant has its own suppliers),
-- not system-wide like the other lookups.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.restaurantsuppliers (
    restaurantsupplierid SERIAL PRIMARY KEY,
    farmid      text NOT NULL,
    name        character varying(200) NOT NULL,
    contactname character varying(100),
    phone       character varying(50),
    email       character varying(200),
    address     text,
    category    character varying(100),
    notes       text,
    isactive    boolean DEFAULT true NOT NULL,
    createdat   timestamp with time zone DEFAULT now() NOT NULL,
    updatedat   timestamp with time zone
);

CREATE INDEX IF NOT EXISTS ix_restaurantsuppliers_farm ON public.restaurantsuppliers (farmid);

CREATE OR REPLACE FUNCTION public.sprestaurant_supplier_list(p_farmid text)
 RETURNS SETOF restaurantsuppliers
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM restaurantsuppliers WHERE farmid = p_farmid AND isactive = true ORDER BY name;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sprestaurant_supplier_insert(
    p_farmid text, p_name text, p_contactname text DEFAULT NULL,
    p_phone text DEFAULT NULL, p_email text DEFAULT NULL,
    p_address text DEFAULT NULL, p_category text DEFAULT NULL, p_notes text DEFAULT NULL
) RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantsuppliers(farmid, name, contactname, phone, email, address, category, notes)
    VALUES(p_farmid, p_name, p_contactname, p_phone, p_email, p_address, p_category, p_notes)
    RETURNING restaurantsupplierid INTO v_id;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sprestaurant_supplier_update(
    p_id integer, p_farmid text, p_name text, p_contactname text DEFAULT NULL,
    p_phone text DEFAULT NULL, p_email text DEFAULT NULL,
    p_address text DEFAULT NULL, p_category text DEFAULT NULL, p_notes text DEFAULT NULL,
    p_isactive boolean DEFAULT true
) RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE restaurantsuppliers SET name=p_name, contactname=p_contactname, phone=p_phone,
        email=p_email, address=p_address, category=p_category, notes=p_notes,
        isactive=p_isactive, updatedat=NOW()
    WHERE restaurantsupplierid=p_id AND farmid=p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sprestaurant_supplier_delete(p_id integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    DELETE FROM restaurantsuppliers WHERE restaurantsupplierid=p_id AND farmid=p_farmid;
END;
$function$;
