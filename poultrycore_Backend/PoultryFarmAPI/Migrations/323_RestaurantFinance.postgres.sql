-- =============================================================================
-- 323  Restaurant finance: one cash ledger, shift tills, transfers, owner money,
--      loans, cash counts, daily closing with a period lock -- and the money
--      bugs that would otherwise be written straight into that ledger.
-- =============================================================================
--
-- WHY ONE LEDGER
-- Poultry and Water keep three views of money (a cash ledger, a Cash Flow report
-- built from business tables, and a P&L built from other tables) that never
-- agree. Here every document that moves money posts exactly one signed row to
-- restaurantcashtransactions IN THE SAME DATABASE CALL that writes the document:
--
--   order payment / refund, expense / expense delete, gift-card sale / reload,
--   transfer / reversal, owner contribution / draw / reversal, loan received /
--   repaid / reversed / cancelled, till float / drop, shift variance, count
--   variance, account opening balance.
--
-- Cash Flow is then just the ledger with internal moves (transfers, floats,
-- drops) and opening balances left out, so "cash at hand" on the Cash Flow page
-- equals the sum of the account balances by construction.
--
-- Every balance change goes through fnrestaurant_post, which takes the account
-- row FOR UPDATE, checks the overdraft rule and writes the row and the cached
-- balance together. Nothing else updates currentbalance.
--
-- PERIOD LOCK
-- restaurantdailyclosings. Closing a day locks it and every earlier day:
-- fnrestaurant_assert_day_open refuses any money write dated on or before the
-- last closed day. Reversals are dated today, so correcting an old entry never
-- rewrites a closed day.
--
-- BUG FIXES CARRIED HERE (they feed the ledger, so they had to land first)
--   * sprestaurant_order_recalc applies the tax and service-charge rates saved in
--     Setup when the caller passes NULL (the POS passed 0/0, so the rates were
--     dead). Service charge is dine-in only. The delivery fee is now part of the
--     total, so the online finalize no longer adds it on top.
--   * A payment can no longer exceed the balance due: the POS used to store the
--     cash tendered, change included.
--   * An order can only be Completed when it is fully paid, and cannot be
--     Cancelled while money is held against it.
--   * Refunds are a real money-out: a negative payment row plus a ledger row.
--   * sprestaurant_recipe_deduct_order: the UPDATE subtracted the WHOLE recipe's
--     quantity from every ingredient (uncorrelated subquery) and the C# ran it on
--     both Served and Completed. Now correlated and idempotent.
--   * Gift cards: a sale records how it was paid and posts cash in; redeem honours
--     the expiry date; the balance lookup is tenant-scoped; POS can take a card.
--   * P&L revenue is net of discounts and partial refunds, and includes service
--     charge and delivery fees; loan interest, fees and cash over/short count.
--
-- Column additions to existing tables: NONE. restaurantexpenses and
-- restaurantorderpayments are read with `SELECT x.*` / by ordinal elsewhere, so
-- the link from a document to its cash account lives on the ledger row
-- (sourcetype + sourceid) instead.
--
-- Re-runnable: tables are IF NOT EXISTS, every function this file defines is
-- dropped by name (all overloads) first, and the backfill skips rows it already
-- posted.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Drop every function this migration (re)defines, all overloads.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'fnrestaurant_assert_day_open', 'fnrestaurant_default_account',
            'fnrestaurant_method_account', 'fnrestaurant_resolve_account',
            'fnrestaurant_post', 'fnrestaurant_is_cash_method',
            'sprestaurant_cashaccount_list', 'sprestaurant_cashaccount_create',
            'sprestaurant_cashaccount_update', 'sprestaurant_cashaccount_ledger',
            'sprestaurant_cashshift_open', 'sprestaurant_cashshift_close',
            'sprestaurant_cashshift_list', 'sprestaurant_cashshift_zreport',
            'sprestaurant_cashtransfer_create', 'sprestaurant_cashtransfer_reverse',
            'sprestaurant_cashtransfer_list',
            'sprestaurant_ownermoney_record', 'sprestaurant_ownermoney_reverse',
            'sprestaurant_ownermoney_list',
            'sprestaurant_loan_create', 'sprestaurant_loan_repay',
            'sprestaurant_loan_payment_reverse', 'sprestaurant_loan_cancel',
            'sprestaurant_loan_list', 'sprestaurant_loan_payments',
            'sprestaurant_cashcount_post', 'sprestaurant_cashcount_reverse',
            'sprestaurant_cashcount_list',
            'sprestaurant_dailyclosing_preview', 'sprestaurant_dailyclosing_close',
            'sprestaurant_dailyclosing_reopen', 'sprestaurant_dailyclosing_list',
            'fnrestaurant_order_settle',
            'sprestaurant_order_recalc', 'sprestaurant_online_order_finalize',
            'sprestaurant_orderpayment_insert', 'sprestaurant_orderpayment_refund',
            'sprestaurant_order_update_status', 'sprestaurant_recipe_deduct_order',
            'sprestaurant_expense_insert', 'sprestaurant_expense_record',
            'sprestaurant_expense_delete',
            'sprestaurant_giftcard_create', 'sprestaurant_giftcard_reload',
            'sprestaurant_giftcard_redeem', 'sprestaurant_giftcard_balance',
            'sprestaurant_giftcard_stats',
            'sprestaurantcashflow_rows', 'sprestaurantcashflow_detail',
            'sprestaurantcashflow_summary',
            'sprestaurant_report_pnl_summary', 'sprestaurant_report_pnl_expenses',
            'sprestaurant_report_pnl_lines')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS restaurantcashaccounts (
    cashaccountid       SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    name                TEXT NOT NULL,
    -- Till = a cash drawer used in shifts. CashBox = a safe / office cash.
    accounttype         TEXT NOT NULL
        CHECK (accounttype IN ('Till','CashBox','Bank','MobileMoney','PettyCash','Other')),
    -- Which payment method lands here by default: Cash, Bank (card, transfer,
    -- cheque) or MobileMoney. At most one active account per value per farm.
    defaultfor          TEXT CHECK (defaultfor IN ('Cash','Bank','MobileMoney')),
    openingbalance      NUMERIC(14,2) NOT NULL DEFAULT 0,
    -- Cache of SUM(restaurantcashtransactions.amount). Written only by fnrestaurant_post.
    currentbalance      NUMERIC(14,2) NOT NULL DEFAULT 0,
    allownegative       BOOLEAN NOT NULL DEFAULT FALSE,
    isactive            BOOLEAN NOT NULL DEFAULT TRUE,
    notes               TEXT,
    lastcountedat       TIMESTAMP,
    lastcountedbalance  NUMERIC(14,2),
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcashaccounts_name
    ON restaurantcashaccounts (farmid, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcashaccounts_default
    ON restaurantcashaccounts (farmid, defaultfor) WHERE defaultfor IS NOT NULL AND isactive;

CREATE TABLE IF NOT EXISTS restaurantcashshifts (
    shiftid             SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    cashaccountid       INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    shiftnumber         TEXT,
    status              TEXT NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Closed')),
    openedat            TIMESTAMP NOT NULL DEFAULT NOW(),
    openedby            TEXT,
    openingfloat        NUMERIC(14,2) NOT NULL DEFAULT 0,
    floatfromaccountid  INT REFERENCES restaurantcashaccounts(cashaccountid),
    openingbalance      NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes               TEXT,
    closedat            TIMESTAMP,
    closedby            TEXT,
    expectedcash        NUMERIC(14,2),
    countedcash         NUMERIC(14,2),
    variance            NUMERIC(14,2),
    dropamount          NUMERIC(14,2) NOT NULL DEFAULT 0,
    droptoaccountid     INT REFERENCES restaurantcashaccounts(cashaccountid),
    closingbalance      NUMERIC(14,2),
    closenotes          TEXT
);
-- One open shift per till.
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcashshifts_open
    ON restaurantcashshifts (cashaccountid) WHERE status = 'Open';
CREATE INDEX IF NOT EXISTS ix_restaurantcashshifts_farm ON restaurantcashshifts (farmid, openedat);

CREATE TABLE IF NOT EXISTS restaurantcashtransactions (
    cashtxnid           SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    cashaccountid       INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    txndate             DATE NOT NULL,
    txntype             TEXT NOT NULL CHECK (txntype IN ('CashIn','CashOut')),
    -- SIGNED: positive = money into the account, negative = money out.
    amount              NUMERIC(14,2) NOT NULL CHECK (amount <> 0),
    sourcetype          TEXT NOT NULL,
    sourceid            INT,
    shiftid             INT REFERENCES restaurantcashshifts(shiftid),
    reversesid          INT REFERENCES restaurantcashtransactions(cashtxnid),
    description         TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantcashtxn_farm_date ON restaurantcashtransactions (farmid, txndate);
CREATE INDEX IF NOT EXISTS ix_restaurantcashtxn_account ON restaurantcashtransactions (cashaccountid, txndate);
CREATE INDEX IF NOT EXISTS ix_restaurantcashtxn_shift ON restaurantcashtransactions (shiftid);
-- A document posts once. This is what makes a retried request harmless.
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcashtxn_source
    ON restaurantcashtransactions (sourcetype, sourceid)
    WHERE sourceid IS NOT NULL;

CREATE TABLE IF NOT EXISTS restaurantcashtransfers (
    transferid          SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    transfernumber      TEXT,
    fromaccountid       INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    toaccountid         INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    amount              NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    transferdate        DATE NOT NULL,
    reference           TEXT,
    notes               TEXT,
    status              TEXT NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted','Reversed')),
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby          TEXT,
    reversedat          TIMESTAMP,
    reversalreason      TEXT,
    CHECK (fromaccountid <> toaccountid)
);
CREATE INDEX IF NOT EXISTS ix_restaurantcashtransfers_farm ON restaurantcashtransfers (farmid, transferdate);

CREATE TABLE IF NOT EXISTS restaurantownermoney (
    ownermoneyid        SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    entrynumber         TEXT,
    entrytype           TEXT NOT NULL CHECK (entrytype IN ('Contribution','Draw')),
    cashaccountid       INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    amount              NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    entrydate           DATE NOT NULL,
    ownername           TEXT,
    notes               TEXT,
    status              TEXT NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted','Reversed')),
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby          TEXT,
    reversedat          TIMESTAMP,
    reversalreason      TEXT
);
CREATE INDEX IF NOT EXISTS ix_restaurantownermoney_farm ON restaurantownermoney (farmid, entrydate);

CREATE TABLE IF NOT EXISTS restaurantloans (
    loanid              SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    loannumber          TEXT,
    lendername          TEXT NOT NULL,
    -- What is owed. amountreceived can be lower when the lender withholds fees.
    principal           NUMERIC(14,2) NOT NULL CHECK (principal > 0),
    amountreceived      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amountreceived >= 0),
    receivedaccountid   INT REFERENCES restaurantcashaccounts(cashaccountid),
    loandate            DATE NOT NULL,
    interestrate        NUMERIC(8,4),
    duedate             DATE,
    outstandingprincipal NUMERIC(14,2) NOT NULL,
    principalrepaid     NUMERIC(14,2) NOT NULL DEFAULT 0,
    interestpaid        NUMERIC(14,2) NOT NULL DEFAULT 0,
    feespaid            NUMERIC(14,2) NOT NULL DEFAULT 0,
    status              TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active','PaidOff','Cancelled')),
    notes               TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    cancelledby         TEXT,
    cancelledat         TIMESTAMP,
    cancelreason        TEXT,
    CHECK (amountreceived <= principal),
    CHECK (outstandingprincipal >= 0)
);
CREATE INDEX IF NOT EXISTS ix_restaurantloans_farm ON restaurantloans (farmid, loandate);

CREATE TABLE IF NOT EXISTS restaurantloanpayments (
    loanpaymentid       SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    loanid              INT NOT NULL REFERENCES restaurantloans(loanid),
    paymentdate         DATE NOT NULL,
    cashaccountid       INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    principalamount     NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (principalamount >= 0),
    interestamount      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    feeamount           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (feeamount >= 0),
    status              TEXT NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted','Reversed')),
    notes               TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby          TEXT,
    reversedat          TIMESTAMP,
    reversalreason      TEXT,
    CHECK (principalamount + interestamount + feeamount > 0)
);
CREATE INDEX IF NOT EXISTS ix_restaurantloanpayments_loan ON restaurantloanpayments (loanid);
CREATE INDEX IF NOT EXISTS ix_restaurantloanpayments_farm ON restaurantloanpayments (farmid, paymentdate);

CREATE TABLE IF NOT EXISTS restaurantcashcounts (
    countid             SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    cashaccountid       INT NOT NULL REFERENCES restaurantcashaccounts(cashaccountid),
    countdate           DATE NOT NULL,
    systembalance       NUMERIC(14,2) NOT NULL,
    countedbalance      NUMERIC(14,2) NOT NULL,
    difference          NUMERIC(14,2) NOT NULL,
    status              TEXT NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted','Reversed')),
    notes               TEXT,
    createdby           TEXT,
    createdat           TIMESTAMP NOT NULL DEFAULT NOW(),
    reversedby          TEXT,
    reversedat          TIMESTAMP,
    reversalreason      TEXT
);
CREATE INDEX IF NOT EXISTS ix_restaurantcashcounts_farm ON restaurantcashcounts (farmid, countdate);

CREATE TABLE IF NOT EXISTS restaurantdailyclosings (
    closingid           SERIAL PRIMARY KEY,
    farmid              TEXT NOT NULL,
    closingdate         DATE NOT NULL,
    status              TEXT NOT NULL DEFAULT 'Closed' CHECK (status IN ('Closed','Reopened')),
    ordercount          INT NOT NULL DEFAULT 0,
    netsales            NUMERIC(14,2) NOT NULL DEFAULT 0,
    taxcollected        NUMERIC(14,2) NOT NULL DEFAULT 0,
    moneyin             NUMERIC(14,2) NOT NULL DEFAULT 0,
    moneyout            NUMERIC(14,2) NOT NULL DEFAULT 0,
    cashvariance        NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes               TEXT,
    closedby            TEXT,
    closedat            TIMESTAMP NOT NULL DEFAULT NOW(),
    reopenedby          TEXT,
    reopenedat          TIMESTAMP,
    reopenreason        TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantdailyclosings_day
    ON restaurantdailyclosings (farmid, closingdate);

-- -----------------------------------------------------------------------------
-- 2. Core helpers
-- -----------------------------------------------------------------------------

-- Refuses a money write dated on or before the last closed day.
CREATE FUNCTION fnrestaurant_assert_day_open(p_farmid TEXT, p_date DATE)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_last DATE;
BEGIN
    IF p_date IS NULL THEN RAISE EXCEPTION 'A date is required.'; END IF;
    SELECT MAX(d.closingdate) INTO v_last
      FROM restaurantdailyclosings d
     WHERE d.farmid = p_farmid AND d.status = 'Closed';
    IF v_last IS NOT NULL AND p_date <= v_last THEN
        RAISE EXCEPTION 'The books are closed up to %. Nothing dated % can be added or changed; reopen that day in Daily Closing first.',
            to_char(v_last, 'DD Mon YYYY'), to_char(p_date, 'DD Mon YYYY');
    END IF;
END $$;

-- True for methods that move real money. GiftCard / Voucher / Complimentary do not.
CREATE FUNCTION fnrestaurant_is_cash_method(p_method TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(replace(COALESCE(p_method, 'Cash'), ' ', ''))
           NOT IN ('giftcard', 'voucher', 'complimentary', 'noncash', 'promotional');
$$;

-- The default account for Cash / Bank / MobileMoney, created on first use.
-- Auto-created accounts allow a negative balance: they receive history and
-- everyday expenses before anyone has set balances up, and refusing an expense
-- because nobody recorded an opening balance would stop the restaurant working.
CREATE FUNCTION fnrestaurant_default_account(p_farmid TEXT, p_defaultfor TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_name TEXT; v_type TEXT;
BEGIN
    SELECT a.cashaccountid INTO v_id FROM restaurantcashaccounts a
     WHERE a.farmid = p_farmid AND a.defaultfor = p_defaultfor AND a.isactive
     LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    v_name := CASE p_defaultfor WHEN 'Cash' THEN 'Main Cash Box'
                                WHEN 'Bank' THEN 'Bank Account'
                                WHEN 'MobileMoney' THEN 'Mobile Money Wallet' END;
    v_type := CASE p_defaultfor WHEN 'Cash' THEN 'CashBox'
                                WHEN 'Bank' THEN 'Bank'
                                WHEN 'MobileMoney' THEN 'MobileMoney' END;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Unknown default account kind %.', p_defaultfor; END IF;

    -- An account the owner already made with that name is adopted, not duplicated.
    SELECT a.cashaccountid INTO v_id FROM restaurantcashaccounts a
     WHERE a.farmid = p_farmid AND lower(a.name) = lower(v_name) AND a.isactive
     LIMIT 1;
    IF v_id IS NOT NULL THEN
        UPDATE restaurantcashaccounts SET defaultfor = p_defaultfor, updatedat = NOW()
         WHERE cashaccountid = v_id;
        RETURN v_id;
    END IF;

    INSERT INTO restaurantcashaccounts (farmid, name, accounttype, defaultfor, allownegative, createdby, notes)
    VALUES (p_farmid, v_name, v_type, p_defaultfor, TRUE, 'System',
            'Created automatically for ' || p_defaultfor || ' payments.')
    ON CONFLICT DO NOTHING
    RETURNING cashaccountid INTO v_id;

    IF v_id IS NULL THEN
        -- A concurrent call created it between our check and insert.
        SELECT a.cashaccountid INTO v_id FROM restaurantcashaccounts a
         WHERE a.farmid = p_farmid AND a.defaultfor = p_defaultfor AND a.isactive LIMIT 1;
    END IF;
    RETURN v_id;
END $$;

-- Payment method -> default account kind. NULL for non-cash methods.
CREATE FUNCTION fnrestaurant_method_account(p_farmid TEXT, p_method TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_m TEXT := lower(replace(COALESCE(p_method, 'Cash'), ' ', ''));
BEGIN
    IF NOT fnrestaurant_is_cash_method(p_method) THEN RETURN NULL; END IF;
    IF v_m IN ('card', 'bank', 'banktransfer', 'transfer', 'cheque', 'check', 'pos') THEN
        RETURN fnrestaurant_default_account(p_farmid, 'Bank');
    ELSIF v_m IN ('mobilemoney', 'momo', 'mobile') THEN
        RETURN fnrestaurant_default_account(p_farmid, 'MobileMoney');
    END IF;
    RETURN fnrestaurant_default_account(p_farmid, 'Cash');
END $$;

-- Where money for this method goes. An explicit account wins. Cash goes to the
-- till of the given shift, else the only open till, else the main cash box.
-- p_strict: with several tills open and none chosen, raise (POS) rather than
-- fall back to the cash box (back-office entries).
CREATE FUNCTION fnrestaurant_resolve_account(p_farmid TEXT, p_method TEXT, p_accountid INT,
                                             p_shiftid INT, p_strict BOOLEAN)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_n INT;
BEGIN
    IF p_accountid IS NOT NULL THEN RETURN p_accountid; END IF;
    IF NOT fnrestaurant_is_cash_method(p_method) THEN RETURN NULL; END IF;

    IF lower(replace(COALESCE(p_method, 'Cash'), ' ', '')) = 'cash' THEN
        IF p_shiftid IS NOT NULL THEN
            SELECT s.cashaccountid INTO v_id FROM restaurantcashshifts s
             WHERE s.shiftid = p_shiftid AND s.farmid = p_farmid AND s.status = 'Open';
            IF v_id IS NULL THEN
                RAISE EXCEPTION 'That till shift is not open any more. Refresh and pick an open till.';
            END IF;
            RETURN v_id;
        END IF;
        SELECT COUNT(*), MIN(s.cashaccountid) INTO v_n, v_id
          FROM restaurantcashshifts s WHERE s.farmid = p_farmid AND s.status = 'Open';
        IF v_n = 1 THEN RETURN v_id; END IF;
        IF v_n > 1 AND p_strict THEN
            RAISE EXCEPTION 'More than one till is open. Choose which till this cash goes into.';
        END IF;
        RETURN fnrestaurant_default_account(p_farmid, 'Cash');
    END IF;

    RETURN fnrestaurant_method_account(p_farmid, p_method);
END $$;

-- THE one place a balance changes. Locks the account, enforces the overdraft
-- rule, writes the ledger row and the cached balance together.
CREATE FUNCTION fnrestaurant_post(p_farmid TEXT, p_accountid INT, p_date DATE, p_amount NUMERIC,
                                  p_sourcetype TEXT, p_sourceid INT, p_description TEXT,
                                  p_createdby TEXT, p_reversesid INT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_acc restaurantcashaccounts%ROWTYPE; v_id INT; v_shift INT; v_amt NUMERIC;
BEGIN
    v_amt := ROUND(COALESCE(p_amount, 0), 2);
    IF v_amt = 0 THEN RETURN NULL; END IF;

    SELECT * INTO v_acc FROM restaurantcashaccounts
     WHERE cashaccountid = p_accountid AND farmid = p_farmid
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cash account % does not belong to this restaurant.', p_accountid;
    END IF;
    IF NOT v_acc.isactive THEN
        RAISE EXCEPTION '"%" is inactive. Reactivate it or choose another account.', v_acc.name;
    END IF;
    IF v_amt < 0 AND NOT v_acc.allownegative AND v_acc.currentbalance + v_amt < 0 THEN
        RAISE EXCEPTION '"%" only holds %; this needs %. Move money into it first or choose another account.',
            v_acc.name, to_char(v_acc.currentbalance, 'FM999,999,999,990.00'),
            to_char(-v_amt, 'FM999,999,999,990.00');
    END IF;

    IF v_acc.accounttype = 'Till' THEN
        SELECT s.shiftid INTO v_shift FROM restaurantcashshifts s
         WHERE s.cashaccountid = p_accountid AND s.status = 'Open' LIMIT 1;
    END IF;

    INSERT INTO restaurantcashtransactions
        (farmid, cashaccountid, txndate, txntype, amount, sourcetype, sourceid,
         shiftid, reversesid, description, createdby)
    VALUES
        (p_farmid, p_accountid, p_date, CASE WHEN v_amt > 0 THEN 'CashIn' ELSE 'CashOut' END,
         v_amt, p_sourcetype, p_sourceid, v_shift, p_reversesid, p_description, p_createdby)
    RETURNING cashtxnid INTO v_id;

    UPDATE restaurantcashaccounts
       SET currentbalance = currentbalance + v_amt, updatedat = NOW()
     WHERE cashaccountid = p_accountid;

    RETURN v_id;
END $$;

-- -----------------------------------------------------------------------------
-- 3. Cash accounts
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_cashaccount_create(
    p_farmid TEXT, p_name TEXT, p_accounttype TEXT, p_openingbalance NUMERIC DEFAULT 0,
    p_allownegative BOOLEAN DEFAULT FALSE, p_defaultfor TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_open NUMERIC := ROUND(COALESCE(p_openingbalance, 0), 2);
BEGIN
    IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'Account name is required.'; END IF;
    IF p_accounttype NOT IN ('Till','CashBox','Bank','MobileMoney','PettyCash','Other') THEN
        RAISE EXCEPTION 'Unknown account type "%".', p_accounttype;
    END IF;
    IF v_open < 0 THEN RAISE EXCEPTION 'Opening balance cannot be negative.'; END IF;
    IF p_defaultfor IS NOT NULL AND p_defaultfor NOT IN ('Cash','Bank','MobileMoney') THEN
        RAISE EXCEPTION 'Default-for must be Cash, Bank or MobileMoney.';
    END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a
                WHERE a.farmid = p_farmid AND lower(a.name) = lower(btrim(p_name))) THEN
        RAISE EXCEPTION 'An account called "%" already exists.', btrim(p_name);
    END IF;
    IF v_open > 0 THEN PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE); END IF;

    IF p_defaultfor IS NOT NULL THEN
        UPDATE restaurantcashaccounts SET defaultfor = NULL, updatedat = NOW()
         WHERE farmid = p_farmid AND defaultfor = p_defaultfor;
    END IF;

    INSERT INTO restaurantcashaccounts (farmid, name, accounttype, defaultfor, openingbalance,
                                        allownegative, notes, createdby)
    VALUES (p_farmid, btrim(p_name), p_accounttype, p_defaultfor, v_open,
            COALESCE(p_allownegative, FALSE), p_notes, p_createdby)
    RETURNING cashaccountid INTO v_id;

    IF v_open > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_id, CURRENT_DATE, v_open, 'OpeningBalance', v_id,
                                  'Opening balance', p_createdby);
    END IF;
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_cashaccount_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_accounttype TEXT, p_allownegative BOOLEAN,
    p_isactive BOOLEAN, p_defaultfor TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_acc restaurantcashaccounts%ROWTYPE; v_open BOOLEAN;
BEGIN
    SELECT * INTO v_acc FROM restaurantcashaccounts
     WHERE cashaccountid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash account not found.'; END IF;
    IF btrim(COALESCE(p_name, '')) = '' THEN RAISE EXCEPTION 'Account name is required.'; END IF;
    IF p_accounttype NOT IN ('Till','CashBox','Bank','MobileMoney','PettyCash','Other') THEN
        RAISE EXCEPTION 'Unknown account type "%".', p_accounttype;
    END IF;
    IF p_defaultfor IS NOT NULL AND p_defaultfor NOT IN ('Cash','Bank','MobileMoney') THEN
        RAISE EXCEPTION 'Default-for must be Cash, Bank or MobileMoney.';
    END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a
                WHERE a.farmid = p_farmid AND lower(a.name) = lower(btrim(p_name))
                  AND a.cashaccountid <> p_id) THEN
        RAISE EXCEPTION 'An account called "%" already exists.', btrim(p_name);
    END IF;

    v_open := EXISTS (SELECT 1 FROM restaurantcashshifts s
                       WHERE s.cashaccountid = p_id AND s.status = 'Open');
    IF v_open AND (p_accounttype <> 'Till' OR NOT p_isactive) THEN
        RAISE EXCEPTION '"%" has an open shift. Close the shift first.', v_acc.name;
    END IF;
    IF NOT p_isactive AND v_acc.isactive AND v_acc.currentbalance <> 0 THEN
        RAISE EXCEPTION '"%" still holds %. Transfer it out before deactivating the account.',
            v_acc.name, to_char(v_acc.currentbalance, 'FM999,999,999,990.00');
    END IF;
    IF NOT COALESCE(p_allownegative, FALSE) AND v_acc.currentbalance < 0 THEN
        RAISE EXCEPTION '"%" is already below zero, so it has to keep allowing a negative balance until money is moved in.', v_acc.name;
    END IF;

    IF p_defaultfor IS NOT NULL AND p_isactive THEN
        UPDATE restaurantcashaccounts SET defaultfor = NULL, updatedat = NOW()
         WHERE farmid = p_farmid AND defaultfor = p_defaultfor AND cashaccountid <> p_id;
    END IF;

    UPDATE restaurantcashaccounts
       SET name = btrim(p_name), accounttype = p_accounttype,
           allownegative = COALESCE(p_allownegative, FALSE), isactive = COALESCE(p_isactive, TRUE),
           defaultfor = CASE WHEN COALESCE(p_isactive, TRUE) THEN p_defaultfor ELSE NULL END,
           notes = p_notes, updatedat = NOW()
     WHERE cashaccountid = p_id;
END $$;

-- Lists accounts, creating the three defaults on first use so every screen that
-- posts money has somewhere to post it.
CREATE FUNCTION sprestaurant_cashaccount_list(p_farmid TEXT)
RETURNS TABLE(cashaccountid INT, name TEXT, accounttype TEXT, defaultfor TEXT,
              openingbalance NUMERIC, currentbalance NUMERIC, ledgerbalance NUMERIC,
              allownegative BOOLEAN, isactive BOOLEAN, notes TEXT,
              lastcountedat TIMESTAMP, lastcountedbalance NUMERIC,
              openshiftid INT, openshiftnumber TEXT, openshiftopenedby TEXT,
              openshiftopenedat TIMESTAMP, createdat TIMESTAMP)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
BEGIN
    PERFORM fnrestaurant_default_account(p_farmid, 'Cash');
    PERFORM fnrestaurant_default_account(p_farmid, 'Bank');
    PERFORM fnrestaurant_default_account(p_farmid, 'MobileMoney');

    RETURN QUERY
    SELECT a.cashaccountid, a.name, a.accounttype, a.defaultfor, a.openingbalance,
           a.currentbalance,
           COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                      WHERE t.cashaccountid = a.cashaccountid), 0)::NUMERIC,
           a.allownegative, a.isactive, a.notes, a.lastcountedat, a.lastcountedbalance,
           s.shiftid, s.shiftnumber, s.openedby, s.openedat, a.createdat
      FROM restaurantcashaccounts a
      LEFT JOIN restaurantcashshifts s ON s.cashaccountid = a.cashaccountid AND s.status = 'Open'
     WHERE a.farmid = p_farmid
     ORDER BY a.isactive DESC,
              CASE a.accounttype WHEN 'Till' THEN 0 WHEN 'CashBox' THEN 1 WHEN 'PettyCash' THEN 2
                                 WHEN 'MobileMoney' THEN 3 WHEN 'Bank' THEN 4 ELSE 5 END,
              a.name;
END $$;

CREATE FUNCTION sprestaurant_cashaccount_ledger(p_farmid TEXT, p_accountid INT,
                                                p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(cashtxnid INT, txndate DATE, txntype TEXT, sourcetype TEXT, sourceid INT,
              amount NUMERIC, runningbalance NUMERIC, description TEXT, shiftid INT,
              reversesid INT, createdby TEXT, createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT x.cashtxnid, x.txndate, x.txntype, x.sourcetype, x.sourceid, x.amount,
           x.running, x.description, x.shiftid, x.reversesid, x.createdby, x.createdat
    FROM (
        SELECT t.*, SUM(t.amount) OVER (ORDER BY t.txndate, t.cashtxnid) AS running
          FROM restaurantcashtransactions t
         WHERE t.cashaccountid = p_accountid AND t.farmid = p_farmid
    ) x
    WHERE (p_from IS NULL OR x.txndate >= p_from)
      AND (p_to IS NULL OR x.txndate <= p_to)
    ORDER BY x.txndate DESC, x.cashtxnid DESC;
$$;

-- -----------------------------------------------------------------------------
-- 4. Till shifts
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_cashshift_open(p_farmid TEXT, p_tillaccountid INT,
                                            p_openingfloat NUMERIC DEFAULT 0,
                                            p_floatfromaccountid INT DEFAULT NULL,
                                            p_openedby TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_till restaurantcashaccounts%ROWTYPE; v_id INT; v_float NUMERIC := ROUND(COALESCE(p_openingfloat, 0), 2);
        v_num TEXT;
BEGIN
    SELECT * INTO v_till FROM restaurantcashaccounts
     WHERE cashaccountid = p_tillaccountid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Till not found.'; END IF;
    IF v_till.accounttype <> 'Till' THEN
        RAISE EXCEPTION '"%" is not a till. Shifts run on accounts of type Till.', v_till.name;
    END IF;
    IF NOT v_till.isactive THEN RAISE EXCEPTION '"%" is inactive.', v_till.name; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashshifts s WHERE s.cashaccountid = p_tillaccountid AND s.status = 'Open') THEN
        RAISE EXCEPTION '"%" already has an open shift.', v_till.name;
    END IF;
    IF v_float < 0 THEN RAISE EXCEPTION 'The float cannot be negative.'; END IF;
    IF v_float > 0 AND p_floatfromaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the account the float is taken from.';
    END IF;
    IF p_floatfromaccountid = p_tillaccountid THEN
        RAISE EXCEPTION 'The float must come from a different account than the till.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    INSERT INTO restaurantcashshifts (farmid, cashaccountid, status, openedby, openingfloat,
                                      floatfromaccountid, notes)
    VALUES (p_farmid, p_tillaccountid, 'Open', p_openedby, v_float,
            CASE WHEN v_float > 0 THEN p_floatfromaccountid END, p_notes)
    RETURNING shiftid INTO v_id;

    v_num := 'SH-' || to_char(NOW(), 'YYYYMMDD') || '-' || v_id;
    UPDATE restaurantcashshifts SET shiftnumber = v_num WHERE shiftid = v_id;

    IF v_float > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, p_floatfromaccountid, CURRENT_DATE, -v_float,
                                  'ShiftFloatOut', v_id, 'Float for ' || v_till.name || ' (' || v_num || ')', p_openedby);
        PERFORM fnrestaurant_post(p_farmid, p_tillaccountid, CURRENT_DATE, v_float,
                                  'ShiftFloatIn', v_id, 'Opening float (' || v_num || ')', p_openedby);
    END IF;

    UPDATE restaurantcashshifts s
       SET openingbalance = (SELECT a.currentbalance FROM restaurantcashaccounts a WHERE a.cashaccountid = p_tillaccountid)
     WHERE s.shiftid = v_id;
    RETURN v_id;
END $$;

-- Cash-up. Expected = the till's ledger balance; the difference is posted as
-- ShiftVariance so the till ends at what was counted. Optional drop moves the
-- takings to a safe or bank and leaves the rest in the drawer.
CREATE FUNCTION sprestaurant_cashshift_close(p_farmid TEXT, p_shiftid INT, p_countedcash NUMERIC,
                                             p_dropamount NUMERIC DEFAULT 0, p_droptoaccountid INT DEFAULT NULL,
                                             p_closedby TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL)
RETURNS TABLE(expectedcash NUMERIC, countedcash NUMERIC, variance NUMERIC,
              dropamount NUMERIC, closingbalance NUMERIC)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE v_shift restaurantcashshifts%ROWTYPE; v_till restaurantcashaccounts%ROWTYPE;
        v_counted NUMERIC := ROUND(COALESCE(p_countedcash, -1), 2);
        v_drop NUMERIC := ROUND(COALESCE(p_dropamount, 0), 2);
        v_expected NUMERIC; v_var NUMERIC; v_closing NUMERIC;
BEGIN
    SELECT * INTO v_shift FROM restaurantcashshifts
     WHERE shiftid = p_shiftid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Shift not found.'; END IF;
    IF v_shift.status <> 'Open' THEN RAISE EXCEPTION 'Shift % is already closed.', v_shift.shiftnumber; END IF;
    IF v_counted < 0 THEN RAISE EXCEPTION 'Enter the cash counted in the drawer.'; END IF;
    IF v_drop < 0 THEN RAISE EXCEPTION 'The drop cannot be negative.'; END IF;
    IF v_drop > v_counted THEN RAISE EXCEPTION 'You cannot drop more than the cash counted.'; END IF;
    IF v_drop > 0 AND p_droptoaccountid IS NULL THEN RAISE EXCEPTION 'Choose where the dropped cash goes.'; END IF;
    IF p_droptoaccountid = v_shift.cashaccountid THEN RAISE EXCEPTION 'The drop must go to another account.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    SELECT * INTO v_till FROM restaurantcashaccounts WHERE cashaccountid = v_shift.cashaccountid FOR UPDATE;
    v_expected := v_till.currentbalance;
    v_var := v_counted - v_expected;

    IF v_var <> 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_shift.cashaccountid, CURRENT_DATE, v_var, 'ShiftVariance',
                                  p_shiftid,
                                  CASE WHEN v_var > 0 THEN 'Cash over at close of ' ELSE 'Cash short at close of ' END
                                  || v_shift.shiftnumber, p_closedby);
    END IF;
    IF v_drop > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_shift.cashaccountid, CURRENT_DATE, -v_drop, 'ShiftDropOut',
                                  p_shiftid, 'Takings dropped at close of ' || v_shift.shiftnumber, p_closedby);
        PERFORM fnrestaurant_post(p_farmid, p_droptoaccountid, CURRENT_DATE, v_drop, 'ShiftDropIn',
                                  p_shiftid, 'Takings from ' || v_till.name || ' (' || v_shift.shiftnumber || ')', p_closedby);
    END IF;

    SELECT a.currentbalance INTO v_closing FROM restaurantcashaccounts a WHERE a.cashaccountid = v_shift.cashaccountid;

    UPDATE restaurantcashshifts
       SET status = 'Closed', closedat = NOW(), closedby = p_closedby,
           expectedcash = v_expected, countedcash = v_counted, variance = v_var,
           dropamount = v_drop, droptoaccountid = CASE WHEN v_drop > 0 THEN p_droptoaccountid END,
           closingbalance = v_closing, closenotes = p_notes
     WHERE shiftid = p_shiftid;

    RETURN QUERY SELECT v_expected, v_counted, v_var, v_drop, v_closing;
