-- =============================================================================
-- 248 — Restaurant QR self-ordering: staff confirmation gate + hardening
-- =============================================================================
--
-- Builds on 220_RestaurantOnlineOrdering.sql, which already ships the public
-- ordering API, per-table QR tokens and the guest ordering page. This migration
-- closes the gaps that stop that foundation being safe to put in front of a
-- paying guest:
--
--   1. PRICES WERE TRUSTED FROM THE CLIENT. RestaurantOnlineOrderService passed
--      item.UnitPrice and item.ItemName straight from the request body into
--      sprestaurant_orderitem_insert, so a guest could order anything for 0.00.
--      sprestaurant_online_orderitem_insert now reads both from the menu table.
--
--   2. EVERY GUEST ORDER TOTALLED ZERO. Nothing on the online path ever called
--      sprestaurant_order_recalc, so totalamount stayed at its default.
--      sprestaurant_online_order_finalize fixes this and re-validates the promo
--      server-side against the real subtotal.
--
--   3. UNCONFIRMED ORDERS REACHED THE KITCHEN. sprestaurant_online_order_insert
--      left status at the 'Placed' table default, and sprestaurant_kds_queue
--      shows anything not Cancelled/Refunded/Completed. One added predicate in
--      the KDS query is the confirmation gate.
--
--   4. A PRANK ORDER SEIZED A TABLE. The insert marked the table Occupied
--      immediately. Occupancy moves to the accept step.
--
-- Status model: we deliberately reuse the existing lifecycle from
-- 217_RestaurantFloorPlanAndPOS.sql:58 — 'Placed' means "guest submitted,
-- awaiting staff", 'Confirmed' means "staff accepted". No new status string is
-- introduced, so badges, filters and reports elsewhere keep working untouched.
--
-- POS orders (onlinesource IS NULL) are NOT affected by the gate: they continue
-- to reach the kitchen at 'Placed' exactly as before.
--
-- Idempotent. Safe to re-run.
--
-- IMPORTANT: Postgres refuses CREATE OR REPLACE FUNCTION when the RETURNS TABLE
-- shape changes, and a changed ARGUMENT list silently creates an overload rather
-- than replacing — after which the C# named-parameter calls may bind to either
-- copy. Every function whose signature or return shape changes below is
-- therefore preceded by an explicit DROP with its exact argument types.
-- sprestaurant_kds_queue keeps its exact signature and return shape (only the
-- WHERE clause changes), so it is replaced in place without a DROP.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. SCHEMA
-- =============================================================================

ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS qrcodeid INT;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS confirmedat TIMESTAMP;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS confirmedby TEXT;
-- Indicative only. The guest tells staff how they plan to settle at the counter;
-- no money moves through the app.
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS guestpaymentintent TEXT;
-- What the guest said they would hand over. Recorded alongside the method so staff
-- can see the intent, but it is NOT a payment: nothing is charged, paidamount is
-- untouched, and the order stays Unpaid until it is settled through the POS.
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS guestpaymentamount NUMERIC(12,2);

COMMENT ON COLUMN restaurantorders.guestpaymentintent IS
    'MobileMoney | CreditCard | Cash - what the guest chose at checkout. Indicative only; no gateway is wired yet.';
COMMENT ON COLUMN restaurantorders.guestpaymentamount IS
    'Amount the guest entered at checkout. Indicative only - never treat as a received payment.';

COMMENT ON COLUMN restaurantorders.qrcodeid IS
    'The restaurantqrcodes row this order was placed through. Proof the order came from a real scan; NULL for POS and plain web orders.';

-- The pending tray polls this every 10s per farm. Partial index keeps it cheap
-- as the orders table grows.
CREATE INDEX IF NOT EXISTS ix_restaurantorders_pending_online
    ON restaurantorders(farmid, createdat DESC)
    WHERE onlinesource IS NOT NULL AND status = 'Placed';

-- A QR code is either the restaurant's own (one poster at the counter, the
-- queue-skipping case) or a specific table's (waiter service). Stored explicitly
-- rather than inferred from "tableid IS NULL" so the UI can label a card
-- correctly and the guest page knows whether to default to DineIn or Takeaway.
ALTER TABLE restaurantqrcodes ADD COLUMN IF NOT EXISTS codetype TEXT NOT NULL DEFAULT 'Table';
COMMENT ON COLUMN restaurantqrcodes.codetype IS 'Restaurant = one code for the whole venue; Table = tied to one table.';

ALTER TABLE restaurantonlineorderingsettings
    ADD COLUMN IF NOT EXISTS publicbaseurl TEXT;
