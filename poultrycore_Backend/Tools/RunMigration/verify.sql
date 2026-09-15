-- Post-migration verification for 287. Read-only.
SELECT 'farmid column' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name='restaurantmenuitemnames' AND column_name='farmid')
            THEN 'PRESENT' ELSE 'MISSING' END AS result
UNION ALL
SELECT 'old global unique on code',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conname='restaurantmenuitemnames_code_key')
            THEN 'STILL THERE (bad)' ELSE 'DROPPED (ok)' END
UNION ALL
SELECT 'ux farm_code index',
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_restaurantmenuitemnames_farm_code')
            THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
SELECT 'ux farm_desc index',
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_restaurantmenuitemnames_farm_desc')
            THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
SELECT 'fn list_for_farm',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='sprestaurant_menuitemname_list_for_farm')
            THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
SELECT 'fn insert',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname='sprestaurant_menuitemname_insert')
            THEN 'PRESENT' ELSE 'MISSING' END
UNION ALL
-- The seam that matters: Hotel Setup reads sprestaurant_menuitemname_list().
-- It must still return every seeded row, exactly as before.
SELECT 'HOTEL list() row count',
       (SELECT count(*)::text FROM sprestaurant_menuitemname_list())
UNION ALL
SELECT 'total rows in table',
       (SELECT count(*)::text FROM restaurantmenuitemnames)
UNION ALL
SELECT 'rows with farmid set (should be 0 now)',
       (SELECT count(*)::text FROM restaurantmenuitemnames WHERE farmid IS NOT NULL);
