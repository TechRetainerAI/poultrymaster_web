-- =============================================================================
-- Migration 292: Let a QR guest rate the restaurant  (PostgreSQL)
-- =============================================================================
-- A guest scans the table QR, orders, eats -- and then has no way to say the
-- service was good. Staff already have a full feedback system (migration 224:
-- restaurantcustomerfeedback, surfaced at Growth -> Customers & CRM -> Feedback,
-- with ratings, a status workflow and a reply box). Only the guest's door was
-- missing.
--
-- NO NEW COLUMNS, AND NO NEW TABLE. A deliberate constraint, not laziness:
--   * restaurantcustomerfeedback already carries rating, foodrating,
--     servicerating, ambiencerating, comment, orderid, customerid, customername,
--     and a `source` column whose own comment already lists 'QR' as a value.
--   * More importantly, adding a column would BREAK the staff list. Two places
--     depend on this table's exact column order:
--       - sprestaurant_feedback_list (224) does `SELECT f.*` into a RETURNS TABLE
--         of 16 explicit columns -> a 17th column fails at runtime with 42804.
--       - Business/RestaurantCRMService.ListFeedbackAsync reads by ORDINAL
--         (r.GetInt32(0) .. r.GetDateTime(15)) -> a new column shifts every read.
--     Migration 251 left a note warning about exactly this hazard on
--     restaurantcustomers. The same trap exists here. Do not add columns.
--
-- THE TOKEN IS THE CREDENTIAL
-- This is a PUBLIC, unauthenticated write, so it is keyed on the order's
-- trackingtoken rather than on a farmid in the URL. That choice does the work of
-- an auth check:
--   * possession of the token proves the guest actually placed that order;
--   * farmid, orderid, customerid and customername are read FROM THE ORDER, never
--     from the request body -- the same rule the rest of this module follows
--     (see 251, and the guest-order price handling in 248);
--   * without it, POST /public/{farmid}/feedback would let anyone on the internet
--     flood a restaurant's CRM with invented reviews.
-- =============================================================================

-- 0. Drop any earlier version of these two functions -------------------------
-- CREATE OR REPLACE cannot change a return type, and the column names of a
-- RETURNS TABLE are part of it. An earlier draft of this migration named the
-- first status column `found`; replacing it in place fails with 42P13. Dropping
-- by name (all overloads) makes this file safe to re-apply over any earlier
-- version of itself -- same approach as migration 251.
DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('sprestaurant_public_feedback_status',
                            'sprestaurant_public_feedback_insert')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- 1. One guest rating per order ----------------------------------------------
-- Partial, and scoped to source='QR' on purpose: a guest gets exactly one bite
-- at it, while staff remain free to log several notes against the same order
-- from the CRM screen (existing behaviour, and not ours to restrict).
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantfeedback_qr_order
    ON public.restaurantcustomerfeedback (orderid)
    WHERE source = 'QR' AND orderid IS NOT NULL;

-- 2. What the guest UI is allowed to show ------------------------------------
-- Returns one row describing the order behind a token, so the page can choose
-- between "not yet", "rate us" and "thanks, you already did" without guessing.
-- Safe to call with a junk token: orderfound = false and nothing leaks.
CREATE FUNCTION public.sprestaurant_public_feedback_status(p_token text)
 RETURNS TABLE (
    -- NOT named `found`: FOUND is a built-in PL/pgSQL variable, so a result
    -- column of that name makes every plpgsql caller fail with 42702. Learned
    -- from this migration's own self-test on its first run.
    orderfound     boolean,
    ordernumber    text,
    orderstatus    text,
    can_rate       boolean,
    already_rated  boolean,
    rating         int,
    comment        text
 )
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_orderid   integer;
    v_number    text;
    v_status    text;
    v_fbrating  integer;
    v_fbcomment text;