END $$;

CREATE FUNCTION sprestaurant_cashshift_list(p_farmid TEXT, p_status TEXT DEFAULT NULL,
                                            p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(shiftid INT, shiftnumber TEXT, cashaccountid INT, tillname TEXT, status TEXT,
              openedat TIMESTAMP, openedby TEXT, openingfloat NUMERIC, openingbalance NUMERIC,
              closedat TIMESTAMP, closedby TEXT, expectedcash NUMERIC, countedcash NUMERIC,
              variance NUMERIC, dropamount NUMERIC, closingbalance NUMERIC,
              currentbalance NUMERIC, cashsales NUMERIC, notes TEXT, closenotes TEXT)
LANGUAGE sql STABLE AS $$
    SELECT s.shiftid, s.shiftnumber, s.cashaccountid, a.name, s.status, s.openedat, s.openedby,
           s.openingfloat, s.openingbalance, s.closedat, s.closedby, s.expectedcash, s.countedcash,
           s.variance, s.dropamount, s.closingbalance, a.currentbalance,
           COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                      WHERE t.shiftid = s.shiftid AND t.sourcetype IN ('OrderPayment','OrderRefund')), 0),
           s.notes, s.closenotes
      FROM restaurantcashshifts s
      JOIN restaurantcashaccounts a ON a.cashaccountid = s.cashaccountid
     WHERE s.farmid = p_farmid
       AND (p_status IS NULL OR s.status = p_status)
       AND (p_from IS NULL OR s.openedat::DATE >= p_from)
       AND (p_to IS NULL OR s.openedat::DATE <= p_to)
     ORDER BY (s.status = 'Open') DESC, s.openedat DESC;
