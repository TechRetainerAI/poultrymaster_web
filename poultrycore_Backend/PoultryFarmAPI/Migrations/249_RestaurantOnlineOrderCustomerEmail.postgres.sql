-- =============================================================================
-- 249. Optional customer email on guest (QR / online) orders
-- =============================================================================
-- WHY
--   The guest checkout collects a name and a phone number. A receipt, an order
--   confirmation or any follow-up needs an email address, and `restaurantorders`
--   had no column for one -- `customeremail` existed only on
--   `restaurantdeliveryaddresses` (220_RestaurantOnlineOrdering.sql:86).
--   Adding the field to the form without this migration would have thrown away
--   whatever the customer typed.
--
--   Optional by design: requiring it would cost orders from guests who do not
--   have an email to hand, and the phone number is already the contact of record.
--
-- BACKWARD COMPATIBILITY -- this matters, because the Farm API is restarted by
-- hand here and will be running the OLD binary when this is applied:
--   * `p_customeremail` is appended LAST and defaults to NULL, so the old
--     binary's call -- which does not pass it -- still binds and still works.
--   * `customeremail` is appended to the pending-list result. The service reads
--     that result by column NAME (`GetOrdinal`), never by position, so the old
--     binary simply ignores the extra column.
--   Applying this migration before restarting the API is therefore safe.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, and every function is dropped by name
-- (all overloads) before being recreated, so re-running is a no-op.
-- =============================================================================

BEGIN;

ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS customeremail TEXT;

-- Drop by NAME rather than by signature: a per-signature DROP only matches
-- whichever version happens to be installed, which is what made 248
-- un-re-appliable until it was rewritten this way. No CASCADE -- a dependency
-- should fail loudly rather than be silently deleted.
DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'sprestaurant_online_order_insert',
              'sprestaurant_online_order_pending_list'
          )
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- ---------------------------------------------------------------------------
-- Insert, now carrying the optional email.
-- Unchanged from 248 apart from the new trailing parameter and column.
-- ---------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_online_order_insert(
    p_farmid TEXT, p_ordertype TEXT, p_tableid INT, p_tablenumber TEXT,
    p_customername TEXT, p_customerphone TEXT, p_covers INT, p_notes TEXT,
    p_onlinesource TEXT, p_deliveryaddress TEXT, p_deliveryfee NUMERIC,
    p_promocodeid INT, p_promocode TEXT, p_promodiscount NUMERIC,
    p_qrcodeid INT DEFAULT NULL, p_guestpaymentintent TEXT DEFAULT NULL,
    p_guestpaymentamount NUMERIC DEFAULT NULL,
    p_customeremail TEXT DEFAULT NULL
) RETURNS TABLE (orderid INT, ordernumber TEXT, trackingtoken TEXT) AS $$
DECLARE v_id INT; v_num TEXT; v_token TEXT; v_email TEXT;
BEGIN
    v_num := sprestaurant_order_next_number(p_farmid);
    v_token := 'TRK-' || EXTRACT(EPOCH FROM NOW())::BIGINT || '-' || FLOOR(RANDOM() * 1000000)::INT;

    -- An empty string is not an email address. Normalise blank-ish input to NULL
    -- so "has an email" is a single, honest test everywhere downstream.
    v_email := NULLIF(BTRIM(COALESCE(p_customeremail, '')), '');

    -- status falls through to the 'Placed' table default = awaiting staff confirmation.
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, tableid, tablenumber,
        customername, customerphone, customeremail, covers, notes,
        onlinesource, deliveryaddress, deliveryfee, promocodeid, promocode, promodiscount,
        trackingtoken, createdby, qrcodeid, guestpaymentintent, guestpaymentamount)
    VALUES (p_farmid, v_num, p_ordertype, p_tableid, p_tablenumber,
        p_customername, p_customerphone, v_email, p_covers, p_notes,
        p_onlinesource, p_deliveryaddress, p_deliveryfee, p_promocodeid, p_promocode, p_promodiscount,
        v_token, 'Online', p_qrcodeid, p_guestpaymentintent, p_guestpaymentamount)
    RETURNING restaurantorders.orderid INTO v_id;

    RETURN QUERY SELECT v_id, v_num, v_token;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Pending tray, now showing the email so staff can actually use it. Capturing
-- an address nobody can see would make the field decorative.
-- ---------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_online_order_pending_list(p_farmid TEXT)
RETURNS TABLE (
    orderid INT, ordernumber TEXT, ordertype TEXT, onlinesource TEXT,
    tableid INT, tablenumber TEXT, customername TEXT, customerphone TEXT,
    customeremail TEXT,
    guestpaymentintent TEXT, guestpaymentamount NUMERIC, notes TEXT, totalamount NUMERIC,
    itemcount BIGINT, itemsummary TEXT,
    createdat TIMESTAMP, waitingminutes DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.ordernumber, o.ordertype, o.onlinesource,
           o.tableid, o.tablenumber, o.customername, o.customerphone,
           o.customeremail,
           o.guestpaymentintent, o.guestpaymentamount, o.notes, o.totalamount,
           (SELECT COUNT(*) FROM restaurantorderitems i
             WHERE i.orderid = o.orderid AND i.farmid = o.farmid),
           (SELECT STRING_AGG(i.quantity || ' x ' || i.itemname, ', ' ORDER BY i.orderitemid)
              FROM restaurantorderitems i
             WHERE i.orderid = o.orderid AND i.farmid = o.farmid),
           o.createdat,
           (EXTRACT(EPOCH FROM (NOW() - o.createdat)) / 60.0)::DOUBLE PRECISION
    FROM restaurantorders o
    WHERE o.farmid = p_farmid
      AND o.onlinesource IS NOT NULL
      AND o.status = 'Placed'
    ORDER BY o.createdat ASC;   -- oldest first: longest-waiting guest served first
END;
$$ LANGUAGE plpgsql;

COMMIT;
