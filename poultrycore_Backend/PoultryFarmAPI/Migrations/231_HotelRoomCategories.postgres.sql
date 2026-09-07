-- =============================================================================
-- Migration 231: Hotel Room Categories Lookup Table  (PostgreSQL)
-- =============================================================================
-- Adds a system-wide HotelRoomCategories lookup table (not per-farm).
-- Pre-populates with 10 standard hotel room categories.
-- Adds a nullable FK HotelRoomCategoryId to HotelRoomTypes so each
-- customer-defined room type is classified under a pre-defined category.
-- =============================================================================

-- 1. Create the lookup table
CREATE TABLE IF NOT EXISTS public.hotelroomcategories (
    hotelroomcategoryid SERIAL PRIMARY KEY,
    code        character varying(10) NOT NULL UNIQUE,
    description character varying(100) NOT NULL,
    sortorder   integer DEFAULT 0 NOT NULL,
    isactive    boolean DEFAULT true NOT NULL
);

-- 2. Pre-populate with standard hotel room categories (idempotent)
INSERT INTO public.hotelroomcategories (code, description, sortorder) VALUES
    ('STD',  'Standard Room',   1),
    ('SUP',  'Superior Room',   2),
    ('DLX',  'Deluxe Room',     3),
    ('JNR',  'Junior Suite',    4),
    ('STE',  'Suite',           5),
    ('EXE',  'Executive Room',  6),
    ('FAM',  'Family Room',     7),
    ('STU',  'Studio',          8),
    ('PNT',  'Penthouse',       9),
    ('VIL',  'Villa / Cottage', 10)
ON CONFLICT (code) DO NOTHING;

-- 3. Add nullable FK column to hotelroomtypes
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'hotelroomtypes'
          AND column_name  = 'hotelroomcategoryid'
    ) THEN
        ALTER TABLE public.hotelroomtypes
            ADD COLUMN hotelroomcategoryid integer
            REFERENCES public.hotelroomcategories(hotelroomcategoryid);
    END IF;
END $$;

-- 4. Function: list all room categories (system-wide, no farmId needed)
CREATE OR REPLACE FUNCTION public.sphotel_roomcategory_list()
 RETURNS SETOF hotelroomcategories
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelroomcategories
    WHERE isactive = true
    ORDER BY sortorder, description;
END;
$function$;

-- 5. Update roomtype_insert to accept the new column
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
    p_hotelroomcategoryid integer DEFAULT NULL
)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_id INT;
BEGIN
    INSERT INTO hotelroomtypes(farmid, name, description, baserate, maxoccupancy, bedtype, imageurl, isactive, sortorder, hotelroomcategoryid)
    VALUES(p_farmid, p_name, p_description, p_baserate, p_maxoccupancy, p_bedtype, p_imageurl, p_isactive, p_sortorder, p_hotelroomcategoryid)
    RETURNING hotelroomtypeid INTO v_id;
    RETURN v_id;
END;
$function$;

-- 6. Update roomtype_update to accept the new column
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
    p_hotelroomcategoryid integer DEFAULT NULL
)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE hotelroomtypes
    SET name=p_name, description=p_description, baserate=p_baserate,
        maxoccupancy=p_maxoccupancy, bedtype=p_bedtype, imageurl=p_imageurl,
        isactive=p_isactive, sortorder=p_sortorder,
        hotelroomcategoryid=p_hotelroomcategoryid, updatedat=NOW()
    WHERE hotelroomtypeid=p_hotelroomtypeid AND farmid=p_farmid;
END;
$function$;

-- 7. Drop old roomtype_list/get (return type changed from SETOF to TABLE)
DROP FUNCTION IF EXISTS public.sphotel_roomtype_list(text);
DROP FUNCTION IF EXISTS public.sphotel_roomtype_get(integer, text);

-- 7a. Recreate roomtype_list to join category info
CREATE OR REPLACE FUNCTION public.sphotel_roomtype_list(p_farmid text)
 RETURNS TABLE(
    "HotelRoomTypeId" integer, "FarmId" text, "Name" character varying,
    "Description" character varying, "BaseRate" numeric, "MaxOccupancy" integer,
    "BedType" character varying, "ImageUrl" character varying,
    "IsActive" boolean, "SortOrder" integer,
    "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone,
    "HotelRoomCategoryId" integer, "CategoryCode" character varying, "CategoryName" character varying
 )
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT rt.hotelroomtypeid, rt.farmid, rt.name, rt.description,
           rt.baserate, rt.maxoccupancy, rt.bedtype, rt.imageurl,
           rt.isactive, rt.sortorder, rt.createdat, rt.updatedat,
           rt.hotelroomcategoryid,
           c.code, c.description
    FROM hotelroomtypes rt
    LEFT JOIN hotelroomcategories c ON rt.hotelroomcategoryid = c.hotelroomcategoryid
    WHERE rt.farmid = p_farmid
    ORDER BY rt.sortorder, rt.name;
END;
$function$;

-- 8. Update roomtype_get to join category info
CREATE OR REPLACE FUNCTION public.sphotel_roomtype_get(p_hotelroomtypeid integer, p_farmid text)
 RETURNS TABLE(
    "HotelRoomTypeId" integer, "FarmId" text, "Name" character varying,
    "Description" character varying, "BaseRate" numeric, "MaxOccupancy" integer,
    "BedType" character varying, "ImageUrl" character varying,
    "IsActive" boolean, "SortOrder" integer,
    "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone,
    "HotelRoomCategoryId" integer, "CategoryCode" character varying, "CategoryName" character varying
 )
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT rt.hotelroomtypeid, rt.farmid, rt.name, rt.description,
           rt.baserate, rt.maxoccupancy, rt.bedtype, rt.imageurl,
           rt.isactive, rt.sortorder, rt.createdat, rt.updatedat,
           rt.hotelroomcategoryid,
           c.code, c.description
    FROM hotelroomtypes rt
    LEFT JOIN hotelroomcategories c ON rt.hotelroomcategoryid = c.hotelroomcategoryid
    WHERE rt.hotelroomtypeid = p_hotelroomtypeid AND rt.farmid = p_farmid;
END;
$function$;
