-- =============================================================================
-- 333  Reopening a flock reverses its closeout sales and their money
-- =============================================================================
--
-- 332 left a closeout's sales standing when the flock was reopened ("they are
-- real sales"), and only unlocked them. In practice a reopen almost always
-- means the close was wrong, and leaving the sale behind left its revenue, its
-- cash and its receivable on the books for birds that are now back in the
-- house. So a reopen now undoes the sale side too, by default.
--
-- HOW, using only the paths that already exist -- no new money logic:
--
--   1. every Posted payment on the sale is reversed with
--      sppoultrycustomerpayment_reverse, the function behind Reverse on
--      Payments Received. The payment rows stay, stamped Reversed with the
--      reason; the allocation is reversed; the sale is recomputed and the
--      payment's CashIn is taken back off the cash account.
--   2. the sale's own residual cash is cleared with sppoultrysalecash_sync(0),
--      exactly what SaleService.Delete does first.
--   3. the sale is removed with spsale_delete, which reverses its 'Bird Sale'
--      ledger row append-only -- the birds come back.
--
-- Order matters: SaleService.Delete alone would leave a payment's
-- 'CustomerPayment' cash row behind (it only clears sourcetype 'Sale'), so the
-- money would stay in the account. Payments are therefore reversed FIRST.
--
-- REFUSED, not guessed: a payment group that ALSO pays another sale (one
-- customer payment allocated across several invoices). Reversing the group
-- would un-pay the other sale as well. The reopen stops and says so; the user
-- reverses that payment on Payments Received, or reopens keeping the sales.
--
-- p_reversesales = false keeps 332's behaviour (sales stand, just unlocked),
-- for the case where the birds really were sold and the flock is reopened only
-- to correct something else.
--
-- The disposition keeps a snapshot of the sale (total, customer) and when it
-- was reversed, so the closeout history still reads correctly after the sale
-- row is gone.
--
-- EFFECT ON TODAY'S NUMBERS: none until a flock is reopened.
-- =============================================================================

BEGIN;

ALTER TABLE flockcloseoutdispositions ADD COLUMN IF NOT EXISTS saletotalamount  numeric(14,2);
ALTER TABLE flockcloseoutdispositions ADD COLUMN IF NOT EXISTS salecustomername text;
ALTER TABLE flockcloseoutdispositions ADD COLUMN IF NOT EXISTS salereversedat   timestamp without time zone;

-- Snapshot the sales already linked, so history is complete for them too.
UPDATE flockcloseoutdispositions x
SET    saletotalamount  = s.totalamount,
       salecustomername = s.customername
FROM   sale s
WHERE  s.saleid = x.saleid AND s.farmid = x.farmid
  AND  x.saletotalamount IS NULL;