BEGIN
    SELECT o.orderid, o.ordernumber, o.status
      INTO v_orderid, v_number, v_status
    FROM restaurantorders o
    WHERE o.trackingtoken = p_token;

    IF v_orderid IS NULL THEN
        RETURN QUERY SELECT false, NULL::text, NULL::text, false, false, NULL::int, NULL::text;
        RETURN;
    END IF;

    SELECT f.rating, f.comment INTO v_fbrating, v_fbcomment
    FROM restaurantcustomerfeedback f
    WHERE f.orderid = v_orderid AND f.source = 'QR'
    LIMIT 1;

    RETURN QUERY SELECT
        true,
        v_number,
        v_status,
        -- Rating is offered only once the food has actually arrived. Rating a
        -- 'Placed' order would be meaningless, and a Cancelled order has nothing
        -- to rate (that flow already tells the guest to speak to staff).
        (v_status IN ('Ready','Served','Completed') AND v_fbrating IS NULL),
        (v_fbrating IS NOT NULL),
        v_fbrating,
        v_fbcomment;
END;
$function$;

-- 3. Take the rating ---------------------------------------------------------
-- Idempotent: a guest who submits twice (double tap, or a retry after a flaky
-- connection) gets their existing rating back rather than an error or a second
-- row. The unique index in step 1 is the real guard; this check keeps the common
-- case from ever reaching it.
CREATE FUNCTION public.sprestaurant_public_feedback_insert(
    p_token     text,
    p_rating    int,
    p_food      int DEFAULT NULL,
    p_service   int DEFAULT NULL,
    p_ambience  int DEFAULT NULL,
    p_comment   text DEFAULT NULL
)
 RETURNS TABLE (feedbackid int, alreadyrated boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_farmid   text;
    v_orderid  integer;
    v_status   text;
    v_custid   integer;
    v_custname text;
    v_existing integer;
    v_new      integer;
BEGIN
    IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
        RAISE EXCEPTION 'Rating must be between 1 and 5';
    END IF;
    -- Sub-ratings are optional, but an out-of-range value is a caller bug, not
    -- something to store quietly: the table CHECK constraints would reject it
    -- anyway, with a far less readable message.
    IF p_food     IS NOT NULL AND (p_food     < 1 OR p_food     > 5) THEN RAISE EXCEPTION 'Food rating must be between 1 and 5';     END IF;
    IF p_service  IS NOT NULL AND (p_service  < 1 OR p_service  > 5) THEN RAISE EXCEPTION 'Service rating must be between 1 and 5';  END IF;
    IF p_ambience IS NOT NULL AND (p_ambience < 1 OR p_ambience > 5) THEN RAISE EXCEPTION 'Ambience rating must be between 1 and 5'; END IF;

    SELECT o.farmid, o.orderid, o.status, o.customerid, o.customername
      INTO v_farmid, v_orderid, v_status, v_custid, v_custname
    FROM restaurantorders o
    WHERE o.trackingtoken = p_token;

    IF v_orderid IS NULL THEN
        RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_status NOT IN ('Ready','Served','Completed') THEN
        RAISE EXCEPTION 'This order cannot be rated yet';
    END IF;

    SELECT f.feedbackid INTO v_existing
    FROM restaurantcustomerfeedback f
    WHERE f.orderid = v_orderid AND f.source = 'QR'
    LIMIT 1;

    IF v_existing IS NOT NULL THEN
        RETURN QUERY SELECT v_existing, true;
        RETURN;
    END IF;

    -- customerid is carried over so a rating attaches to the CRM record when the
    -- guest has been saved as a customer (migration 251 links the two). It stays
    -- NULL for a walk-up stranger, which the feedback table already allows.
    INSERT INTO restaurantcustomerfeedback
           (farmid, customerid, customername, orderid,
            rating, foodrating, servicerating, ambiencerating,
            comment, source, status)
    VALUES (v_farmid, v_custid, NULLIF(btrim(coalesce(v_custname,'')),''), v_orderid,
            p_rating, p_food, p_service, p_ambience,
            NULLIF(btrim(coalesce(p_comment,'')),''), 'QR', 'New')
    RETURNING restaurantcustomerfeedback.feedbackid INTO v_new;

    RETURN QUERY SELECT v_new, false;
END;
$function$;
