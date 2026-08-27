-- =============================================================================
-- 225_WaterSalePaymentMethodOnList.postgres.sql
--
-- Purpose
-- -------
-- The water Sales list shows Total / Paid / Balance / Status but never says HOW
-- a sale was paid -- the method lives on `waterpayments`, not on the sale
-- header, so it never reached the list endpoint. This adds a derived
-- `paymentmethod` to the two header readers so the UI can show Method as its
-- own column, separate from Status (which is a state, not a method).
--
-- Derivation
-- ----------
-- A sale can have several payments, each with its own method, so one column has
-- to summarise them:
--
--     no payments yet          -> NULL   (UI renders an em dash)
--     one distinct method      -> that method
--     several distinct methods -> 'Mixed'
--
-- Payments with a NULL/blank method are ignored for the distinct count -- an
-- unlabelled row shouldn't turn a clean "Cash" into "Mixed". If every payment
-- is unlabelled the result is NULL, which reads the same as "not paid yet"; the
-- Paid/Balance columns already distinguish those two cases.
--
-- Both functions keep the new column LAST in the result set. The service reads
-- it through HasCol(), so an API running against a database without this
-- migration keeps working and simply reports no method.
--
-- Idempotent, transactional. Both functions are DROPped first: adding an OUT
-- column changes the return type, which CREATE OR REPLACE alone refuses.
-- =============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- List: adds paymentmethod after sourceid (migration 111 added those two).
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwatersale_getall(text);

CREATE OR REPLACE FUNCTION public.spwatersale_getall(p_farmid text)
RETURNS TABLE(
    watersaleid     integer,
    farmid          text,
    watercustomerid integer,
    customername    text,
    saledate        timestamp without time zone,
    totalamount     numeric,
    amountpaid      numeric,
    balance         numeric,
    status          text,
    notes           text,
    createddate     timestamp without time zone,
    createdby       text,
    updateddate     timestamp without time zone,
    sourcetype      text,
    sourceid        integer,
    paymentmethod   text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.watersaleid, s.farmid::text, s.watercustomerid, c.name::text AS customername,
           s.saledate, s.totalamount, s.amountpaid,
           (s.totalamount - s.amountpaid) AS balance,
           s.status::text, s.notes::text, s.createddate, s.createdby::text, s.updateddate,
           s.sourcetype::text, s.sourceid,
           m.paymentmethod
    FROM   watersales s
    LEFT   JOIN watercustomers c ON c.watercustomerid = s.watercustomerid
    LEFT   JOIN LATERAL (
               SELECT CASE COUNT(DISTINCT p.paymentmethod)
                        WHEN 0 THEN NULL
                        WHEN 1 THEN MIN(p.paymentmethod)::text
                        ELSE 'Mixed'
                      END AS paymentmethod
               FROM   waterpayments p
               WHERE  p.watersaleid = s.watersaleid
                 AND  p.farmid = s.farmid
                 AND  NULLIF(BTRIM(p.paymentmethod), '') IS NOT NULL
           ) m ON TRUE
    WHERE  s.farmid = p_farmid
    ORDER  BY s.saledate DESC, s.watersaleid DESC;
END;
$function$;

-- ----------------------------------------------------------------------------
-- Detail header: same column, appended last. (rs1 never carried sourcetype /
-- sourceid -- left as-is so this migration changes one thing only.)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spwatersale_getbyid_rs1(integer, text);

CREATE OR REPLACE FUNCTION public.spwatersale_getbyid_rs1(p_watersaleid integer, p_farmid text)
RETURNS TABLE(
    watersaleid     integer,
    farmid          text,
    watercustomerid integer,
    customername    text,
    saledate        timestamp without time zone,
    totalamount     numeric,
    amountpaid      numeric,
    balance         numeric,
    status          text,
    notes           text,
    createddate     timestamp without time zone,
    createdby       text,
    updateddate     timestamp without time zone,
    paymentmethod   text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.watersaleid, s.farmid::text, s.watercustomerid, c.name::text,
           s.saledate, s.totalamount, s.amountpaid,
           (s.totalamount - s.amountpaid),
           s.status::text, s.notes::text, s.createddate, s.createdby::text, s.updateddate,
           m.paymentmethod
    FROM   watersales s
    LEFT   JOIN watercustomers c ON c.watercustomerid = s.watercustomerid
    LEFT   JOIN LATERAL (
               SELECT CASE COUNT(DISTINCT p.paymentmethod)
                        WHEN 0 THEN NULL
                        WHEN 1 THEN MIN(p.paymentmethod)::text
                        ELSE 'Mixed'
                      END AS paymentmethod
               FROM   waterpayments p
               WHERE  p.watersaleid = s.watersaleid
                 AND  p.farmid = s.farmid
                 AND  NULLIF(BTRIM(p.paymentmethod), '') IS NOT NULL
           ) m ON TRUE
    WHERE  s.watersaleid = p_watersaleid AND s.farmid = p_farmid;
END;
$function$;

COMMIT;
