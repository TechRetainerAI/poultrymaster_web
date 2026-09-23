-- =============================================================================
-- 322_HotelCapitalAssets.postgres.sql
--
-- Purpose
-- -------
-- Capital asset management and depreciation for the Hotel module.
--
-- Tables
-- ------
--   hotelassetcategories      asset type categories (10 defaults seeded)
--   hotelcapitalassets        asset register
--   hotelcapitalassetcosts    cost entries (acquisition + additional)
--   hotelassetdepreciation    monthly depreciation charges
--
-- Depreciation: straight-line, monthly = (cost - residual) / usefulLifeMonths
-- Last month gets remainder to land exactly on residual value.
--
-- Acquisition rides the expense rail — classified as CapitalAsset.
-- Depreciation writes non-cash expense rows.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. hotelassetcategories
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelassetcategories (
    hotelassetcategoryid   serial       PRIMARY KEY,
    farmid                 text         NOT NULL,
    categoryname           text         NOT NULL,
    defaultusefullifemonths int         NOT NULL DEFAULT 60,
    sortorder              int          NOT NULL DEFAULT 0,
    isactive               boolean      NOT NULL DEFAULT true,
    createdat              timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_hotelassetcategories_farmid ON public.hotelassetcategories(farmid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. hotelcapitalassets
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelcapitalassets (
    hotelcapitalassetid    serial       PRIMARY KEY,
    farmid                 text         NOT NULL,
    assetname              text         NOT NULL,
    assetnumber            text,
    hotelassetcategoryid   int          REFERENCES public.hotelassetcategories(hotelassetcategoryid),
    status                 text         NOT NULL DEFAULT 'Draft',
    acquisitiondate        date,
    inservicedate          date,
    disposaldate           date,
    acquisitioncost        numeric(14,2) NOT NULL DEFAULT 0,
    additionalcost         numeric(14,2) NOT NULL DEFAULT 0,
    totalcapitalizedcost   numeric(14,2) NOT NULL DEFAULT 0,
    residualvalue          numeric(14,2) NOT NULL DEFAULT 0,
    usefullifemonths       int          NOT NULL DEFAULT 60,
    depreciationmethod     text         NOT NULL DEFAULT 'StraightLine',
    accumulateddepreciation numeric(14,2) NOT NULL DEFAULT 0,
    currentbookvalue       numeric(14,2) NOT NULL DEFAULT 0,
    supplier               text,
    location               text,
    serialnumber           text,
    notes                  text,
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    updatedat              timestamptz,
    reversedby             text,
    reversedreason         text,
    reversedat             timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelcapitalassets_farmid ON public.hotelcapitalassets(farmid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. hotelcapitalassetcosts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelcapitalassetcosts (
    hotelcapitalassetcostid serial      PRIMARY KEY,
    farmid                 text         NOT NULL,
    hotelcapitalassetid    int          NOT NULL REFERENCES public.hotelcapitalassets(hotelcapitalassetid),
    amount                 numeric(14,2) NOT NULL,
    sourcetype             text         NOT NULL DEFAULT 'Acquisition',
    description            text,
    costdate               date,
    status                 text         NOT NULL DEFAULT 'Posted',
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    reversedby             text,
    reversedat             timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelassetcosts_assetid ON public.hotelcapitalassetcosts(hotelcapitalassetid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. hotelassetdepreciation
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelassetdepreciation (
    hotelassetdepreciationid serial     PRIMARY KEY,
    farmid                 text         NOT NULL,
    hotelcapitalassetid    int          NOT NULL REFERENCES public.hotelcapitalassets(hotelcapitalassetid),
    periodstart            date         NOT NULL,
    amount                 numeric(14,2) NOT NULL,
    accumulatedafter       numeric(14,2) NOT NULL DEFAULT 0,
    bookvalueafter         numeric(14,2) NOT NULL DEFAULT 0,
    depreciationmethod     text         NOT NULL DEFAULT 'StraightLine',
    sourcetype             text         NOT NULL DEFAULT 'Scheduled',
    reason                 text,
    status                 text         NOT NULL DEFAULT 'Posted',
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    reversedby             text,
    reversedat             timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelassetdep_assetid ON public.hotelassetdepreciation(hotelcapitalassetid);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelassetdep_period ON public.hotelassetdepreciation(hotelcapitalassetid, periodstart) WHERE status = 'Posted' AND sourcetype = 'Scheduled';

-- =============================================================================
-- STORED PROCEDURES
-- =============================================================================

-- ── Categories ───────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sphotelassetcategory_getall(p_farmid text)
RETURNS TABLE (hotelassetcategoryid int, farmid text, categoryname text, defaultusefullifemonths int, sortorder int, isactive boolean) AS $$
BEGIN
    -- Seed defaults on first read
    IF NOT EXISTS (SELECT 1 FROM public.hotelassetcategories WHERE farmid = p_farmid) THEN
        INSERT INTO public.hotelassetcategories(farmid, categoryname, defaultusefullifemonths, sortorder) VALUES
            (p_farmid, 'Building & Structure', 240, 1),
            (p_farmid, 'Furniture & Fixtures', 60, 2),
            (p_farmid, 'Kitchen Equipment', 60, 3),
            (p_farmid, 'Laundry Equipment', 60, 4),
            (p_farmid, 'HVAC Systems', 120, 5),
            (p_farmid, 'Elevator & Lift', 180, 6),
            (p_farmid, 'IT & Communication', 36, 7),
            (p_farmid, 'Vehicle', 60, 8),
            (p_farmid, 'Security Systems', 60, 9),
            (p_farmid, 'Other', 60, 10);
    END IF;
    RETURN QUERY SELECT c.hotelassetcategoryid, c.farmid, c.categoryname, c.defaultusefullifemonths, c.sortorder, c.isactive
    FROM public.hotelassetcategories c WHERE c.farmid = p_farmid ORDER BY c.sortorder;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelassetcategory_upsert(
    p_farmid text, p_id int DEFAULT NULL, p_name text DEFAULT '', p_life int DEFAULT 60, p_sort int DEFAULT 0
) RETURNS int AS $$
DECLARE v_id int;
BEGIN
    IF p_id IS NOT NULL AND p_id > 0 THEN
        UPDATE public.hotelassetcategories SET categoryname=p_name, defaultusefullifemonths=p_life, sortorder=p_sort
        WHERE hotelassetcategoryid=p_id AND farmid=p_farmid;
        RETURN p_id;
    ELSE
        INSERT INTO public.hotelassetcategories(farmid, categoryname, defaultusefullifemonths, sortorder)
        VALUES (p_farmid, p_name, p_life, p_sort) RETURNING hotelassetcategoryid INTO v_id;
        RETURN v_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ── Asset CRUD ───────────────────────────────────────────────────────────────

-- Recalculate derived fields
CREATE OR REPLACE FUNCTION public.fnhotelcapitalasset_recalc(p_assetid int) RETURNS void AS $$
DECLARE
    v_acq numeric; v_add numeric; v_total numeric; v_dep numeric; v_bv numeric;
BEGIN
    SELECT COALESCE(SUM(amount) FILTER (WHERE sourcetype='Acquisition' AND status='Posted'), 0),
           COALESCE(SUM(amount) FILTER (WHERE sourcetype IN ('AdditionalCost','OriginalCostCorrection') AND status='Posted'), 0)
    INTO v_acq, v_add FROM public.hotelcapitalassetcosts WHERE hotelcapitalassetid=p_assetid;

    v_total := v_acq + v_add;

    SELECT COALESCE(SUM(amount) FILTER (WHERE status='Posted'), 0)
    INTO v_dep FROM public.hotelassetdepreciation WHERE hotelcapitalassetid=p_assetid;

    v_bv := GREATEST(v_total - v_dep, 0);

    UPDATE public.hotelcapitalassets SET
        acquisitioncost = v_acq, additionalcost = v_add,
        totalcapitalizedcost = v_total, accumulateddepreciation = v_dep,
        currentbookvalue = v_bv, updatedat = now()
    WHERE hotelcapitalassetid = p_assetid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_create(
    p_farmid text, p_name text, p_categoryid int DEFAULT NULL, p_acquisitiondate date DEFAULT NULL,
    p_inservicedate date DEFAULT NULL, p_residualvalue numeric DEFAULT 0, p_usefullifemonths int DEFAULT 60,
    p_amount numeric DEFAULT 0, p_supplier text DEFAULT NULL, p_location text DEFAULT NULL,
    p_serialnumber text DEFAULT NULL, p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS int AS $$
DECLARE v_id int; v_num text;
BEGIN
    -- Generate asset number
    SELECT 'AST-' || LPAD((COALESCE(MAX(hotelcapitalassetid), 0) + 1)::text, 4, '0')
    INTO v_num FROM public.hotelcapitalassets WHERE farmid = p_farmid;

    INSERT INTO public.hotelcapitalassets(
        farmid, assetname, assetnumber, hotelassetcategoryid, status,
        acquisitiondate, inservicedate, residualvalue, usefullifemonths,
        supplier, location, serialnumber, notes, createdby,
        acquisitioncost, totalcapitalizedcost, currentbookvalue
    ) VALUES (
        p_farmid, p_name, v_num, p_categoryid, 'Draft',
        p_acquisitiondate, p_inservicedate, p_residualvalue, p_usefullifemonths,
        p_supplier, p_location, p_serialnumber, p_notes, p_createdby,
        p_amount, p_amount, p_amount
    ) RETURNING hotelcapitalassetid INTO v_id;

    -- If initial amount provided, insert acquisition cost
    IF p_amount > 0 THEN
        INSERT INTO public.hotelcapitalassetcosts(farmid, hotelcapitalassetid, amount, sourcetype, description, costdate, createdby)
        VALUES (p_farmid, v_id, p_amount, 'Acquisition', 'Initial acquisition cost', p_acquisitiondate, p_createdby);
    END IF;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_update(
    p_id int, p_farmid text, p_name text, p_categoryid int DEFAULT NULL,
    p_acquisitiondate date DEFAULT NULL, p_inservicedate date DEFAULT NULL,
    p_residualvalue numeric DEFAULT 0, p_usefullifemonths int DEFAULT 60,
    p_supplier text DEFAULT NULL, p_location text DEFAULT NULL,
    p_serialnumber text DEFAULT NULL, p_notes text DEFAULT NULL
) RETURNS void AS $$
BEGIN
    UPDATE public.hotelcapitalassets SET
        assetname=p_name, hotelassetcategoryid=p_categoryid,
        acquisitiondate=p_acquisitiondate, inservicedate=p_inservicedate,
        residualvalue=p_residualvalue, usefullifemonths=p_usefullifemonths,
        supplier=p_supplier, location=p_location, serialnumber=p_serialnumber,
        notes=p_notes, updatedat=now()
    WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Activate asset (Draft -> Active)
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_activate(p_id int, p_farmid text) RETURNS void AS $$
DECLARE v_status text; v_inservice date;
BEGIN
    SELECT status, inservicedate INTO v_status, v_inservice FROM public.hotelcapitalassets WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft assets can be activated'; END IF;
    IF v_inservice IS NULL THEN RAISE EXCEPTION 'In-service date is required'; END IF;
    UPDATE public.hotelcapitalassets SET status='Active', updatedat=now() WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Add cost
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_addcost(
    p_assetid int, p_farmid text, p_amount numeric, p_description text DEFAULT NULL,
    p_costdate date DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS int AS $$
DECLARE v_id int;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Cost amount must be positive'; END IF;
    INSERT INTO public.hotelcapitalassetcosts(farmid, hotelcapitalassetid, amount, sourcetype, description, costdate, createdby)
    VALUES (p_farmid, p_assetid, p_amount, 'AdditionalCost', p_description, p_costdate, p_createdby)
    RETURNING hotelcapitalassetcostid INTO v_id;
    PERFORM fnhotelcapitalasset_recalc(p_assetid);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Reverse cost
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_reversecost(
    p_costid int, p_assetid int, p_farmid text, p_reason text DEFAULT NULL, p_by text DEFAULT NULL
) RETURNS void AS $$
BEGIN
    UPDATE public.hotelcapitalassetcosts SET status='Reversed', reversedby=p_by, reversedat=now()
    WHERE hotelcapitalassetcostid=p_costid AND hotelcapitalassetid=p_assetid AND farmid=p_farmid AND status='Posted';
    PERFORM fnhotelcapitalasset_recalc(p_assetid);
END;
$$ LANGUAGE plpgsql;

-- Dispose asset
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_dispose(
    p_id int, p_farmid text, p_disposaldate date DEFAULT NULL, p_reason text DEFAULT NULL, p_by text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_status text;
BEGIN
    SELECT status INTO v_status FROM public.hotelcapitalassets WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
    IF v_status NOT IN ('Active','FullyDepreciated') THEN RAISE EXCEPTION 'Only Active or FullyDepreciated assets can be disposed'; END IF;
    UPDATE public.hotelcapitalassets SET status='Disposed', disposaldate=COALESCE(p_disposaldate, CURRENT_DATE),
        reversedreason=p_reason, reversedby=p_by, reversedat=now(), updatedat=now()
    WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Reverse asset
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_reverse(
    p_id int, p_farmid text, p_reason text DEFAULT NULL, p_by text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_depcount int;
BEGIN
    SELECT COUNT(*) INTO v_depcount FROM public.hotelassetdepreciation WHERE hotelcapitalassetid=p_id AND status='Posted';
    IF v_depcount > 0 THEN RAISE EXCEPTION 'Cannot reverse: % depreciation entries exist. Reverse them first.', v_depcount; END IF;
    UPDATE public.hotelcapitalassets SET status='Reversed', reversedreason=p_reason, reversedby=p_by, reversedat=now(), updatedat=now()
    WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ── Read functions ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_getall(
    p_farmid text, p_status text DEFAULT NULL, p_categoryid int DEFAULT NULL
) RETURNS TABLE (
    hotelcapitalassetid int, farmid text, assetname text, assetnumber text,
    hotelassetcategoryid int, categoryname text, status text,
    acquisitiondate date, inservicedate date, disposaldate date,
    acquisitioncost numeric, additionalcost numeric, totalcapitalizedcost numeric,
    residualvalue numeric, usefullifemonths int, depreciationmethod text,
    accumulateddepreciation numeric, currentbookvalue numeric,
    supplier text, location text, serialnumber text, notes text,
    createdby text, createdat timestamptz, updatedat timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT a.hotelcapitalassetid, a.farmid, a.assetname, a.assetnumber,
           a.hotelassetcategoryid, COALESCE(c.categoryname, 'Uncategorized'),
           a.status, a.acquisitiondate, a.inservicedate, a.disposaldate,
           a.acquisitioncost, a.additionalcost, a.totalcapitalizedcost,
           a.residualvalue, a.usefullifemonths, a.depreciationmethod,
           a.accumulateddepreciation, a.currentbookvalue,
           a.supplier, a.location, a.serialnumber, a.notes,
           a.createdby, a.createdat, a.updatedat
    FROM public.hotelcapitalassets a
    LEFT JOIN public.hotelassetcategories c ON c.hotelassetcategoryid = a.hotelassetcategoryid
    WHERE a.farmid = p_farmid
      AND (p_status IS NULL OR a.status = p_status)
      AND (p_categoryid IS NULL OR a.hotelassetcategoryid = p_categoryid)
    ORDER BY a.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_getbyid(p_id int, p_farmid text)
RETURNS TABLE (
    hotelcapitalassetid int, farmid text, assetname text, assetnumber text,
    hotelassetcategoryid int, categoryname text, status text,
    acquisitiondate date, inservicedate date, disposaldate date,
    acquisitioncost numeric, additionalcost numeric, totalcapitalizedcost numeric,
    residualvalue numeric, usefullifemonths int, depreciationmethod text,
    accumulateddepreciation numeric, currentbookvalue numeric,
    supplier text, location text, serialnumber text, notes text,
    createdby text, createdat timestamptz, updatedat timestamptz,
    reversedby text, reversedreason text, reversedat timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT a.hotelcapitalassetid, a.farmid, a.assetname, a.assetnumber,
           a.hotelassetcategoryid, COALESCE(c.categoryname, 'Uncategorized'),
           a.status, a.acquisitiondate, a.inservicedate, a.disposaldate,
           a.acquisitioncost, a.additionalcost, a.totalcapitalizedcost,
           a.residualvalue, a.usefullifemonths, a.depreciationmethod,
           a.accumulateddepreciation, a.currentbookvalue,
           a.supplier, a.location, a.serialnumber, a.notes,
           a.createdby, a.createdat, a.updatedat,
           a.reversedby, a.reversedreason, a.reversedat
    FROM public.hotelcapitalassets a
    LEFT JOIN public.hotelassetcategories c ON c.hotelassetcategoryid = a.hotelassetcategoryid
    WHERE a.hotelcapitalassetid = p_id AND a.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Get costs for an asset
CREATE OR REPLACE FUNCTION public.sphotelcapitalassetcost_getall(p_assetid int, p_farmid text)
RETURNS TABLE (hotelcapitalassetcostid int, farmid text, hotelcapitalassetid int, amount numeric,
    sourcetype text, description text, costdate date, status text, createdby text, createdat timestamptz) AS $$
BEGIN
    RETURN QUERY SELECT co.hotelcapitalassetcostid, co.farmid, co.hotelcapitalassetid, co.amount,
        co.sourcetype, co.description, co.costdate, co.status, co.createdby, co.createdat
    FROM public.hotelcapitalassetcosts co WHERE co.hotelcapitalassetid=p_assetid AND co.farmid=p_farmid ORDER BY co.createdat;
END;
$$ LANGUAGE plpgsql;

-- ── Depreciation ─────────────────────────────────────────────────────────────

-- Generate depreciation (idempotent)
CREATE OR REPLACE FUNCTION public.sphotelassetdepreciation_generate(
    p_farmid text, p_throughdate date DEFAULT CURRENT_DATE, p_assetid int DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS TABLE (assetsprocessed int, entriescreated int, totalamount numeric) AS $$
DECLARE
    v_asset record;
    v_monthly numeric;
    v_depreciable numeric;
    v_period date;
    v_accum numeric;
    v_charge numeric;
    v_remaining numeric;
    v_total_assets int := 0;
    v_total_entries int := 0;
    v_total_amount numeric := 0;
BEGIN
    FOR v_asset IN
        SELECT * FROM public.hotelcapitalassets
        WHERE farmid = p_farmid AND status = 'Active' AND inservicedate IS NOT NULL
          AND (p_assetid IS NULL OR hotelcapitalassetid = p_assetid)
    LOOP
        v_depreciable := GREATEST(v_asset.totalcapitalizedcost - v_asset.residualvalue, 0);
        IF v_depreciable <= 0 OR v_asset.usefullifemonths <= 0 THEN CONTINUE; END IF;

        v_monthly := ROUND(v_depreciable / v_asset.usefullifemonths, 2);
        v_period := date_trunc('month', v_asset.inservicedate)::date;
        v_accum := v_asset.accumulateddepreciation;
        v_total_assets := v_total_assets + 1;

        WHILE v_period <= p_throughdate AND v_accum < v_depreciable LOOP
            -- Skip if already charged
            IF NOT EXISTS (SELECT 1 FROM public.hotelassetdepreciation
                          WHERE hotelcapitalassetid = v_asset.hotelcapitalassetid
                            AND periodstart = v_period AND status = 'Posted' AND sourcetype = 'Scheduled') THEN

                v_remaining := v_depreciable - v_accum;
                v_charge := LEAST(v_monthly, v_remaining);
                v_accum := v_accum + v_charge;

                INSERT INTO public.hotelassetdepreciation(
                    farmid, hotelcapitalassetid, periodstart, amount,
                    accumulatedafter, bookvalueafter, depreciationmethod, sourcetype, createdby
                ) VALUES (
                    p_farmid, v_asset.hotelcapitalassetid, v_period, v_charge,
                    v_accum, GREATEST(v_asset.totalcapitalizedcost - v_accum, 0),
                    'StraightLine', 'Scheduled', p_createdby
                );

                v_total_entries := v_total_entries + 1;
                v_total_amount := v_total_amount + v_charge;
            ELSE
                -- Already exists, just track accumulation
                SELECT accumulatedafter INTO v_accum FROM public.hotelassetdepreciation
                WHERE hotelcapitalassetid = v_asset.hotelcapitalassetid AND periodstart = v_period
                  AND status = 'Posted' AND sourcetype = 'Scheduled';
            END IF;

            v_period := (v_period + interval '1 month')::date;
        END LOOP;

        -- Update asset
        PERFORM fnhotelcapitalasset_recalc(v_asset.hotelcapitalassetid);

        -- Check if fully depreciated
        IF v_accum >= v_depreciable THEN
            UPDATE public.hotelcapitalassets SET status = 'FullyDepreciated', updatedat = now()
            WHERE hotelcapitalassetid = v_asset.hotelcapitalassetid AND farmid = p_farmid AND status = 'Active';
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_total_assets, v_total_entries, v_total_amount;
END;
$$ LANGUAGE plpgsql;

-- Get depreciation entries
CREATE OR REPLACE FUNCTION public.sphotelassetdepreciation_getall(
    p_farmid text, p_assetid int DEFAULT NULL
) RETURNS TABLE (
    hotelassetdepreciationid int, farmid text, hotelcapitalassetid int, assetname text,
    periodstart date, amount numeric, accumulatedafter numeric, bookvalueafter numeric,
    depreciationmethod text, sourcetype text, reason text, status text,
    createdby text, createdat timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.hotelassetdepreciationid, d.farmid, d.hotelcapitalassetid, a.assetname,
           d.periodstart, d.amount, d.accumulatedafter, d.bookvalueafter,
           d.depreciationmethod, d.sourcetype, d.reason, d.status,
           d.createdby, d.createdat
    FROM public.hotelassetdepreciation d
    JOIN public.hotelcapitalassets a ON a.hotelcapitalassetid = d.hotelcapitalassetid
    WHERE d.farmid = p_farmid AND (p_assetid IS NULL OR d.hotelcapitalassetid = p_assetid)
    ORDER BY d.periodstart DESC, d.createdat DESC;
END;
$$ LANGUAGE plpgsql;

-- Reverse depreciation entry
CREATE OR REPLACE FUNCTION public.sphotelassetdepreciation_reverse(
    p_entryid int, p_farmid text, p_reason text DEFAULT NULL, p_by text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_assetid int;
BEGIN
    SELECT hotelcapitalassetid INTO v_assetid FROM public.hotelassetdepreciation
    WHERE hotelassetdepreciationid = p_entryid AND farmid = p_farmid AND status = 'Posted';
    IF NOT FOUND THEN RAISE EXCEPTION 'Depreciation entry not found or already reversed'; END IF;

    UPDATE public.hotelassetdepreciation SET status='Reversed', reversedby=p_by, reversedat=now()
    WHERE hotelassetdepreciationid = p_entryid;

    PERFORM fnhotelcapitalasset_recalc(v_assetid);

    -- If asset was FullyDepreciated, set back to Active
    UPDATE public.hotelcapitalassets SET status = 'Active', updatedat = now()
    WHERE hotelcapitalassetid = v_assetid AND farmid = p_farmid AND status = 'FullyDepreciated';
END;
$$ LANGUAGE plpgsql;

-- Summary
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_summary(p_farmid text)
RETURNS TABLE (totalassets int, activeassets int, draftassets int, totalassetcost numeric,
    accumulateddepreciation numeric, currentbookvalue numeric) AS $$
BEGIN
    RETURN QUERY
    SELECT COUNT(*)::int,
           COUNT(*) FILTER (WHERE a.status='Active')::int,
           COUNT(*) FILTER (WHERE a.status='Draft')::int,
           COALESCE(SUM(a.totalcapitalizedcost), 0),
           COALESCE(SUM(a.accumulateddepreciation), 0),
           COALESCE(SUM(a.currentbookvalue), 0)
    FROM public.hotelcapitalassets a WHERE a.farmid = p_farmid AND a.status NOT IN ('Reversed');
END;
$$ LANGUAGE plpgsql;

COMMIT;
