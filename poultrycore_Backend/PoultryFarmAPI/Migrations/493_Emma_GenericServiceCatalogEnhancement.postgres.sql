-- =============================================================================
-- Migration 493 — Enhance GenericServices table for the full Products & Services
-- catalog spec: add ServiceCode, Description, PricingUnit, ArchivedAt,
-- CreatedBy, UpdatedBy.  Rewrite all service-catalog SPs to include the new
-- columns.
-- =============================================================================
-- Idempotent: every DDL is guarded.
-- =============================================================================

-- 1. New columns on genericservices
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'genericservices' AND column_name = 'servicecode') THEN
        ALTER TABLE public.genericservices
            ADD COLUMN servicecode   varchar(60)  NULL,
            ADD COLUMN description   text         NULL,
            ADD COLUMN pricingunit   varchar(30)  NOT NULL DEFAULT 'Per Job',
            ADD COLUMN archivedat    timestamp    NULL,
            ADD COLUMN createdby     text         NULL,
            ADD COLUMN updatedby     text         NULL;
    END IF;
END $$;

-- 2. Unique constraint: (farmid, servicecode) where servicecode is not null
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes
                   WHERE indexname = 'uq_genericservices_farm_code') THEN
        CREATE UNIQUE INDEX uq_genericservices_farm_code
            ON public.genericservices (farmid, servicecode)
            WHERE servicecode IS NOT NULL;
    END IF;
END $$;

-- =============================================================================
-- 3. Rewrite service-catalog SPs to include new columns
-- =============================================================================

-- Drop functions whose return type is changing (PG requires explicit drop)
DROP FUNCTION IF EXISTS public.spgenericservice_getall(text);
DROP FUNCTION IF EXISTS public.spgenericservice_getbyid(integer, text);

-- 3a. GetAll
CREATE OR REPLACE FUNCTION public.spgenericservice_getall(p_farmid text)
RETURNS TABLE(
    genericserviceid         integer,
    farmid                   text,
    genericservicecategoryid integer,
    categoryname             text,
    servicename              text,
    servicecode              text,
    description              text,
    pricingunit              text,
    defaultprice             numeric,
    estimatedcost            numeric,
    durationminutes          integer,
    assignedstaffid          integer,
    isactive                 boolean,
    isdeleted                boolean,
    notes                    text,
    archivedat               timestamp,
    createdby                text,
    updatedby                text,
    createdat                timestamp,
    updatedat                timestamp
)
LANGUAGE plpgsql AS $function$
BEGIN
    RETURN QUERY
    SELECT s.genericserviceid,
           s.farmid::text,
           s.genericservicecategoryid,
           c.name::text AS categoryname,
           s.servicename::text,
           s.servicecode::text,
           s.description::text,
           s.pricingunit::text,
           s.defaultprice,
           s.estimatedcost,
           s.durationminutes,
           s.assignedstaffid,
           s.isactive,
           s.isdeleted,
           s.notes::text,
           s.archivedat,
           s.createdby::text,
           s.updatedby::text,
           s.createdat,
           s.updatedat
    FROM   public.genericservices s
    LEFT   JOIN public.genericservicecategories c
           ON c.genericservicecategoryid = s.genericservicecategoryid
    WHERE  s.farmid = p_farmid AND s.isdeleted = FALSE
    ORDER  BY s.servicename;
END;
$function$;

-- 3b. GetById
CREATE OR REPLACE FUNCTION public.spgenericservice_getbyid(
    p_genericserviceid integer,
    p_farmid text)
RETURNS TABLE(
    genericserviceid         integer,
    farmid                   text,
    genericservicecategoryid integer,
    categoryname             text,
    servicename              text,
    servicecode              text,
    description              text,
    pricingunit              text,
    defaultprice             numeric,
    estimatedcost            numeric,
    durationminutes          integer,
    assignedstaffid          integer,
    isactive                 boolean,
    isdeleted                boolean,
    notes                    text,
    archivedat               timestamp,
    createdby                text,
    updatedby                text,
    createdat                timestamp,
    updatedat                timestamp
)
LANGUAGE plpgsql AS $function$
BEGIN
    RETURN QUERY
    SELECT s.genericserviceid,
           s.farmid::text,
           s.genericservicecategoryid,
           c.name::text AS categoryname,
           s.servicename::text,
           s.servicecode::text,
           s.description::text,
           s.pricingunit::text,
           s.defaultprice,
           s.estimatedcost,
           s.durationminutes,
           s.assignedstaffid,
           s.isactive,
           s.isdeleted,
           s.notes::text,
           s.archivedat,
           s.createdby::text,
           s.updatedby::text,
           s.createdat,
           s.updatedat
    FROM   public.genericservices s
    LEFT   JOIN public.genericservicecategories c
           ON c.genericservicecategoryid = s.genericservicecategoryid
    WHERE  s.genericserviceid = p_genericserviceid
      AND  s.farmid = p_farmid;
END;
$function$;

