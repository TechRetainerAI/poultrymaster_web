-- What is actually IN this database, migration by migration.
--
-- Read-only. Creates nothing, changes nothing, needs no transaction. Safe to
-- run against production.
--
--   psql -h <host> -U <user> -d <db> -X -w -f poultry-migration-state.probe.sql
--
-- WHY THIS EXISTS
-- ---------------
-- Migrations here are applied by hand, and nothing records that they were. The
-- file being present in Migrations/ says only that somebody WROTE it. So when a
-- screen fails with "function ... does not exist", the question is not "is the
-- file there" but "did anyone run it against THIS database" -- and the only
-- honest way to answer is to look for what each one actually created.
--
-- Each row probes a landmark: a function, a table or a column that a specific
-- migration introduced and nothing else creates. present = t means that
-- migration ran here.
--
-- READING IT
-- ----------
-- The poultry cost-recognition chain 261-268 is ORDERED -- each builds on the
-- one before -- so the first f in that block is where the chain stops, and
-- everything after it is unreachable regardless of whether its file exists.
-- 288 sits on top of the whole chain and cannot work without it.
--
-- The gaps in the file numbering (275, 277-281, 285) are WATER migrations that
-- were never written -- blocked on SP bodies that are not in this repo. They
-- are not missing poultry work and nothing here depends on them.

\pset footer off
\echo ''
\echo '=== poultry cost-recognition chain: what this database actually has ==='
\echo ''

WITH probe(ord, migration, landmark, kind, present) AS (
    VALUES
    -- 261: the settings table, the resolver, and the item-level override.
    (1, '261 CostRecognitionFoundation', 'poultryfinancialsettings', 'table',
        to_regclass('public.poultryfinancialsettings') IS NOT NULL),
    (2, '261 CostRecognitionFoundation', 'fnpoultrycostrecognition_expenseatpurchase', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'fnpoultrycostrecognition_expenseatpurchase')),
    (3, '261 CostRecognitionFoundation', 'purchases.costrecognitionmethod', 'column',
        EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name = 'poultryrawmaterialpurchases' AND column_name = 'costrecognitionmethod')),

    -- 264: the deferred pair on the lot, and on the allocation.
    (4, '264 DeferredCostLayers', 'purchases.deferredremainingcost', 'column',
        EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name = 'poultryrawmaterialpurchases' AND column_name = 'deferredremainingcost')),
    (5, '264 DeferredCostLayers', 'usagebatch.deferredcostdrawn', 'column',
        EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name = 'poultryrawmaterialusagebatch' AND column_name = 'deferredcostdrawn')),

    -- 265/266: the deferred cost is opened, carried, and finally spent.
    (6, '266 ConsumptionRecognition', 'sppoultryconsumption_recognise', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultryconsumption_recognise')),
    (7, '266 ConsumptionRecognition', 'sppoultryconsumption_unrecognise', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultryconsumption_unrecognise')),

    -- 267/268: the two inventory values, the audit, and the read surface the
    -- Inventory Items page already uses.
    (8, '267 CostLayerGuards', 'fnpoultryinventoryvaluation', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'fnpoultryinventoryvaluation')),
    (9, '268 CostRecognitionReads', 'sppoultryinventoryvaluation_getall', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultryinventoryvaluation_getall')),

    -- 269-273: the later poultry work, listed so a gap here is visible too.
    (10, '272 ProfitLossRedesign', 'sppoultryreport_profitloss', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultryreport_profitloss')),
    (11, '270 CapitalAssets', 'poultrycapitalassets', 'table',
        to_regclass('public.poultrycapitalassets') IS NOT NULL),

    -- 287: uncommitted at the time of writing, so worth confirming separately.
    (12, '287 OwnerMoneyReadsCashAdjustments', 'fnpoultryownermoney_legacy', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'fnpoultryownermoney_legacy')),

    -- 288: the Deferred Inventory Costs page. All five, because a partial
    -- apply is impossible (one transaction) but a partial DROP is not.
    (13, '288 DeferredInventoryCostReads', 'fnpoultrydeferredpurchase_rows', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'fnpoultrydeferredpurchase_rows')),
    (14, '288 DeferredInventoryCostReads', 'sppoultrydeferredpurchase_getall', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultrydeferredpurchase_getall')),
    (15, '288 DeferredInventoryCostReads', 'sppoultrydeferredpurchase_summary', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultrydeferredpurchase_summary')),
    (16, '288 DeferredInventoryCostReads', 'sppoultrydeferredpurchase_history', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultrydeferredpurchase_history')),
    (17, '288 DeferredInventoryCostReads', 'sppoultryconsumption_costbreakdown', 'function',
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'public' AND p.proname = 'sppoultryconsumption_costbreakdown'))
)
SELECT migration,
       kind,
       landmark,
       present,
       CASE WHEN present THEN '' ELSE '  <-- NOT APPLIED' END AS note
FROM   probe
ORDER  BY ord;

\echo ''
\echo '=== verdict ==='

WITH f AS (
    SELECT count(*) FILTER (WHERE p.proname IN (
               'fnpoultrydeferredpurchase_rows', 'sppoultrydeferredpurchase_getall',
               'sppoultrydeferredpurchase_summary', 'sppoultrydeferredpurchase_history',
               'sppoultryconsumption_costbreakdown')) AS n288,
           count(*) FILTER (WHERE p.proname IN (
               'fnpoultrycostrecognition_expenseatpurchase', 'sppoultryconsumption_recognise',
               'fnpoultryinventoryvaluation', 'sppoultryinventoryvaluation_getall')) AS nchain
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public'
)
SELECT CASE
    WHEN nchain < 4 THEN
        'The 261-268 chain is INCOMPLETE (' || nchain || '/4 landmarks). Apply stages 1-8 '
        || 'of apply-poultry-cost-recognition.ps1 BEFORE stage 9 -- 288 reads columns and '
        || 'functions those create and will fail without them.'
    WHEN n288 = 5 THEN
        '288 is fully applied (5/5). If the page still errors, it is not the database.'
    WHEN n288 = 0 THEN
        'The 261-268 chain is present, and 288 is NOT applied (0/5). This is the ordinary '
        || 'case: run apply-poultry-cost-recognition.ps1 -Stage 9 -Apply.'
    ELSE
        '288 is PARTIALLY present (' || n288 || '/5), which a single-transaction apply cannot '
        || 'produce. Something dropped functions afterwards. Re-run stage 9 with -Apply.'
END AS verdict
FROM f;

\echo ''
