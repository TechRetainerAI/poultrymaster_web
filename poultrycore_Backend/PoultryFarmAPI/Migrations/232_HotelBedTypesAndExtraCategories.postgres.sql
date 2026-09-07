-- =============================================================================
-- Migration 232: Hotel Bed Types Lookup + Extra Room Categories  (PostgreSQL)
-- =============================================================================
-- 1. Adds missing room categories (Presidential Suite, Connecting, etc.)
-- 2. Creates HotelBedTypes system-wide lookup table with pre-defined bed types
-- 3. Adds HotelBedTypeId FK to HotelRoomTypes (replaces free-text BedType)
-- 4. Updates stored procedures accordingly
-- =============================================================================

-- =========================================================
-- PART A: Additional room categories
-- =========================================================
INSERT INTO public.hotelroomcategories (code, description, sortorder) VALUES
    ('PRS', 'Presidential Suite',  11),
    ('CON', 'Connecting Room',     12),
    ('ACC', 'Accessible Room',     13),
    ('BNG', 'Bungalow',            14),
    ('APT', 'Serviced Apartment',  15)
ON CONFLICT (code) DO NOTHING;

-- =========================================================
-- PART B: Bed Types lookup table
-- =========================================================
CREATE TABLE IF NOT EXISTS public.hotelbedtypes (
    hotelbedtypeid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

INSERT INTO public.hotelbedtypes (code, description, sortorder) VALUES
    ('SGL',  'Single',              1),
    ('TWN',  'Twin',                2),
    ('DBL',  'Double',              3),
    ('QEN',  'Queen',               4),
    ('KNG',  'King',                5),
    ('SKNG', 'Super King',          6),
    ('BNK',  'Bunk Bed',            7),
    ('SFA',  'Sofa Bed',            8),
    ('MRP',  'Murphy / Wall Bed',   9),
    ('ROL',  'Rollaway / Cot',      10),
    ('FTN',  'Futon',               11)
ON CONFLICT (code) DO NOTHING;

-- =========================================================
-- PART C: Add FK column to hotelroomtypes
-- =========================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'hotelroomtypes'
          AND column_name  = 'hotelbedtypeid'
    ) THEN
        ALTER TABLE public.hotelroomtypes
            ADD COLUMN hotelbedtypeid integer
            REFERENCES public.hotelbedtypes(hotelbedtypeid);
    END IF;
END $$;

-- =========================================================
-- PART D: Stored procedures
-- =========================================================

-- List all bed types
CREATE OR REPLACE FUNCTION public.sphotel_bedtype_list()
 RETURNS SETOF hotelbedtypes
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelbedtypes
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;

-- Drop old roomtype functions (return type changed again to add bed type join)
DROP FUNCTION IF EXISTS public.sphotel_roomtype_list(text);
DROP FUNCTION IF EXISTS public.sphotel_roomtype_get(integer, text);

-- Recreate roomtype_list with bed type join
CREATE OR REPLACE FUNCTION public.sphotel_roomtype_list(p_farmid text)
 RETURNS TABLE(
    "HotelRoomTypeId" integer, "FarmId" text, "Name" character varying,
    "Description" character varying, "BaseRate" numeric, "MaxOccupancy" integer,
    "BedType" character varying, "ImageUrl" character varying,
    "IsActive" boolean, "SortOrder" integer,
    "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone,
    "HotelRoomCategoryId" integer, "CategoryCode" character varying, "CategoryName" character varying,
    "HotelBedTypeId" integer, "BedTypeCode" character varying, "BedTypeName" character varying
 )
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT rt.hotelroomtypeid, rt.farmid, rt.name, rt.description,
           rt.baserate, rt.maxoccupancy, rt.bedtype, rt.imageurl,
           rt.isactive, rt.sortorder, rt.createdat, rt.updatedat,
           rt.hotelroomcategoryid,
           c.code, c.description,
           rt.hotelbedtypeid,
           bt.code, bt.description
    FROM hotelroomtypes rt
    LEFT JOIN hotelroomcategories c ON rt.hotelroomcategoryid = c.hotelroomcategoryid
    LEFT JOIN hotelbedtypes bt ON rt.hotelbedtypeid = bt.hotelbedtypeid
    WHERE rt.farmid = p_farmid
    ORDER BY rt.sortorder, rt.name;
