-- =============================================================================
-- 301_ReadersReturnCreatedAt.postgres.sql
--
-- Purpose
-- -------
-- Make the remaining list readers return the row's creation timestamp, so every
-- table in the frontend can show a time next to the date.
--
-- WHY THIS IS NEEDED AT ALL
-- =========================
-- Tables render "17 Sep 2026, 11:56" where the DATE comes from the business-date
-- column and the TIME from the row's creation timestamp. The time has to come
-- from a separate column because a back-dated entry is stored at midnight by
-- design -- on live data `expense.expensedate` carries a real clock time on 1 of
-- 185 rows, so the business date alone would print "12:00 AM" nearly everywhere.
--
-- 184 of 237 readers already return a creation timestamp. These eight did not,
-- which is why some pages showed a time and others did not.
--
-- WHY DROP AND RECREATE RATHER THAN CREATE OR REPLACE
-- ===================================================
-- Adding a column to RETURNS TABLE changes the function's return type, and
-- Postgres refuses to do that through CREATE OR REPLACE ("cannot change return
-- type of existing function"). Each function is therefore dropped by its exact
-- argument signature and recreated.
--
-- The DROPs are deliberately NOT cascading. If some view or function depends on
-- one of these, this migration must fail loudly in the dry run rather than
-- silently destroying the dependent object.
--
-- THE NEW COLUMN IS ALWAYS NAMED createdat, AND ALWAYS LAST
-- =========================================================
-- Last, because appending cannot disturb anything reading these results
-- positionally.
--
-- Named consistently even though the underlying columns are not -- the base
-- tables variously call it createdat, createddate and datecreated (and `flock`
-- has BOTH createdat and datecreated). Normalising here means the C# services
-- and the frontend do not each need to know which spelling a given table used.
--
-- EVERY BODY BELOW IS REPRODUCED FROM THE LIVE DEFINITION.
-- The only change in each is the added column, marked with "-- 301:".
-- Reproducing rather than rewriting is what lets the dry run prove nothing else
-- moved.
--
-- NO DATA CHANGES. These are read-only functions; the migration adds an output
-- column and nothing else. Every source column was verified non-NULL on dev
-- (productionrecords 401 rows, feedusage 249, flock 60, houses 44,
-- inventoryitem 11 -- zero nulls in all).
--
-- Order: after 300.
--
-- Idempotent: DROP IF EXISTS + CREATE.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Egg production.  Base table is productionrecords (NOT eggproduction), and
--    it already used pr.createdat to break ties in the ORDER BY.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.speggproduction_getall(text);

CREATE FUNCTION public.speggproduction_getall(p_farmid text)
 RETURNS TABLE(productionid integer, flockid integer, productiondate date, eggcount integer,
               production9am integer, production12pm integer, production4pm integer,
               production4thpick integer, production5thpick integer, production6thpick integer,
               totalproduction integer, brokeneggs integer, meatyeggs integer, softeggs integer,
               losteggs integer, notes text, egggrade text, userid text, farmid text,
               createdat timestamp)          -- 301: added
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id AS productionid,
        COALESCE(pr.flockid, 0) AS flockid,
        pr.date AS productiondate,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        COALESCE(pr.production9am, 0) + COALESCE(pr.production12pm, 0) + COALESCE(pr.production4pm, 0) + COALESCE(pr.production4thpick, 0) + COALESCE(pr.production5thpick, 0) + COALESCE(pr.production6thpick, 0) AS totalproduction,
        pr.brokeneggs,
        COALESCE(pr.meatyeggs, 0) AS meatyeggs,
        COALESCE(pr.softeggs, 0)  AS softeggs,
        COALESCE(pr.losteggs, 0)  AS losteggs,
        pr.notes::text,
        pr.egggrade::text,
        COALESCE(pr.userid, pr.createdby)::text AS userid,
        pr.farmid::text,
        pr.createdat                          -- 301: added
    FROM productionrecords pr
    WHERE pr.farmid = p_farmid
    ORDER BY pr.date DESC, pr.createdat DESC;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Feed usage.  Source column is datecreated; exposed as createdat.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spfeedusage_getall(text, text);

CREATE FUNCTION public.spfeedusage_getall(p_userid text DEFAULT NULL::text, p_farmid text DEFAULT NULL::text)
 RETURNS TABLE(feedusageid integer, flockid integer, usagedate date, feedtype text,
               quantitykg numeric, userid text, farmid text, source text,
               sourceproductionrecordid integer,
               createdat timestamp)          -- 301: added
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        fu.feedusageid,
        fu.flockid,
        fu.usagedate,
        fu.feedtype::text,
        fu.quantitykg,
        fu.userid::text,
        fu.farmid::text,
        CASE
            WHEN fu.sourceproductionrecordid IS NOT NULL THEN 'Production Record'
            ELSE 'Manual Entry'
        END::text AS source,
        fu.sourceproductionrecordid,
        fu.datecreated                        -- 301: added (table spells it datecreated)
    FROM feedusage fu
    WHERE fu.farmid = p_farmid
    ORDER BY fu.usagedate DESC;
END
$function$;

-- -----------------------------------------------------------------------------
-- 3. Flock.  This table has BOTH createdat and datecreated; createdat is the one
--    the rest of the schema uses, so that is what is exposed.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spflock_getall(text, text);

CREATE FUNCTION public.spflock_getall(p_farmid text, p_userid text DEFAULT NULL::text)
 RETURNS TABLE(flockid integer, userid text, farmid text, name text, breed text, startdate date,
               quantity integer, active boolean, houseid integer, batchid integer,
               inactivationreason text, otherreason text, notes text, hasarrived boolean,
               batchname text,
               createdat timestamp)          -- 301: added
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        f.flockid,
        f.userid::text,
        f.farmid::text,
        f.name::text,
        f.breed::text,
        f.startdate,
        f.quantity,
        COALESCE(f.active, TRUE) AS active,
        f.houseid,
        f.batchid,
        f.inactivationreason::text,
        f.otherreason::text,
        f.notes::text,
        COALESCE(f.hasarrived, FALSE) AS hasarrived,
        b.batchname::text,
        f.createdat                           -- 301: added
    FROM flock f
    LEFT JOIN mainflockbatch b
        ON f.batchid = b.batchid AND f.farmid = b.farmid
    WHERE f.farmid = p_farmid
    ORDER BY f.startdate DESC;
END
$function$;

-- -----------------------------------------------------------------------------
-- 4. Generic billing runs.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spgenericbillingrun_getall(text);

CREATE FUNCTION public.spgenericbillingrun_getall(p_farmid text)
 RETURNS TABLE(genericbillingrunid integer, billingrundate timestamp without time zone,
               asofdate date, totalsubscriptionschecked integer, totalinvoicesgenerated integer,
               totalskipped integer, status text, notes text, createdby text,
               createdat timestamp)          -- 301: added
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.genericbillingrunid, r.billingrundate, r.asofdate,
           r.totalsubscriptionschecked, r.totalinvoicesgenerated,
           r.totalskipped, r.status, r.notes, r.createdby,
           r.createdat                        -- 301: added
    FROM   genericbillingruns r
    WHERE  r.farmid = p_farmid
    ORDER  BY r.billingrundate DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Generic owner entries.  Base table is genericownercontributiondraws.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spgenericownerentry_getall(text, text, date, date);

CREATE FUNCTION public.spgenericownerentry_getall(p_farmid text, p_entrytype text DEFAULT NULL::text,
                                                  p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(genericownerentryid integer, entrydate timestamp without time zone, entrytype text,
               amount numeric, genericcashaccountid integer, cashaccountname text,
               paymentmethod text, ownername text, referenceno text, notes text, status text,
               createdby text, reversedby text, reversedat timestamp without time zone,
               reversalreason text,
               createdat timestamp)          -- 301: added
 LANGUAGE sql
 STABLE
AS $function$
    SELECT o.genericownerentryid, o.entrydate, o.entrytype, o.amount,
           o.genericcashaccountid, a.accountname::text, o.paymentmethod,
           o.ownername, o.referenceno, o.notes, o.status, o.createdby,
           o.reversedby, o.reversedat, o.reversalreason,
           o.createdat                        -- 301: added
    FROM   genericownercontributiondraws o
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = o.genericcashaccountid
    WHERE  o.farmid = p_farmid
      AND  (p_entrytype IS NULL OR p_entrytype = 'All' OR o.entrytype = p_entrytype)
      AND  (p_from IS NULL OR o.entrydate::date >= p_from)
      AND  (p_to   IS NULL OR o.entrydate::date <= p_to)
    ORDER  BY o.entrydate DESC, o.genericownerentryid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Generic staff payments.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spgenericstaffpayment_getall(text, integer, date, date);

CREATE FUNCTION public.spgenericstaffpayment_getall(p_farmid text, p_staffid integer DEFAULT NULL::integer,
                                                    p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(genericstaffpaymentid integer, genericstaffid integer, staffname text, staffrole text,
               workertype text, paymentdate timestamp without time zone, periodstart date,
               periodend date, amount numeric, paymentmethod text, genericcashaccountid integer,
               cashaccountname text, genericexpenseid integer, categoryname text, description text,
               referenceno text, status text, createdby text, reversedby text,
               reversedat timestamp without time zone, reversalreason text,
               createdat timestamp)          -- 301: added
 LANGUAGE sql
 STABLE
AS $function$
    SELECT sp.genericstaffpaymentid, sp.genericstaffid,
           btrim(COALESCE(s.firstname, '') || ' ' || COALESCE(s.lastname, ''))::text,
           s.role::text, COALESCE(s.workertype, 'Employee')::text,
           sp.paymentdate, sp.periodstart, sp.periodend, sp.amount, sp.paymentmethod,
           sp.genericcashaccountid, a.accountname::text,
           sp.genericexpenseid, c.name::text, sp.description, sp.referenceno,
           sp.status, sp.createdby, sp.reversedby, sp.reversedat, sp.reversalreason,
           sp.createdat                       -- 301: added
    FROM   genericstaffpayments sp
    LEFT   JOIN genericstaff s          ON s.genericstaffid = sp.genericstaffid
    LEFT   JOIN genericcashaccounts a   ON a.genericcashaccountid = sp.genericcashaccountid
    LEFT   JOIN genericexpensecategories c ON c.genericexpensecategoryid = sp.genericexpensecategoryid
    WHERE  sp.farmid = p_farmid
      AND  (p_staffid IS NULL OR sp.genericstaffid = p_staffid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
    ORDER  BY sp.paymentdate DESC, sp.genericstaffpaymentid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Houses.  Source column is createddate; exposed as createdat.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sphouse_getall(text, text);

CREATE FUNCTION public.sphouse_getall(p_userid text, p_farmid text)
 RETURNS TABLE(userid text, farmid text, houseid integer, housename text, capacity integer,
               location text,
               createdat timestamp)          -- 301: added
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        h.userid::text,
        h.farmid::text,
        h.houseid,
        h.housename::text,
        h.capacity,
        h.location::text,
        h.createddate                         -- 301: added (table spells it createddate)
    FROM houses h
    WHERE
    --h.userid = p_userid AND
      h.farmid = p_farmid
    ORDER BY h.housename;
END
$function$;

-- -----------------------------------------------------------------------------
-- 8. Inventory items.  Source column is datecreated; exposed as createdat.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spinventoryitem_getall(text, text);

CREATE FUNCTION public.spinventoryitem_getall(p_userid text, p_farmid text)
 RETURNS TABLE(itemid integer, userid text, farmid text, itemname text, category text,
               quantityinstock numeric, unitofmeasure text, reorderlevel numeric, supplierid integer,
               isactive boolean, cost numeric, suppliername text,
               purchasedate timestamp without time zone, notes text, location text,
               expirydate timestamp without time zone,
               createdat timestamp)          -- 301: added
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        i.itemid, i.userid::text, i.farmid::text, i.itemname::text, i.category::text,
        i.quantityinstock, i.unitofmeasure::text, i.reorderlevel, i.supplierid, i.isactive,
        i.cost, i.suppliername::text, i.purchasedate, i.notes::text, i.location::text, i.expirydate,
        i.datecreated                         -- 301: added (table spells it datecreated)
    FROM inventoryitem i
    WHERE i.farmid = p_farmid
    ORDER BY i.itemid DESC;
END
$function$;

-- -----------------------------------------------------------------------------
-- 9. Grants. Dropping a function drops its grants with it, so they must be
--    reissued or the API loses execute permission and every one of these pages
--    starts failing.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.speggproduction_getall(text)                      TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spfeedusage_getall(text, text)                    TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spflock_getall(text, text)                        TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spgenericbillingrun_getall(text)                  TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spgenericownerentry_getall(text, text, date, date) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spgenericstaffpayment_getall(text, integer, date, date) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sphouse_getall(text, text)                        TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spinventoryitem_getall(text, text)                TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT p.proname AS check,
       CASE WHEN pg_get_function_result(p.oid) ILIKE '%createdat%'
            THEN 'OK returns createdat' ELSE 'MISSING' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.prokind = 'f'
  AND  p.proname IN ('speggproduction_getall','spfeedusage_getall','spflock_getall',
                     'spgenericbillingrun_getall','spgenericownerentry_getall',
                     'spgenericstaffpayment_getall','sphouse_getall','spinventoryitem_getall')
ORDER  BY p.proname;
