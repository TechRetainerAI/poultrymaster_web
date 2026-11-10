-- =============================================================================
-- 402: Broilers, phase 4 -- the figures a meat-bird flock is judged by.
--
-- 1. fnflock_broilerkpis(farm, flock, broilersonly) -- one row per flock.
--    Built on fnflock_lifetimesummary (352), so placed / mortality / feed /
--    cost / revenue / profit are THE SAME numbers the flock summary shows;
--    this only adds the meat side:
--
--      birds started  = originally placed (history known) else opening live
--      liveability %  = (started - deaths) / started x 100
--      age (days)     = fnflock_ageondate on the close date, else today
--                       (start date + any lifecycle age at start, 400)
--      kg sold        = live weight on the flock's posted bird sale lines (401)
--                       + birds sold WITHOUT a weight x the average sale weight
--                         (else the latest weigh-in)                [estimate]
--      kg in house    = live birds x the latest weigh-in average (400) [estimate]
--      kg produced    = kg sold + kg in house
--      avg weight     = kg produced / (birds sold + live birds)
--      FCR            = feed kg / kg produced
--      EPEF           = liveability % x avg weight kg / (age days x FCR) x 100
--      cost per kg    = total cost (chick cost included) / kg produced
--      revenue per kg = bird sale revenue / kg sold
--
--    A figure that cannot be known is NULL, never a guess dressed as fact:
--    no weigh-in for birds still standing, no weight anywhere for birds
--    sold, or no feed recorded. kgisestimated says when any part came from an
--    average rather than a scale; "missing" says what would complete it.
--    Feed is what the production records say was fed (lifetime summary), and
--    the chick's own weight at placement is not subtracted -- the usual
--    on-farm FCR.
--
-- 2. sppoultryreport_profitlossbyflock gains birdcost: the chick purchase,
--    shared to the flock by birds placed exactly as the flock summary shares
--    it, charged in the period the flock STARTED. The chick purchase expense
--    (sourcetype MainFlockBatch) is never tagged to a flock -- 27 of 27 on dev,
--    2026-11-03 -- and is excluded from the expense sums explicitly, so it
--    can never be counted twice. RETURNS TABLE changes: DROP + CREATE, body
--    is the LIVE one read from dev 2026-11-03.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1. Broiler figures -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnflock_broilerkpis(
    p_farmid       text,
    p_flockid      integer DEFAULT NULL,
    p_broilersonly boolean DEFAULT FALSE)
RETURNS TABLE(
    flockid integer, flockname text, flocktype text, breed text, status text,
    startdate date, closeddate date, ageindays integer,
    birdsstarted integer, deaths integer, liveabilitypct numeric,
    birdssold integer, birdssoldweighed integer, kgsoldweighed numeric, avgsaleweightkg numeric,
    livebirds integer, latestweighdate date, latestavgweightkg numeric,
    kgsoldestimated numeric, kginhouseestimated numeric,
    kgproduced numeric, kgisestimated boolean, avgliveweightkg numeric,
    feedkg numeric, fcr numeric, epef numeric,
    birdcost numeric, birdcostrecorded boolean, totalcost numeric, costperkg numeric,
    birdsalerevenue numeric, revenueperkg numeric, profit numeric, profitperkg numeric,
    missing text)