ALTER TABLE restaurantonlineorderingsettings
    ADD COLUMN IF NOT EXISTS maxordersperqrslot INT DEFAULT 3;
ALTER TABLE restaurantonlineorderingsettings
    ADD COLUMN IF NOT EXISTS qrslotdurationmins INT DEFAULT 10;

COMMENT ON COLUMN restaurantonlineorderingsettings.publicbaseurl IS
    'Origin baked into printed QR codes, e.g. https://poultrymaster.com. Blank means the browser uses window.location.origin. Stored rather than compiled in because NEXT_PUBLIC_* vars are fixed at Docker build time.';
COMMENT ON COLUMN restaurantonlineorderingsettings.maxordersperqrslot IS
    'Per-table rate limit: max orders from one QR code within qrslotdurationmins. 0 = unlimited.';

-- ---------------------------------------------------------------------------
-- Drop every overload of the functions this migration redefines.
--
-- Postgres will not CREATE OR REPLACE a function whose RETURNS TABLE shape has
-- changed, and a changed ARGUMENT list silently creates a second overload rather
-- than replacing - after which a named-parameter call can bind to either copy.
-- Dropping by name (rather than by a hard-coded signature) makes this migration
-- safe to re-run: a per-signature DROP only matches whichever version happens to
-- be installed, so the second run fails with "already exists with same argument
-- types". Dependent objects are recreated below.
-- ---------------------------------------------------------------------------
DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'sprestaurant_qrcode_scan',
              'sprestaurant_qrcode_generate',
              'sprestaurant_qrcode_list',
              'sprestaurant_online_order_insert',
              'sprestaurant_order_list',
              'sprestaurant_order_get',
              'sprestaurant_order_track',
              'sprestaurant_kds_queue',
              'sprestaurant_onlinesettings_get',
              'sprestaurant_kds_stats',
              'sprestaurant_onlinesettings_toggle'
          )
    LOOP
        -- No CASCADE on purpose. CASCADE would silently drop anything that
        -- depends on these functions; failing loudly is far safer than quietly
        -- deleting a dependent object nobody knew about.
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;