-- A defaulted parameter is being added, so the old signature must go first or
-- every named call becomes ambiguous (postgres-sp-gotchas #3). By name.
DO $d$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig
             FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE  n.nspname = 'public' AND p.proname = 'spflock_reopen'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$d$;

CREATE FUNCTION spflock_reopen(
    p_farmid       text,
    p_flockid      integer,
    p_reason       text,
    p_reopenedby   text,
    p_reversesales boolean DEFAULT TRUE
)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_flock       flock%ROWTYPE;
    v_closeout    flockcloseouts%ROWTYPE;
    v_disp        record;
    v_group       uuid;
    v_shared      record;
    v_today       date;
    v_hascloseout boolean;
    v_note        text;
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'A reason is required to reopen a flock.' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_flock FROM flock f
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flock not found on this farm.' USING ERRCODE = 'P0002';
    END IF;
    IF v_flock.closeddate IS NULL THEN
        RAISE EXCEPTION 'Flock "%" is not closed.', v_flock.name USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_closeout FROM flockcloseouts c
    WHERE  c.flockid = p_flockid AND c.farmid = p_farmid AND c.reopenedat IS NULL
    FOR UPDATE;
    -- Captured now: every PERFORM below resets FOUND.
    v_hascloseout := FOUND;

    v_today := fncompany_businessdate(p_farmid);
    v_note  := 'Flock reopened: ' || btrim(p_reason);

    -- Refuse BEFORE changing anything: a payment that also pays another sale.
    IF v_hascloseout AND p_reversesales THEN
        SELECT pp.saleid, pp.paymentnumber, pp.paymentgroupid INTO v_shared
        FROM   flockcloseoutdispositions x
        JOIN   poultrypayments pp
               ON pp.saleid = x.saleid AND pp.farmid = p_farmid
              AND COALESCE(pp.status, 'Posted') = 'Posted'
        WHERE  x.closeoutid = v_closeout.closeoutid
          AND  x.disposition = 'Sale' AND x.reversedat IS NULL
          AND  EXISTS (SELECT 1 FROM poultrypayments o
                       WHERE o.paymentgroupid = pp.paymentgroupid AND o.farmid = p_farmid
                         AND o.saleid IS DISTINCT FROM pp.saleid
                         AND COALESCE(o.status, 'Posted') = 'Posted')
        LIMIT  1;
        IF FOUND THEN
            RAISE EXCEPTION 'Payment % on sale #% also pays other sales, so it cannot be reversed with this flock. Reverse it on Payments Received first, or reopen the flock keeping its sales.',
                COALESCE(v_shared.paymentnumber, v_shared.paymentgroupid::text), v_shared.saleid
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    PERFORM set_config('app.flock_closeout', 'on', true);

    IF v_hascloseout THEN
        FOR v_disp IN
            SELECT x.dispositionid, x.disposition, x.saleid
            FROM   flockcloseoutdispositions x
            WHERE  x.closeoutid = v_closeout.closeoutid AND x.reversedat IS NULL
        LOOP
            -- Posting quantity 0 makes the append-only sync write the exact
            -- opposite of what the closeout posted.
            IF v_disp.disposition = 'Cull' THEN
                PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Cull', 0, v_disp.dispositionid,
                                                     v_today, NULL, p_reopenedby);
            ELSIF v_disp.disposition = 'Transfer' THEN
                PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Transfer Out', 0, v_disp.dispositionid,
                                                     v_today, NULL, p_reopenedby);
            ELSIF v_disp.disposition = 'Sale' AND p_reversesales
                  AND EXISTS (SELECT 1 FROM sale s WHERE s.saleid = v_disp.saleid AND s.farmid = p_farmid) THEN

                -- Keep what the sale was, for the history, before it goes.
                UPDATE flockcloseoutdispositions x
                SET    saletotalamount  = s.totalamount,
                       salecustomername = s.customername
                FROM   sale s
                WHERE  x.dispositionid = v_disp.dispositionid
                  AND  s.saleid = v_disp.saleid AND s.farmid = p_farmid;

                -- 1. The money received: Reverse, as on Payments Received.
                FOR v_group IN
                    SELECT DISTINCT pp.paymentgroupid
                    FROM   poultrypayments pp
                    WHERE  pp.saleid = v_disp.saleid AND pp.farmid = p_farmid
                      AND  COALESCE(pp.status, 'Posted') = 'Posted'
                      AND  pp.paymentgroupid IS NOT NULL
                LOOP
                    PERFORM sppoultrycustomerpayment_reverse(p_farmid, v_group, v_note, p_reopenedby);
                END LOOP;

                -- 2. The sale's own residual cash, as SaleService.Delete does.
                PERFORM sppoultrysalecash_sync(p_farmid, v_disp.saleid, NULL, 0, FALSE, NULL, p_reopenedby);

                -- 3. The sale, and with it the 'Bird Sale' ledger row (reversed, not deleted).
                PERFORM spsale_delete(p_farmid, p_reopenedby, v_disp.saleid);

                UPDATE flockcloseoutdispositions x
                SET    salereversedat = (now() AT TIME ZONE 'utc')
                WHERE  x.dispositionid = v_disp.dispositionid;
            END IF;
        END LOOP;

        UPDATE flockcloseoutdispositions x
        SET    reversedat = (now() AT TIME ZONE 'utc')
        WHERE  x.closeoutid = v_closeout.closeoutid AND x.reversedat IS NULL;

        UPDATE flockcloseouts c
        SET    reopenedat   = (now() AT TIME ZONE 'utc'),
               reopenedby   = p_reopenedby,
               reopenreason = btrim(p_reason)
        WHERE  c.closeoutid = v_closeout.closeoutid;
    END IF;

    UPDATE flock f
    SET    active             = COALESCE(v_closeout.wasactive, TRUE),
           inactivationreason = CASE WHEN COALESCE(v_closeout.wasactive, TRUE) THEN NULL
                                     ELSE 'other' END,
           otherreason        = CASE WHEN COALESCE(v_closeout.wasactive, TRUE) THEN NULL
                                     ELSE 'Reopened after closeout: ' || btrim(p_reason) END,
           closeddate         = NULL,
           closedat           = NULL,
           closedby           = NULL,
           closereason        = NULL,
           closeoutid         = NULL,
           updatedat          = (now() AT TIME ZONE 'utc')
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;

    PERFORM set_config('app.flock_closeout', 'off', true);

    RETURN v_closeout.closeoutid;
