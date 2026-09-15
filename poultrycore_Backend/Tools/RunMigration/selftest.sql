-- End-to-end self-test of migration 287, using a throwaway farm id.
-- Read/write, but only against farmid '__selftest__'; cleaned up by cleanup.sql.
WITH ins AS (
    SELECT * FROM sprestaurant_menuitemname_insert('__selftest__', 'Kelewele Special', 'Sides')
),
ins_again AS (
    -- idempotency: adding the same name twice must NOT create a second row
    SELECT * FROM sprestaurant_menuitemname_insert('__selftest__', 'kelewele special', 'Sides')
),
results AS (
    SELECT 'insert returned id'          AS check, (SELECT restaurantmenuitemnameid::text FROM ins) AS result
    UNION ALL
    SELECT 'generated code',             (SELECT code FROM ins)
    UNION ALL
    SELECT 'idempotent (same id twice)',
           CASE WHEN (SELECT restaurantmenuitemnameid FROM ins) = (SELECT restaurantmenuitemnameid FROM ins_again)
                THEN 'YES (ok)' ELSE 'NO (bug)' END
    UNION ALL
    SELECT 'rows for __selftest__ farm', (SELECT count(*)::text FROM restaurantmenuitemnames WHERE farmid='__selftest__')
    UNION ALL
    SELECT 'farm list sees it',
           CASE WHEN EXISTS (SELECT 1 FROM sprestaurant_menuitemname_list_for_farm('__selftest__')
                             WHERE description='Kelewele Special')
                THEN 'YES (ok)' ELSE 'NO (bug)' END
    UNION ALL
    SELECT 'farm list total (43 seed + 1)',
           (SELECT count(*)::text FROM sprestaurant_menuitemname_list_for_farm('__selftest__'))
    UNION ALL
    SELECT 'OTHER farm does NOT see it',
           CASE WHEN EXISTS (SELECT 1 FROM sprestaurant_menuitemname_list_for_farm('__other_farm__')
                             WHERE description='Kelewele Special')
                THEN 'LEAKED (bug)' ELSE 'isolated (ok)' END
    UNION ALL
    SELECT 'HOTEL list does NOT see it',
           CASE WHEN EXISTS (SELECT 1 FROM sprestaurant_menuitemname_list() WHERE description='Kelewele Special')
                THEN 'LEAKED INTO HOTEL (bug)' ELSE 'isolated (ok)' END
    UNION ALL
    SELECT 'HOTEL list still 43',        (SELECT count(*)::text FROM sprestaurant_menuitemname_list())
)
SELECT * FROM results;