-- ---------------------------------------------------------------------------
-- Settings reader, rebuilt with an explicit column list.
--
-- The 220 version was "RETURN QUERY SELECT s.* FROM restaurantonlineorderingsettings s".
-- Adding the three columns above therefore broke it instantly: the body started
-- returning 25 columns against a 22-column RETURNS TABLE, and every call failed
-- with 42804 "structure of query does not match function result type" - which took
-- out the whole guest ordering flow, since placing an order checks settings first.
--
-- SELECT * inside a RETURNS TABLE function is a trap: it silently couples the
-- function's contract to the table's column list. Named columns instead.
-- ---------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_onlinesettings_get(p_farmid TEXT)
RETURNS TABLE (
    onlineorderingsettingid INT, farmid TEXT, isenabled BOOLEAN,
    allowdineinqr BOOLEAN, allowtakeaway BOOLEAN, allowdelivery BOOLEAN,
    minorderamount NUMERIC, maxordersperslot INT, slotdurationmins INT,
    estimatedprepminsdine INT, estimatedprepminstake INT, estimatedprepminsdeliv INT,
    deliveryfeetype TEXT, deliveryfeeamount NUMERIC, freedeliveryabove NUMERIC,
    maxdeliverydistancekm NUMERIC, acceptingorders BOOLEAN, pausedreason TEXT,
    welcomemessage TEXT, termsandconditions TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP,
    publicbaseurl TEXT, maxordersperqrslot INT, qrslotdurationmins INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.onlineorderingsettingid, s.farmid, s.isenabled,
           s.allowdineinqr, s.allowtakeaway, s.allowdelivery,
           s.minorderamount, s.maxordersperslot, s.slotdurationmins,
           s.estimatedprepminsdine, s.estimatedprepminstake, s.estimatedprepminsdeliv,
           s.deliveryfeetype, s.deliveryfeeamount, s.freedeliveryabove,
           s.maxdeliverydistancekm, s.acceptingorders, s.pausedreason,
           s.welcomemessage, s.termsandconditions,
           s.createdat, s.updatedat,
           s.publicbaseurl, s.maxordersperqrslot, s.qrslotdurationmins
    FROM restaurantonlineorderingsettings s WHERE s.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;


-- Kitchen stats: same PostgreSQL 14+ EXTRACT change as the queue above. AVG/MAX
-- over a numeric yield numeric, but the signature promises DOUBLE PRECISION, so
-- on PostgreSQL 18 this failed with 42804 and the KDS header showed nothing.
-- Body copied from 218_RestaurantKDS.sql with explicit casts added.
CREATE FUNCTION sprestaurant_kds_stats(p_farmid TEXT)
RETURNS TABLE (
    pending_count BIGINT, preparing_count BIGINT, ready_count BIGINT,
    avg_prep_minutes DOUBLE PRECISION, longest_wait_minutes DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE oi.status = 'Pending') AS pending_count,
        COUNT(*) FILTER (WHERE oi.status = 'Preparing') AS preparing_count,
        COUNT(*) FILTER (WHERE oi.status = 'Ready') AS ready_count,
        AVG(EXTRACT(EPOCH FROM (oi.readyat - oi.prepstartedat)) / 60.0)
            FILTER (WHERE oi.readyat IS NOT NULL AND oi.prepstartedat IS NOT NULL)::DOUBLE PRECISION AS avg_prep_minutes,
        MAX(EXTRACT(EPOCH FROM (NOW() - oi.createdat)) / 60.0)
            FILTER (WHERE oi.status IN ('Pending', 'Preparing'))::DOUBLE PRECISION AS longest_wait_minutes
    FROM restaurantorderitems oi
    JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
    WHERE oi.farmid = p_farmid
      AND oi.status IN ('Pending', 'Preparing', 'Ready')
      AND o.status NOT IN ('Cancelled', 'Refunded', 'Completed');
END;
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------------
-- Accepting-orders toggle, as an UPSERT.
--
-- The 220 version was a bare UPDATE. A restaurant that had never opened the
-- settings tab has no row, so the UPDATE matched nothing and returned VOID -
-- the switch appeared to work in the UI and silently changed nothing, which is
-- indistinguishable from a broken feature. Now it creates the row.
-- ---------------------------------------------------------------------------
CREATE FUNCTION sprestaurant_onlinesettings_toggle(p_farmid TEXT, p_accepting BOOLEAN, p_reason TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    INSERT INTO restaurantonlineorderingsettings (farmid, isenabled, acceptingorders, pausedreason)
    VALUES (p_farmid, TRUE, p_accepting, p_reason)
    ON CONFLICT (farmid) DO UPDATE
        SET acceptingorders = p_accepting,
            pausedreason    = p_reason,
            updatedat       = NOW();
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 2. QR SCAN — also return the qr code id so an order can be bound to it
-- =============================================================================


CREATE FUNCTION sprestaurant_qrcode_scan(p_token TEXT)
RETURNS TABLE (qrcodeid INT, farmid TEXT, tableid INT, tablenumber TEXT, isactive BOOLEAN, codetype TEXT) AS $$
BEGIN
    -- Only count scans of live codes, so a deactivated code's counter doesn't
    -- keep climbing and look like real traffic.
    UPDATE restaurantqrcodes q SET scanccount = q.scanccount + 1, lastscanndat = NOW()
    WHERE q.qrtoken = p_token AND q.isactive = TRUE;

    RETURN QUERY
    SELECT q.qrcodeid, q.farmid, q.tableid, q.tablenumber, q.isactive, q.codetype
    FROM restaurantqrcodes q WHERE q.qrtoken = p_token;
END;
$$ LANGUAGE plpgsql;

-- Generate: a restaurant-wide code has no table. The old signature stays valid
-- (codetype defaults to 'Table'), so nothing that calls it today breaks.

CREATE FUNCTION sprestaurant_qrcode_generate(
    p_farmid TEXT, p_tableid INT, p_tablenumber TEXT, p_codetype TEXT DEFAULT 'Table'
) RETURNS TABLE (qrcodeid INT, qrtoken TEXT) AS $$
DECLARE v_id INT; v_token TEXT; v_label TEXT; v_existing INT;
BEGIN
    IF p_codetype = 'Restaurant' THEN
        -- One per restaurant. Handing out two would split the scan counts and
        -- leave stale posters on the wall, so reuse the live one instead.
        SELECT q.qrcodeid INTO v_existing FROM restaurantqrcodes q
        WHERE q.farmid = p_farmid AND q.codetype = 'Restaurant' AND q.isactive = TRUE LIMIT 1;
        IF v_existing IS NOT NULL THEN
            RETURN QUERY SELECT q.qrcodeid, q.qrtoken FROM restaurantqrcodes q WHERE q.qrcodeid = v_existing;
            RETURN;
        END IF;
        v_label := 'restaurant';

        -- Generating the venue code IS the act of opening online ordering. Leaving
        -- the restaurant switched off here is what produced "online ordering is
        -- currently unavailable" the moment anyone scanned the code they had just
        -- been told to print.
        INSERT INTO restaurantonlineorderingsettings (farmid, isenabled, acceptingorders)
        VALUES (p_farmid, TRUE, TRUE)
        ON CONFLICT (farmid) DO UPDATE
            SET isenabled = TRUE, acceptingorders = TRUE, pausedreason = NULL, updatedat = NOW();
    ELSE
        v_label := COALESCE(p_tablenumber, 'table');
    END IF;

    v_token := p_farmid || '-' || v_label || '-' || EXTRACT(EPOCH FROM NOW())::BIGINT || '-' || FLOOR(RANDOM() * 100000)::INT;

    INSERT INTO restaurantqrcodes (farmid, tableid, tablenumber, qrtoken, codetype)
    VALUES (p_farmid,
            CASE WHEN p_codetype = 'Restaurant' THEN NULL ELSE p_tableid END,
            CASE WHEN p_codetype = 'Restaurant' THEN '' ELSE p_tablenumber END,
            v_token, p_codetype)
    RETURNING restaurantqrcodes.qrcodeid INTO v_id;

    RETURN QUERY SELECT v_id, v_token;
END;
$$ LANGUAGE plpgsql;

-- List: expose the code type, and float the restaurant-wide code to the top
-- since it is the one staff print first.

CREATE FUNCTION sprestaurant_qrcode_list(p_farmid TEXT)
RETURNS TABLE (
    qrcodeid INT, farmid TEXT, tableid INT, tablenumber TEXT,
    qrtoken TEXT, isactive BOOLEAN, scanccount INT,
    lastscanndat TIMESTAMP, createdat TIMESTAMP, codetype TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT q.qrcodeid, q.farmid, q.tableid, q.tablenumber,
           q.qrtoken, q.isactive, q.scanccount, q.lastscanndat, q.createdat, q.codetype
    FROM restaurantqrcodes q WHERE q.farmid = p_farmid
    ORDER BY (q.codetype = 'Restaurant') DESC, q.tablenumber;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 3. ORDER PLACEMENT
-- =============================================================================

-- Two behaviour changes vs 220: the table is no longer occupied here (an
-- unconfirmed order must not seize a table), and the promo is no longer marked
-- used here (a rejected order must not burn a customer's promo). Both move to
-- the accept/finalize steps.

CREATE FUNCTION sprestaurant_online_order_insert(
    p_farmid TEXT, p_ordertype TEXT, p_tableid INT, p_tablenumber TEXT,
    p_customername TEXT, p_customerphone TEXT, p_covers INT, p_notes TEXT,
    p_onlinesource TEXT, p_deliveryaddress TEXT, p_deliveryfee NUMERIC,
    p_promocodeid INT, p_promocode TEXT, p_promodiscount NUMERIC,
    p_qrcodeid INT DEFAULT NULL, p_guestpaymentintent TEXT DEFAULT NULL,
    p_guestpaymentamount NUMERIC DEFAULT NULL
) RETURNS TABLE (orderid INT, ordernumber TEXT, trackingtoken TEXT) AS $$
DECLARE v_id INT; v_num TEXT; v_token TEXT;
BEGIN
    v_num := sprestaurant_order_next_number(p_farmid);
    v_token := 'TRK-' || EXTRACT(EPOCH FROM NOW())::BIGINT || '-' || FLOOR(RANDOM() * 1000000)::INT;

    -- status falls through to the 'Placed' table default = awaiting staff confirmation.
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, tableid, tablenumber,
        customername, customerphone, covers, notes,
        onlinesource, deliveryaddress, deliveryfee, promocodeid, promocode, promodiscount,
        trackingtoken, createdby, qrcodeid, guestpaymentintent, guestpaymentamount)
    VALUES (p_farmid, v_num, p_ordertype, p_tableid, p_tablenumber,
        p_customername, p_customerphone, p_covers, p_notes,
        p_onlinesource, p_deliveryaddress, p_deliveryfee, p_promocodeid, p_promocode, p_promodiscount,
        v_token, 'Online', p_qrcodeid, p_guestpaymentintent, p_guestpaymentamount)
    RETURNING restaurantorders.orderid INTO v_id;

    RETURN QUERY SELECT v_id, v_num, v_token;
END;
$$ LANGUAGE plpgsql;

-- Price-authoritative item insert. The guest's cart is a request, not a source
-- of truth: name and price are read from the menu, and an item that is not
-- currently orderable is rejected outright rather than silently priced at zero.
CREATE OR REPLACE FUNCTION sprestaurant_online_orderitem_insert(
    p_farmid TEXT, p_orderid INT, p_menuitemid INT, p_quantity INT, p_notes TEXT DEFAULT NULL
) RETURNS INT AS $$
DECLARE v_name TEXT; v_price NUMERIC; v_id INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity < 1 THEN
        RAISE EXCEPTION 'Quantity must be at least 1.';
    END IF;

    SELECT mi.name, mi.price INTO v_name, v_price
    FROM restaurantmenuitems mi
    WHERE mi.menuitemid = p_menuitemid
      AND mi.farmid = p_farmid
      AND mi.isactive = TRUE
      AND mi.isavailable = TRUE;

    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Menu item % is not available.', p_menuitemid;
    END IF;

    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname,
        quantity, unitprice, linetotal, notes)
    VALUES (p_farmid, p_orderid, p_menuitemid, v_name,
        p_quantity, v_price, v_price * p_quantity, p_notes)
    RETURNING orderitemid INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Totals, computed from what was actually inserted. The promo is re-validated
-- here against the true subtotal — the client's claimed discount is never used.
-- Tax and service charge default to 0 to match what the POS does today
-- (app/restaurant-pos/page.tsx calls recalcOrder(orderId, 0, 0)), so a guest's
-- on-screen total equals the POS total for the same basket.
CREATE OR REPLACE FUNCTION sprestaurant_online_order_finalize(
    p_orderid INT, p_farmid TEXT, p_ordertype TEXT,
    p_promocode TEXT DEFAULT NULL, p_channel TEXT DEFAULT NULL,
    p_taxrate NUMERIC DEFAULT 0, p_servicechargerate NUMERIC DEFAULT 0
) RETURNS TABLE (subtotal NUMERIC, discountamount NUMERIC, totalamount NUMERIC) AS $$
DECLARE v_sub NUMERIC; v_promo RECORD; v_fee NUMERIC; v_prep INT; v_tot NUMERIC;
BEGIN
    SELECT COALESCE(SUM(oi.linetotal), 0) INTO v_sub
    FROM restaurantorderitems oi
    WHERE oi.orderid = p_orderid AND oi.farmid = p_farmid AND oi.status != 'Cancelled';

    IF v_sub <= 0 THEN
        RAISE EXCEPTION 'Order % has no items.', p_orderid;
    END IF;

    -- Re-validate the promo against the real subtotal. Anything the client sent
    -- is discarded; an invalid code simply yields no discount.
    IF p_promocode IS NOT NULL AND LENGTH(TRIM(p_promocode)) > 0 THEN
        SELECT * INTO v_promo
        FROM sprestaurant_promocode_validate(p_farmid, p_promocode, v_sub, p_channel);

        IF v_promo.valid THEN
            -- Recorded as a normal order discount so the POS, receipts and
            -- reports all see it through the existing machinery.
            DELETE FROM restaurantorderdiscounts
            WHERE orderid = p_orderid AND farmid = p_farmid AND discountname = 'Promo: ' || UPPER(p_promocode);

            INSERT INTO restaurantorderdiscounts (farmid, orderid, discountname, discounttype, value, appliedamount)
            VALUES (p_farmid, p_orderid, 'Promo: ' || UPPER(p_promocode),
                    v_promo.discounttype, v_promo.discountvalue, v_promo.calculatediscount);

            UPDATE restaurantorders
            SET promocodeid = v_promo.promocodeid, promocode = UPPER(p_promocode),
                promodiscount = v_promo.calculatediscount
            WHERE orderid = p_orderid AND farmid = p_farmid;

            PERFORM sprestaurant_promocode_use(v_promo.promocodeid, p_farmid);
        ELSE
            UPDATE restaurantorders
            SET promocodeid = NULL, promocode = NULL, promodiscount = 0
            WHERE orderid = p_orderid AND farmid = p_farmid;
        END IF;
    END IF;

    -- Reuse the shared POS maths so online and walk-in totals can never drift.
    PERFORM sprestaurant_order_recalc(p_orderid, p_farmid, p_taxrate, p_servicechargerate);

    -- Delivery fee sits outside the taxable base, matching how it was stored in 220.
    SELECT COALESCE(o.deliveryfee, 0) INTO v_fee
    FROM restaurantorders o WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    SELECT CASE p_ordertype
             WHEN 'Delivery' THEN s.estimatedprepminsdeliv
             WHEN 'Takeaway' THEN s.estimatedprepminstake
             ELSE s.estimatedprepminsdine
           END INTO v_prep
    FROM restaurantonlineorderingsettings s WHERE s.farmid = p_farmid;

    UPDATE restaurantorders o
    SET totalamount = o.totalamount + v_fee,
        estimatedreadytime = NOW() + (COALESCE(v_prep, 15) || ' minutes')::INTERVAL,
        updatedat = NOW()
    WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    RETURN QUERY
    SELECT o.subtotal, o.discountamount, o.totalamount
    FROM restaurantorders o WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Per-table rate limit. Cheap, needs no GPS and no SMS: it simply stops one
-- table submitting a flood of orders while staff are still confirming.
CREATE OR REPLACE FUNCTION sprestaurant_online_order_qr_throttle(p_qrcodeid INT, p_farmid TEXT)
RETURNS TABLE (can_accept BOOLEAN, current_count INT, max_per_slot INT, message TEXT) AS $$
DECLARE v_max INT; v_slot INT; v_count INT;
BEGIN
    SELECT COALESCE(maxordersperqrslot, 3), COALESCE(qrslotdurationmins, 10)
    INTO v_max, v_slot
    FROM restaurantonlineorderingsettings WHERE farmid = p_farmid;

    IF v_max IS NULL OR v_max <= 0 THEN
        RETURN QUERY SELECT TRUE, 0, 0, ''::TEXT;
        RETURN;
    END IF;

    SELECT COUNT(*)::INT INTO v_count
    FROM restaurantorders o
    WHERE o.farmid = p_farmid AND o.qrcodeid = p_qrcodeid
      AND o.status != 'Cancelled'
      AND o.createdat > NOW() - (v_slot || ' minutes')::INTERVAL;

    IF v_count >= v_max THEN
        RETURN QUERY SELECT FALSE, v_count, v_max,
            'You have already sent several orders. Please wait for a member of staff.'::TEXT;
    ELSE
        RETURN QUERY SELECT TRUE, v_count, v_max, ''::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 4. STAFF CONFIRMATION
-- =============================================================================

-- One round trip for the pending tray: the item summary is aggregated here so
-- the UI never has to fan out an item fetch per order.
CREATE OR REPLACE FUNCTION sprestaurant_online_order_pending_list(p_farmid TEXT)
RETURNS TABLE (
    orderid INT, ordernumber TEXT, ordertype TEXT, onlinesource TEXT,
    tableid INT, tablenumber TEXT, customername TEXT, customerphone TEXT,
    guestpaymentintent TEXT, guestpaymentamount NUMERIC, notes TEXT, totalamount NUMERIC,
    itemcount BIGINT, itemsummary TEXT,
    createdat TIMESTAMP, waitingminutes DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.ordernumber, o.ordertype, o.onlinesource,
           o.tableid, o.tablenumber, o.customername, o.customerphone,
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

-- Accept: the order becomes real. Only now does it reach the kitchen and only
-- now does it take the table.
CREATE OR REPLACE FUNCTION sprestaurant_online_order_accept(
    p_orderid INT, p_farmid TEXT, p_confirmedby TEXT
) RETURNS TABLE (ok BOOLEAN, message TEXT) AS $$
DECLARE v_order RECORD; v_holder INT;
BEGIN
    SELECT * INTO v_order FROM restaurantorders o
    WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Order not found.'::TEXT; RETURN;
    END IF;
    IF v_order.onlinesource IS NULL THEN
        RETURN QUERY SELECT FALSE, 'This is not a guest order.'::TEXT; RETURN;
    END IF;
    -- Guard against two staff tapping Accept on the same order at once.
    IF v_order.status != 'Placed' THEN
        RETURN QUERY SELECT FALSE, ('Order is already ' || v_order.status || '.')::TEXT; RETURN;
    END IF;

    UPDATE restaurantorders
    SET status = 'Confirmed', confirmedat = NOW(), confirmedby = p_confirmedby, updatedat = NOW()
    WHERE orderid = p_orderid AND farmid = p_farmid;

    -- Take the table, but never steal it from another live order.
    IF v_order.tableid IS NOT NULL THEN
        SELECT t.currentorderid INTO v_holder FROM restauranttables t
        WHERE t.tableid = v_order.tableid AND t.farmid = p_farmid;

        IF v_holder IS NULL OR v_holder = p_orderid THEN
            UPDATE restauranttables
            SET status = 'Occupied', currentorderid = p_orderid, updatedat = NOW()
            WHERE tableid = v_order.tableid AND farmid = p_farmid;
        END IF;
    END IF;

    RETURN QUERY SELECT TRUE, 'Order confirmed.'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Reject: cancel the header AND every item, so nothing can surface in the
-- kitchen queue later. The table is left alone because accept never took it.
CREATE OR REPLACE FUNCTION sprestaurant_online_order_reject(
    p_orderid INT, p_farmid TEXT, p_reason TEXT, p_by TEXT
) RETURNS TABLE (ok BOOLEAN, message TEXT) AS $$
DECLARE v_order RECORD;
BEGIN
    SELECT * INTO v_order FROM restaurantorders o
    WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Order not found.'::TEXT; RETURN;
    END IF;
    IF v_order.status != 'Placed' THEN
        RETURN QUERY SELECT FALSE, ('Order is already ' || v_order.status || '.')::TEXT; RETURN;
    END IF;

    UPDATE restaurantorders
    SET status = 'Cancelled',
        cancelreason = COALESCE(NULLIF(TRIM(p_reason), ''), 'Rejected by staff'),
        confirmedby = p_by, completedat = NOW(), updatedat = NOW()
    WHERE orderid = p_orderid AND farmid = p_farmid;

    UPDATE restaurantorderitems
    SET status = 'Cancelled'
    WHERE orderid = p_orderid AND farmid = p_farmid;

    -- Hand the promo use back.
    IF v_order.promocodeid IS NOT NULL THEN
        UPDATE restaurantpromocodes
        SET currentuses = GREATEST(currentuses - 1, 0)
        WHERE promocodeid = v_order.promocodeid AND farmid = p_farmid;
    END IF;

    RETURN QUERY SELECT TRUE, 'Order rejected.'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 5. THE GATE — keep unconfirmed guest orders out of the kitchen
-- =============================================================================
--
-- Signature and return shape are unchanged from 218_RestaurantKDS.sql:151, so
-- this replaces in place. The only difference is the final predicate.
-- POS orders have onlinesource IS NULL and are therefore untouched: they still
-- reach the kitchen at 'Placed' the moment they are rung up.


CREATE FUNCTION sprestaurant_kds_queue(
    p_farmid TEXT, p_kdsstationid INT DEFAULT NULL, p_isexpo BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    orderitemid INT, orderid INT, ordernumber TEXT, ordertype TEXT,
    tablenumber TEXT, itemname TEXT, quantity INT, notes TEXT,
    status TEXT, seatnumber INT, kdsstation TEXT,
    senttoktchenat TIMESTAMP, prepstartedat TIMESTAMP, readyat TIMESTAMP,
    createdat TIMESTAMP, modifiers TEXT,
    elapsedminutes DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT oi.orderitemid, oi.orderid, o.ordernumber, o.ordertype,
           o.tablenumber, oi.itemname, oi.quantity, oi.notes,
           oi.status, oi.seatnumber, oi.kdsstation,
           oi.senttoktchenat, oi.prepstartedat, oi.readyat,
           oi.createdat,
           (SELECT STRING_AGG(m.modifiername || CASE WHEN m.quantity > 1 THEN ' x' || m.quantity ELSE '' END, ', ')
            FROM restaurantorderitemmodifiers m WHERE m.orderitemid = oi.orderitemid) AS modifiers,
           (EXTRACT(EPOCH FROM (NOW() - oi.createdat)) / 60.0)::DOUBLE PRECISION AS elapsedminutes
    FROM restaurantorderitems oi
    JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
    WHERE oi.farmid = p_farmid
      AND oi.status IN ('Pending', 'Preparing', 'Ready')
      AND o.status NOT IN ('Cancelled', 'Refunded', 'Completed')
      AND NOT (o.onlinesource IS NOT NULL AND o.status = 'Placed')   -- <= the gate
      AND (
          p_isexpo = TRUE
          OR p_kdsstationid IS NULL
          OR EXISTS (
              SELECT 1 FROM restaurantkdsstationitems si
              WHERE si.menuitemid = oi.menuitemid AND si.kdsstationid = p_kdsstationid AND si.farmid = oi.farmid
          )
      )
    ORDER BY oi.createdat ASC;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 6. EXPOSE ONLINE FIELDS TO STAFF READS
-- =============================================================================
-- The columns have existed since 220 but were never returned, so staff had no
-- way to tell a QR order from a walk-in.


CREATE FUNCTION sprestaurant_order_list(
    p_farmid TEXT, p_status TEXT DEFAULT NULL, p_ordertype TEXT DEFAULT NULL,
    p_fromdate TIMESTAMP DEFAULT NULL, p_todate TIMESTAMP DEFAULT NULL
)
RETURNS TABLE (
    orderid INT, farmid TEXT, ordernumber TEXT, ordertype TEXT, status TEXT,
    tableid INT, tablenumber TEXT, customerid INT, customername TEXT, customerphone TEXT,
    covers INT, subtotal NUMERIC, discountamount NUMERIC, taxamount NUMERIC,
    servicechargeamount NUMERIC, totalamount NUMERIC, paidamount NUMERIC,
    paymentstatus TEXT, notes TEXT, createdby TEXT, servedby TEXT,
    cancelreason TEXT, refundreason TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP, completedat TIMESTAMP,
    itemcount BIGINT,
    onlinesource TEXT, trackingtoken TEXT, qrcodeid INT,
    deliveryaddress TEXT, deliveryfee NUMERIC, promocode TEXT, promodiscount NUMERIC,
    estimatedreadytime TIMESTAMP, confirmedat TIMESTAMP, confirmedby TEXT,
    guestpaymentintent TEXT, guestpaymentamount NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.farmid, o.ordernumber, o.ordertype, o.status,
           o.tableid, o.tablenumber, o.customerid, o.customername, o.customerphone,
           o.covers, o.subtotal, o.discountamount, o.taxamount,
           o.servicechargeamount, o.totalamount, o.paidamount,
           o.paymentstatus, o.notes, o.createdby, o.servedby,
           o.cancelreason, o.refundreason,
           o.createdat, o.updatedat, o.completedat,
           (SELECT COUNT(*) FROM restaurantorderitems i WHERE i.orderid = o.orderid) AS itemcount,
           o.onlinesource, o.trackingtoken, o.qrcodeid,
           o.deliveryaddress, o.deliveryfee, o.promocode, o.promodiscount,
           o.estimatedreadytime, o.confirmedat, o.confirmedby,
           o.guestpaymentintent, o.guestpaymentamount
    FROM restaurantorders o
    WHERE o.farmid = p_farmid
      AND (p_status IS NULL OR o.status = p_status)
      AND (p_ordertype IS NULL OR o.ordertype = p_ordertype)
      AND (p_fromdate IS NULL OR o.createdat >= p_fromdate)
      AND (p_todate IS NULL OR o.createdat <= p_todate)
    ORDER BY o.createdat DESC;
END;
$$ LANGUAGE plpgsql;


CREATE FUNCTION sprestaurant_order_get(p_id INT, p_farmid TEXT)
RETURNS TABLE (
    orderid INT, farmid TEXT, ordernumber TEXT, ordertype TEXT, status TEXT,
    tableid INT, tablenumber TEXT, customerid INT, customername TEXT, customerphone TEXT,
    covers INT, subtotal NUMERIC, discountamount NUMERIC, taxamount NUMERIC,
    servicechargeamount NUMERIC, totalamount NUMERIC, paidamount NUMERIC,
    paymentstatus TEXT, notes TEXT, createdby TEXT, servedby TEXT,
    cancelreason TEXT, refundreason TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP, completedat TIMESTAMP,
    onlinesource TEXT, trackingtoken TEXT, qrcodeid INT,
    deliveryaddress TEXT, deliveryfee NUMERIC, promocode TEXT, promodiscount NUMERIC,
    estimatedreadytime TIMESTAMP, confirmedat TIMESTAMP, confirmedby TEXT,
    guestpaymentintent TEXT, guestpaymentamount NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.farmid, o.ordernumber, o.ordertype, o.status,
           o.tableid, o.tablenumber, o.customerid, o.customername, o.customerphone,
           o.covers, o.subtotal, o.discountamount, o.taxamount,
           o.servicechargeamount, o.totalamount, o.paidamount,
           o.paymentstatus, o.notes, o.createdby, o.servedby,
           o.cancelreason, o.refundreason,
           o.createdat, o.updatedat, o.completedat,
           o.onlinesource, o.trackingtoken, o.qrcodeid,
           o.deliveryaddress, o.deliveryfee, o.promocode, o.promodiscount,
           o.estimatedreadytime, o.confirmedat, o.confirmedby,
           o.guestpaymentintent, o.guestpaymentamount
    FROM restaurantorders o
    WHERE o.orderid = p_id AND o.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 7. PUBLIC TRACKING — let the guest see "awaiting confirmation" and rejections
-- =============================================================================


CREATE FUNCTION sprestaurant_order_track(p_token TEXT)
RETURNS TABLE (
    orderid INT, ordernumber TEXT, ordertype TEXT, status TEXT,
    tablenumber TEXT, totalamount NUMERIC, paymentstatus TEXT,
    estimatedreadytime TIMESTAMP, createdat TIMESTAMP, updatedat TIMESTAMP,
    onlinesource TEXT, cancelreason TEXT, confirmedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.ordernumber, o.ordertype, o.status,
           o.tablenumber, o.totalamount, o.paymentstatus,
           o.estimatedreadytime, o.createdat, o.updatedat,
           o.onlinesource, o.cancelreason, o.confirmedat
    FROM restaurantorders o WHERE o.trackingtoken = p_token;
END;
$$ LANGUAGE plpgsql;

COMMIT;