END;
$function$;

-- Recreate roomtype_get with bed type join
CREATE OR REPLACE FUNCTION public.sphotel_roomtype_get(p_hotelroomtypeid integer, p_farmid text)
 RETURNS TABLE(
    "HotelRoomTypeId" integer, "FarmId" text, "Name" character varying,
    "Description" character varying, "BaseRate" numeric, "MaxOccupancy" integer,
    "BedType" character varying, "ImageUrl" character varying,
    "IsActive" boolean, "SortOrder" integer,
    "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone,
    "HotelRoomCategoryId" integer, "CategoryCode" character varying, "CategoryName" character varying,
    "HotelBedTypeId" integer, "BedTypeCode" character varying, "BedTypeName" character varying
 )
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT rt.hotelroomtypeid, rt.farmid, rt.name, rt.description,
           rt.baserate, rt.maxoccupancy, rt.bedtype, rt.imageurl,
           rt.isactive, rt.sortorder, rt.createdat, rt.updatedat,
           rt.hotelroomcategoryid,
           c.code, c.description,
           rt.hotelbedtypeid,
           bt.code, bt.description
    FROM hotelroomtypes rt
    LEFT JOIN hotelroomcategories c ON rt.hotelroomcategoryid = c.hotelroomcategoryid
    LEFT JOIN hotelbedtypes bt ON rt.hotelbedtypeid = bt.hotelbedtypeid
    WHERE rt.hotelroomtypeid = p_hotelroomtypeid AND rt.farmid = p_farmid;
END;
$function$;

-- Update roomtype_insert to accept bed type id
CREATE OR REPLACE FUNCTION public.sphotel_roomtype_insert(
    p_farmid text,
    p_name text,
    p_description text DEFAULT NULL,
    p_baserate numeric DEFAULT 0,
    p_maxoccupancy integer DEFAULT 2,
    p_bedtype text DEFAULT NULL,
    p_imageurl text DEFAULT NULL,
    p_isactive boolean DEFAULT true,
    p_sortorder integer DEFAULT 0,
    p_hotelroomcategoryid integer DEFAULT NULL,
    p_hotelbedtypeid integer DEFAULT NULL
)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_id INT;
BEGIN
    INSERT INTO hotelroomtypes(farmid, name, description, baserate, maxoccupancy, bedtype, imageurl, isactive, sortorder, hotelroomcategoryid, hotelbedtypeid)
    VALUES(p_farmid, p_name, p_description, p_baserate, p_maxoccupancy, p_bedtype, p_imageurl, p_isactive, p_sortorder, p_hotelroomcategoryid, p_hotelbedtypeid)
    RETURNING hotelroomtypeid INTO v_id;
    RETURN v_id;
END;
$function$;

-- Update roomtype_update to accept bed type id
CREATE OR REPLACE FUNCTION public.sphotel_roomtype_update(
    p_hotelroomtypeid integer,
    p_farmid text,
    p_name text,
    p_description text DEFAULT NULL,
    p_baserate numeric DEFAULT 0,
    p_maxoccupancy integer DEFAULT 2,
    p_bedtype text DEFAULT NULL,
    p_imageurl text DEFAULT NULL,
    p_isactive boolean DEFAULT true,
    p_sortorder integer DEFAULT 0,
    p_hotelroomcategoryid integer DEFAULT NULL,
    p_hotelbedtypeid integer DEFAULT NULL
)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE hotelroomtypes
    SET name=p_name, description=p_description, baserate=p_baserate,
        maxoccupancy=p_maxoccupancy, bedtype=p_bedtype, imageurl=p_imageurl,
        isactive=p_isactive, sortorder=p_sortorder,
        hotelroomcategoryid=p_hotelroomcategoryid,
        hotelbedtypeid=p_hotelbedtypeid, updatedat=NOW()
    WHERE hotelroomtypeid=p_hotelroomtypeid AND farmid=p_farmid;
END;
$function$;