-- 3c. Insert
CREATE OR REPLACE FUNCTION public.spgenericservice_insert(
    p_farmid                   text,
    p_genericservicecategoryid integer DEFAULT NULL,
    p_servicename              text    DEFAULT NULL,
    p_servicecode              text    DEFAULT NULL,
    p_description              text    DEFAULT NULL,
    p_pricingunit              text    DEFAULT 'Per Job',
    p_defaultprice             numeric DEFAULT 0,
    p_estimatedcost            numeric DEFAULT NULL,
    p_durationminutes          integer DEFAULT NULL,
    p_assignedstaffid          integer DEFAULT NULL,
    p_isactive                 boolean DEFAULT TRUE,
    p_notes                    text    DEFAULT NULL,
    p_createdby                text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $function$
DECLARE v_id integer;
BEGIN
    INSERT INTO public.genericservices (
        farmid, genericservicecategoryid, servicename, servicecode,
        description, pricingunit, defaultprice, estimatedcost,
        durationminutes, assignedstaffid, isactive, notes, createdby
    ) VALUES (
        p_farmid, p_genericservicecategoryid, p_servicename, NULLIF(btrim(p_servicecode), ''),
        p_description, COALESCE(NULLIF(btrim(p_pricingunit), ''), 'Per Job'),
        COALESCE(p_defaultprice, 0), p_estimatedcost,
        p_durationminutes, p_assignedstaffid, p_isactive, p_notes, p_createdby
    )
    RETURNING genericserviceid INTO v_id;
    RETURN v_id;
END;
$function$;

-- 3d. Update
CREATE OR REPLACE FUNCTION public.spgenericservice_update(
    p_genericserviceid         integer,
    p_farmid                   text,
    p_genericservicecategoryid integer DEFAULT NULL,
    p_servicename              text    DEFAULT NULL,
    p_servicecode              text    DEFAULT NULL,
    p_description              text    DEFAULT NULL,
    p_pricingunit              text    DEFAULT NULL,
    p_defaultprice             numeric DEFAULT NULL,
    p_estimatedcost            numeric DEFAULT NULL,
    p_durationminutes          integer DEFAULT NULL,
    p_assignedstaffid          integer DEFAULT NULL,
    p_isactive                 boolean DEFAULT NULL,
    p_notes                    text    DEFAULT NULL,
    p_updatedby                text    DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $function$
BEGIN
    UPDATE public.genericservices
    SET    genericservicecategoryid = p_genericservicecategoryid,
           servicename             = COALESCE(p_servicename, servicename),
           servicecode             = NULLIF(btrim(p_servicecode), ''),
           description             = p_description,
           pricingunit             = COALESCE(NULLIF(btrim(p_pricingunit), ''), pricingunit),
           defaultprice            = COALESCE(p_defaultprice, defaultprice),
           estimatedcost           = p_estimatedcost,
           durationminutes         = p_durationminutes,
           assignedstaffid         = p_assignedstaffid,
           isactive                = COALESCE(p_isactive, isactive),
           notes                   = p_notes,
           updatedby               = p_updatedby,
           updatedat               = now()
    WHERE  genericserviceid = p_genericserviceid
      AND  farmid = p_farmid;
END;
$function$;

-- 3e. Delete (soft-delete)
CREATE OR REPLACE FUNCTION public.spgenericservice_delete(
    p_genericserviceid integer,
    p_farmid text)
RETURNS void
LANGUAGE plpgsql AS $function$
BEGIN
    UPDATE public.genericservices
    SET    isdeleted = TRUE, updatedat = now()
    WHERE  genericserviceid = p_genericserviceid
      AND  farmid = p_farmid;
END;
$function$;

-- 3f. Archive
CREATE OR REPLACE FUNCTION public.spgenericservice_archive(
    p_genericserviceid integer,
    p_farmid text,
    p_archivedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $function$
BEGIN
    UPDATE public.genericservices
    SET    archivedat = now(),
           isactive   = FALSE,
           updatedby  = p_archivedby,
           updatedat  = now()
    WHERE  genericserviceid = p_genericserviceid
      AND  farmid = p_farmid;
END;
$function$;

-- 3g. Activate / Deactivate
CREATE OR REPLACE FUNCTION public.spgenericservice_setactive(
    p_genericserviceid integer,
    p_farmid text,
    p_isactive boolean DEFAULT TRUE,
    p_updatedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $function$
BEGIN
    UPDATE public.genericservices
    SET    isactive  = p_isactive,
           updatedby = p_updatedby,
           updatedat = now()
    WHERE  genericserviceid = p_genericserviceid
      AND  farmid = p_farmid;
END;
$function$;

-- 3h. Check if service has posted sales (for safe delete guard)
CREATE OR REPLACE FUNCTION public.spgenericservice_haspostedsales(
    p_genericserviceid integer,
    p_farmid text)
RETURNS boolean
LANGUAGE plpgsql AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM   public.genericsaleitems i
        INNER  JOIN public.genericsales s
               ON s.genericsaleid = i.genericsaleid AND s.farmid = i.farmid
        WHERE  i.genericserviceid = p_genericserviceid
          AND  i.farmid = p_farmid
          AND  s.status = 'Approved'
    );
END;
$function$;
