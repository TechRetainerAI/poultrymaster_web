-- =============================================================================
-- Migration 239: Maintenance Asset/Area Lookup + Stored Procedures for ALL
-- lookup tables added in this session (PostgreSQL)
-- =============================================================================

-- =========================================================
-- PART A: Maintenance Asset/Area Lookup Table
-- =========================================================

CREATE TABLE IF NOT EXISTS public.hotelmaintenanceassets (
    hotelmaintenanceassetid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelmaintenanceassets (code, description, sortorder) VALUES
    ('AC',   'Air Conditioner',       1),
    ('PLB',  'Plumbing / Pipes',      2),
    ('ELC',  'Electrical / Wiring',   3),
    ('LGT',  'Lighting / Bulbs',      4),
    ('FRN',  'Furniture',             5),
    ('DOR',  'Door / Lock',           6),
    ('WND',  'Window / Curtain',      7),
    ('FLR',  'Flooring / Carpet',     8),
    ('WLL',  'Wall / Paint',          9),
    ('RFG',  'Refrigerator / Minibar',10),
    ('TV',   'TV / Electronics',      11),
    ('WFI',  'WiFi / Network',        12),
    ('ELV',  'Elevator / Lift',       13),
    ('BTH',  'Bathroom Fixture',      14),
    ('KIT',  'Kitchen Equipment',     15),
    ('POL',  'Pool / Spa',            16),
    ('GEN',  'Generator / Power',     17),
    ('SEC',  'Security / CCTV',       18),
    ('LND',  'Landscaping / Garden',  19),
    ('PRK',  'Parking Area',          20),
    ('OTH',  'Other',                 21)
ON CONFLICT (code) DO NOTHING;

-- =========================================================
-- PART B: Stored procedures for ALL lookup tables
-- =========================================================

-- 1. Room Categories (migration 231)
CREATE OR REPLACE FUNCTION public.sphotel_roomcategory_list()
 RETURNS SETOF hotelroomcategories
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelroomcategories WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 2. Bed Types (migration 232)
CREATE OR REPLACE FUNCTION public.sphotel_bedtype_list()
 RETURNS SETOF hotelbedtypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelbedtypes WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 3. ID Types (migration 233)
CREATE OR REPLACE FUNCTION public.sphotel_idtype_list()
 RETURNS SETOF hotelidtypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelidtypes WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 4. Communication Subjects (migration 234)
CREATE OR REPLACE FUNCTION public.sphotel_commsubject_list()
 RETURNS SETOF hotelcommsubjects
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelcommsubjects WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 5. Guest Request Types (migration 235)
CREATE OR REPLACE FUNCTION public.sphotel_requesttype_list()
 RETURNS SETOF hotelrequesttypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelrequesttypes WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 6. HK Task Types (migration 236)
CREATE OR REPLACE FUNCTION public.sphotel_hktasktype_list()
 RETURNS SETOF hotelhktasktypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelhktasktypes WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 7. Table Locations (migration 237)
CREATE OR REPLACE FUNCTION public.sphotel_tablelocation_list()
 RETURNS SETOF hoteltablelocations
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hoteltablelocations WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- 8. Maintenance Assets (this migration)
CREATE OR REPLACE FUNCTION public.sphotel_maintenanceasset_list()
 RETURNS SETOF hotelmaintenanceassets
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY SELECT * FROM hotelmaintenanceassets WHERE isactive = true ORDER BY sortorder, description;
END;
$function$;

-- =========================================================
-- PART C: CRUD stored procedures for each lookup table
-- These allow adding/updating/deleting items from any lookup
-- =========================================================

-- Generic INSERT for any lookup
CREATE OR REPLACE FUNCTION public.sphotel_lookup_insert(
    p_table text, p_code text, p_description text, p_sortorder integer DEFAULT 0
) RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_id INT; v_sql TEXT;
BEGIN
    v_sql := format('INSERT INTO %I (code, description, sortorder) VALUES ($1, $2, $3) RETURNING %I',
        p_table, regexp_replace(p_table, 's$', '') || 'id');
    EXECUTE v_sql INTO v_id USING p_code, p_description, p_sortorder;
    RETURN v_id;
END;
$function$;

-- Generic UPDATE for any lookup
CREATE OR REPLACE FUNCTION public.sphotel_lookup_update(
    p_table text, p_id integer, p_code text, p_description text, p_sortorder integer DEFAULT 0, p_isactive boolean DEFAULT true
) RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_sql TEXT; v_idcol TEXT;
BEGIN
    v_idcol := regexp_replace(p_table, 's$', '') || 'id';
    v_sql := format('UPDATE %I SET code=$1, description=$2, sortorder=$3, isactive=$4 WHERE %I=$5', p_table, v_idcol);
    EXECUTE v_sql USING p_code, p_description, p_sortorder, p_isactive, p_id;
END;
$function$;

-- Generic DELETE for any lookup
CREATE OR REPLACE FUNCTION public.sphotel_lookup_delete(
    p_table text, p_id integer
) RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_sql TEXT; v_idcol TEXT;
BEGIN
    v_idcol := regexp_replace(p_table, 's$', '') || 'id';
    v_sql := format('DELETE FROM %I WHERE %I=$1', p_table, v_idcol);
    EXECUTE v_sql USING p_id;
END;
$function$;

-- =========================================================
-- PART D: Shift handover stored procedures
-- =========================================================

CREATE OR REPLACE FUNCTION public.sphotel_shifthandover_list(p_farmid text)
 RETURNS TABLE(
    "HotelShiftHandoverId" integer, "FarmId" text, "ShiftDate" date,
    "ShiftType" character varying, "HandoverBy" character varying,
    "HandoverTo" character varying, "ReceivedBy" character varying,
    "KeyMessages" text, "PendingItems" text, "VipGuests" text,
    "Incidents" text, "CashBalance" numeric, "Status" character varying,
    "AcknowledgedAt" timestamp with time zone, "CreatedAt" timestamp with time zone
 )
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT h.hotelshifthandoverid, h.farmid, h.shiftdate, h.shifttype,
           h.handoverby, h.handoverto, h.receivedby,
           h.keymessages, h.pendingitems, h.vipguests,
           h.incidents, h.cashbalance, h.status,
           h.acknowledgedat, h.createdat
    FROM hotelshifthandovers h
    WHERE h.farmid = p_farmid
    ORDER BY h.shiftdate DESC, h.createdat DESC
    LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sphotel_shifthandover_insert(
    p_farmid text, p_shiftdate date, p_shifttype text, p_handoverby text,
    p_handoverto text DEFAULT NULL, p_keymessages text DEFAULT NULL,
    p_pendingitems text DEFAULT NULL, p_vipguests text DEFAULT NULL,
    p_incidents text DEFAULT NULL, p_cashbalance numeric DEFAULT NULL
) RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_id INT;
BEGIN
    INSERT INTO hotelshifthandovers(farmid, shiftdate, shifttype, handoverby, handoverto,
        keymessages, pendingitems, vipguests, incidents, cashbalance, status)
    VALUES(p_farmid, p_shiftdate, p_shifttype, p_handoverby, p_handoverto,
        p_keymessages, p_pendingitems, p_vipguests, p_incidents, p_cashbalance, 'Submitted')
    RETURNING hotelshifthandoverid INTO v_id;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sphotel_shifthandover_acknowledge(
    p_id integer, p_farmid text, p_receivedby text
) RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE hotelshifthandovers
    SET status = 'Acknowledged', receivedby = p_receivedby, acknowledgedat = NOW()
    WHERE hotelshifthandoverid = p_id AND farmid = p_farmid;
END;
$function$;
