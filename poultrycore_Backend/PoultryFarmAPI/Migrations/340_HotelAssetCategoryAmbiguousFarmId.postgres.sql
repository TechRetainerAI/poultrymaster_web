-- =============================================================================
-- 340_HotelAssetCategoryAmbiguousFarmId.postgres.sql
--
-- sphotelassetcategory_getall (322) failed on every call with
--   42702: column reference "farmid" is ambiguous
-- Its RETURNS TABLE declares an output column named farmid, and the
-- "seed defaults on first read" check used an unqualified farmid, which
-- PL/pgSQL can't tell apart from that output column. The Hotel's Capital
-- Investments/Assets page loads categories first, so the whole page showed
-- "Failed". Same signature and columns; the table is now aliased.
-- Idempotent (CREATE OR REPLACE, unchanged RETURNS TABLE).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sphotelassetcategory_getall(p_farmid text)
RETURNS TABLE (hotelassetcategoryid int, farmid text, categoryname text, defaultusefullifemonths int, sortorder int, isactive boolean) AS $$
BEGIN
    -- Seed defaults on first read
    IF NOT EXISTS (SELECT 1 FROM public.hotelassetcategories x WHERE x.farmid = p_farmid) THEN
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