END
$f$;

-- History reads the snapshot once the sale row is gone. Same signature.
CREATE OR REPLACE FUNCTION spflock_closeouthistory(p_farmid text, p_flockid integer)
RETURNS TABLE (
    closeoutid integer, flockid integer, closeddate date, reason text, notes text,
    closedby text, closedat timestamp without time zone, houseid integer,
    hasopeningposition boolean, historyknown boolean, originallyplaced integer,
    openingmortality integer, openingsold integer, openingculled integer,
    openingtransferred integer, openingother integer, openinglivebirds integer,
    recordedmortality integer, correction integer, lastcountedbirds integer,
    lastcountdate date, soldbeforecloseout integer, livebirdsatcloseout integer,
    disposedsold integer, disposedculled integer, disposedtransferred integer,
    reopenedat timestamp without time zone, reopenedby text, reopenreason text,
    dispositions jsonb
)
LANGUAGE sql
STABLE
AS $f$
    SELECT c.closeoutid, c.flockid, c.closeddate, c.reason, c.notes,
           c.closedby, c.closedat, c.houseid,
           c.hasopeningposition, c.historyknown, c.originallyplaced,
           c.openingmortality, c.openingsold, c.openingculled,
           c.openingtransferred, c.openingother, c.openinglivebirds,
           c.recordedmortality, c.correction, c.lastcountedbirds,
           c.lastcountdate, c.soldbeforecloseout, c.livebirdsatcloseout,
           c.disposedsold, c.disposedculled, c.disposedtransferred,
           c.reopenedat, c.reopenedby, c.reopenreason,
           COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                          'dispositionId',  x.dispositionid,
                          'disposition',    x.disposition,
                          'quantity',       x.quantity,
                          'saleId',         x.saleid,
                          'destination',    x.destination,
                          'notes',          x.notes,
                          'reversedAt',     x.reversedat,
                          'saleReversedAt', x.salereversedat,
                          'totalAmount',    COALESCE(s.totalamount, x.saletotalamount),
                          'customerName',   COALESCE(s.customername, x.salecustomername),
                          'paid',           s.paid)
                        ORDER BY x.dispositionid)
               FROM   flockcloseoutdispositions x
               LEFT   JOIN sale s ON s.saleid = x.saleid AND s.farmid = x.farmid
               WHERE  x.closeoutid = c.closeoutid), '[]'::jsonb)
    FROM   flockcloseouts c
    WHERE  c.farmid = p_farmid AND c.flockid = p_flockid
    ORDER  BY c.closeoutid DESC;
$f$;

COMMIT;
