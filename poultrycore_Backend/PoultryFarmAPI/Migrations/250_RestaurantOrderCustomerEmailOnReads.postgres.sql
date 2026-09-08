-- =============================================================================
-- 250. Expose customeremail on the staff order reads
-- =============================================================================
-- WHY
--   Migration 249 stored the guest's optional email and surfaced it in the
--   pending-confirmation tray. But `sprestaurant_order_list` and
--   `sprestaurant_order_get` were left untouched, so the moment staff ACCEPTED an
--   order the email vanished from the interface -- visible while the order was
--   waiting, invisible the second it mattered. That is the gap this closes.
--
--   Both procs are also read by the POS and the orders screen for ordinary
--   walk-in orders, where the column is simply NULL. Nothing else changes: the
--   column is appended last and every other column keeps its position.
--
-- BACKWARD COMPATIBILITY
--   `ReadOrder` in RestaurantOrderService.cs reads every optional column through
--   a by-name helper (`Str`/`Int`/`Dec`), never by position, so an API binary
--   older than this migration ignores the extra column rather than breaking.
--   Applying this before restarting the API is therefore safe.
--
-- Idempotent: functions are dropped by name (all overloads) then recreated.
-- =============================================================================

BEGIN;

DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('sprestaurant_order_list', 'sprestaurant_order_get')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

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
    guestpaymentintent TEXT, guestpaymentamount NUMERIC,
    customeremail TEXT
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
           o.guestpaymentintent, o.guestpaymentamount,
           o.customeremail
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
    guestpaymentintent TEXT, guestpaymentamount NUMERIC,
    customeremail TEXT
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
           o.guestpaymentintent, o.guestpaymentamount,
           o.customeremail
    FROM restaurantorders o
    WHERE o.orderid = p_id AND o.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

COMMIT;
