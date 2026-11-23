-- =============================================================================
-- 481: Egg Cost & Profit Analyzer (Poultry, Tools menu).
--
-- An ANALYTICAL READ MODEL. Nothing here writes to production, stock,
-- expenses, payroll, sales, cash, customer/supplier balances or the P&L. The
-- only rows written are the analyzer's own: costing settings, per-flock
-- lifetime assumptions, historical (pre-VisibilityCore) cost-basis entries,
-- saved snapshots, and an audit trail of who changed which assumption.
--
-- COST BASIS (why it cannot double count)
-- The analyzer uses the OPERATIONAL basis for feed and medication, i.e. what
-- was CONSUMED, valued by the existing cost layers (FIFO/LIFO/HIFO draws):
--     productionrecords.totalfeedcost / totalmedicationcost
-- (one per production record, filled by sppoultryproductionrawmaterialsync;
-- batch production allocations land on the same per-flock records). Every
-- expense row that represents the SAME stock -- raw-material purchase expenses
-- (PoultryRawMaterialPurchase) and consumption recognition expenses
-- (PoultryFeedConsumption / PoultryMedicationConsumption) -- is therefore
-- EXCLUDED and reported in the reconciliation instead. Internally produced
-- feed is costed once: its ingredients become the finished-feed lot's unit
-- cost (265) and only the finished feed EATEN reaches a production record.
--
-- Everything else comes from the expense table through the P&L's own
-- classifier, fnpoultrypl_expenselines (272), so a cost lands on the same line
-- here as on the P&L:
--   Payroll / DirectLabour      -> Labour       (payroll approval rows, never the run totals)
--   Utilities                   -> Utilities    (shared overhead unless flock-tagged)
--   OtherOperating, OtherDirect -> Overhead     (shared overhead unless flock-tagged)
--   Medication (manual)         -> Veterinary   (health services entered as expenses)
--   Feed (manual)               -> DirectFeedExpense (excluded by default: setting)
--   ProductionSupplies          -> Packaging    (purchase-based; packaged cost only)
--   Depreciation                -> Depreciation (posted charges, never acquisition cost)
--   FlockCost (MainFlockBatch)  -> excluded: bird cost enters via pre-laying
--   CapitalAsset / Excluded     -> excluded
--   Loan interest / financing   -> excluded (financing, not production)
--   PoultryInternalUsage        -> excluded (eggs given away at selling price)
--
-- Allocation, metrics, scenarios and reverse calculators are computed by the
-- web client from these facts (lib/egg-cost/engine.ts) so every figure is
-- traceable to the rows returned here.
-- =============================================================================