LANGUAGE sql STABLE AS $function$
    WITH ls AS (
        SELECT s.*, f.flocktype AS c_type
        FROM   public.fnflock_lifetimesummary(p_farmid, p_flockid, FALSE) s
        JOIN   flock f ON f.farmid = p_farmid AND f.flockid = s.flockid
        WHERE  NOT p_broilersonly OR f.flocktype = 'Broiler'
    ),
    sold AS (
        SELECT s.flockid AS c_flockid,
               SUM(l.quantity) FILTER (WHERE l.liveweightkg IS NOT NULL)::int AS c_birds,
               SUM(l.liveweightkg)                                            AS c_kg
        FROM   sale s
        JOIN   saleline l ON l.saleid = s.saleid
        WHERE  s.farmid = p_farmid AND s.status = 'Posted'
          AND  s.flockid IN (SELECT ls.flockid FROM ls)
          AND  public.fnpoultrysale_isbirdsale(l.product)
        GROUP  BY s.flockid
    ),
    wi AS (
        SELECT DISTINCT ON (w.flockid) w.flockid AS c_flockid, w.weighdate AS c_date, w.avgweightg / 1000.0 AS c_kg
        FROM   poultryflockweighins w
        WHERE  w.farmid = p_farmid AND w.deletedat IS NULL
          AND  w.flockid IN (SELECT ls.flockid FROM ls)
        ORDER  BY w.flockid, w.weighdate DESC, w.weighinid DESC
    ),
    a AS (
        SELECT ls.*,
               CASE WHEN ls.historyknown THEN ls.originallyplaced ELSE ls.openinglivebirds END            AS c_started,
               CASE WHEN ls.historyknown THEN ls.openingmortality + ls.recordedmortality
                    ELSE ls.recordedmortality END                                                         AS c_deaths,
               GREATEST(COALESCE(public.fnflock_ageondate(p_farmid, ls.flockid,
                        COALESCE(ls.closeddate, public.fncompany_businessdate(p_farmid))), 0), 0)        AS c_age,
               COALESCE(sold.c_birds, 0)                                                                  AS c_wbirds,
               COALESCE(sold.c_kg, 0)                                                                     AS c_wkg,
               wi.c_date                                                                                  AS c_wdate,
               wi.c_kg                                                                                    AS c_wikg
        FROM   ls
        LEFT   JOIN sold ON sold.c_flockid = ls.flockid
        LEFT   JOIN wi   ON wi.c_flockid   = ls.flockid
    ),
    b AS (
        SELECT a.*,
               CASE WHEN a.c_wbirds > 0 THEN a.c_wkg / a.c_wbirds END                                     AS c_avgsale,
               GREATEST(a.birdssold - a.c_wbirds, 0)                                                      AS c_unweighed
        FROM   a
    ),
    c AS (
        SELECT b.*,
               CASE WHEN b.c_unweighed = 0 THEN 0
                    ELSE b.c_unweighed * COALESCE(b.c_avgsale, b.c_wikg) END                              AS c_kgsoldest,
               CASE WHEN b.finalbirds <= 0 THEN 0
                    ELSE b.finalbirds * b.c_wikg END                                                      AS c_kghouse
        FROM   b
    ),
    d AS (
        SELECT c.*,
               c.c_wkg + c.c_kgsoldest + c.c_kghouse                                                      AS c_kgprod,   -- NULL if either estimate is unknown
               CASE WHEN c.c_started > 0
                    THEN round(100.0 * (c.c_started - c.c_deaths) / c.c_started, 2) END                  AS c_live
        FROM   c
    ),
    e AS (
        SELECT d.*,
               CASE WHEN d.c_kgprod > 0 AND (d.birdssold + d.finalbirds) > 0
                    THEN d.c_kgprod / (d.birdssold + d.finalbirds) END                                    AS c_avgw,
               CASE WHEN d.c_kgprod > 0 AND d.feedconsumedkg > 0
                    THEN d.feedconsumedkg / d.c_kgprod END                                                AS c_fcr
        FROM   d
    )
    SELECT
        e.flockid, e.flockname, e.c_type, e.breed, e.status, e.startdate, e.closeddate, e.c_age::int,
        e.c_started, e.c_deaths, e.c_live,
        e.birdssold, e.c_wbirds, round(e.c_wkg, 3), round(e.c_avgsale, 3),
        e.finalbirds, e.c_wdate, round(e.c_wikg, 3),
        round(e.c_kgsoldest, 3), round(e.c_kghouse, 3),
        round(e.c_kgprod, 3),
        (e.c_kgprod IS NOT NULL AND (e.c_unweighed > 0 OR e.finalbirds > 0)),
        round(e.c_avgw, 3),
        round(e.feedconsumedkg, 3),
        round(e.c_fcr, 3),
        CASE WHEN e.c_live > 0 AND e.c_avgw > 0 AND e.c_age > 0 AND e.c_fcr > 0
             THEN round(e.c_live * e.c_avgw / (e.c_age * e.c_fcr) * 100, 0) END,
        e.birdcost, e.birdcostrecorded, e.totalcost,
        CASE WHEN e.c_kgprod > 0 THEN round(e.totalcost / e.c_kgprod, 2) END,
        e.birdsalerevenue,
        CASE WHEN (e.c_wkg + e.c_kgsoldest) > 0 THEN round(e.birdsalerevenue / (e.c_wkg + e.c_kgsoldest), 2) END,
        e.profit,
        CASE WHEN e.c_kgprod > 0 THEN round(e.profit / e.c_kgprod, 2) END,
        NULLIF(concat_ws('; ',
            CASE WHEN e.birdssold > 0 AND e.c_wbirds = 0 AND e.c_wikg IS NULL
                 THEN 'No live weight on the bird sales' END,
            CASE WHEN e.finalbirds > 0 AND e.c_wikg IS NULL
                 THEN 'No weigh-in for the birds still in the house' END,
            CASE WHEN e.feedconsumedkg <= 0 THEN 'No feed recorded' END), '')
    FROM e
    ORDER BY e.startdate DESC, e.flockid DESC;
$function$;