$$;

-- Z-report: every movement through the drawer during the shift, grouped, plus
-- the takings of all methods taken while the shift was open (informational).
CREATE FUNCTION sprestaurant_cashshift_zreport(p_farmid TEXT, p_shiftid INT)
RETURNS TABLE(section TEXT, label TEXT, txncount BIGINT, amount NUMERIC, sortorder INT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_shift restaurantcashshifts%ROWTYPE; v_end TIMESTAMP;
BEGIN
    SELECT * INTO v_shift FROM restaurantcashshifts WHERE shiftid = p_shiftid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Shift not found.'; END IF;
    v_end := COALESCE(v_shift.closedat, NOW());

    RETURN QUERY
    SELECT 'Drawer'::TEXT,
           CASE t.sourcetype
               WHEN 'ShiftFloatIn'  THEN 'Opening float'
               WHEN 'OrderPayment'  THEN 'Cash sales (incl. tips)'
               WHEN 'OrderRefund'   THEN 'Cash refunds'
               WHEN 'Expense'       THEN 'Expenses paid from till'
               WHEN 'ExpenseReversal' THEN 'Expenses reversed'
               WHEN 'GiftCardSale'  THEN 'Gift card sales'
               WHEN 'GiftCardReload' THEN 'Gift card reloads'
               WHEN 'TransferIn'    THEN 'Transfers in'
               WHEN 'TransferOut'   THEN 'Transfers out'
               WHEN 'ShiftVariance' THEN CASE WHEN SUM(t.amount) >= 0 THEN 'Cash over' ELSE 'Cash short' END
               WHEN 'ShiftDropOut'  THEN 'Dropped to safe / bank'
               ELSE t.sourcetype END,
           COUNT(*), SUM(t.amount),
           CASE t.sourcetype WHEN 'ShiftFloatIn' THEN 1 WHEN 'OrderPayment' THEN 2 WHEN 'OrderRefund' THEN 3
                             WHEN 'GiftCardSale' THEN 4 WHEN 'GiftCardReload' THEN 5 WHEN 'Expense' THEN 6
                             WHEN 'ExpenseReversal' THEN 7 WHEN 'TransferIn' THEN 8 WHEN 'TransferOut' THEN 9
                             WHEN 'ShiftVariance' THEN 10 WHEN 'ShiftDropOut' THEN 11 ELSE 12 END
      FROM restaurantcashtransactions t
     WHERE t.shiftid = p_shiftid
     GROUP BY t.sourcetype;

    -- Takings by method during the shift window, all tills and methods.
    RETURN QUERY
    SELECT 'Takings'::TEXT, p.paymentmethod, COUNT(*),
           SUM(p.amount + COALESCE(p.tipamount, 0)), 20
      FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed'
       AND p.createdat >= v_shift.openedat AND p.createdat <= v_end
     GROUP BY p.paymentmethod;
END $$;

-- -----------------------------------------------------------------------------
-- 5. Transfers
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_cashtransfer_create(p_farmid TEXT, p_fromaccountid INT, p_toaccountid INT,
                                                 p_amount NUMERIC, p_transferdate DATE DEFAULT NULL,
                                                 p_reference TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL,
                                                 p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_date DATE := COALESCE(p_transferdate, CURRENT_DATE); v_num TEXT;
        v_from TEXT; v_to TEXT;
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Transfer amount must be more than zero.'; END IF;
    IF p_fromaccountid IS NULL OR p_toaccountid IS NULL THEN RAISE EXCEPTION 'Choose both accounts.'; END IF;
    IF p_fromaccountid = p_toaccountid THEN RAISE EXCEPTION 'Choose two different accounts.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A transfer cannot be dated in the future.'; END IF;
    SELECT a.name INTO v_from FROM restaurantcashaccounts a WHERE a.cashaccountid = p_fromaccountid AND a.farmid = p_farmid;
    SELECT a.name INTO v_to   FROM restaurantcashaccounts a WHERE a.cashaccountid = p_toaccountid AND a.farmid = p_farmid;
    IF v_from IS NULL OR v_to IS NULL THEN RAISE EXCEPTION 'Both accounts must belong to this restaurant.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    INSERT INTO restaurantcashtransfers (farmid, fromaccountid, toaccountid, amount, transferdate,
                                         reference, notes, createdby)
    VALUES (p_farmid, p_fromaccountid, p_toaccountid, v_amt, v_date, p_reference, p_notes, p_createdby)
    RETURNING transferid INTO v_id;
    v_num := 'TRF-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::TEXT, 5, '0');
    UPDATE restaurantcashtransfers SET transfernumber = v_num WHERE transferid = v_id;

    PERFORM fnrestaurant_post(p_farmid, p_fromaccountid, v_date, -v_amt, 'TransferOut', v_id,
                              v_num || ' to ' || v_to, p_createdby);
    PERFORM fnrestaurant_post(p_farmid, p_toaccountid, v_date, v_amt, 'TransferIn', v_id,
                              v_num || ' from ' || v_from, p_createdby);
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_cashtransfer_reverse(p_farmid TEXT, p_transferid INT, p_reason TEXT,
                                                  p_reversedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_t restaurantcashtransfers%ROWTYPE;
BEGIN
    SELECT * INTO v_t FROM restaurantcashtransfers WHERE transferid = p_transferid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
    IF v_t.status <> 'Posted' THEN RAISE EXCEPTION 'Transfer % is already reversed.', v_t.transfernumber; END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for the reversal.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    -- Take the money back out of the destination first, so its overdraft check runs.
    PERFORM fnrestaurant_post(p_farmid, v_t.toaccountid, CURRENT_DATE, -v_t.amount, 'TransferReversalOut',
                              p_transferid, 'Reversal of ' || v_t.transfernumber || ': ' || btrim(p_reason), p_reversedby);
    PERFORM fnrestaurant_post(p_farmid, v_t.fromaccountid, CURRENT_DATE, v_t.amount, 'TransferReversalIn',
                              p_transferid, 'Reversal of ' || v_t.transfernumber || ': ' || btrim(p_reason), p_reversedby);

    UPDATE restaurantcashtransfers
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE transferid = p_transferid;
END $$;

CREATE FUNCTION sprestaurant_cashtransfer_list(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(transferid INT, transfernumber TEXT, fromaccountid INT, fromaccountname TEXT,
              toaccountid INT, toaccountname TEXT, amount NUMERIC, transferdate DATE,
              reference TEXT, notes TEXT, status TEXT, createdby TEXT, createdat TIMESTAMP,
              reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT t.transferid, t.transfernumber, t.fromaccountid, fa.name, t.toaccountid, ta.name,
           t.amount, t.transferdate, t.reference, t.notes, t.status, t.createdby, t.createdat,
           t.reversedby, t.reversedat, t.reversalreason
      FROM restaurantcashtransfers t
      JOIN restaurantcashaccounts fa ON fa.cashaccountid = t.fromaccountid
      JOIN restaurantcashaccounts ta ON ta.cashaccountid = t.toaccountid
     WHERE t.farmid = p_farmid
       AND (p_from IS NULL OR t.transferdate >= p_from)
       AND (p_to IS NULL OR t.transferdate <= p_to)
     ORDER BY t.transferdate DESC, t.transferid DESC;
$$;

-- -----------------------------------------------------------------------------
-- 6. Owner money
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_ownermoney_record(p_farmid TEXT, p_entrytype TEXT, p_cashaccountid INT,
                                               p_amount NUMERIC, p_entrydate DATE DEFAULT NULL,
                                               p_ownername TEXT DEFAULT NULL, p_notes TEXT DEFAULT NULL,
                                               p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_date DATE := COALESCE(p_entrydate, CURRENT_DATE); v_num TEXT;
BEGIN
    IF p_entrytype NOT IN ('Contribution','Draw') THEN
        RAISE EXCEPTION 'Owner money must be a Contribution or a Draw.';
    END IF;
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Amount must be more than zero.'; END IF;
    IF p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Choose the account the money moves through.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'Owner money cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    INSERT INTO restaurantownermoney (farmid, entrytype, cashaccountid, amount, entrydate, ownername, notes, createdby)
    VALUES (p_farmid, p_entrytype, p_cashaccountid, v_amt, v_date, NULLIF(btrim(p_ownername), ''), p_notes, p_createdby)
    RETURNING ownermoneyid INTO v_id;
    v_num := CASE p_entrytype WHEN 'Contribution' THEN 'OWC-' ELSE 'OWD-' END
             || to_char(v_date, 'YYYY') || '-' || lpad(v_id::TEXT, 5, '0');
    UPDATE restaurantownermoney SET entrynumber = v_num WHERE ownermoneyid = v_id;

    PERFORM fnrestaurant_post(p_farmid, p_cashaccountid, v_date,
                              CASE p_entrytype WHEN 'Contribution' THEN v_amt ELSE -v_amt END,
                              CASE p_entrytype WHEN 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END,
                              v_id,
                              v_num || CASE p_entrytype WHEN 'Contribution' THEN ' owner contribution' ELSE ' owner drawing' END
                              || COALESCE(' — ' || NULLIF(btrim(p_ownername), ''), ''),
                              p_createdby);
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_ownermoney_reverse(p_farmid TEXT, p_id INT, p_reason TEXT, p_reversedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_o restaurantownermoney%ROWTYPE;
BEGIN
    SELECT * INTO v_o FROM restaurantownermoney WHERE ownermoneyid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Owner money entry not found.'; END IF;
    IF v_o.status <> 'Posted' THEN RAISE EXCEPTION '% is already reversed.', v_o.entrynumber; END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for the reversal.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    PERFORM fnrestaurant_post(p_farmid, v_o.cashaccountid, CURRENT_DATE,
                              CASE v_o.entrytype WHEN 'Contribution' THEN -v_o.amount ELSE v_o.amount END,
                              CASE v_o.entrytype WHEN 'Contribution' THEN 'OwnerContributionReversal' ELSE 'OwnerDrawReversal' END,
                              p_id, 'Reversal of ' || v_o.entrynumber || ': ' || btrim(p_reason), p_reversedby);

    UPDATE restaurantownermoney
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE ownermoneyid = p_id;
END $$;

CREATE FUNCTION sprestaurant_ownermoney_list(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(ownermoneyid INT, entrynumber TEXT, entrytype TEXT, cashaccountid INT, accountname TEXT,
              amount NUMERIC, entrydate DATE, ownername TEXT, notes TEXT, status TEXT,
              createdby TEXT, createdat TIMESTAMP, reversedby TEXT, reversedat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT o.ownermoneyid, o.entrynumber, o.entrytype, o.cashaccountid, a.name, o.amount, o.entrydate,
           o.ownername, o.notes, o.status, o.createdby, o.createdat, o.reversedby, o.reversedat, o.reversalreason
      FROM restaurantownermoney o
      JOIN restaurantcashaccounts a ON a.cashaccountid = o.cashaccountid
     WHERE o.farmid = p_farmid
       AND (p_from IS NULL OR o.entrydate >= p_from)
       AND (p_to IS NULL OR o.entrydate <= p_to)
     ORDER BY o.entrydate DESC, o.ownermoneyid DESC;
$$;

-- -----------------------------------------------------------------------------
-- 7. Loans (money the restaurant borrowed)
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_loan_create(p_farmid TEXT, p_lendername TEXT, p_principal NUMERIC,
                                         p_amountreceived NUMERIC, p_receivedaccountid INT,
                                         p_loandate DATE DEFAULT NULL, p_interestrate NUMERIC DEFAULT NULL,
                                         p_duedate DATE DEFAULT NULL, p_notes TEXT DEFAULT NULL,
                                         p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_p NUMERIC := ROUND(COALESCE(p_principal, 0), 2);
        v_r NUMERIC := ROUND(COALESCE(p_amountreceived, 0), 2);
        v_date DATE := COALESCE(p_loandate, CURRENT_DATE); v_num TEXT;
BEGIN
    IF btrim(COALESCE(p_lendername, '')) = '' THEN RAISE EXCEPTION 'Lender name is required.'; END IF;
    IF v_p <= 0 THEN RAISE EXCEPTION 'Loan amount must be more than zero.'; END IF;
    IF v_r < 0 OR v_r > v_p THEN RAISE EXCEPTION 'Amount received must be between zero and the loan amount.'; END IF;
    IF v_r > 0 AND p_receivedaccountid IS NULL THEN RAISE EXCEPTION 'Choose the account the loan money went into.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A loan cannot be dated in the future.'; END IF;
    IF p_duedate IS NOT NULL AND p_duedate < v_date THEN RAISE EXCEPTION 'The due date is before the loan date.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    INSERT INTO restaurantloans (farmid, lendername, principal, amountreceived, receivedaccountid, loandate,
                                 interestrate, duedate, outstandingprincipal, notes, createdby)
    VALUES (p_farmid, btrim(p_lendername), v_p, v_r, CASE WHEN v_r > 0 THEN p_receivedaccountid END, v_date,
            p_interestrate, p_duedate, v_p, p_notes, p_createdby)
    RETURNING loanid INTO v_id;
    v_num := 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::TEXT, 5, '0');
    UPDATE restaurantloans SET loannumber = v_num WHERE loanid = v_id;

    IF v_r > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, p_receivedaccountid, v_date, v_r, 'LoanReceived', v_id,
                                  v_num || ' from ' || btrim(p_lendername), p_createdby);
    END IF;
    RETURN v_id;
END $$;

-- Principal reduces what is owed; interest and fees are costs (they reach the
-- P&L from this table). One ledger row for the whole payment.
CREATE FUNCTION sprestaurant_loan_repay(p_farmid TEXT, p_loanid INT, p_cashaccountid INT,
                                        p_principal NUMERIC DEFAULT 0, p_interest NUMERIC DEFAULT 0,
                                        p_fees NUMERIC DEFAULT 0, p_paymentdate DATE DEFAULT NULL,
                                        p_notes TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_l restaurantloans%ROWTYPE; v_id INT;
        v_pr NUMERIC := ROUND(COALESCE(p_principal, 0), 2);
        v_in NUMERIC := ROUND(COALESCE(p_interest, 0), 2);
        v_fe NUMERIC := ROUND(COALESCE(p_fees, 0), 2);
        v_date DATE := COALESCE(p_paymentdate, CURRENT_DATE);
BEGIN
    SELECT * INTO v_l FROM restaurantloans WHERE loanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v_l.status <> 'Active' THEN RAISE EXCEPTION 'Loan % is %; it cannot take repayments.', v_l.loannumber, lower(v_l.status); END IF;
    IF v_pr < 0 OR v_in < 0 OR v_fe < 0 THEN RAISE EXCEPTION 'Amounts cannot be negative.'; END IF;
    IF v_pr + v_in + v_fe <= 0 THEN RAISE EXCEPTION 'Enter the principal, interest or fees being paid.'; END IF;
    IF v_pr > v_l.outstandingprincipal THEN
        RAISE EXCEPTION 'Only % of principal is outstanding on %.', to_char(v_l.outstandingprincipal, 'FM999,999,999,990.00'), v_l.loannumber;
    END IF;
    IF p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Choose the account the repayment is paid from.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A repayment cannot be dated in the future.'; END IF;
    IF v_date < v_l.loandate THEN RAISE EXCEPTION 'A repayment cannot be dated before the loan.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    INSERT INTO restaurantloanpayments (farmid, loanid, paymentdate, cashaccountid, principalamount,
                                        interestamount, feeamount, notes, createdby)
    VALUES (p_farmid, p_loanid, v_date, p_cashaccountid, v_pr, v_in, v_fe, p_notes, p_createdby)
    RETURNING loanpaymentid INTO v_id;

    PERFORM fnrestaurant_post(p_farmid, p_cashaccountid, v_date, -(v_pr + v_in + v_fe), 'LoanRepayment', v_id,
                              'Repayment on ' || v_l.loannumber || ' (' || v_l.lendername || ')', p_createdby);

    UPDATE restaurantloans
       SET outstandingprincipal = outstandingprincipal - v_pr,
           principalrepaid = principalrepaid + v_pr,
           interestpaid = interestpaid + v_in,
           feespaid = feespaid + v_fe,
           status = CASE WHEN outstandingprincipal - v_pr <= 0 THEN 'PaidOff' ELSE 'Active' END
     WHERE loanid = p_loanid;
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_loan_payment_reverse(p_farmid TEXT, p_loanpaymentid INT, p_reason TEXT,
                                                  p_reversedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_p restaurantloanpayments%ROWTYPE; v_l restaurantloans%ROWTYPE;
BEGIN
    SELECT * INTO v_p FROM restaurantloanpayments WHERE loanpaymentid = p_loanpaymentid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Repayment not found.'; END IF;
    IF v_p.status <> 'Posted' THEN RAISE EXCEPTION 'That repayment is already reversed.'; END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for the reversal.'; END IF;
    SELECT * INTO v_l FROM restaurantloans WHERE loanid = v_p.loanid FOR UPDATE;
    IF v_l.status = 'Cancelled' THEN RAISE EXCEPTION 'The loan is cancelled.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    PERFORM fnrestaurant_post(p_farmid, v_p.cashaccountid, CURRENT_DATE,
                              v_p.principalamount + v_p.interestamount + v_p.feeamount,
                              'LoanRepaymentReversal', p_loanpaymentid,
                              'Reversal of repayment on ' || v_l.loannumber || ': ' || btrim(p_reason), p_reversedby);

    UPDATE restaurantloanpayments
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE loanpaymentid = p_loanpaymentid;
    UPDATE restaurantloans
       SET outstandingprincipal = outstandingprincipal + v_p.principalamount,
           principalrepaid = principalrepaid - v_p.principalamount,
           interestpaid = interestpaid - v_p.interestamount,
           feespaid = feespaid - v_p.feeamount,
           status = 'Active'
     WHERE loanid = v_p.loanid;
END $$;

-- For a loan recorded by mistake: only with no live repayments. Returns the
-- money received.
CREATE FUNCTION sprestaurant_loan_cancel(p_farmid TEXT, p_loanid INT, p_reason TEXT, p_cancelledby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_l restaurantloans%ROWTYPE;
BEGIN
    SELECT * INTO v_l FROM restaurantloans WHERE loanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v_l.status = 'Cancelled' THEN RAISE EXCEPTION 'Loan % is already cancelled.', v_l.loannumber; END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for cancelling.'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantloanpayments p WHERE p.loanid = p_loanid AND p.status = 'Posted') THEN
        RAISE EXCEPTION 'Loan % has repayments. Reverse them before cancelling the loan.', v_l.loannumber;
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF v_l.amountreceived > 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_l.receivedaccountid, CURRENT_DATE, -v_l.amountreceived,
                                  'LoanReceivedReversal', p_loanid,
                                  'Cancellation of ' || v_l.loannumber || ': ' || btrim(p_reason), p_cancelledby);
    END IF;
    UPDATE restaurantloans
       SET status = 'Cancelled', cancelledby = p_cancelledby, cancelledat = NOW(), cancelreason = btrim(p_reason)
     WHERE loanid = p_loanid;
END $$;

CREATE FUNCTION sprestaurant_loan_list(p_farmid TEXT)
RETURNS TABLE(loanid INT, loannumber TEXT, lendername TEXT, principal NUMERIC, amountreceived NUMERIC,
              receivedaccountid INT, receivedaccountname TEXT, loandate DATE, interestrate NUMERIC,
              duedate DATE, outstandingprincipal NUMERIC, principalrepaid NUMERIC, interestpaid NUMERIC,
              feespaid NUMERIC, status TEXT, isoverdue BOOLEAN, notes TEXT, createdby TEXT,
              createdat TIMESTAMP, cancelreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT l.loanid, l.loannumber, l.lendername, l.principal, l.amountreceived, l.receivedaccountid, a.name,
           l.loandate, l.interestrate, l.duedate, l.outstandingprincipal, l.principalrepaid, l.interestpaid,
           l.feespaid, l.status,
           (l.status = 'Active' AND l.duedate IS NOT NULL AND l.duedate < CURRENT_DATE AND l.outstandingprincipal > 0),
           l.notes, l.createdby, l.createdat, l.cancelreason
      FROM restaurantloans l
      LEFT JOIN restaurantcashaccounts a ON a.cashaccountid = l.receivedaccountid
     WHERE l.farmid = p_farmid
     ORDER BY (l.status = 'Active') DESC, l.loandate DESC, l.loanid DESC;
$$;

CREATE FUNCTION sprestaurant_loan_payments(p_farmid TEXT, p_loanid INT)
RETURNS TABLE(loanpaymentid INT, loanid INT, paymentdate DATE, cashaccountid INT, accountname TEXT,
              principalamount NUMERIC, interestamount NUMERIC, feeamount NUMERIC, totalamount NUMERIC,
              status TEXT, notes TEXT, createdby TEXT, createdat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT p.loanpaymentid, p.loanid, p.paymentdate, p.cashaccountid, a.name, p.principalamount,
           p.interestamount, p.feeamount, p.principalamount + p.interestamount + p.feeamount,
           p.status, p.notes, p.createdby, p.createdat, p.reversalreason
      FROM restaurantloanpayments p
      JOIN restaurantcashaccounts a ON a.cashaccountid = p.cashaccountid
     WHERE p.farmid = p_farmid AND p.loanid = p_loanid
     ORDER BY p.paymentdate DESC, p.loanpaymentid DESC;
$$;

-- -----------------------------------------------------------------------------
-- 8. Cash counts (reconciliation for safes, banks, wallets; tills use shifts)
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_cashcount_post(p_farmid TEXT, p_cashaccountid INT, p_counted NUMERIC,
                                            p_notes TEXT DEFAULT NULL, p_createdby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_acc restaurantcashaccounts%ROWTYPE; v_id INT; v_sys NUMERIC; v_diff NUMERIC; v_ledger NUMERIC;
        v_counted NUMERIC := ROUND(COALESCE(p_counted, -1), 2);
BEGIN
    SELECT * INTO v_acc FROM restaurantcashaccounts WHERE cashaccountid = p_cashaccountid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cash account not found.'; END IF;
    IF v_counted < 0 THEN RAISE EXCEPTION 'Enter the balance you counted or confirmed.'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashshifts s WHERE s.cashaccountid = p_cashaccountid AND s.status = 'Open') THEN
        RAISE EXCEPTION '"%" has an open shift. Count it by closing the shift.', v_acc.name;
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    -- Heal the cached balance from the ledger before comparing against it.
    SELECT COALESCE(SUM(t.amount), 0) INTO v_ledger FROM restaurantcashtransactions t WHERE t.cashaccountid = p_cashaccountid;
    IF v_ledger <> v_acc.currentbalance THEN
        UPDATE restaurantcashaccounts SET currentbalance = v_ledger WHERE cashaccountid = p_cashaccountid;
    END IF;
    v_sys := v_ledger;
    v_diff := v_counted - v_sys;

    INSERT INTO restaurantcashcounts (farmid, cashaccountid, countdate, systembalance, countedbalance, difference, notes, createdby)
    VALUES (p_farmid, p_cashaccountid, CURRENT_DATE, v_sys, v_counted, v_diff, p_notes, p_createdby)
    RETURNING countid INTO v_id;

    IF v_diff <> 0 THEN
        PERFORM fnrestaurant_post(p_farmid, p_cashaccountid, CURRENT_DATE, v_diff, 'CountVariance', v_id,
                                  CASE WHEN v_diff > 0 THEN 'Count found more than recorded in ' ELSE 'Count found less than recorded in ' END
                                  || v_acc.name, p_createdby);
    END IF;
    UPDATE restaurantcashaccounts SET lastcountedat = NOW(), lastcountedbalance = v_counted WHERE cashaccountid = p_cashaccountid;
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_cashcount_reverse(p_farmid TEXT, p_countid INT, p_reason TEXT, p_reversedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_c restaurantcashcounts%ROWTYPE;
BEGIN
    SELECT * INTO v_c FROM restaurantcashcounts WHERE countid = p_countid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Count not found.'; END IF;
    IF v_c.status <> 'Posted' THEN RAISE EXCEPTION 'That count is already reversed.'; END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for the reversal.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);
    IF v_c.difference <> 0 THEN
        PERFORM fnrestaurant_post(p_farmid, v_c.cashaccountid, CURRENT_DATE, -v_c.difference, 'CountVarianceReversal',
                                  p_countid, 'Reversal of count: ' || btrim(p_reason), p_reversedby);
    END IF;
    UPDATE restaurantcashcounts
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = NOW(), reversalreason = btrim(p_reason)
     WHERE countid = p_countid;
END $$;

CREATE FUNCTION sprestaurant_cashcount_list(p_farmid TEXT, p_cashaccountid INT DEFAULT NULL)
RETURNS TABLE(countid INT, cashaccountid INT, accountname TEXT, countdate DATE, systembalance NUMERIC,
              countedbalance NUMERIC, difference NUMERIC, status TEXT, notes TEXT, createdby TEXT,
              createdat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT c.countid, c.cashaccountid, a.name, c.countdate, c.systembalance, c.countedbalance, c.difference,
           c.status, c.notes, c.createdby, c.createdat, c.reversalreason
      FROM restaurantcashcounts c
      JOIN restaurantcashaccounts a ON a.cashaccountid = c.cashaccountid
     WHERE c.farmid = p_farmid AND (p_cashaccountid IS NULL OR c.cashaccountid = p_cashaccountid)
     ORDER BY c.createdat DESC;
$$;

-- -----------------------------------------------------------------------------
-- 9. Order money: recalc, payments, refunds, status rules, stock deduction
-- -----------------------------------------------------------------------------

-- NULL rates = use the rates saved in Setup. Service charge is dine-in only.
-- The delivery fee is part of the total. Closed orders are never re-priced.
CREATE FUNCTION sprestaurant_order_recalc(p_orderid INT, p_farmid TEXT,
                                          p_taxrate NUMERIC DEFAULT NULL, p_servicechargerate NUMERIC DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_sub NUMERIC; v_disc NUMERIC; v_tax NUMERIC; v_sc NUMERIC; v_base NUMERIC;
        v_type TEXT; v_status TEXT; v_fee NUMERIC; v_taxr NUMERIC; v_scr NUMERIC;
BEGIN
    SELECT o.ordertype, o.status, COALESCE(o.deliveryfee, 0) INTO v_type, v_status, v_fee
      FROM restaurantorders o WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
    IF NOT FOUND THEN RETURN; END IF;
    IF v_status IN ('Completed', 'Cancelled', 'Refunded') THEN RETURN; END IF;

    v_taxr := p_taxrate; v_scr := p_servicechargerate;
    IF v_taxr IS NULL OR v_scr IS NULL THEN
        SELECT COALESCE(v_taxr, pr.taxrate), COALESCE(v_scr, pr.servicechargerate)
          INTO v_taxr, v_scr
          FROM restaurantprofiles pr WHERE pr.farmid = p_farmid
         ORDER BY pr.restaurantprofileid LIMIT 1;
    END IF;
    v_taxr := COALESCE(v_taxr, 0);
    v_scr := CASE WHEN v_type = 'DineIn' THEN COALESCE(v_scr, 0) ELSE 0 END;

    SELECT COALESCE(SUM(oi.linetotal), 0) INTO v_sub FROM restaurantorderitems oi
     WHERE oi.orderid = p_orderid AND oi.farmid = p_farmid AND oi.status <> 'Cancelled';
    SELECT COALESCE(SUM(d.appliedamount), 0) INTO v_disc FROM restaurantorderdiscounts d
     WHERE d.orderid = p_orderid AND d.farmid = p_farmid;
    v_disc := LEAST(v_disc, v_sub);
    v_base := v_sub - v_disc;
    v_tax := ROUND(v_base * v_taxr / 100, 2);
    v_sc  := ROUND(v_base * v_scr / 100, 2);

    UPDATE restaurantorders
       SET subtotal = v_sub, discountamount = v_disc, taxamount = v_tax, servicechargeamount = v_sc,
           totalamount = v_base + v_tax + v_sc + v_fee, updatedat = NOW(),
           paymentstatus = CASE WHEN paidamount <= 0 THEN 'Unpaid'
                                WHEN paidamount >= v_base + v_tax + v_sc + v_fee THEN 'Paid'
                                ELSE 'Partial' END
     WHERE orderid = p_orderid AND farmid = p_farmid;
END $$;

-- Same as the 248/314 version except the delivery fee: recalc now includes it,
-- so adding it here again would charge it twice.
CREATE FUNCTION sprestaurant_online_order_finalize(p_orderid INT, p_farmid TEXT, p_ordertype TEXT,
                                                   p_promocode TEXT DEFAULT NULL, p_channel TEXT DEFAULT NULL,
                                                   p_taxrate NUMERIC DEFAULT NULL, p_servicechargerate NUMERIC DEFAULT NULL)
RETURNS TABLE(subtotal NUMERIC, discountamount NUMERIC, totalamount NUMERIC)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE v_sub NUMERIC; v_promo RECORD; v_prep INT;
BEGIN
    SELECT COALESCE(SUM(oi.linetotal), 0) INTO v_sub
      FROM restaurantorderitems oi
     WHERE oi.orderid = p_orderid AND oi.farmid = p_farmid AND oi.status != 'Cancelled';
    IF v_sub <= 0 THEN RAISE EXCEPTION 'Order % has no items.', p_orderid; END IF;

    IF p_promocode IS NOT NULL AND LENGTH(TRIM(p_promocode)) > 0 THEN
        SELECT * INTO v_promo FROM sprestaurant_promocode_validate(p_farmid, p_promocode, v_sub, p_channel);
        IF v_promo.valid THEN
            DELETE FROM restaurantorderdiscounts d
             WHERE d.orderid = p_orderid AND d.farmid = p_farmid AND d.discountname = 'Promo: ' || UPPER(p_promocode);
            INSERT INTO restaurantorderdiscounts (farmid, orderid, discountname, discounttype, value, appliedamount)
            VALUES (p_farmid, p_orderid, 'Promo: ' || UPPER(p_promocode),
                    v_promo.discounttype, v_promo.discountvalue, v_promo.calculatediscount);
            UPDATE restaurantorders o
               SET promocodeid = v_promo.promocodeid, promocode = UPPER(p_promocode),
                   promodiscount = v_promo.calculatediscount
             WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
            PERFORM sprestaurant_promocode_use(v_promo.promocodeid, p_farmid);
        ELSE
            UPDATE restaurantorders o SET promocodeid = NULL, promocode = NULL, promodiscount = 0
             WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
        END IF;
    END IF;

    PERFORM sprestaurant_order_recalc(p_orderid, p_farmid, p_taxrate, p_servicechargerate);

    SELECT CASE p_ordertype WHEN 'Delivery' THEN s.estimatedprepminsdeliv
                            WHEN 'Takeaway' THEN s.estimatedprepminstake
                            ELSE s.estimatedprepminsdine END
      INTO v_prep
      FROM restaurantonlineorderingsettings s WHERE s.farmid = p_farmid;

    UPDATE restaurantorders o
       SET estimatedreadytime = NOW() + (COALESCE(v_prep, 15) || ' minutes')::INTERVAL, updatedat = NOW()
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;

    RETURN QUERY SELECT o.subtotal, o.discountamount, o.totalamount
                   FROM restaurantorders o WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
END $$;

-- Recomputes paidamount / paymentstatus from the payment rows. Refund rows are
-- negative, so they net off. A completed order that took a partial refund stays
-- 'Paid' (it was settled); a full refund makes it 'Refunded'.
CREATE FUNCTION fnrestaurant_order_settle(p_orderid INT, p_farmid TEXT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_paid NUMERIC; v_total NUMERIC; v_status TEXT;
BEGIN
    SELECT COALESCE(SUM(p.amount), 0) INTO v_paid FROM restaurantorderpayments p
     WHERE p.orderid = p_orderid AND p.farmid = p_farmid AND p.status = 'Completed';
    SELECT o.totalamount, o.status INTO v_total, v_status FROM restaurantorders o
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
    UPDATE restaurantorders o
       SET paidamount = v_paid, updatedat = NOW(),
           paymentstatus = CASE
               WHEN v_status = 'Refunded' THEN 'Refunded'
               WHEN v_status = 'Completed' AND v_paid > 0 THEN 'Paid'
               WHEN v_paid <= 0 AND EXISTS (SELECT 1 FROM restaurantorderpayments p
                                             WHERE p.orderid = p_orderid AND p.amount < 0) THEN 'Refunded'
               WHEN v_paid <= 0 THEN 'Unpaid'
               WHEN v_paid >= v_total THEN 'Paid'
               ELSE 'Partial' END
     WHERE o.orderid = p_orderid AND o.farmid = p_farmid;
    RETURN v_paid;
END $$;

CREATE FUNCTION sprestaurant_orderpayment_insert(p_farmid TEXT, p_orderid INT, p_paymentmethod TEXT,
                                                 p_amount NUMERIC, p_tipamount NUMERIC, p_reference TEXT,
                                                 p_processedby TEXT, p_cashaccountid INT DEFAULT NULL,
                                                 p_shiftid INT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_o restaurantorders%ROWTYPE; v_id INT; v_due NUMERIC; v_acc INT;
        v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_tip NUMERIC := ROUND(COALESCE(p_tipamount, 0), 2);
        v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
        v_card restaurantgiftcards%ROWTYPE;
BEGIN
    SELECT * INTO v_o FROM restaurantorders WHERE orderid = p_orderid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
    IF v_o.status IN ('Cancelled', 'Refunded') THEN
        RAISE EXCEPTION 'Order % is %; it cannot take payments.', v_o.ordernumber, lower(v_o.status);
    END IF;
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Payment amount must be more than zero.'; END IF;
    IF v_tip < 0 THEN RAISE EXCEPTION 'A tip cannot be negative.'; END IF;
    v_due := ROUND(v_o.totalamount - v_o.paidamount, 2);
    IF v_due <= 0 THEN RAISE EXCEPTION 'Order % is already fully paid.', v_o.ordernumber; END IF;
    IF v_amt > v_due THEN
        RAISE EXCEPTION 'This payment (%) is more than the % still due on %. Enter the amount applied to the bill and give the rest back as change.',
            to_char(v_amt, 'FM999,999,999,990.00'), to_char(v_due, 'FM999,999,999,990.00'), v_o.ordernumber;
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF lower(replace(v_method, ' ', '')) = 'giftcard' THEN
        IF v_tip > 0 THEN RAISE EXCEPTION 'A tip cannot be paid from a gift card.'; END IF;
        IF btrim(COALESCE(p_reference, '')) = '' THEN RAISE EXCEPTION 'Enter the gift card number.'; END IF;
        SELECT * INTO v_card FROM restaurantgiftcards g
         WHERE upper(g.cardnumber) = upper(btrim(p_reference)) AND g.farmid = p_farmid FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Gift card % was not found.', btrim(p_reference); END IF;
        IF v_card.status <> 'Active' THEN RAISE EXCEPTION 'Gift card % is %.', v_card.cardnumber, v_card.status; END IF;
        IF v_card.expirydate IS NOT NULL AND v_card.expirydate < CURRENT_DATE THEN
            RAISE EXCEPTION 'Gift card % expired on %.', v_card.cardnumber, to_char(v_card.expirydate, 'DD Mon YYYY');
        END IF;
        IF v_card.currentbalance < v_amt THEN
            RAISE EXCEPTION 'Gift card % only has % left.', v_card.cardnumber, to_char(v_card.currentbalance, 'FM999,999,999,990.00');
        END IF;
        UPDATE restaurantgiftcards
           SET currentbalance = currentbalance - v_amt,
               status = CASE WHEN currentbalance - v_amt <= 0 THEN 'FullyRedeemed' ELSE status END
         WHERE giftcardid = v_card.giftcardid;
        INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, orderid, processedby, notes)
        VALUES (p_farmid, v_card.giftcardid, 'Redemption', -v_amt, v_card.currentbalance - v_amt, p_orderid, p_processedby,
                'Paid order ' || v_o.ordernumber);
        v_method := 'GiftCard';
    END IF;

    INSERT INTO restaurantorderpayments (farmid, orderid, paymentmethod, amount, tipamount, reference, processedby)
    VALUES (p_farmid, p_orderid, v_method, v_amt, v_tip,
            CASE WHEN v_method = 'GiftCard' THEN v_card.cardnumber ELSE p_reference END, p_processedby)
    RETURNING orderpaymentid INTO v_id;

    v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, p_shiftid, TRUE);
    IF v_acc IS NOT NULL THEN
        PERFORM fnrestaurant_post(p_farmid, v_acc, CURRENT_DATE, v_amt + v_tip, 'OrderPayment', v_id,
                                  'Order ' || v_o.ordernumber || ' (' || v_method || ')'
                                  || CASE WHEN v_tip > 0 THEN ' incl. tip ' || to_char(v_tip, 'FM999,999,990.00') ELSE '' END,
                                  p_processedby);
    END IF;

    PERFORM fnrestaurant_order_settle(p_orderid, p_farmid);
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_orderpayment_refund(p_farmid TEXT, p_orderid INT, p_amount NUMERIC,
                                                 p_paymentmethod TEXT, p_reason TEXT, p_processedby TEXT,
                                                 p_cashaccountid INT DEFAULT NULL, p_shiftid INT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_o restaurantorders%ROWTYPE; v_id INT; v_acc INT; v_paid NUMERIC;
        v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
BEGIN
    SELECT * INTO v_o FROM restaurantorders WHERE orderid = p_orderid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Refund amount must be more than zero.'; END IF;
    IF v_amt > v_o.paidamount THEN
        RAISE EXCEPTION 'Only % has been paid on %; you cannot refund more than that.',
            to_char(v_o.paidamount, 'FM999,999,999,990.00'), v_o.ordernumber;
    END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for the refund.'; END IF;
    IF NOT fnrestaurant_is_cash_method(v_method) THEN
        RAISE EXCEPTION 'Refunds go back as Cash, Card, Bank Transfer or Mobile Money. To return value to a gift card, reload it from Gift Cards.';
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    INSERT INTO restaurantorderpayments (farmid, orderid, paymentmethod, amount, tipamount, reference, processedby)
    VALUES (p_farmid, p_orderid, v_method, -v_amt, 0, 'Refund: ' || btrim(p_reason), p_processedby)
    RETURNING orderpaymentid INTO v_id;

    v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, p_shiftid, FALSE);
    PERFORM fnrestaurant_post(p_farmid, v_acc, CURRENT_DATE, -v_amt, 'OrderRefund', v_id,
                              'Refund on ' || v_o.ordernumber || ': ' || btrim(p_reason), p_processedby);

    SELECT COALESCE(SUM(p.amount), 0) INTO v_paid FROM restaurantorderpayments p
     WHERE p.orderid = p_orderid AND p.farmid = p_farmid AND p.status = 'Completed';
    IF v_paid <= 0 THEN
        UPDATE restaurantorders
           SET status = 'Refunded', refundreason = btrim(p_reason),
               completedat = COALESCE(completedat, NOW()), updatedat = NOW()
         WHERE orderid = p_orderid AND farmid = p_farmid;
        UPDATE restauranttables SET status = 'NeedsCleaning', currentorderid = NULL, updatedat = NOW()
         WHERE currentorderid = p_orderid AND farmid = p_farmid;
    END IF;
    PERFORM fnrestaurant_order_settle(p_orderid, p_farmid);
    RETURN v_id;
END $$;

-- Completed now means paid; Cancelled means nothing is held; Refunded is set by
-- sprestaurant_orderpayment_refund, never by hand.
CREATE FUNCTION sprestaurant_order_update_status(p_id INT, p_farmid TEXT, p_status TEXT, p_reason TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_o restaurantorders%ROWTYPE;
BEGIN
    SELECT * INTO v_o FROM restaurantorders WHERE orderid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;

    IF p_status = 'Completed' AND v_o.status <> 'Completed'
       AND v_o.totalamount > 0 AND v_o.paidamount < v_o.totalamount THEN
        RAISE EXCEPTION 'Order % still has % to pay. Take payment before completing it.',
            v_o.ordernumber, to_char(v_o.totalamount - v_o.paidamount, 'FM999,999,999,990.00');
    END IF;
    IF p_status = 'Cancelled' AND v_o.paidamount > 0 THEN
        RAISE EXCEPTION 'Order % has % paid against it. Refund it instead of cancelling.',
            v_o.ordernumber, to_char(v_o.paidamount, 'FM999,999,999,990.00');
    END IF;
    IF p_status = 'Refunded' AND v_o.status <> 'Refunded' THEN
        RAISE EXCEPTION 'Use Refund on the order to give money back; it sets the Refunded status.';
    END IF;
    IF v_o.status IN ('Cancelled', 'Refunded') AND p_status <> v_o.status THEN
        RAISE EXCEPTION 'Order % is % and cannot change status.', v_o.ordernumber, lower(v_o.status);
    END IF;

    UPDATE restaurantorders SET status = p_status, updatedat = NOW(),
        cancelreason = CASE WHEN p_status = 'Cancelled' THEN p_reason ELSE cancelreason END,
        completedat = CASE WHEN p_status IN ('Completed','Cancelled') THEN NOW() ELSE completedat END
    WHERE orderid = p_id AND farmid = p_farmid;
    IF p_status IN ('Completed', 'Cancelled') THEN
        UPDATE restauranttables SET status = 'NeedsCleaning', currentorderid = NULL, updatedat = NOW()
         WHERE currentorderid = p_id AND farmid = p_farmid;
    END IF;
    IF p_status = 'Completed' THEN PERFORM fnrestaurant_order_settle(p_id, p_farmid); END IF;
END $$;

-- Correlated per ingredient, and idempotent: an order is deducted once.
CREATE FUNCTION sprestaurant_recipe_deduct_order(p_orderid INT, p_farmid TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_count INT := 0; v_item RECORD; v_ref TEXT := 'Order #' || p_orderid;
BEGIN
    IF EXISTS (SELECT 1 FROM restaurantstockmovements m
                WHERE m.farmid = p_farmid AND m.movementtype = 'OrderDeduction' AND m.reference = v_ref) THEN
        RETURN 0;
    END IF;
    FOR v_item IN
        SELECT oi.menuitemid, oi.quantity AS orderqty
          FROM restaurantorderitems oi
         WHERE oi.orderid = p_orderid AND oi.farmid = p_farmid
           AND oi.menuitemid IS NOT NULL AND oi.status <> 'Cancelled'
    LOOP
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference, createdby)
        SELECT p_farmid, r.ingredientid, 'OrderDeduction',
               -(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * v_item.orderqty), i.costperunit, v_ref, 'System'
          FROM restaurantrecipes r
          JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
         WHERE r.menuitemid = v_item.menuitemid AND r.farmid = p_farmid;

        UPDATE restaurantingredients i
           SET currentstock = i.currentstock - d.qty, updatedat = NOW()
          FROM (SELECT r.ingredientid, SUM(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * v_item.orderqty) AS qty
                  FROM restaurantrecipes r
                 WHERE r.menuitemid = v_item.menuitemid AND r.farmid = p_farmid
                 GROUP BY r.ingredientid) d
         WHERE i.ingredientid = d.ingredientid AND i.farmid = p_farmid;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

-- -----------------------------------------------------------------------------
-- 10. Expenses post to the ledger
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_expense_record(p_farmid TEXT, p_expensedate DATE, p_categoryid INT,
                                            p_categoryname TEXT, p_description TEXT, p_amount NUMERIC,
                                            p_paymentmethod TEXT, p_suppliername TEXT, p_receiptref TEXT,
                                            p_createdby TEXT, p_cashaccountid INT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_id INT; v_acc INT; v_cat TEXT := NULLIF(btrim(p_categoryname), '');
        v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_date DATE := COALESCE(p_expensedate, CURRENT_DATE);
        v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Expense amount must be more than zero.'; END IF;
    IF btrim(COALESCE(p_description, '')) = '' THEN RAISE EXCEPTION 'Description is required.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'An expense cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    -- The form sends only the category id; without the name every expense was
    -- reported as "Uncategorised".
    IF v_cat IS NULL AND p_categoryid IS NOT NULL THEN
        SELECT c.name INTO v_cat FROM restaurantexpensecategories c
         WHERE c.expensecategoryid = p_categoryid AND c.farmid = p_farmid;
    END IF;

    INSERT INTO restaurantexpenses (farmid, expensedate, categoryid, categoryname, description, amount,
                                    paymentmethod, suppliername, receiptref, createdby, status)
    VALUES (p_farmid, v_date, p_categoryid, v_cat, btrim(p_description), v_amt, v_method,
            p_suppliername, p_receiptref, p_createdby, 'Approved')
    RETURNING expenseid INTO v_id;

    v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, NULL, FALSE);
    -- Cash expenses default to the cash box, not an open till: money leaves the
    -- drawer only when someone says it did.
    IF p_cashaccountid IS NULL AND lower(replace(v_method, ' ', '')) = 'cash' THEN
        v_acc := fnrestaurant_default_account(p_farmid, 'Cash');
    END IF;
    IF v_acc IS NOT NULL THEN
        PERFORM fnrestaurant_post(p_farmid, v_acc, v_date, -v_amt, 'Expense', v_id,
                                  btrim(p_description) || COALESCE(' (' || v_cat || ')', ''), p_createdby);
    END IF;
    RETURN v_id;
END $$;

-- Old signature, kept for any caller: posts to the default account for the method.
CREATE FUNCTION sprestaurant_expense_insert(p_farmid TEXT, p_expensedate DATE, p_categoryid INT,
                                            p_categoryname TEXT, p_description TEXT, p_amount NUMERIC,
                                            p_paymentmethod TEXT, p_suppliername TEXT, p_receiptref TEXT,
                                            p_createdby TEXT)
RETURNS INT LANGUAGE sql AS $$
    SELECT sprestaurant_expense_record(p_farmid, p_expensedate, p_categoryid, p_categoryname, p_description,
                                       p_amount, p_paymentmethod, p_suppliername, p_receiptref, p_createdby, NULL);
$$;

-- Deleting an expense puts its money back, on the expense's own date (which
-- must still be open).
CREATE FUNCTION sprestaurant_expense_delete(p_id INT, p_farmid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_e restaurantexpenses%ROWTYPE; v_t RECORD;
BEGIN
    SELECT * INTO v_e FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_e.expensedate);

    FOR v_t IN
        SELECT t.cashtxnid, t.cashaccountid, t.amount FROM restaurantcashtransactions t
         WHERE t.sourcetype = 'Expense' AND t.sourceid = p_id AND t.farmid = p_farmid
           AND NOT EXISTS (SELECT 1 FROM restaurantcashtransactions r WHERE r.reversesid = t.cashtxnid)
    LOOP
        PERFORM fnrestaurant_post(p_farmid, v_t.cashaccountid, v_e.expensedate, -v_t.amount, 'ExpenseReversal', p_id,
                                  'Deleted expense: ' || v_e.description, v_e.createdby, v_t.cashtxnid);
    END LOOP;
    DELETE FROM restaurantexpenses WHERE expenseid = p_id AND farmid = p_farmid;
END $$;

-- -----------------------------------------------------------------------------
-- 11. Gift cards
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_giftcard_create(p_farmid TEXT, p_cardtype TEXT, p_amount NUMERIC,
                                             p_purchasername TEXT, p_purchaserphone TEXT, p_recipientname TEXT,
                                             p_recipientemail TEXT, p_message TEXT, p_expirydate DATE,
                                             p_paymentmethod TEXT DEFAULT 'Cash', p_cashaccountid INT DEFAULT NULL,
                                             p_processedby TEXT DEFAULT NULL)
RETURNS TABLE(giftcardid INT, cardnumber TEXT)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE v_id INT; v_num TEXT; v_acc INT; v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Gift card value must be more than zero.'; END IF;
    IF p_expirydate IS NOT NULL AND p_expirydate < CURRENT_DATE THEN RAISE EXCEPTION 'The expiry date is in the past.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    v_num := 'GC-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT || clock_timestamp()::TEXT) FROM 1 FOR 8));
    INSERT INTO restaurantgiftcards (farmid, cardnumber, cardtype, initialbalance, currentbalance, purchasername,
                                     purchaserphone, recipientname, recipientemail, message, expirydate)
    VALUES (p_farmid, v_num, COALESCE(p_cardtype, 'Digital'), v_amt, v_amt, p_purchasername, p_purchaserphone,
            p_recipientname, p_recipientemail, p_message, p_expirydate)
    RETURNING restaurantgiftcards.giftcardid INTO v_id;
    INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, processedby, notes)
    VALUES (p_farmid, v_id, 'Purchase', v_amt, v_amt, p_processedby, 'Initial purchase (' || v_method || ')');

    v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, NULL, FALSE);
    IF v_acc IS NOT NULL THEN
        PERFORM fnrestaurant_post(p_farmid, v_acc, CURRENT_DATE, v_amt, 'GiftCardSale', v_id,
                                  'Gift card ' || v_num || ' sold (' || v_method || ')', p_processedby);
    END IF;
    RETURN QUERY SELECT v_id, v_num;
END $$;

CREATE FUNCTION sprestaurant_giftcard_reload(p_cardnumber TEXT, p_farmid TEXT, p_amount NUMERIC,
                                             p_processedby TEXT DEFAULT NULL, p_paymentmethod TEXT DEFAULT 'Cash',
                                             p_cashaccountid INT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_card restaurantgiftcards%ROWTYPE; v_tx INT; v_acc INT; v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_method TEXT := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Reload amount must be more than zero.'; END IF;
    SELECT * INTO v_card FROM restaurantgiftcards g
     WHERE upper(g.cardnumber) = upper(btrim(p_cardnumber)) AND g.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Gift card % was not found.', p_cardnumber; END IF;
    IF v_card.status = 'Cancelled' THEN RAISE EXCEPTION 'Gift card % is cancelled.', v_card.cardnumber; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    UPDATE restaurantgiftcards SET currentbalance = currentbalance + v_amt, status = 'Active'
     WHERE giftcardid = v_card.giftcardid;
    INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, processedby, notes)
    VALUES (p_farmid, v_card.giftcardid, 'Reload', v_amt, v_card.currentbalance + v_amt, p_processedby, 'Reload (' || v_method || ')')
    RETURNING giftcardtxid INTO v_tx;

    v_acc := fnrestaurant_resolve_account(p_farmid, v_method, p_cashaccountid, NULL, FALSE);
    IF v_acc IS NOT NULL THEN
        PERFORM fnrestaurant_post(p_farmid, v_acc, CURRENT_DATE, v_amt, 'GiftCardReload', v_tx,
                                  'Gift card ' || v_card.cardnumber || ' reloaded (' || v_method || ')', p_processedby);
    END IF;
END $$;

CREATE FUNCTION sprestaurant_giftcard_redeem(p_cardnumber TEXT, p_farmid TEXT, p_amount NUMERIC,
                                             p_orderid INT DEFAULT NULL, p_processedby TEXT DEFAULT NULL)
RETURNS TABLE(success BOOLEAN, newbalance NUMERIC, message TEXT)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE v_card restaurantgiftcards%ROWTYPE; v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_bal NUMERIC;
BEGIN
    -- Against an order: it is a gift-card PAYMENT on that order, so the order's
    -- paid amount moves too. Before 323 the card was debited and the order stayed
    -- Unpaid.
    IF p_orderid IS NOT NULL THEN
        BEGIN
            PERFORM sprestaurant_orderpayment_insert(p_farmid, p_orderid, 'GiftCard', v_amt, 0,
                                                     p_cardnumber, p_processedby, NULL, NULL);
        EXCEPTION WHEN raise_exception THEN
            RETURN QUERY SELECT FALSE, 0::NUMERIC, SQLERRM::TEXT;
            RETURN;
        END;
        SELECT g.currentbalance INTO v_bal FROM restaurantgiftcards g
         WHERE upper(g.cardnumber) = upper(btrim(p_cardnumber)) AND g.farmid = p_farmid;
        RETURN QUERY SELECT TRUE, v_bal, 'Redeemed against the order'::TEXT;
        RETURN;
    END IF;
    IF v_amt <= 0 THEN RETURN QUERY SELECT FALSE, 0::NUMERIC, 'Amount must be more than zero'::TEXT; RETURN; END IF;
    SELECT * INTO v_card FROM restaurantgiftcards g
     WHERE upper(g.cardnumber) = upper(btrim(p_cardnumber)) AND g.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RETURN QUERY SELECT FALSE, 0::NUMERIC, 'Card not found'::TEXT; RETURN; END IF;
    IF v_card.status <> 'Active' THEN
        RETURN QUERY SELECT FALSE, v_card.currentbalance, ('Card is ' || v_card.status)::TEXT; RETURN;
    END IF;
    IF v_card.expirydate IS NOT NULL AND v_card.expirydate < CURRENT_DATE THEN
        RETURN QUERY SELECT FALSE, v_card.currentbalance, ('Card expired on ' || to_char(v_card.expirydate, 'DD Mon YYYY'))::TEXT; RETURN;
    END IF;
    IF v_card.currentbalance < v_amt THEN
        RETURN QUERY SELECT FALSE, v_card.currentbalance, 'Insufficient balance'::TEXT; RETURN;
    END IF;
    UPDATE restaurantgiftcards
       SET currentbalance = currentbalance - v_amt,
           status = CASE WHEN currentbalance - v_amt <= 0 THEN 'FullyRedeemed' ELSE status END
     WHERE giftcardid = v_card.giftcardid;
    INSERT INTO restaurantgiftcardtransactions (farmid, giftcardid, transactiontype, amount, balanceafter, processedby)
    VALUES (p_farmid, v_card.giftcardid, 'Redemption', -v_amt, v_card.currentbalance - v_amt, p_processedby);
    RETURN QUERY SELECT TRUE, v_card.currentbalance - v_amt, 'Redeemed successfully'::TEXT;
END $$;

CREATE FUNCTION sprestaurant_giftcard_balance(p_cardnumber TEXT, p_farmid TEXT)
RETURNS TABLE(cardnumber TEXT, currentbalance NUMERIC, status TEXT, expirydate DATE)
LANGUAGE sql STABLE AS $$
    SELECT g.cardnumber, g.currentbalance, g.status, g.expirydate
      FROM restaurantgiftcards g
     WHERE upper(g.cardnumber) = upper(btrim(p_cardnumber)) AND g.farmid = p_farmid;
$$;

CREATE FUNCTION sprestaurant_giftcard_stats(p_farmid TEXT)
RETURNS TABLE(total_cards BIGINT, active_cards BIGINT, total_issued NUMERIC, total_outstanding NUMERIC, total_redeemed NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE g.status = 'Active'),
           COALESCE(SUM(g.initialbalance), 0),
           COALESCE(SUM(g.currentbalance) FILTER (WHERE g.status = 'Active'), 0),
           COALESCE((SELECT -SUM(t.amount) FROM restaurantgiftcardtransactions t
                      WHERE t.farmid = p_farmid AND t.transactiontype = 'Redemption'), 0)
      FROM restaurantgiftcards g WHERE g.farmid = p_farmid;
$$;

-- -----------------------------------------------------------------------------
-- 12. Cash Flow: the ledger, minus internal moves and opening balances
-- -----------------------------------------------------------------------------
-- Same column shapes as migration 318, so CashFlowService and the page are
-- unchanged.

CREATE FUNCTION sprestaurantcashflow_rows(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                          p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(rowsource TEXT, offledger BOOLEAN, sourcerowid INT, cashaccountid INT, accountname TEXT,
              transactiondate TIMESTAMP, transactiontype TEXT, sourcetype TEXT, sourceid INT,
              istransfer BOOLEAN, amount NUMERIC, description TEXT, flowgroup TEXT, createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT t.sourcetype, FALSE, t.cashtxnid, t.cashaccountid, a.name, t.txndate::TIMESTAMP, t.txntype,
           t.sourcetype, t.sourceid, FALSE, t.amount, t.description,
           CASE WHEN t.sourcetype LIKE 'Owner%' OR t.sourcetype LIKE 'Loan%'
                THEN CASE WHEN t.amount > 0 THEN 'FinancingIn' ELSE 'FinancingOut' END
                ELSE CASE WHEN t.amount > 0 THEN 'OperatingIn' ELSE 'OperatingOut' END END,
           t.createdat
      FROM restaurantcashtransactions t
      JOIN restaurantcashaccounts a ON a.cashaccountid = t.cashaccountid
     WHERE t.farmid = p_farmid
       AND t.sourcetype NOT IN ('OpeningBalance', 'TransferOut', 'TransferIn', 'TransferReversalOut',
                                'TransferReversalIn', 'ShiftFloatOut', 'ShiftFloatIn', 'ShiftDropOut', 'ShiftDropIn')
       AND (p_fromdate IS NULL OR t.txndate::TIMESTAMP >= p_fromdate)
       AND (p_todate IS NULL OR t.txndate::TIMESTAMP <= p_todate);
$$;

CREATE FUNCTION sprestaurantcashflow_detail(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                            p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(rowsource TEXT, offledger BOOLEAN, sourcerowid INT, cashaccountid INT, accountname TEXT,
              transactiondate TIMESTAMP, transactiontype TEXT, sourcetype TEXT, sourceid INT,
              istransfer BOOLEAN, amount NUMERIC, description TEXT, flowgroup TEXT, category TEXT,
              createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname, r.transactiondate,
           r.transactiontype, r.sourcetype, r.sourceid, r.istransfer, r.amount, r.description, r.flowgroup,
           CASE r.sourcetype
               WHEN 'OrderPayment' THEN 'Sales (' || COALESCE(NULLIF(btrim(p.paymentmethod), ''), 'Cash') || ')'
               WHEN 'OrderRefund' THEN 'Refunds to customers'
               WHEN 'Expense' THEN COALESCE(NULLIF(btrim(e.categoryname), ''), 'Uncategorised')
               WHEN 'ExpenseReversal' THEN 'Expense corrections'
               WHEN 'GiftCardSale' THEN 'Gift card sales'
               WHEN 'GiftCardReload' THEN 'Gift card sales'
               WHEN 'OwnerContribution' THEN 'Owner contributions'
               WHEN 'OwnerDraw' THEN 'Owner drawings'
               WHEN 'OwnerContributionReversal' THEN 'Owner money corrections'
               WHEN 'OwnerDrawReversal' THEN 'Owner money corrections'
               WHEN 'LoanReceived' THEN 'Loans received'
               WHEN 'LoanRepayment' THEN 'Loan repayments'
               WHEN 'LoanRepaymentReversal' THEN 'Loan corrections'
               WHEN 'LoanReceivedReversal' THEN 'Loan corrections'
               WHEN 'ShiftVariance' THEN 'Cash over / short'
               WHEN 'CountVariance' THEN 'Cash over / short'
               WHEN 'CountVarianceReversal' THEN 'Cash over / short'
               ELSE 'Other' END::TEXT,
           r.createdat
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
      LEFT JOIN restaurantorderpayments p ON r.sourcetype = 'OrderPayment' AND p.orderpaymentid = r.sourceid
      LEFT JOIN restaurantexpenses e ON r.sourcetype = 'Expense' AND e.expenseid = r.sourceid;
$$;

CREATE FUNCTION sprestaurantcashflow_summary(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                             p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(moneyin NUMERIC, moneyout NUMERIC, netcashflow NUMERIC, ledgercash NUMERIC, offledgernet NUMERIC,
              cashathand NUMERIC, openingbalance NUMERIC, transfervolume NUMERIC, offledgerin NUMERIC,
              offledgerout NUMERIC, rowcount BIGINT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_in NUMERIC := 0; v_out NUMERIC := 0; v_n BIGINT := 0; v_open NUMERIC := 0;
        v_ledger NUMERIC := 0; v_trf NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount) FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0), COUNT(*)
      INTO v_in, v_out, v_n
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r;

    -- Opening cash = every ledger row before the period, plus opening balances
    -- of accounts created inside it (they are money that was already there).
    SELECT COALESCE(SUM(t.amount), 0) INTO v_open
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid
       AND ((p_fromdate IS NOT NULL AND t.txndate::TIMESTAMP < p_fromdate)
            OR (t.sourcetype = 'OpeningBalance'
                AND (p_fromdate IS NULL OR t.txndate::TIMESTAMP >= p_fromdate)
                AND (p_todate IS NULL OR t.txndate::TIMESTAMP <= p_todate)));

    SELECT COALESCE(SUM(t.amount), 0) INTO v_ledger
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND (p_todate IS NULL OR t.txndate::TIMESTAMP <= p_todate);

    SELECT COALESCE(SUM(-t.amount), 0) INTO v_trf
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('TransferOut', 'ShiftFloatOut', 'ShiftDropOut')
       AND (p_fromdate IS NULL OR t.txndate::TIMESTAMP >= p_fromdate)
       AND (p_todate IS NULL OR t.txndate::TIMESTAMP <= p_todate);

    RETURN QUERY SELECT ROUND(v_in, 2), ROUND(v_out, 2), ROUND(v_in - v_out, 2), ROUND(v_ledger, 2),
                        0::NUMERIC, ROUND(v_open + v_in - v_out, 2), ROUND(v_open, 2), ROUND(v_trf, 2),
                        0::NUMERIC, 0::NUMERIC, v_n;
END $$;

-- -----------------------------------------------------------------------------
-- 13. Profit & Loss
-- -----------------------------------------------------------------------------
-- Revenue = what was sold on completed orders, net of discounts and partial
-- refunds, plus service charge and delivery fees. Tax is excluded (owed to the
-- state). Gift-card sales are not revenue; the order they pay for is.
-- Every line is signed from profit's point of view: income +, cost -.

CREATE FUNCTION sprestaurant_report_pnl_lines(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(section TEXT, linekey TEXT, label TEXT, amount NUMERIC, sortorder INT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_sales NUMERIC; v_disc NUMERIC; v_sc NUMERIC; v_fee NUMERIC; v_ref NUMERIC; v_cogs NUMERIC;
        v_int NUMERIC; v_fees NUMERIC; v_var NUMERIC;
BEGIN
    SELECT COALESCE(SUM(o.subtotal), 0), COALESCE(SUM(o.discountamount), 0),
           COALESCE(SUM(o.servicechargeamount), 0), COALESCE(SUM(o.deliveryfee), 0)
      INTO v_sales, v_disc, v_sc, v_fee
      FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_ref
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.amount < 0 AND p.status = 'Completed' AND o.status = 'Completed'
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(oi.quantity * COALESCE((
               SELECT SUM(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * i.costperunit)
                 FROM restaurantrecipes r
                 JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
                WHERE r.menuitemid = oi.menuitemid AND r.farmid = oi.farmid), 0)), 0)
      INTO v_cogs
      FROM restaurantorderitems oi
      JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
     WHERE oi.farmid = p_farmid AND o.status = 'Completed' AND oi.status <> 'Cancelled'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(lp.interestamount), 0), COALESCE(SUM(lp.feeamount), 0)
      INTO v_int, v_fees
      FROM restaurantloanpayments lp
     WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_var
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
       AND t.txndate BETWEEN p_from AND p_to;

    RETURN QUERY VALUES
        ('Revenue', 'food_sales', 'Food & beverage sales', ROUND(v_sales, 2), 10),
        ('Revenue', 'discounts', 'Less: discounts & promotions', ROUND(-v_disc, 2), 11),
        ('Revenue', 'refunds', 'Less: partial refunds', ROUND(v_ref, 2), 12),
        ('Revenue', 'service_charge', 'Service charge', ROUND(v_sc, 2), 13),
        ('Revenue', 'delivery_fees', 'Delivery fees', ROUND(v_fee, 2), 14),
        ('CostOfSales', 'recipe_cost', 'Ingredients (recipe cost)', ROUND(-v_cogs, 2), 20);

    RETURN QUERY
    SELECT 'Expenses'::TEXT, 'expense:' || COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
           COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'), ROUND(-SUM(e.amount), 2), 30
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
     GROUP BY COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised')
     ORDER BY SUM(e.amount) DESC;

    RETURN QUERY VALUES
        ('Other', 'loan_interest', 'Loan interest', ROUND(-v_int, 2), 40),
        ('Other', 'loan_fees', 'Loan fees', ROUND(-v_fees, 2), 41),
        ('Other', 'cash_variance', 'Cash over / short', ROUND(v_var, 2), 42);
END $$;

CREATE FUNCTION sprestaurant_report_pnl_summary(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(revenue NUMERIC, cogs NUMERIC, gross_profit NUMERIC, gross_margin_pct NUMERIC,
              expenses_total NUMERIC, net_profit NUMERIC, net_margin_pct NUMERIC, food_cost_pct NUMERIC,
              tips_total NUMERIC, order_count BIGINT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_rev NUMERIC; v_cogs NUMERIC; v_exp NUMERIC; v_tips NUMERIC; v_ord BIGINT;
BEGIN
    SELECT COALESCE(SUM(l.amount) FILTER (WHERE l.section = 'Revenue'), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.section = 'CostOfSales'), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.section IN ('Expenses', 'Other')), 0)
      INTO v_rev, v_cogs, v_exp
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    SELECT COUNT(*) INTO v_ord FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    RETURN QUERY SELECT
        v_rev, v_cogs, v_rev - v_cogs,
        CASE WHEN v_rev > 0 THEN ROUND((v_rev - v_cogs) / v_rev * 100, 2) ELSE 0 END,
        v_exp, v_rev - v_cogs - v_exp,
        CASE WHEN v_rev > 0 THEN ROUND((v_rev - v_cogs - v_exp) / v_rev * 100, 2) ELSE 0 END,
        CASE WHEN v_rev > 0 THEN ROUND(v_cogs / v_rev * 100, 2) ELSE 0 END,
        v_tips, v_ord;
END $$;

-- The expense breakdown the P&L page and report list: categories plus loan
-- costs and cash over/short, so the rows add up to expenses_total.
CREATE FUNCTION sprestaurant_report_pnl_expenses(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(expense_category TEXT, entry_count BIGINT, expense_total NUMERIC, share_pct NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised') AS cat, COUNT(*) AS n, SUM(e.amount) AS tot
          FROM restaurantexpenses e
         WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
           AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
         GROUP BY 1
        UNION ALL
        SELECT 'Loan interest & fees', COUNT(*), SUM(lp.interestamount + lp.feeamount)
          FROM restaurantloanpayments lp
         WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to
        HAVING SUM(lp.interestamount + lp.feeamount) > 0
        UNION ALL
        SELECT 'Cash over / short', COUNT(*), -SUM(t.amount)
          FROM restaurantcashtransactions t
         WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
           AND t.txndate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(t.amount), 0) <> 0
    ), tot AS (SELECT COALESCE(SUM(x.tot), 0) AS allv FROM x)
    SELECT x.cat, x.n, ROUND(x.tot, 2),
           CASE WHEN tot.allv <> 0 THEN ROUND(x.tot / tot.allv * 100, 2) ELSE 0 END
      FROM x, tot
     ORDER BY x.tot DESC;
$$;

-- -----------------------------------------------------------------------------
-- 14. Daily closing
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_dailyclosing_preview(p_farmid TEXT, p_date DATE)
RETURNS TABLE(closingdate DATE, isclosed BOOLEAN, lastcloseddate DATE, ordercount BIGINT, netsales NUMERIC,
              discounts NUMERIC, taxcollected NUMERIC, servicecharge NUMERIC, deliveryfees NUMERIC,
              refunds NUMERIC, tips NUMERIC, takingscash NUMERIC, takingscard NUMERIC, takingsmobile NUMERIC,
              takingsgiftcard NUMERIC, takingsother NUMERIC, expenses NUMERIC, moneyin NUMERIC, moneyout NUMERIC,
              cashvariance NUMERIC, openshifts BIGINT, openorders BIGINT, unpaidorders BIGINT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_last DATE; v_closed BOOLEAN;
BEGIN
    SELECT MAX(d.closingdate) INTO v_last FROM restaurantdailyclosings d WHERE d.farmid = p_farmid AND d.status = 'Closed';
    v_closed := v_last IS NOT NULL AND p_date <= v_last;

    RETURN QUERY
    WITH ord AS (
        SELECT COUNT(*) AS n,
               COALESCE(SUM(o.subtotal - o.discountamount), 0) AS net,
               COALESCE(SUM(o.discountamount), 0) AS disc,
               COALESCE(SUM(o.taxamount), 0) AS tax,
               COALESCE(SUM(o.servicechargeamount), 0) AS sc,
               COALESCE(SUM(o.deliveryfee), 0) AS fee
          FROM restaurantorders o
         WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE = p_date
    ), pay AS (
        SELECT COALESCE(SUM(-p.amount) FILTER (WHERE p.amount < 0), 0) AS ref,
               COALESCE(SUM(p.tipamount) FILTER (WHERE p.amount > 0), 0) AS tip,
               COALESCE(SUM(p.amount) FILTER (WHERE p.amount > 0 AND lower(p.paymentmethod) = 'cash'), 0) AS cash,
               COALESCE(SUM(p.amount) FILTER (WHERE p.amount > 0 AND lower(p.paymentmethod) = 'card'), 0) AS card,
               COALESCE(SUM(p.amount) FILTER (WHERE p.amount > 0 AND lower(p.paymentmethod) = 'mobilemoney'), 0) AS mobile,
               COALESCE(SUM(p.amount) FILTER (WHERE p.amount > 0 AND lower(p.paymentmethod) = 'giftcard'), 0) AS gift,
               COALESCE(SUM(p.amount) FILTER (WHERE p.amount > 0 AND lower(p.paymentmethod) NOT IN ('cash','card','mobilemoney','giftcard')), 0) AS other
          FROM restaurantorderpayments p
         WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.createdat::DATE = p_date
    ), exp AS (
        SELECT COALESCE(SUM(e.amount), 0) AS tot FROM restaurantexpenses e
         WHERE e.farmid = p_farmid AND e.expensedate = p_date
           AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
    ), led AS (
        SELECT COALESCE(SUM(r.amount) FILTER (WHERE r.amount > 0), 0) AS mi,
               COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0) AS mo
          FROM sprestaurantcashflow_rows(p_farmid, p_date::TIMESTAMP, p_date::TIMESTAMP) r
    ), var AS (
        SELECT COALESCE(SUM(t.amount), 0) AS v FROM restaurantcashtransactions t
         WHERE t.farmid = p_farmid AND t.txndate = p_date
           AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
    )
    SELECT p_date, v_closed, v_last, ord.n, ord.net, ord.disc, ord.tax, ord.sc, ord.fee, pay.ref, pay.tip,
           pay.cash, pay.card, pay.mobile, pay.gift, pay.other, exp.tot, led.mi, led.mo, var.v,
           (SELECT COUNT(*) FROM restaurantcashshifts s WHERE s.farmid = p_farmid AND s.status = 'Open'
                                                        AND s.openedat::DATE <= p_date),
           (SELECT COUNT(*) FROM restaurantorders o WHERE o.farmid = p_farmid AND o.createdat::DATE = p_date
                                                   AND o.status NOT IN ('Completed', 'Cancelled', 'Refunded')),
           (SELECT COUNT(*) FROM restaurantorders o WHERE o.farmid = p_farmid AND o.createdat::DATE = p_date
                                                   AND o.status NOT IN ('Cancelled', 'Refunded')
                                                   AND o.paidamount < o.totalamount)
      FROM ord, pay, exp, led, var;
END $$;

CREATE FUNCTION sprestaurant_dailyclosing_close(p_farmid TEXT, p_date DATE, p_notes TEXT DEFAULT NULL,
                                                p_closedby TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_pv RECORD; v_id INT; v_last DATE; v_shift TEXT;
BEGIN
    IF p_date IS NULL THEN RAISE EXCEPTION 'Choose the day to close.'; END IF;
    IF p_date > CURRENT_DATE THEN RAISE EXCEPTION 'You cannot close a day that has not happened yet.'; END IF;
    -- Serialise closings for this restaurant.
    PERFORM pg_advisory_xact_lock(hashtext('restaurantdailyclosing:' || p_farmid));

    SELECT MAX(d.closingdate) INTO v_last FROM restaurantdailyclosings d WHERE d.farmid = p_farmid AND d.status = 'Closed';
    IF v_last IS NOT NULL AND p_date <= v_last THEN
        RAISE EXCEPTION 'The books are already closed up to %.', to_char(v_last, 'DD Mon YYYY');
    END IF;
    SELECT s.shiftnumber INTO v_shift FROM restaurantcashshifts s
     WHERE s.farmid = p_farmid AND s.status = 'Open' AND s.openedat::DATE <= p_date
     ORDER BY s.openedat LIMIT 1;
    IF v_shift IS NOT NULL THEN
        RAISE EXCEPTION 'Till shift % is still open. Close it before closing the day.', v_shift;
    END IF;

    SELECT * INTO v_pv FROM sprestaurant_dailyclosing_preview(p_farmid, p_date);

    INSERT INTO restaurantdailyclosings (farmid, closingdate, status, ordercount, netsales, taxcollected,
                                         moneyin, moneyout, cashvariance, notes, closedby, closedat)
    VALUES (p_farmid, p_date, 'Closed', v_pv.ordercount, v_pv.netsales, v_pv.taxcollected, v_pv.moneyin,
            v_pv.moneyout, v_pv.cashvariance, p_notes, p_closedby, NOW())
    ON CONFLICT (farmid, closingdate) DO UPDATE
       SET status = 'Closed', ordercount = EXCLUDED.ordercount, netsales = EXCLUDED.netsales,
           taxcollected = EXCLUDED.taxcollected, moneyin = EXCLUDED.moneyin, moneyout = EXCLUDED.moneyout,
           cashvariance = EXCLUDED.cashvariance, notes = EXCLUDED.notes, closedby = EXCLUDED.closedby,
           closedat = NOW()
    RETURNING closingid INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_dailyclosing_reopen(p_farmid TEXT, p_date DATE, p_reason TEXT,
                                                 p_reopenedby TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_last DATE;
BEGIN
    IF btrim(COALESCE(p_reason, '')) = '' THEN RAISE EXCEPTION 'Give a reason for reopening the day.'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('restaurantdailyclosing:' || p_farmid));
    SELECT MAX(d.closingdate) INTO v_last FROM restaurantdailyclosings d WHERE d.farmid = p_farmid AND d.status = 'Closed';
    IF v_last IS NULL OR v_last <> p_date THEN
        RAISE EXCEPTION 'Only the most recently closed day (%) can be reopened.',
            COALESCE(to_char(v_last, 'DD Mon YYYY'), 'none');
    END IF;
    UPDATE restaurantdailyclosings
       SET status = 'Reopened', reopenedby = p_reopenedby, reopenedat = NOW(), reopenreason = btrim(p_reason)
     WHERE farmid = p_farmid AND closingdate = p_date;
END $$;

CREATE FUNCTION sprestaurant_dailyclosing_list(p_farmid TEXT, p_limit INT DEFAULT 60)
RETURNS TABLE(closingid INT, closingdate DATE, status TEXT, ordercount INT, netsales NUMERIC,
              taxcollected NUMERIC, moneyin NUMERIC, moneyout NUMERIC, cashvariance NUMERIC, notes TEXT,
              closedby TEXT, closedat TIMESTAMP, reopenedby TEXT, reopenedat TIMESTAMP, reopenreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT d.closingid, d.closingdate, d.status, d.ordercount, d.netsales, d.taxcollected, d.moneyin,
           d.moneyout, d.cashvariance, d.notes, d.closedby, d.closedat, d.reopenedby, d.reopenedat, d.reopenreason
      FROM restaurantdailyclosings d
     WHERE d.farmid = p_farmid
     ORDER BY d.closingdate DESC
     LIMIT COALESCE(p_limit, 60);
$$;

-- -----------------------------------------------------------------------------
-- 15. Backfill: carry existing payments and expenses into the ledger so the
--     Cash Flow page keeps its history. Posted to the default accounts by
--     method, on the day the money moved. Idempotent (skips posted sources).
-- -----------------------------------------------------------------------------
DO $$
DECLARE r RECORD; v_acc INT; v_n INT := 0;
BEGIN
    FOR r IN
        SELECT p.orderpaymentid, p.farmid, p.paymentmethod, p.amount, p.tipamount, p.createdat, o.ordernumber
          FROM restaurantorderpayments p
          JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
         WHERE p.status = 'Completed' AND p.amount + COALESCE(p.tipamount, 0) <> 0
           AND o.status <> 'Cancelled'
           AND fnrestaurant_is_cash_method(p.paymentmethod)
           AND NOT EXISTS (SELECT 1 FROM restaurantcashtransactions t
                            WHERE t.sourcetype IN ('OrderPayment', 'OrderRefund') AND t.sourceid = p.orderpaymentid)
         ORDER BY p.orderpaymentid
    LOOP
        v_acc := fnrestaurant_method_account(r.farmid, r.paymentmethod);
        INSERT INTO restaurantcashtransactions (farmid, cashaccountid, txndate, txntype, amount, sourcetype, sourceid,
                                                description, createdby, createdat)
        VALUES (r.farmid, v_acc, COALESCE(r.createdat::DATE, CURRENT_DATE),
                CASE WHEN r.amount + COALESCE(r.tipamount, 0) > 0 THEN 'CashIn' ELSE 'CashOut' END,
                ROUND(r.amount + COALESCE(r.tipamount, 0), 2),
                CASE WHEN r.amount < 0 THEN 'OrderRefund' ELSE 'OrderPayment' END, r.orderpaymentid,
                'Order ' || r.ordernumber || ' (' || COALESCE(r.paymentmethod, 'Cash') || ') - carried over',
                'Migration 323', COALESCE(r.createdat, NOW()));
        v_n := v_n + 1;
    END LOOP;

    FOR r IN
        SELECT e.expenseid, e.farmid, e.paymentmethod, e.amount, e.expensedate, e.description, e.createdat
          FROM restaurantexpenses e
         WHERE COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft') AND e.amount > 0
           AND fnrestaurant_is_cash_method(e.paymentmethod)
           AND NOT EXISTS (SELECT 1 FROM restaurantcashtransactions t
                            WHERE t.sourcetype = 'Expense' AND t.sourceid = e.expenseid)
         ORDER BY e.expenseid
    LOOP
        v_acc := fnrestaurant_method_account(r.farmid, r.paymentmethod);
        INSERT INTO restaurantcashtransactions (farmid, cashaccountid, txndate, txntype, amount, sourcetype, sourceid,
                                                description, createdby, createdat)
        VALUES (r.farmid, v_acc, r.expensedate, 'CashOut', -ROUND(r.amount, 2), 'Expense', r.expenseid,
                r.description || ' - carried over', 'Migration 323', COALESCE(r.createdat, NOW()));
        v_n := v_n + 1;
    END LOOP;

    -- Bring every cached balance in line with its ledger.
    UPDATE restaurantcashaccounts a
       SET currentbalance = COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                                       WHERE t.cashaccountid = a.cashaccountid), 0);
    RAISE NOTICE 'Migration 323 backfill: % ledger rows posted.', v_n;
END $$;