-- ---------------------------------------------------------------- settings
CREATE TABLE IF NOT EXISTS public.poultryeggcostsettings (
    farmid                  text PRIMARY KEY,
    labourallocation        text    NOT NULL DEFAULT 'BirdDays'      CHECK (labourallocation   IN ('BirdDays', 'SaleableEggs')),
    overheadallocation      text    NOT NULL DEFAULT 'BirdDays'      CHECK (overheadallocation IN ('BirdDays', 'SaleableEggs')),
    labourindirect          boolean NOT NULL DEFAULT true,            -- labour counts in the DIRECT cost
    includeprelaying        boolean NOT NULL DEFAULT true,
    includedepreciation     boolean NOT NULL DEFAULT true,
    depreciationeggsharepct numeric(5,2) NOT NULL DEFAULT 100 CHECK (depreciationeggsharepct BETWEEN 0 AND 100),
    overheadeggsharepct     numeric(5,2) NOT NULL DEFAULT 100 CHECK (overheadeggsharepct BETWEEN 0 AND 100),
    directfeedexpenses      text    NOT NULL DEFAULT 'Exclude'       CHECK (directfeedexpenses IN ('Exclude', 'Include')),
    packagingtreatment      text    NOT NULL DEFAULT 'PackagedOnly'  CHECK (packagingtreatment IN ('PackagedOnly', 'Exclude')),
    byproducttreatment      text    NOT NULL DEFAULT 'None'          CHECK (byproducttreatment IN ('None', 'DeductBrokenEggSales')),
    version                 integer NOT NULL DEFAULT 1,
    updatedby               text,
    updatedat               timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
COMMENT ON TABLE public.poultryeggcostsettings IS
  '481 Egg Cost & Profit Analyzer costing assumptions, one row per company. Analytical only.';

-- One audit trail for every material assumption the analyzer stores.
CREATE TABLE IF NOT EXISTS public.poultryeggcostaudit (
    auditid     serial PRIMARY KEY,
    farmid      text NOT NULL,
    kind        text NOT NULL,            -- Settings | FlockAssumption | HistoricalCost | Snapshot
    refid       integer,
    action      text NOT NULL,            -- Save | Reverse | Delete
    changedby   text,
    changedat   timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    beforejson  jsonb,
    afterjson   jsonb
);
CREATE INDEX IF NOT EXISTS ix_poultryeggcostaudit_farm ON public.poultryeggcostaudit (farmid, changedat DESC);

-- ------------------------------------------------- per-flock lifetime assumptions
-- Pre-laying cost is spread over the flock's EXPECTED lifetime saleable eggs.
-- Nothing is invented: either the farmer states the expected eggs, or the
-- laying weeks + lay rate + mortality from which they are worked out.
CREATE TABLE IF NOT EXISTS public.poultryeggcostflockassumptions (
    farmid                        text    NOT NULL,
    flockid                       integer NOT NULL,
    expectedlifetimesaleableeggs  numeric(14,0) CHECK (expectedlifetimesaleableeggs IS NULL OR expectedlifetimesaleableeggs > 0),
    expectedlayingweeks           integer       CHECK (expectedlayingweeks IS NULL OR expectedlayingweeks BETWEEN 1 AND 260),
    expectedlayratepct            numeric(5,2)  CHECK (expectedlayratepct IS NULL OR expectedlayratepct BETWEEN 0 AND 100),
    expectedmortalitypct          numeric(5,2)  CHECK (expectedmortalitypct IS NULL OR expectedmortalitypct BETWEEN 0 AND 100),
    expectedresidualvalue         numeric(14,2) CHECK (expectedresidualvalue IS NULL OR expectedresidualvalue >= 0),
    useresidualvalue              boolean NOT NULL DEFAULT false,
    notes                         text,
    updatedby                     text,
    updatedat                     timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    PRIMARY KEY (farmid, flockid)
);

-- ------------------------------------------------- historical cost basis
-- Rearing costs incurred BEFORE the farm used VisibilityCore. Management
-- analysis only: never an expense, cash movement or P&L row.
CREATE TABLE IF NOT EXISTS public.poultryeggcosthistoricalcosts (
    historicalcostid  serial PRIMARY KEY,
    farmid            text    NOT NULL,
    flockid           integer,
    batchid           integer,
    category          text    NOT NULL CHECK (category IN ('BirdPurchase', 'Feed', 'Medication', 'Labour', 'Overhead', 'Other')),
    amount            numeric(14,2) NOT NULL CHECK (amount > 0),
    periodfrom        date,
    periodto          date,
    reason            text    NOT NULL,
    reference         text,
    isestimate        boolean NOT NULL DEFAULT true,
    status            text    NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Reversed')),
    enteredby         text,
    enteredat         timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedby        text,
    reversedat        timestamp,
    reversalreason    text,
    CHECK (flockid IS NOT NULL OR batchid IS NOT NULL),
    CHECK (periodfrom IS NULL OR periodto IS NULL OR periodfrom <= periodto)
);
CREATE INDEX IF NOT EXISTS ix_poultryeggcosthist_farm ON public.poultryeggcosthistoricalcosts (farmid, status);

-- ------------------------------------------------- saved analyses
CREATE TABLE IF NOT EXISTS public.poultryeggcostsnapshots (
    snapshotid        serial PRIMARY KEY,
    farmid            text    NOT NULL,
    name              text    NOT NULL,
    mode              text    NOT NULL CHECK (mode IN ('Recorded', 'Scenario')),
    params            jsonb   NOT NULL,   -- period, scope, batch/flock, cost definition, scenario inputs
    result            jsonb   NOT NULL,   -- the calculated figures as shown when saved (frozen)
    calcversion       text    NOT NULL,
    settingsversion   integer,
    sourcefingerprint text,               -- facts fingerprint when saved: changed records are detectable
    createdby         text,
    createdat         timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    isdeleted         boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS ix_poultryeggcostsnap_farm ON public.poultryeggcostsnapshots (farmid, isdeleted, createdat DESC);

-- ------------------------------------------------- helpers
CREATE OR REPLACE FUNCTION public.fnpoultryeggcost_settingsjson(p_farmid text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'labourAllocation',        COALESCE(s.labourallocation, 'BirdDays'),
        'overheadAllocation',      COALESCE(s.overheadallocation, 'BirdDays'),
        'labourInDirect',          COALESCE(s.labourindirect, true),
        'includePreLaying',        COALESCE(s.includeprelaying, true),
        'includeDepreciation',     COALESCE(s.includedepreciation, true),
        'depreciationEggSharePct', COALESCE(s.depreciationeggsharepct, 100),
        'overheadEggSharePct',     COALESCE(s.overheadeggsharepct, 100),
        'directFeedExpenses',      COALESCE(s.directfeedexpenses, 'Exclude'),
        'packagingTreatment',      COALESCE(s.packagingtreatment, 'PackagedOnly'),
        'byproductTreatment',      COALESCE(s.byproducttreatment, 'None'),
        'version',                 COALESCE(s.version, 0),
        'updatedBy',               s.updatedby,
        'updatedAt',               s.updatedat,
        'isDefault',               s.farmid IS NULL)
    FROM (SELECT 1) one
    LEFT JOIN public.poultryeggcostsettings s ON s.farmid = p_farmid;
$$;

-- Which analyzer component an expense line belongs to (see header).
CREATE OR REPLACE FUNCTION public.fnpoultryeggcost_component(p_plline text, p_plsection text, p_sourcetype text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_plsection = 'Excluded'                                                    THEN 'ExcludedCapital'
        WHEN p_plline = 'Feed' AND COALESCE(p_sourcetype, '') IN ('PoultryRawMaterialPurchase', 'PoultryFeedConsumption', 'RecordPurchase')
                                                                                         THEN 'ExcludedStockFeed'
        WHEN p_plline = 'Medication' AND COALESCE(p_sourcetype, '') IN ('PoultryRawMaterialPurchase', 'PoultryMedicationConsumption', 'RecordPurchase')
                                                                                         THEN 'ExcludedStockMedication'
        WHEN p_plline = 'Feed'                                                           THEN 'DirectFeedExpense'
        WHEN p_plline = 'Medication'                                                     THEN 'Veterinary'
        WHEN p_plline = 'FlockCost'                                                      THEN 'ExcludedBirdPurchase'
        WHEN p_plline IN ('Payroll', 'DirectLabour')                                     THEN 'Labour'
        WHEN p_plline = 'Utilities'                                                      THEN 'Utilities'
        WHEN p_plline = 'ProductionSupplies'                                             THEN 'Packaging'
        WHEN p_plline = 'Depreciation'                                                   THEN 'Depreciation'
        WHEN COALESCE(p_sourcetype, '') = 'PoultryInternalUsage'                         THEN 'ExcludedInternalUse'
        WHEN p_plsection = 'OtherCost'                                                   THEN 'ExcludedFinancing'
        ELSE 'Overhead'
    END;
$$;

-- ------------------------------------------------- THE FACTS
-- Everything the analyzer computes from, for one company and one period.
-- Farm-wide on purpose: shared costs are allocated across ALL flocks, and the
-- client narrows to a batch or flock afterwards, so a flock's share is the
-- same whichever scope is on screen.
CREATE OR REPLACE FUNCTION public.sppoultryeggcost_facts(p_farmid text, p_startdate date, p_enddate date)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $function$
DECLARE
    v_facts jsonb;
    v_pack  record;
BEGIN
    IF p_startdate IS NULL OR p_enddate IS NULL OR p_enddate < p_startdate THEN
        RAISE EXCEPTION 'Choose a period whose end is on or after its start.';
    END IF;
    IF p_enddate - p_startdate > 3660 THEN
        RAISE EXCEPTION 'Choose a period of ten years or less.';
    END IF;

    SELECT * INTO v_pack FROM public.fnpoultry_eggpackaging(p_farmid);

    WITH
    -- every record of the company, once: lifetime and pre-laying figures need all time
    pr AS (
        SELECT r.id, r.date, r.flockid,
               COALESCE(r.totalproduction, 0) AS gross,
               COALESCE(r.brokeneggs, 0) AS broken, COALESCE(r.meatyeggs, 0) AS meaty,
               COALESCE(r.softeggs, 0) AS soft, COALESCE(r.losteggs, 0) AS lost,
               GREATEST(COALESCE(r.totalproduction, 0) - COALESCE(r.brokeneggs, 0) - COALESCE(r.meatyeggs, 0)
                        - COALESCE(r.softeggs, 0) - COALESCE(r.losteggs, 0), 0) AS saleable,
               r.noofbirdsleft AS birds, COALESCE(r.feedkg, 0) AS feedkg,
               COALESCE(r.totalfeedcost, 0) AS feedcost, COALESCE(r.totalmedicationcost, 0) AS medcost,
               r.sourcetype
        FROM   public.productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid IS NOT NULL
    ),
    firstegg AS (
        SELECT flockid, MIN(date) AS firsteggdate FROM pr WHERE gross > 0 GROUP BY flockid
    ),
    life AS (
        SELECT pr.flockid,
               SUM(pr.saleable) FILTER (WHERE pr.date <= p_enddate)                       AS lifetimesaleable,
               SUM(pr.saleable) FILTER (WHERE pr.date <  p_startdate)                     AS saleablebeforeperiod,
               SUM(pr.feedcost) FILTER (WHERE fe.firsteggdate IS NULL OR pr.date < fe.firsteggdate) AS prelayfeedcost,
               SUM(pr.medcost)  FILTER (WHERE fe.firsteggdate IS NULL OR pr.date < fe.firsteggdate) AS prelaymedcost,
               COUNT(*) FILTER (WHERE (fe.firsteggdate IS NULL OR pr.date < fe.firsteggdate)
                                  AND pr.feedkg > 0 AND pr.feedcost = 0)                  AS prelayfeednocost,
               COUNT(*) FILTER (WHERE fe.firsteggdate IS NULL OR pr.date < fe.firsteggdate) AS prelayrecords
        FROM   pr LEFT JOIN firstegg fe ON fe.flockid = pr.flockid
        GROUP  BY pr.flockid
    ),
    fl AS (
        SELECT f.flockid, f.name, f.batchid, f.flocktype, f.startdate, f.closeddate
        FROM   public.flock f
        WHERE  f.farmid = p_farmid AND NOT COALESCE(f.isdeleted, false)
          AND  (    (f.startdate IS NULL OR f.startdate <= p_enddate)
                AND (f.closeddate IS NULL OR f.closeddate >= p_startdate)
                OR EXISTS (SELECT 1 FROM pr WHERE pr.flockid = f.flockid AND pr.date BETWEEN p_startdate AND p_enddate))
    ),
    hist AS (
        -- a batch-level entry is shared by the batch's flocks pro rata to birds placed
        SELECT h.historicalcostid, h.flockid, h.batchid, h.category, h.amount, h.periodfrom, h.periodto,
               h.reason, h.reference, h.isestimate, h.enteredby, h.enteredat
        FROM   public.poultryeggcosthistoricalcosts h
        WHERE  h.farmid = p_farmid AND h.status = 'Active'
    ),
    flockjson AS (
        SELECT jsonb_agg(jsonb_build_object(
                   'flockId', fl.flockid, 'name', fl.name, 'batchId', fl.batchid,
                   'batchCode', b.batchcode, 'batchName', b.batchname,
                   'flockType', COALESCE(fl.flocktype, 'Layer'),
                   'startDate', fl.startdate, 'closedDate', fl.closeddate,
                   'firstEggDate', fe.firsteggdate,
                   'originallyPlaced', bp.originallyplaced,
                   'birdsAtStart', bs.currentlivebirds, 'birdsAtEnd', be.currentlivebirds,
                   'birdCost', CASE WHEN b.totalcost > 0 AND b.numberofbirds > 0 AND bp.originallyplaced > 0
                                    THEN ROUND(b.totalcost * bp.originallyplaced / b.numberofbirds, 2) END,
                   'birdCostBasis', CASE WHEN b.totalcost > 0 AND b.numberofbirds > 0 AND bp.originallyplaced > 0
                                    THEN format('Batch %s: %s for %s birds; this flock was placed with %s',
                                                COALESCE(b.batchcode, b.batchid::text), b.totalcost, b.numberofbirds, bp.originallyplaced) END,
                   'batchIsHistorical', COALESCE(b.ishistorical, false),
                   'lifetimeSaleableEggs', COALESCE(lf.lifetimesaleable, 0),
                   'saleableEggsBeforePeriod', COALESCE(lf.saleablebeforeperiod, 0),
                   'preLayFeedCost', COALESCE(lf.prelayfeedcost, 0),
                   'preLayMedicationCost', COALESCE(lf.prelaymedcost, 0),
                   'preLayRecords', COALESCE(lf.prelayrecords, 0),
                   'preLayFeedWithoutCost', COALESCE(lf.prelayfeednocost, 0),
                   'historicalCost', COALESCE((
                        SELECT SUM(CASE WHEN h.flockid = fl.flockid THEN h.amount
                                        WHEN h.flockid IS NULL AND h.batchid = fl.batchid AND tot.placed > 0
                                        THEN ROUND(h.amount * COALESCE(bp.originallyplaced, 0) / tot.placed, 2)
                                        ELSE 0 END)
                        FROM hist h
                        LEFT JOIN LATERAL (
                            SELECT SUM(p2.originallyplaced) AS placed
                            FROM   public.flock f2
                            CROSS  JOIN LATERAL public.fnflock_birdposition(p_farmid, f2.flockid) p2
                            WHERE  h.flockid IS NULL AND f2.farmid = p_farmid AND f2.batchid = h.batchid AND NOT COALESCE(f2.isdeleted, false)
                        ) tot ON true
                        WHERE h.flockid = fl.flockid OR (h.flockid IS NULL AND h.batchid = fl.batchid)), 0),
                   'historicalCostHasEstimate', EXISTS (SELECT 1 FROM hist h WHERE h.isestimate
                                                         AND (h.flockid = fl.flockid OR (h.flockid IS NULL AND h.batchid = fl.batchid))),
                   'assumptions', (SELECT jsonb_build_object(
                                        'expectedLifetimeSaleableEggs', a.expectedlifetimesaleableeggs,
                                        'expectedLayingWeeks', a.expectedlayingweeks,
                                        'expectedLayRatePct', a.expectedlayratepct,
                                        'expectedMortalityPct', a.expectedmortalitypct,
                                        'expectedResidualValue', a.expectedresidualvalue,
                                        'useResidualValue', a.useresidualvalue,
                                        'notes', a.notes, 'updatedBy', a.updatedby, 'updatedAt', a.updatedat)
                                   FROM public.poultryeggcostflockassumptions a
                                   WHERE a.farmid = p_farmid AND a.flockid = fl.flockid)
               ) ORDER BY b.batchcode NULLS LAST, fl.name) AS j
        FROM   fl
        LEFT   JOIN public.mainflockbatch b ON b.batchid = fl.batchid AND b.farmid = p_farmid
        LEFT   JOIN firstegg fe ON fe.flockid = fl.flockid
        LEFT   JOIN life lf ON lf.flockid = fl.flockid
        LEFT   JOIN LATERAL public.fnflock_birdposition(p_farmid, fl.flockid) bp ON true
        LEFT   JOIN LATERAL public.fnflock_birdpositionasof(p_farmid, fl.flockid, p_startdate) bs ON true
        LEFT   JOIN LATERAL public.fnflock_birdpositionasof(p_farmid, fl.flockid, p_enddate) be ON true
    ),
    recjson AS (
        SELECT jsonb_agg(jsonb_build_object(
                   'id', pr.id, 'date', pr.date, 'flockId', pr.flockid,
                   'gross', pr.gross, 'broken', pr.broken, 'meaty', pr.meaty, 'soft', pr.soft, 'lost', pr.lost,
                   'saleable', pr.saleable, 'birds', pr.birds, 'feedKg', pr.feedkg,
                   'feedCost', pr.feedcost, 'medicationCost', pr.medcost, 'sourceType', pr.sourcetype
               ) ORDER BY pr.date, pr.id) AS j
        FROM   pr WHERE pr.date BETWEEN p_startdate AND p_enddate
    ),
    linejson AS (
        -- the items behind each record's feed and medication cost (drilldown)
        SELECT jsonb_agg(x.j ORDER BY x.recid, x.kind, x.item) AS j FROM (
            SELECT l.productionrecordid AS recid, 'Feed' AS kind, l.itemname AS item,
                   jsonb_build_object('recordId', l.productionrecordid, 'kind', 'Feed', 'item', l.itemname,
                                      'quantity', l.quantityconsumed, 'unitCost', l.unitcost, 'totalCost', l.totalcost) AS j
            FROM   public.productionrecordfeeds l JOIN pr ON pr.id = l.productionrecordid
            WHERE  pr.date BETWEEN p_startdate AND p_enddate
            UNION ALL
            SELECT m.productionrecordid, 'Medication', m.itemname,
                   jsonb_build_object('recordId', m.productionrecordid, 'kind', 'Medication', 'item', m.itemname,
                                      'quantity', m.quantityconsumed, 'unitCost', m.unitcost, 'totalCost', m.totalcost)
            FROM   public.productionrecordmedications m JOIN pr ON pr.id = m.productionrecordid
            WHERE  pr.date BETWEEN p_startdate AND p_enddate
        ) x
    ),
    exp AS (
        SELECT l.expenseid, l.expensedate::date AS date, e.flockid, l.plline, l.plsection, l.sourcetype, l.sourceid,
               l.category, l.description, l.amount,
               public.fnpoultryeggcost_component(l.plline, l.plsection, l.sourcetype) AS component,
               ca.assetname
        FROM   public.fnpoultrypl_expenselines(p_farmid, p_startdate, p_enddate) l
        JOIN   public.expense e ON e.expenseid = l.expenseid
        LEFT   JOIN public.poultrycapitalassets ca ON ca.poultrycapitalassetid = l.poultrycapitalassetid
    ),
    expjson AS (
        SELECT jsonb_agg(jsonb_build_object(
                   'expenseId', exp.expenseid, 'date', exp.date, 'flockId', exp.flockid,
                   'component', exp.component, 'plLine', exp.plline, 'plSection', exp.plsection,
                   'sourceType', exp.sourcetype, 'sourceId', exp.sourceid,
                   'category', exp.category, 'description', exp.description, 'amount', exp.amount,
                   'assetName', exp.assetname
               ) ORDER BY exp.date, exp.expenseid) AS j
        FROM   exp
    ),
    salejson AS (
        SELECT jsonb_agg(jsonb_build_object(
                   'saleId', s.saleid, 'date', s.saledate, 'flockId', s.flockid,
                   'product', sl.product, 'size', NULLIF(sl.size, ''),
                   'eggs', sl.quantity, 'amount', sl.totalamount
               ) ORDER BY s.saledate, s.saleid) AS j
        FROM   public.sale s
        JOIN   public.saleline sl ON sl.saleid = s.saleid
        WHERE  s.farmid = p_farmid AND s.status = 'Posted'
          AND  s.saledate BETWEEN p_startdate AND p_enddate
          AND  sl.product ILIKE '%egg%' AND public.fnpoultrysale_byproductrole(sl.product) IS NULL
          AND  COALESCE(sl.quantity, 0) > 0
    ),
    brokenjson AS (
        SELECT jsonb_build_object('eggs', COALESCE(SUM(sl.quantity), 0), 'amount', COALESCE(SUM(sl.totalamount), 0)) AS j
        FROM   public.sale s JOIN public.saleline sl ON sl.saleid = s.saleid
        WHERE  s.farmid = p_farmid AND s.status = 'Posted' AND s.saledate BETWEEN p_startdate AND p_enddate
          AND  public.fnpoultrysale_byproductrole(sl.product) = 'BrokenEggs'
    ),
    histjson AS (
        SELECT jsonb_agg(jsonb_build_object(
                   'historicalCostId', h.historicalcostid, 'flockId', h.flockid, 'batchId', h.batchid,
                   'category', h.category, 'amount', h.amount, 'periodFrom', h.periodfrom, 'periodTo', h.periodto,
                   'reason', h.reason, 'reference', h.reference, 'isEstimate', h.isestimate,
                   'enteredBy', h.enteredby, 'enteredAt', h.enteredat) ORDER BY h.historicalcostid) AS j
        FROM   hist h
    )
    SELECT jsonb_build_object(
        'farmId', p_farmid,
        'startDate', p_startdate, 'endDate', p_enddate,
        'packaging', jsonb_build_object('eggsPerCrate', COALESCE(v_pack.eggspercrate, public.fnpoultry_eggspercrate(p_farmid), 30),
                                        'enableBoxes', COALESCE(v_pack.enableboxes, false),
                                        'cratesPerBox', v_pack.cratesperbox),
        'settings', public.fnpoultryeggcost_settingsjson(p_farmid),
        'flocks', COALESCE((SELECT j FROM flockjson), '[]'::jsonb),
        'records', COALESCE((SELECT j FROM recjson), '[]'::jsonb),
        'recordLines', COALESCE((SELECT j FROM linejson), '[]'::jsonb),
        'costs', COALESCE((SELECT j FROM expjson), '[]'::jsonb),
        'sales', COALESCE((SELECT j FROM salejson), '[]'::jsonb),
        'brokenEggSales', (SELECT j FROM brokenjson),
        'historicalCosts', COALESCE((SELECT j FROM histjson), '[]'::jsonb),
        'assetsInService', (SELECT COUNT(*) FROM public.poultrycapitalassets a
                            WHERE a.farmid = p_farmid AND COALESCE(a.inservicedate, a.acquisitiondate) <= p_enddate
                              AND (a.disposaldate IS NULL OR a.disposaldate >= p_startdate)
                              AND COALESCE(a.status, '') NOT IN ('Reversed', 'Cancelled', 'Deleted')),
        'generatedAt', now() AT TIME ZONE 'utc')
    INTO v_facts;

    -- Changes when any source row behind the figures changes: a saved snapshot
    -- compares it to know whether the records have moved since.
    RETURN v_facts || jsonb_build_object('fingerprint',
        md5((v_facts - 'generatedAt' - 'settings')::text || COALESCE((v_facts -> 'settings' ->> 'version'), '')));
END;
$function$;

-- ------------------------------------------------- settings save
CREATE OR REPLACE FUNCTION public.sppoultryeggcost_settingssave(p_farmid text, p_settings jsonb, p_by text)
RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE
    v_before jsonb := public.fnpoultryeggcost_settingsjson(p_farmid);
    v_after  jsonb;
BEGIN
    INSERT INTO public.poultryeggcostsettings AS s (
        farmid, labourallocation, overheadallocation, labourindirect, includeprelaying, includedepreciation,
        depreciationeggsharepct, overheadeggsharepct, directfeedexpenses, packagingtreatment, byproducttreatment,
        version, updatedby, updatedat)
    VALUES (p_farmid,
        COALESCE(p_settings ->> 'labourAllocation', 'BirdDays'),
        COALESCE(p_settings ->> 'overheadAllocation', 'BirdDays'),
        COALESCE((p_settings ->> 'labourInDirect')::boolean, true),
        COALESCE((p_settings ->> 'includePreLaying')::boolean, true),
        COALESCE((p_settings ->> 'includeDepreciation')::boolean, true),
        COALESCE((p_settings ->> 'depreciationEggSharePct')::numeric, 100),
        COALESCE((p_settings ->> 'overheadEggSharePct')::numeric, 100),
        COALESCE(p_settings ->> 'directFeedExpenses', 'Exclude'),
        COALESCE(p_settings ->> 'packagingTreatment', 'PackagedOnly'),
        COALESCE(p_settings ->> 'byproductTreatment', 'None'),
        1, p_by, now() AT TIME ZONE 'utc')
    ON CONFLICT (farmid) DO UPDATE SET
        labourallocation = EXCLUDED.labourallocation, overheadallocation = EXCLUDED.overheadallocation,
        labourindirect = EXCLUDED.labourindirect, includeprelaying = EXCLUDED.includeprelaying,
        includedepreciation = EXCLUDED.includedepreciation, depreciationeggsharepct = EXCLUDED.depreciationeggsharepct,
        overheadeggsharepct = EXCLUDED.overheadeggsharepct, directfeedexpenses = EXCLUDED.directfeedexpenses,
        packagingtreatment = EXCLUDED.packagingtreatment, byproducttreatment = EXCLUDED.byproducttreatment,
        version = s.version + 1, updatedby = EXCLUDED.updatedby, updatedat = EXCLUDED.updatedat;

    v_after := public.fnpoultryeggcost_settingsjson(p_farmid);
    INSERT INTO public.poultryeggcostaudit (farmid, kind, refid, action, changedby, beforejson, afterjson)
    VALUES (p_farmid, 'Settings', NULL, 'Save', p_by, v_before, v_after);
    RETURN v_after;
END;
$function$;

-- ------------------------------------------------- flock assumptions save
CREATE OR REPLACE FUNCTION public.sppoultryeggcost_assumptionsave(p_farmid text, p_flockid integer, p_assumption jsonb, p_by text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_before jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Flock not found in this company.';
    END IF;
    SELECT to_jsonb(a) INTO v_before FROM public.poultryeggcostflockassumptions a WHERE a.farmid = p_farmid AND a.flockid = p_flockid;

    INSERT INTO public.poultryeggcostflockassumptions AS a (
        farmid, flockid, expectedlifetimesaleableeggs, expectedlayingweeks, expectedlayratepct, expectedmortalitypct,
        expectedresidualvalue, useresidualvalue, notes, updatedby, updatedat)
    VALUES (p_farmid, p_flockid,
        NULLIF(p_assumption ->> 'expectedLifetimeSaleableEggs', '')::numeric,
        NULLIF(p_assumption ->> 'expectedLayingWeeks', '')::integer,
        NULLIF(p_assumption ->> 'expectedLayRatePct', '')::numeric,
        NULLIF(p_assumption ->> 'expectedMortalityPct', '')::numeric,
        NULLIF(p_assumption ->> 'expectedResidualValue', '')::numeric,
        COALESCE((p_assumption ->> 'useResidualValue')::boolean, false),
        NULLIF(btrim(p_assumption ->> 'notes'), ''),
        p_by, now() AT TIME ZONE 'utc')
    ON CONFLICT (farmid, flockid) DO UPDATE SET
        expectedlifetimesaleableeggs = EXCLUDED.expectedlifetimesaleableeggs,
        expectedlayingweeks = EXCLUDED.expectedlayingweeks, expectedlayratepct = EXCLUDED.expectedlayratepct,
        expectedmortalitypct = EXCLUDED.expectedmortalitypct, expectedresidualvalue = EXCLUDED.expectedresidualvalue,
        useresidualvalue = EXCLUDED.useresidualvalue, notes = EXCLUDED.notes,
        updatedby = EXCLUDED.updatedby, updatedat = EXCLUDED.updatedat;

    INSERT INTO public.poultryeggcostaudit (farmid, kind, refid, action, changedby, beforejson, afterjson)
    SELECT p_farmid, 'FlockAssumption', p_flockid, 'Save', p_by, v_before, to_jsonb(a)
    FROM   public.poultryeggcostflockassumptions a WHERE a.farmid = p_farmid AND a.flockid = p_flockid;
END;
$function$;

-- ------------------------------------------------- historical cost basis
CREATE OR REPLACE FUNCTION public.sppoultryeggcost_historicaladd(
    p_farmid text, p_flockid integer, p_batchid integer, p_category text, p_amount numeric,
    p_periodfrom date, p_periodto date, p_reason text, p_reference text, p_isestimate boolean, p_by text)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_id integer;
    v_batch integer := p_batchid;
    v_dup numeric;
BEGIN
    IF p_flockid IS NULL AND p_batchid IS NULL THEN RAISE EXCEPTION 'Choose the batch or flock this cost belongs to.'; END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN RAISE EXCEPTION 'Enter an amount greater than zero.'; END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for this historical cost.'; END IF;
    IF p_periodfrom IS NOT NULL AND p_periodto IS NOT NULL AND p_periodfrom > p_periodto THEN
        RAISE EXCEPTION 'The period must end on or after it starts.';
    END IF;
    IF p_flockid IS NOT NULL THEN
        SELECT f.batchid INTO v_batch FROM public.flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid AND NOT COALESCE(f.isdeleted, false);
        IF NOT FOUND THEN RAISE EXCEPTION 'Flock not found in this company.'; END IF;
    ELSIF NOT EXISTS (SELECT 1 FROM public.mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Batch not found in this company.';
    END IF;

    -- Never the same cost twice: bird cost already on the batch, or feed /
    -- medication already costed on production records in the same period.
    IF p_category = 'BirdPurchase' AND EXISTS (
        SELECT 1 FROM public.mainflockbatch b WHERE b.batchid = v_batch AND b.farmid = p_farmid AND COALESCE(b.totalcost, 0) > 0) THEN
        RAISE EXCEPTION 'This batch already records what the birds cost. Correct the batch instead of adding it again here.';
    END IF;
    IF p_category IN ('Feed', 'Medication') THEN
        SELECT COALESCE(SUM(CASE WHEN p_category = 'Feed' THEN r.totalfeedcost ELSE r.totalmedicationcost END), 0) INTO v_dup
        FROM   public.productionrecords r
        JOIN   public.flock f ON f.flockid = r.flockid
        WHERE  r.farmid = p_farmid
          AND  (r.flockid = p_flockid OR (p_flockid IS NULL AND f.batchid = p_batchid))
          AND  (p_periodfrom IS NULL OR r.date >= p_periodfrom)
          AND  (p_periodto IS NULL OR r.date <= p_periodto);
        IF v_dup > 0 THEN
            RAISE EXCEPTION '% costing % is already recorded on production records in that period. Enter only costs VisibilityCore does not already hold.',
                p_category, v_dup;
        END IF;
    END IF;

    INSERT INTO public.poultryeggcosthistoricalcosts (farmid, flockid, batchid, category, amount, periodfrom, periodto,
                                                      reason, reference, isestimate, enteredby)
    VALUES (p_farmid, p_flockid, CASE WHEN p_flockid IS NULL THEN p_batchid END, p_category, p_amount, p_periodfrom, p_periodto,
            btrim(p_reason), NULLIF(btrim(COALESCE(p_reference, '')), ''), COALESCE(p_isestimate, true), p_by)
    RETURNING historicalcostid INTO v_id;

    INSERT INTO public.poultryeggcostaudit (farmid, kind, refid, action, changedby, afterjson)
    SELECT p_farmid, 'HistoricalCost', v_id, 'Save', p_by, to_jsonb(h)
    FROM   public.poultryeggcosthistoricalcosts h WHERE h.historicalcostid = v_id;
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggcost_historicalreverse(p_farmid text, p_id integer, p_reason text, p_by text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for removing this historical cost.'; END IF;
    UPDATE public.poultryeggcosthistoricalcosts
    SET    status = 'Reversed', reversedby = p_by, reversedat = now() AT TIME ZONE 'utc', reversalreason = btrim(p_reason)
    WHERE  historicalcostid = p_id AND farmid = p_farmid AND status = 'Active';
    IF NOT FOUND THEN RAISE EXCEPTION 'Historical cost not found, or already removed.'; END IF;
    INSERT INTO public.poultryeggcostaudit (farmid, kind, refid, action, changedby, afterjson)
    SELECT p_farmid, 'HistoricalCost', p_id, 'Reverse', p_by, to_jsonb(h)
    FROM   public.poultryeggcosthistoricalcosts h WHERE h.historicalcostid = p_id;
END;
$function$;

-- ------------------------------------------------- snapshots
CREATE OR REPLACE FUNCTION public.sppoultryeggcost_snapshotsave(
    p_farmid text, p_name text, p_mode text, p_params jsonb, p_result jsonb,
    p_calcversion text, p_settingsversion integer, p_fingerprint text, p_by text)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE v_id integer;
BEGIN
    IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'Give the analysis a name.'; END IF;
    IF p_mode NOT IN ('Recorded', 'Scenario') THEN RAISE EXCEPTION 'Unknown analysis mode.'; END IF;
    INSERT INTO public.poultryeggcostsnapshots (farmid, name, mode, params, result, calcversion, settingsversion, sourcefingerprint, createdby)
    VALUES (p_farmid, left(btrim(p_name), 200), p_mode, COALESCE(p_params, '{}'), COALESCE(p_result, '{}'),
            COALESCE(p_calcversion, 'unknown'), p_settingsversion, p_fingerprint, p_by)
    RETURNING snapshotid INTO v_id;
    INSERT INTO public.poultryeggcostaudit (farmid, kind, refid, action, changedby, afterjson)
    VALUES (p_farmid, 'Snapshot', v_id, 'Save', p_by, jsonb_build_object('name', p_name, 'mode', p_mode));
    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggcost_snapshotlist(p_farmid text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'snapshotId', s.snapshotid, 'name', s.name, 'mode', s.mode, 'params', s.params,
               'calcVersion', s.calcversion, 'settingsVersion', s.settingsversion,
               'sourceFingerprint', s.sourcefingerprint, 'createdBy', s.createdby, 'createdAt', s.createdat,
               'headline', s.result -> 'headline') ORDER BY s.createdat DESC), '[]'::jsonb)
    FROM public.poultryeggcostsnapshots s
    WHERE s.farmid = p_farmid AND NOT s.isdeleted;
$$;

CREATE OR REPLACE FUNCTION public.sppoultryeggcost_snapshotget(p_farmid text, p_id integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
               'snapshotId', s.snapshotid, 'name', s.name, 'mode', s.mode, 'params', s.params, 'result', s.result,
               'calcVersion', s.calcversion, 'settingsVersion', s.settingsversion,
               'sourceFingerprint', s.sourcefingerprint, 'createdBy', s.createdby, 'createdAt', s.createdat)
    FROM public.poultryeggcostsnapshots s
    WHERE s.farmid = p_farmid AND s.snapshotid = p_id AND NOT s.isdeleted;
$$;

CREATE OR REPLACE FUNCTION public.sppoultryeggcost_snapshotdelete(p_farmid text, p_id integer, p_by text)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
    UPDATE public.poultryeggcostsnapshots SET isdeleted = true
    WHERE  farmid = p_farmid AND snapshotid = p_id AND NOT isdeleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'Saved analysis not found.'; END IF;
    INSERT INTO public.poultryeggcostaudit (farmid, kind, refid, action, changedby)
    VALUES (p_farmid, 'Snapshot', p_id, 'Delete', p_by);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggcost_auditlist(p_farmid text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'auditId', a.auditid, 'kind', a.kind, 'refId', a.refid, 'action', a.action,
               'changedBy', a.changedby, 'changedAt', a.changedat, 'before', a.beforejson, 'after', a.afterjson)
           ORDER BY a.changedat DESC), '[]'::jsonb)
    FROM (SELECT * FROM public.poultryeggcostaudit WHERE farmid = p_farmid ORDER BY changedat DESC LIMIT 200) a;
$$;