-- 2. P&L by flock: the chick cost -----------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryreport_profitlossbyflock(text, date, date, integer, boolean);
CREATE FUNCTION public.sppoultryreport_profitlossbyflock(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false)
 RETURNS TABLE(flockid integer, flockname text, birdsplaced integer, eggrevenue numeric, birdsalesrevenue numeric, otherrevenue numeric, totalrevenue numeric, eggsproduced bigint, feedcost numeric, medicinevaccinecost numeric, laborcost numeric, otherexpenses numeric, active boolean, birdcost numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;               -- TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId)
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    RETURN QUERY
    WITH rev AS (
        SELECT s.flockid AS c_flockid,
            -- 375: byproducts are neither eggs nor live birds (they count in total revenue)
            SUM(CASE WHEN s.product ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL THEN s.totalamount ELSE 0 END) AS c_eggrevenue,
            SUM(CASE WHEN s.product NOT ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL AND (
                     s.product ILIKE '%bird%'     OR s.product ILIKE '%layer%'  OR s.product ILIKE '%broiler%'
                  OR s.product ILIKE '%cockerel%' OR s.product ILIKE '%chick%'  OR s.product ILIKE '%cock%'
                  OR s.product ILIKE '%hen%'      OR s.product ILIKE '%spent%'  OR s.product ILIKE '%pullet%'
                  OR s.product ILIKE '%fowl%'     OR s.product ILIKE '%culled%')
                THEN s.totalamount ELSE 0 END)                                                      AS c_birdrevenue,
            SUM(s.totalamount)                                                                      AS c_revenue
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.farmid = p_farmid
          AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
        GROUP  BY s.flockid
    ),
    eggs AS (
        SELECT r.flockid AS c_flockid, SUM(r.totalproduction::bigint) AS c_eggs
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate
        GROUP  BY r.flockid
    ),
    cost AS (
        SELECT e.flockid AS c_flockid,
            SUM(CASE WHEN e.category ILIKE '%feed%' THEN e.amount ELSE 0 END)                       AS c_feedcost,
            SUM(CASE WHEN e.category ILIKE '%medic%' OR e.category ILIKE '%vaccin%'
                       OR e.category ILIKE '%drug%'  OR e.category ILIKE '%health%'
                     THEN e.amount ELSE 0 END)                                                      AS c_medcost,
            SUM(CASE WHEN e.category ILIKE '%labo%'   OR e.category ILIKE '%salary%'
                       OR e.category ILIKE '%wage%'   OR e.category ILIKE '%payroll%'
                     THEN e.amount ELSE 0 END)                                                      AS c_laborcost,
            SUM(CASE WHEN e.category ILIKE '%feed%'   OR e.category ILIKE '%medic%'
                       OR e.category ILIKE '%vaccin%' OR e.category ILIKE '%drug%'
                       OR e.category ILIKE '%health%' OR e.category ILIKE '%labo%'
                       OR e.category ILIKE '%salary%' OR e.category ILIKE '%wage%'
                       OR e.category ILIKE '%payroll%'
                     THEN 0 ELSE e.amount END)                                                      AS c_othercost
        FROM   expense e
        WHERE  e.farmid = v_gid
          AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)
          AND  COALESCE(e.sourcetype, '') <> 'MainFlockBatch'     -- 402: the chick purchase is birdcost below
        GROUP  BY e.flockid
    ),
    -- 402: the chick purchase, shared by birds placed (as fnflock_lifetimesummary
    -- shares it), charged in the period the flock started.
    chicks AS (
        SELECT f.flockid AS c_flockid,
               ROUND(b.totalcost * p.originallyplaced / b.numberofbirds, 2) AS c_birdcost
        FROM   flock f
        JOIN   mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
        CROSS  JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) p
        WHERE  f.farmid = p_farmid
          AND  (p_flockid IS NULL OR f.flockid = p_flockid)
          AND  NOT COALESCE(f.isdeleted, FALSE)
          AND  f.startdate >= p_startdate AND f.startdate <= p_enddate
          AND  COALESCE(b.totalcost, 0) > 0 AND COALESCE(b.numberofbirds, 0) > 0
    )
    SELECT
        f.flockid,
        f.name::text                                                                                AS flockname,
        COALESCE(f.quantity, 0)                                                                     AS birdsplaced,
        COALESCE(rev.c_eggrevenue, 0)                                                               AS eggrevenue,
        COALESCE(rev.c_birdrevenue, 0)                                                              AS birdsalesrevenue,
        COALESCE(rev.c_revenue, 0) - COALESCE(rev.c_eggrevenue, 0) - COALESCE(rev.c_birdrevenue, 0) AS otherrevenue,
        COALESCE(rev.c_revenue, 0)                                                                  AS totalrevenue,
        COALESCE(eggs.c_eggs, 0)::bigint                                                            AS eggsproduced,
        COALESCE(cost.c_feedcost, 0)                                                                AS feedcost,
        COALESCE(cost.c_medcost, 0)                                                                 AS medicinevaccinecost,
        COALESCE(cost.c_laborcost, 0)                                                               AS laborcost,
        COALESCE(cost.c_othercost, 0)                                                               AS otherexpenses,
        COALESCE(f.active, TRUE)                                                                    AS active,
        COALESCE(chicks.c_birdcost, 0)                                                              AS birdcost
    FROM   flock f
    LEFT JOIN rev    ON rev.c_flockid    = f.flockid
    LEFT JOIN eggs   ON eggs.c_flockid   = f.flockid
    LEFT JOIN cost   ON cost.c_flockid   = f.flockid
    LEFT JOIN chicks ON chicks.c_flockid = f.flockid
    WHERE  f.farmid = p_farmid
      AND  (p_flockid IS NULL OR f.flockid = p_flockid)
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
    ORDER  BY f.name;
END
$function$;

COMMIT;
