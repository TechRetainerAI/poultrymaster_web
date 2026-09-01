-- Migration 228: Restaurant Gift Cards
-- Applied: 2026-08-30

CREATE TABLE IF NOT EXISTS restaurantgiftcards (
    giftcardid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    cardnumber           TEXT NOT NULL UNIQUE,
    cardtype             TEXT DEFAULT 'Digital', -- Digital, Physical
    initialbalance       NUMERIC(12,2) NOT NULL,
    currentbalance       NUMERIC(12,2) NOT NULL,
    purchasername        TEXT,
    purchaserphone       TEXT,
    purchaseremail       TEXT,
    recipientname        TEXT,
    recipientemail       TEXT,
    recipientphone       TEXT,
    message              TEXT,
    status               TEXT DEFAULT 'Active', -- Active, Suspended, Expired, FullyRedeemed
    expirydate           DATE,
    activatedat          TIMESTAMP DEFAULT NOW(),
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantgiftcards_farm ON restaurantgiftcards(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantgiftcards_number ON restaurantgiftcards(cardnumber);

CREATE TABLE IF NOT EXISTS restaurantgiftcardtransactions (
    giftcardtxid         SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    giftcardid           INT NOT NULL REFERENCES restaurantgiftcards(giftcardid) ON DELETE CASCADE,
    transactiontype      TEXT NOT NULL, -- Purchase, Redemption, Reload, Refund
    amount               NUMERIC(12,2) NOT NULL,
    balanceafter         NUMERIC(12,2) NOT NULL,
    orderid              INT,
    notes                TEXT,
    processedby          TEXT,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantgiftcardtx_card ON restaurantgiftcardtransactions(farmid, giftcardid);

-- SP: Gift Card CRUD
CREATE OR REPLACE FUNCTION sprestaurant_giftcard_list(p_farmid TEXT, p_status TEXT DEFAULT NULL)
RETURNS TABLE (giftcardid INT, farmid TEXT, cardnumber TEXT, cardtype TEXT, initialbalance NUMERIC, currentbalance NUMERIC,
    purchasername TEXT, purchaserphone TEXT, recipientname TEXT, status TEXT, expirydate DATE, createdat TIMESTAMP
) AS $$ BEGIN RETURN QUERY SELECT g.giftcardid, g.farmid, g.cardnumber, g.cardtype, g.initialbalance, g.currentbalance,
    g.purchasername, g.purchaserphone, g.recipientname, g.status, g.expirydate, g.createdat
FROM restaurantgiftcards g WHERE g.farmid=p_farmid AND (p_status IS NULL OR g.status=p_status) ORDER BY g.createdat DESC; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_giftcard_create(
    p_farmid TEXT, p_cardtype TEXT, p_amount NUMERIC, p_purchasername TEXT, p_purchaserphone TEXT,
    p_recipientname TEXT, p_recipientemail TEXT, p_message TEXT, p_expirydate DATE
) RETURNS TABLE (giftcardid INT, cardnumber TEXT) AS $$
DECLARE v_id INT; v_num TEXT;
BEGIN
    v_num := 'GC-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT || NOW()::TEXT) FROM 1 FOR 8));
    INSERT INTO restaurantgiftcards (farmid, cardnumber, cardtype, initialbalance, currentbalance, purchasername, purchaserphone, recipientname, recipientemail, message, expirydate)
    VALUES (p_farmid, v_num, p_cardtype, p_amount, p_amount, p_purchasername, p_purchaserphone, p_recipientname, p_recipientemail, p_message, p_expirydate)
    RETURNING restaurantgiftcards.giftcardid INTO v_id;
    INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, notes) VALUES (p_farmid, v_id, 'Purchase', p_amount, p_amount, 'Initial purchase');
    RETURN QUERY SELECT v_id, v_num;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_giftcard_redeem(p_cardnumber TEXT, p_farmid TEXT, p_amount NUMERIC, p_orderid INT DEFAULT NULL, p_processedby TEXT DEFAULT NULL) RETURNS TABLE (success BOOLEAN, newbalance NUMERIC, message TEXT) AS $$
DECLARE v_card RECORD;
BEGIN
    SELECT * INTO v_card FROM restaurantgiftcards WHERE cardnumber=p_cardnumber AND farmid=p_farmid;
    IF v_card IS NULL THEN RETURN QUERY SELECT FALSE, 0::NUMERIC, 'Card not found'::TEXT; RETURN; END IF;
    IF v_card.status != 'Active' THEN RETURN QUERY SELECT FALSE, v_card.currentbalance, ('Card is ' || v_card.status)::TEXT; RETURN; END IF;
    IF v_card.currentbalance < p_amount THEN RETURN QUERY SELECT FALSE, v_card.currentbalance, 'Insufficient balance'::TEXT; RETURN; END IF;
    UPDATE restaurantgiftcards SET currentbalance=currentbalance-p_amount,
        status=CASE WHEN currentbalance-p_amount<=0 THEN 'FullyRedeemed' ELSE status END
    WHERE giftcardid=v_card.giftcardid;
    INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, orderid, processedby)
    VALUES (p_farmid, v_card.giftcardid, 'Redemption', -p_amount, v_card.currentbalance-p_amount, p_orderid, p_processedby);
    RETURN QUERY SELECT TRUE, v_card.currentbalance-p_amount, 'Redeemed successfully'::TEXT;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_giftcard_reload(p_cardnumber TEXT, p_farmid TEXT, p_amount NUMERIC, p_processedby TEXT DEFAULT NULL) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantgiftcards SET currentbalance=currentbalance+p_amount, status='Active' WHERE cardnumber=p_cardnumber AND farmid=p_farmid;
    INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, processedby)
    SELECT p_farmid, giftcardid, 'Reload', p_amount, currentbalance, p_processedby FROM restaurantgiftcards WHERE cardnumber=p_cardnumber AND farmid=p_farmid;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_giftcard_balance(p_cardnumber TEXT) RETURNS TABLE (cardnumber TEXT, currentbalance NUMERIC, status TEXT, expirydate DATE) AS $$
BEGIN RETURN QUERY SELECT g.cardnumber, g.currentbalance, g.status, g.expirydate FROM restaurantgiftcards g WHERE g.cardnumber=p_cardnumber; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_giftcard_transactions(p_giftcardid INT, p_farmid TEXT)
RETURNS TABLE (giftcardtxid INT, transactiontype TEXT, amount NUMERIC, balanceafter NUMERIC, orderid INT, notes TEXT, processedby TEXT, createdat TIMESTAMP) AS $$
BEGIN RETURN QUERY SELECT t.giftcardtxid, t.transactiontype, t.amount, t.balanceafter, t.orderid, t.notes, t.processedby, t.createdat
FROM restaurantgiftcardtransactions t WHERE t.giftcardid=p_giftcardid AND t.farmid=p_farmid ORDER BY t.createdat DESC; END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_giftcard_stats(p_farmid TEXT)
RETURNS TABLE (total_cards BIGINT, active_cards BIGINT, total_issued NUMERIC, total_outstanding NUMERIC, total_redeemed NUMERIC) AS $$
BEGIN RETURN QUERY SELECT COUNT(*), COUNT(*) FILTER (WHERE g.status='Active'),
    COALESCE(SUM(g.initialbalance),0), COALESCE(SUM(g.currentbalance) FILTER (WHERE g.status='Active'),0),
    COALESCE(SUM(g.initialbalance-g.currentbalance),0)
FROM restaurantgiftcards g WHERE g.farmid=p_farmid; END; $$ LANGUAGE plpgsql;
