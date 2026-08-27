-- Applies 211_DriverDistributionEggUnits.postgres.sql inside one transaction,
-- then prints the resulting egg stock per farm.
--
-- Run from the Migrations folder:
--   psql "<PoultryConn>" -f 211_apply.sql
--
-- Swap COMMIT for ROLLBACK below to dry-run it again.
BEGIN;

\i 211_DriverDistributionEggUnits.postgres.sql

COMMIT;

\echo ''
\echo '===== egg stock per farm ====='
SELECT p.farmid,
       SUM(t.quantity) AS eggs,
       floor(SUM(t.quantity)/30) || ' crates + ' || (SUM(t.quantity)::int % 30) || ' loose' AS as_crates
FROM   poultryproducts p
JOIN   poultrystocktransactions t
       ON t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid
WHERE  COALESCE(p.israweggproduct, FALSE)
GROUP  BY p.farmid
ORDER  BY p.farmid;
