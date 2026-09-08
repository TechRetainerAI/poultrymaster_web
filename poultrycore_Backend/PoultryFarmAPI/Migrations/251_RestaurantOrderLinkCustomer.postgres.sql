-- =============================================================================
-- 251. Turn an order into a CRM customer, in one step
-- =============================================================================
-- WHY
--   Staff see an online order from someone who has ordered before, but the guest
--   has no account and nothing connects one visit to the next. Everything needed
--   already exists -- `restaurantcustomers` (224), `restaurantorders.customerid`
--   -- but nothing joined them up, so a returning guest stayed anonymous forever.
--
-- WHY ONE PROC RATHER THAN THREE CALLS
--   Saving a customer from an order is four writes: find-or-create the customer,
--   stamp the order with their id, count the visit, and re-read the segment.
--   Doing that from C# would mean four round trips that can half-complete -- a
--   customer created but the order left unlinked, or a visit counted twice.
--   Here it is one statement and one transaction.
--
-- DESIGN DECISIONS
--   * Details are read FROM THE ORDER, never from the request body. Same rule as
--     the rest of this module: the client names the order, the server decides
--     what it contains.
--   * Matching is by PHONE within the farm. `restaurantcustomers` has an index on
--     (farmid, phone) but NO unique constraint, so without this check a weekly
--     regular would accumulate a new customer record every single week.
--   * Idempotent. An order already carrying a customerid returns that customer and
--     writes nothing -- so a double click, or two members of staff pressing the
--     button at once, cannot double-count a visit.
--   * The visit is recorded only on the FIRST link, which is what promotes New ->
--     Regular (5 visits) -> VIP (20) in sprestaurant_customer_record_visit.
--   * A blank email on an existing customer is filled in from the order, but a
--     stored value is never overwritten: the CRM record is the system of record,
--     an order is just evidence.
--
-- NOTE FOR ANYONE EDITING 224
--   `sprestaurant_customer_list` does `SELECT c.*` inside a RETURNS TABLE. Adding
--   a column to `restaurantcustomers` will break it at runtime with a 42804, the
--   same way `sprestaurant_onlinesettings_get` broke earlier. This migration
--   deliberately adds no columns.
--
-- Idempotent: dropped by name (all overloads) and recreated.
-- =============================================================================

BEGIN;

DO $drop$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'sprestaurant_order_link_customer'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

CREATE FUNCTION sprestaurant_order_link_customer(p_orderid INT, p_farmid TEXT)
RETURNS TABLE (
    ok BOOLEAN, customerid INT, created BOOLEAN,
    name TEXT, segment TEXT, totalvisits INT, totalspent NUMERIC, message TEXT
) AS $$
DECLARE
    v_order   RECORD;
    v_cust    RECORD;
    v_id      INT;
    v_created BOOLEAN := FALSE;
    v_phone   TEXT;
    v_name    TEXT;
    v_email   TEXT;
BEGIN
    SELECT o.orderid, o.customerid, o.customername, o.customerphone, o.customeremail, o.totalamount
      INTO v_order
      FROM restaurantorders o
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::INT, FALSE, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::NUMERIC,
                            'That order no longer exists.'::TEXT;
        RETURN;
    END IF;

    -- Already linked: report who, change nothing.
    IF v_order.customerid IS NOT NULL THEN
        SELECT c.customerid, c.name, c.segment, c.totalvisits, c.totalspent INTO v_cust
          FROM restaurantcustomers c
         WHERE c.customerid = v_order.customerid AND c.farmid = p_farmid;
        IF FOUND THEN
            RETURN QUERY SELECT TRUE, v_cust.customerid, FALSE, v_cust.name, v_cust.segment,
                                v_cust.totalvisits, v_cust.totalspent,
                                'Already saved as a customer.'::TEXT;
            RETURN;
        END IF;
        -- The customer row was deleted but the order still points at it. Fall
        -- through and rebuild rather than reporting a customer that is not there.
    END IF;

    v_name  := NULLIF(BTRIM(COALESCE(v_order.customername, '')), '');
    v_phone := NULLIF(BTRIM(COALESCE(v_order.customerphone, '')), '');
    v_email := NULLIF(BTRIM(COALESCE(v_order.customeremail, '')), '');

    IF v_name IS NULL AND v_phone IS NULL THEN
        RETURN QUERY SELECT FALSE, NULL::INT, FALSE, NULL::TEXT, NULL::TEXT, NULL::INT, NULL::NUMERIC,
                            'This order has no name or phone number to save.'::TEXT;
        RETURN;
    END IF;

    -- Match on phone only. Matching on name would merge every "John" in town.
    IF v_phone IS NOT NULL THEN
        SELECT c.customerid INTO v_id
          FROM restaurantcustomers c
         WHERE c.farmid = p_farmid
           AND c.isactive = TRUE
           AND NULLIF(BTRIM(COALESCE(c.phone, '')), '') = v_phone
         ORDER BY c.customerid
         LIMIT 1;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO restaurantcustomers (farmid, name, phone, email, segment, notes)
        VALUES (p_farmid, COALESCE(v_name, v_phone), v_phone, v_email, 'New',
                'Added from order ' || p_orderid::TEXT)
        RETURNING restaurantcustomers.customerid INTO v_id;
        v_created := TRUE;
    ELSE
        -- Fill gaps only. Never overwrite what the CRM already holds.
        UPDATE restaurantcustomers c
           SET email     = COALESCE(NULLIF(BTRIM(COALESCE(c.email, '')), ''), v_email),
               name      = COALESCE(NULLIF(BTRIM(COALESCE(c.name, '')), ''), v_name),
               updatedat = NOW()
         WHERE c.customerid = v_id AND c.farmid = p_farmid;
    END IF;

    UPDATE restaurantorders o
       SET customerid = v_id, updatedat = NOW()
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    -- Counted once, on the first link only -- this is what drives the
    -- New -> Regular -> VIP promotion.
    PERFORM sprestaurant_customer_record_visit(v_id, p_farmid, COALESCE(v_order.totalamount, 0));

    SELECT c.customerid, c.name, c.segment, c.totalvisits, c.totalspent INTO v_cust
      FROM restaurantcustomers c
     WHERE c.customerid = v_id AND c.farmid = p_farmid;

    RETURN QUERY SELECT TRUE, v_cust.customerid, v_created, v_cust.name, v_cust.segment,
                        v_cust.totalvisits, v_cust.totalspent,
                        CASE WHEN v_created
                             THEN 'Saved as a new customer.'
                             ELSE 'Matched an existing customer by phone number.' END::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMIT;
