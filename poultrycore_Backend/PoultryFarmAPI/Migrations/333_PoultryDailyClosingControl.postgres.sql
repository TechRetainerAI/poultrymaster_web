-- =============================================================================
-- 333_PoultryDailyClosingControl.postgres.sql
--
-- Purpose
-- -------
-- Turn Poultry Daily Closing from a list of totals into an owner-control step:
-- "is today's farm activity complete, internally consistent, and ready to be
-- closed?" -- and make closing and reopening a day auditable.
--
-- THIS EXTENDS THE EXISTING CLOSING; IT DOES NOT ADD A SECOND ONE
-- ===============================================================
-- poultrydailyclosings (128 / 148 / 152, ported to Postgres outside this repo)
-- stays the one row per (farm, date), and its Draft -> Submitted -> Approved |
-- Rejected workflow keeps working. A day is CLOSED when its row is Approved;
-- "Close Business Day" is the owner's one-step way there, and the existing
-- Approve now goes through the same guarded close, so there is exactly one
-- definition of what closing a day checks and records.
--
-- WHAT WAS WRONG WITH THE EXISTING FLOW, AND WHAT THIS CHANGES
-- ============================================================
--   * Reopen took no reason and NULLed approvedby/approvedat -- the fact that
--     the day had ever been closed disappeared. It now requires a reason and
--     every close/reopen is written to poultrydailyclosingevents, which is
--     append-only (a trigger refuses UPDATE and DELETE).
--   * Approve stored four numbers, from the pre-151 sources (computefordate
--     still reads poultryproductionbatches), while every money figure on an
--     Approved row was recomputed live -- so "the state at closing" could not
--     be shown at all. Closing now stores the whole workspace as a jsonb
--     snapshot; the live workspace is still available beside it, which is what
--     lets the page show "State At Closing" vs "Current Corrected State".
--   * Recreate reset an Approved row to Draft with no trace. It now refuses a
--     closed day (reopen first, with a reason). Delete refuses a day that has
--     ever been closed, so its history cannot be orphaned by removing the row.
--   * Submit only accepted Draft, so the UI's "Resubmit" after a rejection
--     always failed. It now accepts Rejected too.
--   * The closing REPORTS (getall / getbyid, read by the daily closing report,
--     the closing report in the catalogue and both daily summaries) recomputed
--     every money figure live even for an Approved day, so a sale entered after
--     closing silently rewrote a closed day on every report. A close now also
--     freezes the legacy totals row (fnpoultrydailyclosing_livetotals, exactly
--     what those reports read) inside the snapshot, and getall / getbyid return
--     it for a closed day. Open days are unchanged: still live. Days approved
--     before this migration have no snapshot and also stay live.
--
-- WHERE EACH FIGURE COMES FROM (nothing is re-derived differently)
-- =================================================================
--   Production  productionrecords for the date (as the closing live totals and
--               the daily egg report read it); damaged = broken + meaty + soft
--               + lost, as sppoultryreport_dailyeggproduction defines it.
--               Completeness = sppoultryactivity_productioncompletenesssummary
--               (332) -- the Missing Activity Detector, not a second engine.
--   Sales       sale.totalamount by saledate is REVENUE (the P&L rule, 272).
--               Cash vs credit by sale.paid (default TRUE). Payments received =
--               Posted poultrypayments by paymentdate -- the cash-flow Receipt
--               arm. Payments are never added to revenue.
--   Cash        sppoultrycashflow_summary for [date, date+1) -- the Cash Flow
--               report's own function. Expected-vs-actual comes ONLY from
--               Posted poultrycashreconciliations dated that day (system vs
--               counted, per account): the only place both numbers are real.
--   Expenses    expense by expensedate. paymentmethod = 'NonCash' is non-cash
--               (216 / 266 / 271); otherwise COALESCE(amountpaid, amount) is
--               the paid part and the rest is credit -- the 238 rule behind the
--               generated paymentstatus column.
--   Inventory   poultryrawmaterialitems: currentquantity < 0, and <=
--               minimumstockalert (the same test as islowstock, 261). Feed days
--               remaining = current stock / average daily consumption over the
--               7 days ending on the date, from productionrecordfeeds (147/148).
--   Outstanding unposted productionbatchrecords, Draft driver returns and
--               Loaded vehicle loadings with no approved return for the date.
--
-- BLOCKING vs WARNING IS POLICY
-- =============================
-- poultrydailyclosingpolicy holds one row per farm; a farm with no row gets the
-- defaults below. Only these checks can block, and each can be downgraded to a
-- warning: missing production, unposted batch production, impossible bird
-- counts, pending driver returns, negative stock, cash difference. Everything
-- else (low feed, unusual mortality, credit sales, an unfinished day, an
-- unclosed previous day) is only ever a warning.
--
-- NOT A LOCK
-- ==========
-- Closing does not stop anyone recording against the day. Nothing in this
-- schema refused back-dated writes before, and adding a hard lock to every
-- write path is a separate decision (the restaurant module's
-- fnrestaurant_assert_day_open is the pattern if it is wanted). Instead a
-- correction after closing is VISIBLE: the stored snapshot does not move, the
-- live workspace does, and the page shows the difference.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. Existing rows keep their status; the new
-- columns are NULL/0 until a day is next closed.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Closing row: what was closed, when, by whom, and the state at that moment.
-- -----------------------------------------------------------------------------
ALTER TABLE public.poultrydailyclosings
    ADD COLUMN IF NOT EXISTS closedatutc        timestamptz,
    ADD COLUMN IF NOT EXISTS closedby           text,
    ADD COLUMN IF NOT EXISTS closingsnapshot    jsonb,
    ADD COLUMN IF NOT EXISTS closeversion       integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS warningsatclose    integer,
    ADD COLUMN IF NOT EXISTS lastreopenedatutc  timestamptz,
    ADD COLUMN IF NOT EXISTS lastreopenedby     text,
    ADD COLUMN IF NOT EXISTS lastreopenreason   text;

-- -----------------------------------------------------------------------------
-- 2. History. Append-only: every close keeps its own snapshot, so reopening and
--    re-closing never overwrites what the day looked like the first time.
--    No FK to the closing row on purpose -- history must outlive the row.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultrydailyclosingevents (
    eventid                bigserial   PRIMARY KEY,
    poultrydailyclosingid  integer     NOT NULL,
    farmid                 text        NOT NULL,
    closingdate            date        NOT NULL,
    eventtype              text        NOT NULL
        CONSTRAINT ck_poultryclosingevent_type
        CHECK (eventtype IN ('Created', 'Submitted', 'Rejected', 'Closed', 'Reopened', 'Recreated', 'Deleted')),
    fromstatus             text,
    tostatus               text,
    actor                  text,
    reason                 text,
    closeversion           integer,
    warningcount           integer,
    blockingcount          integer,
    snapshot               jsonb,
    occurredatutc          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_poultryclosingevents_farm_date
    ON public.poultrydailyclosingevents (farmid, closingdate, eventid);

CREATE OR REPLACE FUNCTION public.trg_poultrydailyclosingevents_appendonly()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE EXCEPTION 'Daily closing history is append-only; % is not allowed.', TG_OP;
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultrydailyclosingevents_appendonly ON public.poultrydailyclosingevents;
CREATE TRIGGER trg_poultrydailyclosingevents_appendonly
    BEFORE UPDATE OR DELETE ON public.poultrydailyclosingevents
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultrydailyclosingevents_appendonly();

-- -----------------------------------------------------------------------------
-- 3. Policy: which checks block. One row per farm, defaults when absent.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultrydailyclosingpolicy (
    farmid                   text PRIMARY KEY,
    missingproduction        text NOT NULL DEFAULT 'Blocking',
    unpostedproduction       text NOT NULL DEFAULT 'Blocking',
    impossiblebirdcounts     text NOT NULL DEFAULT 'Blocking',
    pendingdriverreturns     text NOT NULL DEFAULT 'Warning',
    negativestock            text NOT NULL DEFAULT 'Warning',
    cashdifference           text NOT NULL DEFAULT 'Warning',
    cashdifferencetolerance  numeric(18,2) NOT NULL DEFAULT 0,
    requirecashcount         boolean NOT NULL DEFAULT FALSE,
    lowfeeddays              numeric(8,2)  NOT NULL DEFAULT 3,
    unusualmortalitypct      numeric(8,3)  NOT NULL DEFAULT 1,
    updatedby                text,
    updatedatutc             timestamptz,
    CONSTRAINT ck_poultryclosingpolicy_levels CHECK (
        missingproduction    IN ('Blocking', 'Warning') AND
        unpostedproduction   IN ('Blocking', 'Warning') AND
        impossiblebirdcounts IN ('Blocking', 'Warning') AND
        pendingdriverreturns IN ('Blocking', 'Warning') AND
        negativestock        IN ('Blocking', 'Warning') AND
        cashdifference       IN ('Blocking', 'Warning')),
    CONSTRAINT ck_poultryclosingpolicy_numbers CHECK (
        cashdifferencetolerance >= 0 AND lowfeeddays >= 0 AND unusualmortalitypct >= 0)
);

DROP FUNCTION IF EXISTS public.sppoultrydailyclosingpolicy_get(text);
CREATE FUNCTION public.sppoultrydailyclosingpolicy_get(p_farmid text)
RETURNS TABLE(
    farmid text, missingproduction text, unpostedproduction text, impossiblebirdcounts text,
    pendingdriverreturns text, negativestock text, cashdifference text,
    cashdifferencetolerance numeric, requirecashcount boolean, lowfeeddays numeric,
    unusualmortalitypct numeric, iscustomised boolean, updatedby text, updatedatutc timestamptz)
LANGUAGE sql
STABLE
AS $function$
    SELECT p_farmid,
           COALESCE(p.missingproduction,    'Blocking'),
           COALESCE(p.unpostedproduction,   'Blocking'),
           COALESCE(p.impossiblebirdcounts, 'Blocking'),
           COALESCE(p.pendingdriverreturns, 'Warning'),
           COALESCE(p.negativestock,        'Warning'),
           COALESCE(p.cashdifference,       'Warning'),
           COALESCE(p.cashdifferencetolerance, 0),
           COALESCE(p.requirecashcount, FALSE),
           COALESCE(p.lowfeeddays, 3),
           COALESCE(p.unusualmortalitypct, 1),
           p.farmid IS NOT NULL,
           p.updatedby,
           p.updatedatutc
    FROM   (SELECT 1) one
    LEFT   JOIN public.poultrydailyclosingpolicy p ON p.farmid = p_farmid;
$function$;

DROP FUNCTION IF EXISTS public.sppoultrydailyclosingpolicy_set(text, text, text, text, text, text, text, numeric, boolean, numeric, numeric, text);
CREATE FUNCTION public.sppoultrydailyclosingpolicy_set(
    p_farmid text, p_missingproduction text, p_unpostedproduction text, p_impossiblebirdcounts text,
    p_pendingdriverreturns text, p_negativestock text, p_cashdifference text,
    p_cashdifferencetolerance numeric, p_requirecashcount boolean, p_lowfeeddays numeric,
    p_unusualmortalitypct numeric, p_updatedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;
    -- The CHECK constraints give the precise refusal for a bad level or number.
    INSERT INTO public.poultrydailyclosingpolicy AS t (
        farmid, missingproduction, unpostedproduction, impossiblebirdcounts, pendingdriverreturns,
        negativestock, cashdifference, cashdifferencetolerance, requirecashcount, lowfeeddays,
        unusualmortalitypct, updatedby, updatedatutc)
    VALUES (p_farmid, p_missingproduction, p_unpostedproduction, p_impossiblebirdcounts, p_pendingdriverreturns,
            p_negativestock, p_cashdifference, p_cashdifferencetolerance, p_requirecashcount, p_lowfeeddays,
            p_unusualmortalitypct, p_updatedby, now())
    ON CONFLICT (farmid) DO UPDATE SET
        missingproduction       = EXCLUDED.missingproduction,
        unpostedproduction      = EXCLUDED.unpostedproduction,
        impossiblebirdcounts    = EXCLUDED.impossiblebirdcounts,
        pendingdriverreturns    = EXCLUDED.pendingdriverreturns,
        negativestock           = EXCLUDED.negativestock,
        cashdifference          = EXCLUDED.cashdifference,
        cashdifferencetolerance = EXCLUDED.cashdifferencetolerance,
        requirecashcount        = EXCLUDED.requirecashcount,
        lowfeeddays             = EXCLUDED.lowfeeddays,
        unusualmortalitypct     = EXCLUDED.unusualmortalitypct,
        updatedby               = EXCLUDED.updatedby,
        updatedatutc            = EXCLUDED.updatedatutc;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. The workspace: every section and the checklist for one business date, as
--    one jsonb document. The SAME document is what a close stores, so "state
--    at closing" and "current state" always have the same shape and can be
--    compared field by field.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryclosing_money(p_symbol text, p_amount numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT btrim(COALESCE(p_symbol, '') || ' ' || to_char(COALESCE(p_amount, 0), 'FM999,999,999,990.00'));
$function$;

DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_workspace(text, date, timestamptz);
CREATE FUNCTION public.sppoultrydailyclosing_workspace(
    p_farmid       text,
    p_businessdate date        DEFAULT NULL,
    p_asof         timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_tz        text      := public.fncompany_timezone(p_farmid);
    v_local     timestamp := p_asof AT TIME ZONE public.fncompany_timezone(p_farmid);
    v_today     date;
    v_date      date;
    v_farmuuid  uuid;
    v_sym       text;
    pol         record;
    comp        record;
    pr          record;
    sl          record;
    pay         record;
    cf          record;
    rec         record;
    ex          record;
    v_unposted       jsonb;
    v_impossible     jsonb;
    v_mortality      jsonb;
    v_negative       jsonb;
    v_lowstock       jsonb;
    v_lowfeed        jsonb;
    v_driverreturns  integer;
    v_openloadings   integer;
    v_prevclosed     boolean;
    v_usesclosing    boolean;
    v_checks         jsonb := '[]'::jsonb;
    v_item           jsonb;
    v_level          text;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;

    v_today := v_local::date;
    v_date  := COALESCE(p_businessdate, v_today);
    IF v_date > v_today THEN
        RAISE EXCEPTION 'Business date % is in the future for this company (today is %).', v_date, v_today;
    END IF;

    -- expense.farmid is uuid; everything else is text. Same guard the closing
    -- live totals use, so a non-uuid id simply matches no expense.
    v_farmuuid := CASE WHEN p_farmid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                       THEN p_farmid::uuid END;
    SELECT NULLIF(btrim(f.currencysymbol), '') INTO v_sym
    FROM farms f WHERE lower(f.farmid::text) = lower(p_farmid) OR f.id = p_farmid LIMIT 1;

    SELECT * INTO pol FROM public.sppoultrydailyclosingpolicy_get(p_farmid);

    -- ---- Production -------------------------------------------------------
    SELECT * INTO comp FROM public.sppoultryactivity_productioncompletenesssummary(p_farmid, v_date, p_asof);

    SELECT count(*)::int                                                         AS records,
           COALESCE(sum(p.totalproduction), 0)                                   AS eggs,
           COALESCE(sum(COALESCE(p.brokeneggs,0) + COALESCE(p.meatyeggs,0)
                      + COALESCE(p.softeggs,0) + COALESCE(p.losteggs,0)), 0)     AS damaged,
           COALESCE(sum(p.mortality), 0)                                         AS mortality,
           COALESCE(sum(p.feedkg), 0)                                            AS feedkg,
           COALESCE(sum(p.totalmedicationconsumed), 0)                           AS medication,
           COALESCE(sum(p.totalcostofproduction), 0)                             AS cost
    INTO pr
    FROM productionrecords p
    WHERE p.farmid = p_farmid AND p.date = v_date;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', r.id, 'status', r.status,
                                                 'name', COALESCE(NULLIF(btrim(r.batchname), ''), r.batchselectiontype))
                              ORDER BY r.id), '[]'::jsonb)
    INTO v_unposted
    FROM productionbatchrecords r
    WHERE r.farmid = p_farmid AND r.productiondate = v_date
      AND r.status IN ('Draft', 'PendingAllocation', 'Allocated');

    -- Only what cannot happen: negative counts, or more deaths than birds when
    -- the bird count was entered (noofbirds = 0 is used for "not entered").
    SELECT COALESCE(jsonb_agg(jsonb_build_object('recordId', p.id, 'flockId', p.flockid, 'flock', f.name,
                                                 'birds', p.noofbirds, 'mortality', p.mortality,
                                                 'birdsLeft', p.noofbirdsleft) ORDER BY p.id), '[]'::jsonb)
    INTO v_impossible
    FROM productionrecords p
    LEFT JOIN flock f ON f.flockid = p.flockid
    WHERE p.farmid = p_farmid AND p.date = v_date
      AND (p.noofbirdsleft < 0 OR p.mortality < 0 OR p.noofbirds < 0
           OR (p.noofbirds > 0 AND p.mortality > p.noofbirds));

    SELECT COALESCE(jsonb_agg(jsonb_build_object('flockId', m.flockid, 'flock', m.name,
                                                 'mortality', m.mort, 'birds', m.birds,
                                                 'pct', round(100.0 * m.mort / m.birds, 2))
                              ORDER BY 100.0 * m.mort / m.birds DESC), '[]'::jsonb)
    INTO v_mortality
    FROM (SELECT p.flockid, f.name, sum(p.mortality) AS mort, max(p.noofbirds) AS birds
          FROM productionrecords p LEFT JOIN flock f ON f.flockid = p.flockid
          WHERE p.farmid = p_farmid AND p.date = v_date AND p.noofbirds > 0
          GROUP BY p.flockid, f.name) m
    WHERE m.mort > 0 AND 100.0 * m.mort / m.birds > pol.unusualmortalitypct;

    -- ---- Sales ------------------------------------------------------------
    SELECT count(*)::int                                                            AS n,
           COALESCE(sum(s.totalamount), 0)                                          AS total,
           COALESCE(sum(s.totalamount) FILTER (WHERE COALESCE(s.paid, TRUE)), 0)    AS cash,
           COALESCE(sum(s.totalamount) FILTER (WHERE NOT COALESCE(s.paid, TRUE)), 0) AS credit
    INTO sl
    FROM sale s
    WHERE s.farmid = p_farmid AND s.saledate = v_date;

    SELECT count(DISTINCT COALESCE(pp.paymentgroupid::text, 'row:' || pp.poultrypaymentid))::int AS n,
           COALESCE(sum(pp.amount), 0) AS total
    INTO pay
    FROM poultrypayments pp
    WHERE pp.farmid = p_farmid AND COALESCE(pp.status, 'Posted') = 'Posted'
      AND pp.paymentdate::date = v_date;

    -- ---- Cash (the Cash Flow report's own function, one inclusive day) ----
    SELECT * INTO cf FROM public.sppoultrycashflow_summary(
        p_farmid, v_date::timestamp, (v_date + 1)::timestamp - interval '1 microsecond');

    SELECT count(*)::int                           AS n,
           COALESCE(sum(c.systembalance), 0)       AS expected,
           COALESCE(sum(c.actualbalance), 0)       AS actual,
           COALESCE(sum(c.difference), 0)          AS difference
    INTO rec
    FROM poultrycashreconciliations c
    WHERE c.farmid = p_farmid AND c.status = 'Posted' AND c.reconciliationdate::date = v_date;

    -- ---- Expenses ---------------------------------------------------------
    SELECT count(*)::int AS n,
           COALESCE(sum(e.amount), 0) AS total,
           COALESCE(sum(LEAST(COALESCE(e.amountpaid, e.amount), e.amount))
                    FILTER (WHERE e.paymentmethod IS DISTINCT FROM 'NonCash'), 0) AS cash,
           COALESCE(sum(GREATEST(e.amount - COALESCE(e.amountpaid, e.amount), 0))
                    FILTER (WHERE e.paymentmethod IS DISTINCT FROM 'NonCash'), 0) AS credit,
           COALESCE(sum(e.amount) FILTER (WHERE e.paymentmethod = 'NonCash'), 0)  AS noncash
    INTO ex
    FROM expense e
    WHERE e.farmid = v_farmuuid AND e.expensedate::date = v_date;

    -- ---- Inventory exceptions (current stock) -----------------------------
    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', i.poultryrawmaterialitemid, 'item', i.itemname,
                                                 'quantity', i.currentquantity, 'unit', i.unitofmeasure)
                              ORDER BY i.itemname), '[]'::jsonb)
    INTO v_negative
    FROM poultryrawmaterialitems i
    WHERE i.farmid = p_farmid AND COALESCE(i.isactive, TRUE) AND i.currentquantity < 0;

    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', x.poultryrawmaterialitemid, 'item', x.itemname,
                                                 'quantity', x.currentquantity, 'unit', x.unitofmeasure,
                                                 'dailyUse', round(x.daily, 3),
                                                 'daysRemaining', round(x.currentquantity / x.daily, 1))
                              ORDER BY x.currentquantity / x.daily), '[]'::jsonb)
    INTO v_lowfeed
    FROM (SELECT i.poultryrawmaterialitemid, i.itemname, i.currentquantity, i.unitofmeasure,
                 sum(f.quantityconsumed) / 7.0 AS daily
          FROM poultryrawmaterialitems i
          JOIN productionrecordfeeds f ON f.poultryrawmaterialitemid = i.poultryrawmaterialitemid
          JOIN productionrecords p     ON p.id = f.productionrecordid AND p.farmid = p_farmid
          WHERE i.farmid = p_farmid AND COALESCE(i.isactive, TRUE)
            AND p.date BETWEEN v_date - 6 AND v_date
          GROUP BY i.poultryrawmaterialitemid, i.itemname, i.currentquantity, i.unitofmeasure) x
    WHERE x.daily > 0 AND x.currentquantity >= 0 AND x.currentquantity / x.daily < pol.lowfeeddays;

    -- Reorder-level breaches not already reported as low feed or negative.
    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', i.poultryrawmaterialitemid, 'item', i.itemname,
                                                 'quantity', i.currentquantity, 'minimum', i.minimumstockalert,
                                                 'unit', i.unitofmeasure) ORDER BY i.itemname), '[]'::jsonb)
    INTO v_lowstock
    FROM poultryrawmaterialitems i
    WHERE i.farmid = p_farmid AND COALESCE(i.isactive, TRUE)
      AND COALESCE(i.minimumstockalert, 0) > 0 AND i.currentquantity >= 0
      AND i.currentquantity <= i.minimumstockalert
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_lowfeed) lf
                      WHERE (lf->>'itemId')::int = i.poultryrawmaterialitemid);

    -- ---- Outstanding ------------------------------------------------------
    SELECT count(*)::int INTO v_driverreturns
    FROM poultrydriverreturns d
    WHERE d.farmid = p_farmid AND d.status = 'Draft' AND d.returndate::date = v_date;

    SELECT count(*)::int INTO v_openloadings
    FROM poultryvehicleloadings l
    WHERE l.farmid = p_farmid AND l.status = 'Loaded' AND NOT COALESCE(l.isdeleted, FALSE)
      AND l.loaddate::date = v_date
      AND NOT EXISTS (SELECT 1 FROM poultrydriverreturns d
                      WHERE d.poultryvehicleloadingid = l.poultryvehicleloadingid AND d.status = 'Approved');

    v_prevclosed := EXISTS (SELECT 1 FROM poultrydailyclosings c
                            WHERE c.farmid = p_farmid AND c.closingdate = v_date - 1 AND c.status = 'Approved');
    v_usesclosing := EXISTS (SELECT 1 FROM poultrydailyclosings c
                             WHERE c.farmid = p_farmid AND c.closingdate < v_date);

    -- ---- Checklist --------------------------------------------------------
    -- Each item: key, section, status (Complete | Warning | Blocking), title,
    -- description, action (a key the UI maps to a page -- never a URL here).

    IF comp.expectedcount = 0 THEN
        v_item := jsonb_build_object('key', 'production.recorded', 'section', 'production', 'status', 'Complete',
            'title', 'No flocks are expected to report production', 'description', NULL, 'action', NULL);
    ELSIF comp.missingcount = 0 THEN
        v_item := jsonb_build_object('key', 'production.recorded', 'section', 'production', 'status', 'Complete',
            'title', 'All flock production entered',
            'description', format('%s of %s flocks reported.', comp.completedcount, comp.expectedcount), 'action', NULL);
    ELSE
        v_item := jsonb_build_object('key', 'production.recorded', 'section', 'production', 'status', pol.missingproduction,
            'title', format('Production missing for %s of %s flocks', comp.missingcount, comp.expectedcount),
            'description', CASE WHEN comp.awaitingpostingcount > 0
                                THEN format('%s of them are in a batch entry that has not been posted.', comp.awaitingpostingcount) END,
            'action', 'missing-production');
    END IF;
    v_checks := v_checks || v_item;

    v_checks := v_checks || CASE WHEN jsonb_array_length(v_unposted) = 0
        THEN jsonb_build_object('key', 'production.unposted', 'section', 'production', 'status', 'Complete',
                 'title', 'No unposted batch production', 'description', NULL, 'action', NULL)
        ELSE jsonb_build_object('key', 'production.unposted', 'section', 'production', 'status', pol.unpostedproduction,
                 'title', format('%s batch production %s not posted', jsonb_array_length(v_unposted),
                                 CASE WHEN jsonb_array_length(v_unposted) = 1 THEN 'entry' ELSE 'entries' END),
                 'description', 'Production is only recorded once a batch is allocated and posted.',
                 'action', 'unposted-batches') END;

    v_checks := v_checks || CASE WHEN jsonb_array_length(v_impossible) = 0
        THEN jsonb_build_object('key', 'production.birdcounts', 'section', 'production', 'status', 'Complete',
                 'title', 'Bird counts are consistent', 'description', NULL, 'action', NULL)
        ELSE jsonb_build_object('key', 'production.birdcounts', 'section', 'production', 'status', pol.impossiblebirdcounts,
                 'title', format('Impossible bird counts on %s production %s', jsonb_array_length(v_impossible),
                                 CASE WHEN jsonb_array_length(v_impossible) = 1 THEN 'record' ELSE 'records' END),
                 'description', 'Negative birds or mortality, or more deaths than birds recorded.',
                 'action', 'production-records') END;

    v_checks := v_checks || CASE WHEN jsonb_array_length(v_mortality) = 0
        THEN jsonb_build_object('key', 'production.mortality', 'section', 'production', 'status', 'Complete',
                 'title', format('Mortality within %s%%', pol.unusualmortalitypct::float8), 'description', NULL, 'action', NULL)
        ELSE jsonb_build_object('key', 'production.mortality', 'section', 'production', 'status', 'Warning',
                 'title', format('Unusual mortality in %s %s', jsonb_array_length(v_mortality),
                                 CASE WHEN jsonb_array_length(v_mortality) = 1 THEN 'flock' ELSE 'flocks' END),
                 'description', (SELECT string_agg(format('%s %s%%', m->>'flock', m->>'pct'), ', ')
                                 FROM jsonb_array_elements(v_mortality) m),
                 'action', 'production-records') END;

    IF comp.duplicateflockcount > 0 THEN
        v_checks := v_checks || jsonb_build_object('key', 'production.duplicates', 'section', 'production',
            'status', 'Warning',
            'title', format('%s %s more than one production record', comp.duplicateflockcount,
                            CASE WHEN comp.duplicateflockcount = 1 THEN 'flock has' ELSE 'flocks have' END),
            'description', 'Totals include every record; check whether one is a duplicate.', 'action', 'production-records');
    END IF;

    IF rec.n > 0 THEN
        v_checks := v_checks || CASE WHEN abs(rec.difference) <= pol.cashdifferencetolerance
            THEN jsonb_build_object('key', 'cash.difference', 'section', 'cash', 'status', 'Complete',
                     'title', 'Cash count matches the books',
                     'description', format('%s account %s counted.', rec.n, CASE WHEN rec.n = 1 THEN 'was' ELSE 'were' END),
                     'action', NULL)
            ELSE jsonb_build_object('key', 'cash.difference', 'section', 'cash', 'status', pol.cashdifference,
                     'title', format('Cash difference %s', public.fnpoultryclosing_money(v_sym, rec.difference)),
                     'description', format('Counted %s against %s expected.',
                                           public.fnpoultryclosing_money(v_sym, rec.actual),
                                           public.fnpoultryclosing_money(v_sym, rec.expected)),
                     'action', 'cash-count') END;
    ELSIF pol.requirecashcount THEN
        v_checks := v_checks || jsonb_build_object('key', 'cash.difference', 'section', 'cash', 'status', 'Warning',
            'title', 'No cash count posted for this day', 'description', NULL, 'action', 'cash-count');
    END IF;

    IF jsonb_array_length(v_lowfeed) = 0 THEN
        v_checks := v_checks || jsonb_build_object('key', 'inventory.lowfeed', 'section', 'inventory', 'status', 'Complete',
            'title', format('Feed stock above %s days', pol.lowfeeddays::float8), 'description', NULL, 'action', NULL);
    ELSE
        FOR v_item IN SELECT value FROM jsonb_array_elements(v_lowfeed) LOOP
            v_checks := v_checks || jsonb_build_object(
                'key', 'inventory.lowfeed.' || (v_item->>'itemId'), 'section', 'inventory', 'status', 'Warning',
                'title', format('%s estimated %s days remaining', v_item->>'item', v_item->>'daysRemaining'),
                'description', format('%s %s in stock, using about %s a day.',
                                      v_item->>'quantity', COALESCE(v_item->>'unit', ''), v_item->>'dailyUse'),
                'action', 'inventory');
        END LOOP;
    END IF;

    IF jsonb_array_length(v_lowstock) > 0 THEN
        v_checks := v_checks || jsonb_build_object('key', 'inventory.lowstock', 'section', 'inventory', 'status', 'Warning',
            'title', format('%s %s at or below reorder level', jsonb_array_length(v_lowstock),
                            CASE WHEN jsonb_array_length(v_lowstock) = 1 THEN 'item' ELSE 'items' END),
            'description', (SELECT string_agg(x->>'item', ', ') FROM jsonb_array_elements(v_lowstock) x),
            'action', 'inventory');
    END IF;

    IF jsonb_array_length(v_negative) > 0 THEN
        v_checks := v_checks || jsonb_build_object('key', 'inventory.negative', 'section', 'inventory',
            'status', pol.negativestock,
            'title', format('%s %s negative stock', jsonb_array_length(v_negative),
                            CASE WHEN jsonb_array_length(v_negative) = 1 THEN 'item has' ELSE 'items have' END),
            'description', (SELECT string_agg(x->>'item', ', ') FROM jsonb_array_elements(v_negative) x),
            'action', 'inventory');
    END IF;

    IF sl.credit > 0 THEN
        v_checks := v_checks || jsonb_build_object('key', 'sales.credit', 'section', 'sales', 'status', 'Warning',
            'title', format('%s sold on credit', public.fnpoultryclosing_money(v_sym, sl.credit)),
            'description', 'Outstanding until the customer pays.', 'action', 'customer-balances');
    END IF;

    v_checks := v_checks || CASE WHEN v_driverreturns + v_openloadings = 0
        THEN jsonb_build_object('key', 'outstanding.driverreturns', 'section', 'outstanding', 'status', 'Complete',
                 'title', 'No pending driver returns', 'description', NULL, 'action', NULL)
        ELSE jsonb_build_object('key', 'outstanding.driverreturns', 'section', 'outstanding', 'status', pol.pendingdriverreturns,
                 'title', format('%s driver %s not reconciled', v_driverreturns + v_openloadings,
                                 CASE WHEN v_driverreturns + v_openloadings = 1 THEN 'trip' ELSE 'trips' END),
                 'description', format('%s draft return(s), %s loading(s) with no approved return.', v_driverreturns, v_openloadings),
                 'action', 'driver-returns') END;

    IF v_date = v_today THEN
        v_checks := v_checks || jsonb_build_object('key', 'day.notover', 'section', 'alerts', 'status', 'Warning',
            'title', format('The business day is not over yet (%s local time)', to_char(v_local, 'HH24:MI')),
            'description', 'Anything recorded later today will show as a change after closing.', 'action', NULL);
    END IF;

    IF v_usesclosing AND NOT v_prevclosed THEN
        v_checks := v_checks || jsonb_build_object('key', 'closing.previousday', 'section', 'alerts', 'status', 'Warning',
            'title', format('%s is not closed', to_char(v_date - 1, 'FMMon FMDD')),
            'description', NULL, 'action', 'previous-day');
    END IF;

    -- Blocking first, then warnings, then complete; stable within a level.
    SELECT COALESCE(jsonb_agg(c.value ORDER BY
               CASE c.value->>'status' WHEN 'Blocking' THEN 0 WHEN 'Warning' THEN 1 ELSE 2 END, c.ordinality), '[]'::jsonb)
    INTO v_checks
    FROM jsonb_array_elements(v_checks) WITH ORDINALITY c;

    RETURN jsonb_build_object(
        'farmId',        p_farmid,
        'businessDate',  v_date,
        'companyToday',  v_today,
        'companyLocalTime', v_local,
        'timeZoneId',    v_tz,
        'currencySymbol', v_sym,
        'generatedAtUtc', p_asof,
        'production', jsonb_build_object(
            'expectedFlocks',  comp.expectedcount,
            'reportedFlocks',  comp.completedcount,
            'missingFlocks',   comp.missingcount,
            'awaitingPosting', comp.awaitingpostingcount,
            'duplicateFlocks', comp.duplicateflockcount,
            'records',         pr.records,
            'eggsProduced',    pr.eggs,
            'eggsDamaged',     pr.damaged,
            'goodEggs',        pr.eggs - pr.damaged,
            'mortality',       pr.mortality,
            'feedKg',          pr.feedkg,
            'medicationUsed',  pr.medication,
            'productionCost',  pr.cost,
            'unpostedBatches', v_unposted,
            'impossibleBirdCounts', v_impossible,
            'unusualMortality', v_mortality),
        'sales', jsonb_build_object(
            'count',            sl.n,
            'revenue',          sl.total,
            'cashSales',        sl.cash,
            'creditSales',      sl.credit,
            'paymentsReceived', pay.total,
            'paymentsCount',    pay.n,
            -- Receivables grow by what was sold on credit and shrink by what
            -- customers paid. Payments are cash received, never revenue.
            'receivablesChange', sl.credit - pay.total),
        'cash', jsonb_build_object(
            'moneyIn',        cf.moneyin,
            'moneyOut',       cf.moneyout,
            'netCashFlow',    cf.netcashflow,
            'openingCash',    cf.openingbalance,
            'closingCash',    cf.cashathand,
            'reconciliations', rec.n,
            'expectedCash',   CASE WHEN rec.n > 0 THEN rec.expected END,
            'actualCash',     CASE WHEN rec.n > 0 THEN rec.actual END,
            'difference',     CASE WHEN rec.n > 0 THEN rec.difference END),
        'expenses', jsonb_build_object(
            'count',    ex.n,
            'total',    ex.total,
            'cash',     ex.cash,
            'credit',   ex.credit,
            'nonCash',  ex.noncash),
        'inventory', jsonb_build_object(
            'lowFeed',       v_lowfeed,
            'lowStock',      v_lowstock,
            'negativeStock', v_negative),
        'outstanding', jsonb_build_object(
            'unpostedBatches',       jsonb_array_length(v_unposted),
            'draftDriverReturns',    v_driverreturns,
            'loadingsWithoutReturn', v_openloadings,
            'previousDayClosed',     v_prevclosed),
        'policy', jsonb_build_object(
            'missingProduction',       pol.missingproduction,
            'unpostedProduction',      pol.unpostedproduction,
            'impossibleBirdCounts',    pol.impossiblebirdcounts,
            'pendingDriverReturns',    pol.pendingdriverreturns,
            'negativeStock',           pol.negativestock,
            'cashDifference',          pol.cashdifference,
            'cashDifferenceTolerance', pol.cashdifferencetolerance,
            'requireCashCount',        pol.requirecashcount,
            'lowFeedDays',             pol.lowfeeddays,
            'unusualMortalityPct',     pol.unusualmortalitypct,
            'isCustomised',            pol.iscustomised),
        'checklist', v_checks,
        'counts', jsonb_build_object(
            'blocking', (SELECT count(*) FROM jsonb_array_elements(v_checks) c WHERE c->>'status' = 'Blocking'),
            'warning',  (SELECT count(*) FROM jsonb_array_elements(v_checks) c WHERE c->>'status' = 'Warning'),
            'complete', (SELECT count(*) FROM jsonb_array_elements(v_checks) c WHERE c->>'status' = 'Complete'))
    );
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. History writer (internal).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryclosing_logevent(
    p_id integer, p_farmid text, p_date date, p_type text, p_from text, p_to text,
    p_actor text, p_reason text DEFAULT NULL, p_version integer DEFAULT NULL,
    p_warnings integer DEFAULT NULL, p_blocking integer DEFAULT NULL, p_snapshot jsonb DEFAULT NULL)
RETURNS void
LANGUAGE sql
AS $function$
    INSERT INTO public.poultrydailyclosingevents
        (poultrydailyclosingid, farmid, closingdate, eventtype, fromstatus, tostatus, actor, reason,
         closeversion, warningcount, blockingcount, snapshot)
    VALUES (p_id, p_farmid, p_date, p_type, p_from, p_to, p_actor, p_reason,
            p_version, p_warnings, p_blocking, p_snapshot);
$function$;

-- -----------------------------------------------------------------------------
-- 6. Close Business Day. The ONE place a day becomes closed.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_close(text, date, text, text, timestamptz);
CREATE FUNCTION public.sppoultrydailyclosing_close(
    p_farmid       text,
    p_businessdate date,
    p_closedby     text,
    p_notes        text        DEFAULT NULL,
    p_asof         timestamptz DEFAULT now())
RETURNS TABLE(poultrydailyclosingid integer, closeversion integer, warningcount integer, closedatutc timestamptz)
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_ws       jsonb;
    v_id       integer;
    v_status   text;
    v_version  integer;
    v_blocking integer;
    v_warnings integer;
    v_titles   text;
    v_legacy   jsonb;
BEGIN
    IF p_businessdate IS NULL THEN
        RAISE EXCEPTION 'A business date is required.';
    END IF;

    -- Two people pressing Close at once must produce one close, not two.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-close:' || p_farmid || ':' || p_businessdate::text));

    SELECT c.poultrydailyclosingid, c.status, c.closeversion INTO v_id, v_status, v_version
    FROM poultrydailyclosings c
    WHERE c.farmid = p_farmid AND c.closingdate = p_businessdate
    FOR UPDATE;

    IF v_status = 'Approved' THEN
        RAISE EXCEPTION 'This business day is already closed.' USING ERRCODE = 'P0002';
    END IF;

    -- Raises for a future date (company timezone).
    v_ws := public.sppoultrydailyclosing_workspace(p_farmid, p_businessdate, p_asof);
    v_blocking := (v_ws->'counts'->>'blocking')::int;
    v_warnings := (v_ws->'counts'->>'warning')::int;

    IF v_blocking > 0 THEN
        SELECT string_agg(c->>'title', '; ') INTO v_titles
        FROM jsonb_array_elements(v_ws->'checklist') c WHERE c->>'status' = 'Blocking';
        RAISE EXCEPTION 'Cannot close %: %', to_char(p_businessdate, 'FMMonth FMDD, YYYY'), v_titles
            USING ERRCODE = 'P0003';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO poultrydailyclosings (farmid, closingdate, managernotes, createdby)
        VALUES (p_farmid, p_businessdate, p_notes, p_closedby)
        RETURNING poultrydailyclosings.poultrydailyclosingid INTO v_id;
        v_version := 0;
        PERFORM public.fnpoultryclosing_logevent(v_id, p_farmid, p_businessdate, 'Created', NULL, 'Draft', p_closedby);
        v_status := 'Draft';
    END IF;

    -- The legacy totals row, frozen as closed: what getall / getbyid (and so
    -- every closing report) return for this day from now on.
    SELECT to_jsonb(lt) INTO v_legacy FROM public.fnpoultrydailyclosing_livetotals(p_farmid, p_businessdate) lt;
    v_ws := v_ws || jsonb_build_object('legacyTotals', v_legacy);

    UPDATE poultrydailyclosings c
    SET    status              = 'Approved',
           submittedby         = COALESCE(c.submittedby, p_closedby),
           submittedat         = COALESCE(c.submittedat, (p_asof AT TIME ZONE 'utc')),
           approvedby          = p_closedby,
           approvedat          = (p_asof AT TIME ZONE 'utc'),
           rejectionreason     = NULL,
           managernotes        = COALESCE(p_notes, c.managernotes),
           quantityproduced    = (v_ws->'production'->>'eggsProduced')::numeric,
           quantitydamaged     = (v_ws->'production'->>'eggsDamaged')::numeric,
           totalproductioncost = (v_ws->'production'->>'productionCost')::numeric,
           closingstock        = COALESCE((v_legacy->>'closingstock')::numeric, c.closingstock),
           -- The legacy column keeps its legacy meaning (the closing's own
           -- estimate); the real cash position is in the snapshot's cash section.
           cashathand          = COALESCE((v_legacy->>'cashathand')::numeric, c.cashathand),
           closedatutc         = p_asof,
           closedby            = p_closedby,
           closingsnapshot     = v_ws,
           closeversion        = COALESCE(v_version, 0) + 1,
           warningsatclose     = v_warnings,
           updatedat           = (p_asof AT TIME ZONE 'utc')
    WHERE  c.poultrydailyclosingid = v_id;

    PERFORM public.fnpoultryclosing_logevent(v_id, p_farmid, p_businessdate, 'Closed', v_status, 'Approved',
        p_closedby, NULL, COALESCE(v_version, 0) + 1, v_warnings, 0, v_ws);

    RETURN QUERY SELECT v_id, COALESCE(v_version, 0) + 1, v_warnings, p_asof;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. The existing workflow, routed through the same rules.
-- -----------------------------------------------------------------------------

-- Approve = close a Submitted day. Same blockers, same snapshot. It used to be a
-- silent no-op when the row was not Submitted; it now says so.
CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_approve(
    p_poultrydailyclosingid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date date;
BEGIN
    SELECT c.closingdate INTO v_date FROM poultrydailyclosings c
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid AND c.status = 'Submitted';
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Only Submitted closings can be approved.';
    END IF;
    PERFORM public.sppoultrydailyclosing_close(p_farmid, v_date, p_approvedby);
END;
$function$;

-- Reopen: a reason is required, the snapshot is kept, history records it.
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_reopen(integer, text);
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_reopen(integer, text, text, text);
CREATE FUNCTION public.sppoultrydailyclosing_reopen(
    p_poultrydailyclosingid integer, p_farmid text, p_reason text, p_reopenedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date    date;
    v_status  text;
    v_version integer;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to reopen a day.';
    END IF;

    SELECT c.closingdate, c.status, c.closeversion INTO v_date, v_status, v_version
    FROM poultrydailyclosings c
    WHERE c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid
    FOR UPDATE;

    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Daily closing not found.';
    END IF;
    IF v_status = 'Draft' THEN
        RAISE EXCEPTION 'This day is already open.';
    END IF;

    UPDATE poultrydailyclosings c
    SET    status = 'Draft', submittedby = NULL, submittedat = NULL, approvedby = NULL, approvedat = NULL,
           rejectionreason = NULL, closedatutc = NULL, closedby = NULL,
           -- closingsnapshot is deliberately KEPT: it is the last state at closing.
           lastreopenedatutc = now(), lastreopenedby = p_reopenedby, lastreopenreason = btrim(p_reason),
           updatedat = (now() at time zone 'utc')
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid;

    PERFORM public.fnpoultryclosing_logevent(p_poultrydailyclosingid, p_farmid, v_date, 'Reopened',
        v_status, 'Draft', p_reopenedby, btrim(p_reason), v_version);
END;
$function$;

-- Recreate: refuses a closed day (reopen it first, with a reason).
CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_recreate(p_poultrydailyclosingid integer, p_farmid text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date   date;
    v_status text;
BEGIN
    SELECT c.closingdate, c.status INTO v_date, v_status FROM poultrydailyclosings c
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid;
    IF v_status = 'Approved' THEN
        RAISE EXCEPTION 'This day is closed. Reopen it (with a reason) before recreating it.';
    END IF;

    UPDATE poultrydailyclosings c
    SET    status = 'Draft', actualcashcounted = 0, cashdifference = 0, managernotes = NULL,
           submittedby = NULL, submittedat = NULL, approvedby = NULL, approvedat = NULL,
           rejectionreason = NULL, updatedat = (now() at time zone 'utc')
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid;

    IF v_date IS NOT NULL THEN
        PERFORM public.fnpoultryclosing_logevent(p_poultrydailyclosingid, p_farmid, v_date, 'Recreated',
            v_status, 'Draft', NULL);
    END IF;
END;
$function$;

-- Delete: a day that has ever been closed keeps its row.
CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_delete(p_poultrydailyclosingid integer, p_farmid text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date   date;
    v_status text;
BEGIN
    IF EXISTS (SELECT 1 FROM poultrydailyclosingevents e
               WHERE e.poultrydailyclosingid = p_poultrydailyclosingid AND e.farmid = p_farmid
                 AND e.eventtype = 'Closed') THEN
        RAISE EXCEPTION 'This day has been closed before; its closing cannot be deleted. Reopen or recreate it instead.';
    END IF;

    DELETE FROM poultrydailyclosings c
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid
      AND  c.status IN ('Draft', 'Rejected')
    RETURNING c.closingdate, c.status INTO v_date, v_status;

    IF v_date IS NOT NULL THEN
        PERFORM public.fnpoultryclosing_logevent(p_poultrydailyclosingid, p_farmid, v_date, 'Deleted',
            v_status, NULL, NULL);
    END IF;
END;
$function$;

-- Insert / submit / reject: unchanged behaviour, now recorded in history.
-- Submit also accepts Rejected, which the UI has always offered as "Resubmit".
CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_insert(
    p_farmid text, p_closingdate date, p_managernotes text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_newid integer;
BEGIN
    IF EXISTS (SELECT 1 FROM poultrydailyclosings c WHERE c.farmid = p_farmid AND c.closingdate = p_closingdate) THEN
        RAISE EXCEPTION 'A closing already exists for this date.';
    END IF;
    IF p_closingdate > public.fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'You cannot open a closing for a future date.';
    END IF;
    INSERT INTO poultrydailyclosings (farmid, closingdate, managernotes, createdby)
    VALUES (p_farmid, p_closingdate, p_managernotes, p_createdby)
    RETURNING poultrydailyclosingid INTO v_newid;

    PERFORM public.fnpoultryclosing_logevent(v_newid, p_farmid, p_closingdate, 'Created', NULL, 'Draft', p_createdby);
    RETURN v_newid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_submit(
    p_poultrydailyclosingid integer, p_farmid text, p_actualcashcounted numeric DEFAULT 0,
    p_managernotes text DEFAULT NULL::text, p_submittedby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date   date;
    v_status text;
    v_p numeric; v_d numeric; v_c numeric; v_s numeric;
BEGIN
    SELECT c.closingdate, c.status INTO v_date, v_status FROM poultrydailyclosings c
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid
      AND  c.status IN ('Draft', 'Rejected');
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Only Draft or Rejected closings can be submitted.';
    END IF;

    SELECT f.o_quantityproduced, f.o_quantitydamaged, f.o_totalproductioncost, f.o_closingstock
    INTO   v_p, v_d, v_c, v_s
    FROM   sppoultrydailyclosing_computefordate(p_farmid, v_date) f;

    UPDATE poultrydailyclosings c
    SET    quantityproduced = v_p, quantitydamaged = v_d, totalproductioncost = v_c, closingstock = v_s,
           actualcashcounted = COALESCE(p_actualcashcounted, 0),
           cashdifference = COALESCE(p_actualcashcounted, 0) - c.cashathand,
           managernotes = COALESCE(p_managernotes, c.managernotes),
           rejectionreason = NULL,
           status = 'Submitted', submittedby = p_submittedby, submittedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc')
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid;

    PERFORM public.fnpoultryclosing_logevent(p_poultrydailyclosingid, p_farmid, v_date, 'Submitted',
        v_status, 'Submitted', p_submittedby);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_reject(
    p_poultrydailyclosingid integer, p_farmid text, p_rejectionreason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_date date;
BEGIN
    UPDATE poultrydailyclosings c
    SET    status = 'Rejected', rejectionreason = p_rejectionreason, updatedat = (now() at time zone 'utc')
    WHERE  c.poultrydailyclosingid = p_poultrydailyclosingid AND c.farmid = p_farmid AND c.status = 'Submitted'
    RETURNING c.closingdate INTO v_date;

    IF v_date IS NOT NULL THEN
        PERFORM public.fnpoultryclosing_logevent(p_poultrydailyclosingid, p_farmid, v_date, 'Rejected',
            'Submitted', 'Rejected', NULL, p_rejectionreason);
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Readers.
-- -----------------------------------------------------------------------------

-- The totals a closing row reports: frozen at close for a closed day, live
-- otherwise. The live function is only called when it is needed, so a closed
-- day also stops costing a recomputation on every report.
CREATE OR REPLACE FUNCTION public.fnpoultrydailyclosing_rowtotals(
    p_farmid text, p_closingdate date, p_status text, p_snapshot jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
    SELECT CASE
        WHEN p_status = 'Approved' AND p_snapshot ? 'legacyTotals' THEN p_snapshot->'legacyTotals'
        ELSE (SELECT to_jsonb(lt) FROM public.fnpoultrydailyclosing_livetotals(p_farmid, p_closingdate) lt)
    END;
$function$;

-- Same signatures and columns as before (C# maps them by name); only where the
-- numbers come from changes.
CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_getall(
    p_farmid text, p_status text DEFAULT NULL::text, p_fromdate date DEFAULT NULL::date, p_todate date DEFAULT NULL::date)
RETURNS TABLE(poultrydailyclosingid integer, farmid text, closingdate date, quantityproduced numeric, quantitydamaged numeric,
              totalproductioncost numeric, closingstock numeric, cashathand numeric, actualcashcounted numeric,
              cashdifference numeric, managernotes text, status text, rejectionreason text, createdby text,
              submittedby text, submittedat timestamp without time zone, approvedby text,
              approvedat timestamp without time zone, createdat timestamp without time zone,
              updatedat timestamp without time zone, eggssold numeric, eggsreturned numeric, mortality numeric,
              feedusedqty numeric, medusedqty numeric, totalincome numeric, totalexpenses numeric, creditsales numeric,
              customercollections numeric, cashcollected numeric, momocollected numeric, bankcollected numeric,
              cashbalance numeric, momobalance numeric, bankbalance numeric)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        c.poultrydailyclosingid, c.farmid::text, c.closingdate,
        CASE WHEN c.status = 'Draft' THEN (t.v->>'eggsproduced')::numeric ELSE c.quantityproduced END,
        CASE WHEN c.status = 'Draft' THEN (t.v->>'eggsdamaged')::numeric  ELSE c.quantitydamaged END,
        CASE WHEN c.status = 'Draft' THEN (t.v->>'prodcost')::numeric     ELSE c.totalproductioncost END,
        CASE WHEN c.status = 'Draft' THEN (t.v->>'closingstock')::numeric ELSE c.closingstock END,
        (t.v->>'cashathand')::numeric,
        c.actualcashcounted,
        COALESCE(c.actualcashcounted, 0) - (t.v->>'cashathand')::numeric,
        c.managernotes::text, c.status::text, c.rejectionreason::text,
        c.createdby::text, c.submittedby::text, c.submittedat, c.approvedby::text, c.approvedat, c.createdat, c.updatedat,
        (t.v->>'eggssold')::numeric, (t.v->>'eggsreturned')::numeric, (t.v->>'mortality')::numeric,
        (t.v->>'feedusedqty')::numeric, (t.v->>'medusedqty')::numeric,
        (t.v->>'totalincome')::numeric, (t.v->>'totalexpenses')::numeric, (t.v->>'creditsales')::numeric,
        (t.v->>'customercollections')::numeric,
        (t.v->>'cashcollected')::numeric, (t.v->>'momocollected')::numeric, (t.v->>'bankcollected')::numeric,
        (t.v->>'cashbalance')::numeric, (t.v->>'momobalance')::numeric, (t.v->>'bankbalance')::numeric
    FROM   poultrydailyclosings c
    CROSS  JOIN LATERAL (SELECT public.fnpoultrydailyclosing_rowtotals(c.farmid, c.closingdate, c.status, c.closingsnapshot) AS v) t
    WHERE  c.farmid = p_farmid
       AND (p_status   IS NULL OR c.status = p_status)
       AND (p_fromdate IS NULL OR c.closingdate >= p_fromdate)
       AND (p_todate   IS NULL OR c.closingdate <= p_todate)
    ORDER  BY c.closingdate DESC, c.poultrydailyclosingid DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrydailyclosing_getbyid(p_poultrydailyclosingid integer, p_farmid text)
RETURNS TABLE(poultrydailyclosingid integer, farmid text, closingdate date, quantityproduced numeric, quantitydamaged numeric,
              totalproductioncost numeric, closingstock numeric, cashathand numeric, actualcashcounted numeric,
              cashdifference numeric, managernotes text, status text, rejectionreason text, createdby text,
              submittedby text, submittedat timestamp without time zone, approvedby text,
              approvedat timestamp without time zone, createdat timestamp without time zone,
              updatedat timestamp without time zone, eggssold numeric, eggsreturned numeric, mortality numeric,
              feedusedqty numeric, medusedqty numeric, totalincome numeric, totalexpenses numeric, creditsales numeric,
              customercollections numeric, cashcollected numeric, momocollected numeric, bankcollected numeric,
              cashbalance numeric, momobalance numeric, bankbalance numeric)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT g.* FROM public.sppoultrydailyclosing_getall(p_farmid) g
    WHERE  g.poultrydailyclosingid = p_poultrydailyclosingid;
END;
$function$;

-- The closing row for one date (or nothing), including the stored snapshot.
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_getfordate(text, date);
CREATE FUNCTION public.sppoultrydailyclosing_getfordate(p_farmid text, p_businessdate date)
RETURNS TABLE(
    poultrydailyclosingid integer, closingdate date, status text, managernotes text, rejectionreason text,
    createdby text, submittedby text, submittedat timestamp, approvedby text, approvedat timestamp,
    closedatutc timestamptz, closedby text, closeversion integer, warningsatclose integer,
    lastreopenedatutc timestamptz, lastreopenedby text, lastreopenreason text, closingsnapshot jsonb)
LANGUAGE sql
STABLE
AS $function$
    SELECT c.poultrydailyclosingid, c.closingdate, c.status::text, c.managernotes::text, c.rejectionreason::text,
           c.createdby::text, c.submittedby::text, c.submittedat, c.approvedby::text, c.approvedat,
           c.closedatutc, c.closedby, c.closeversion, c.warningsatclose,
           c.lastreopenedatutc, c.lastreopenedby, c.lastreopenreason, c.closingsnapshot
    FROM   poultrydailyclosings c
    WHERE  c.farmid = p_farmid AND c.closingdate = p_businessdate;
$function$;

-- Previous closings, newest first, with the headline figures AS CLOSED.
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_history(text, date, date);
CREATE FUNCTION public.sppoultrydailyclosing_history(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE(
    poultrydailyclosingid integer, closingdate date, status text, closedatutc timestamptz, closedby text,
    closeversion integer, warningsatclose integer, reopencount integer,
    lastreopenedatutc timestamptz, lastreopenreason text,
    revenue numeric, moneyin numeric, moneyout numeric, netcashflow numeric,
    eggsproduced numeric, missingflocks integer, hassnapshot boolean)
LANGUAGE sql
STABLE
AS $function$
    SELECT c.poultrydailyclosingid, c.closingdate, c.status::text, c.closedatutc, c.closedby,
           c.closeversion, c.warningsatclose,
           (SELECT count(*)::int FROM poultrydailyclosingevents e
            WHERE e.poultrydailyclosingid = c.poultrydailyclosingid AND e.eventtype = 'Reopened'),
           c.lastreopenedatutc, c.lastreopenreason,
           (c.closingsnapshot->'sales'->>'revenue')::numeric,
           (c.closingsnapshot->'cash'->>'moneyIn')::numeric,
           (c.closingsnapshot->'cash'->>'moneyOut')::numeric,
           (c.closingsnapshot->'cash'->>'netCashFlow')::numeric,
           (c.closingsnapshot->'production'->>'eggsProduced')::numeric,
           (c.closingsnapshot->'production'->>'missingFlocks')::int,
           c.closingsnapshot IS NOT NULL
    FROM   poultrydailyclosings c
    WHERE  c.farmid = p_farmid
      AND (p_fromdate IS NULL OR c.closingdate >= p_fromdate)
      AND (p_todate   IS NULL OR c.closingdate <= p_todate)
    ORDER  BY c.closingdate DESC;
$function$;

DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_events(text, date);
CREATE FUNCTION public.sppoultrydailyclosing_events(p_farmid text, p_businessdate date)
RETURNS TABLE(
    eventid bigint, poultrydailyclosingid integer, eventtype text, fromstatus text, tostatus text,
    actor text, reason text, closeversion integer, warningcount integer, occurredatutc timestamptz,
    hassnapshot boolean)
LANGUAGE sql
STABLE
AS $function$
    SELECT e.eventid, e.poultrydailyclosingid, e.eventtype, e.fromstatus, e.tostatus, e.actor, e.reason,
           e.closeversion, e.warningcount, e.occurredatutc, e.snapshot IS NOT NULL
    FROM   poultrydailyclosingevents e
    WHERE  e.farmid = p_farmid AND e.closingdate = p_businessdate
    ORDER  BY e.eventid;
$function$;

-- The snapshot a specific past close stored (for "state at closing v1").
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_eventsnapshot(text, bigint);
CREATE FUNCTION public.sppoultrydailyclosing_eventsnapshot(p_farmid text, p_eventid bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
    SELECT e.snapshot FROM poultrydailyclosingevents e WHERE e.farmid = p_farmid AND e.eventid = p_eventid;
$function$;

-- One company's closing state for a date: the question Business Office will ask
-- of every company ("Poultry Farm A -- Today: Closed").
DROP FUNCTION IF EXISTS public.sppoultrydailyclosing_statusfordate(text, date);
CREATE FUNCTION public.sppoultrydailyclosing_statusfordate(p_farmid text, p_businessdate date DEFAULT NULL)
RETURNS TABLE(businessdate date, companytoday date, closingstatus text, workflowstatus text,
              poultrydailyclosingid integer, closedatutc timestamptz, closedby text)
LANGUAGE sql
STABLE
AS $function$
    WITH d AS (SELECT public.fncompany_businessdate(p_farmid) AS today)
    SELECT COALESCE(p_businessdate, d.today), d.today,
           CASE WHEN c.status = 'Approved' THEN 'Closed' ELSE 'Open' END,
           COALESCE(c.status::text, 'NotStarted'),
           c.poultrydailyclosingid, c.closedatutc, c.closedby
    FROM   d
    LEFT   JOIN poultrydailyclosings c
           ON c.farmid = p_farmid AND c.closingdate = COALESCE(p_businessdate, d.today);
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Runs after COMMIT so a failure here does not undo the migration.
-- Every fixture is rolled back by the sentinel at the end of the inner block
-- (flock and production rows have triggers; a rollback is the only clean exit).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a      text := '11111111-3333-4333-8333-000000000333';   -- expense.farmid is uuid
    b      text := '22222222-3333-4333-8333-000000000333';
    -- Pacific/Auckland is UTC+13 in March. 2026-03-10 10:00 UTC = 23:00 local on
    -- the 10th; 11:30 UTC is already the 11th there.
    t_day  timestamptz := '2026-03-10 10:00:00+00';
    t_next timestamptz := '2026-03-10 11:30:00+00';
    d      date := date '2026-03-10';
    v_created timestamp := timestamp '2026-01-01 08:00';
    f1 integer; f2 integer; fb integer;
    v_sale integer; v_item integer; v_pr integer; v_acct integer;
    ws jsonb; ws2 jsonb; snap jsonb;
    r record;
    v_id integer;
    v_n integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid, currencysymbol)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'Pacific/Auckland', 'GHC'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'Pacific/Auckland', 'GHC');

        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__333__', a, 'F1', d - 30, 'Brown', 1000, TRUE, TRUE, -333, v_created) RETURNING flockid INTO f1;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__333__', a, 'F2', d - 30, 'Brown', 1000, TRUE, TRUE, -333, v_created) RETURNING flockid INTO f2;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__333__', b, 'B1', d - 30, 'Brown', 1000, TRUE, TRUE, -333, v_created) RETURNING flockid INTO fb;

        -- Only F1 has reported: F2 is missing.
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                                       noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                                       totalproduction, brokeneggs, flockid, sourcetype, createdat)
        VALUES (a, '__333__', '__333__', 20, 140, d, 1000, 3, 997, 120, 300, 300, 200, 800, 10, f1, 'ManualSingleFlock', now())
        RETURNING id INTO v_pr;

        -- ---- Missing production blocks by default -------------------------
        ws := public.sppoultrydailyclosing_workspace(a, d, t_day);
        IF (ws->'production'->>'missingFlocks')::int <> 1 OR (ws->'production'->>'expectedFlocks')::int <> 2 THEN
            RAISE EXCEPTION '333: completeness should come from 332 (1 of 2 missing): %', ws->'production';
        END IF;
        IF (ws->'counts'->>'blocking')::int <> 1 OR ws->'checklist'->0->>'key' <> 'production.recorded' THEN
            RAISE EXCEPTION '333: missing production should be the one blocker, listed first: %', ws->'checklist';
        END IF;
        IF (ws->'production'->>'eggsProduced')::numeric <> 800 OR (ws->'production'->>'mortality')::numeric <> 3
           OR (ws->'production'->>'feedKg')::numeric <> 120 OR (ws->'production'->>'eggsDamaged')::numeric <> 10 THEN
            RAISE EXCEPTION '333: production totals wrong: %', ws->'production';
        END IF;

        BEGIN
            PERFORM * FROM public.sppoultrydailyclosing_close(a, d, 'owner', NULL, t_day);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: closed a day with missing production.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;
        IF EXISTS (SELECT 1 FROM poultrydailyclosings WHERE farmid = a) THEN
            RAISE EXCEPTION '333: a refused close left a closing row behind.';
        END IF;

        -- ---- Policy can downgrade it to a warning -------------------------
        PERFORM public.sppoultrydailyclosingpolicy_set(a, 'Warning', 'Blocking', 'Blocking', 'Warning',
                                                       'Warning', 'Warning', 0, FALSE, 3, 1, 'owner');
        ws := public.sppoultrydailyclosing_workspace(a, d, t_day);
        IF (ws->'counts'->>'blocking')::int <> 0 OR ws->'policy'->>'missingProduction' <> 'Warning' THEN
            RAISE EXCEPTION '333: policy did not downgrade missing production: %', ws->'counts';
        END IF;
        -- Back to the default for the rest of the test.
        DELETE FROM poultrydailyclosingpolicy WHERE farmid = a;

        -- F2 reports: production complete. Its mortality (30 of 1000 = 3%) is
        -- above the 1% default -- a warning, never a blocker.
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                                       noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                                       totalproduction, flockid, sourcetype, createdat)
        VALUES (a, '__333__', '__333__', 20, 140, d, 1000, 30, 970, 100, 200, 200, 100, 500, f2, 'ManualSingleFlock', now());

        -- ---- Money: one cash sale, one credit sale part-paid, one expense
        --      paid, one on credit, one non-cash ---------------------------
        INSERT INTO sale (farmid, userid, saledate, product, quantity, unitprice, totalamount, paid, amountpaid)
        VALUES (a, '__333__', d, 'Eggs', 10, 10, 100, TRUE, 0);
        INSERT INTO sale (farmid, userid, saledate, product, quantity, unitprice, totalamount, paid, amountpaid)
        VALUES (a, '__333__', d, 'Eggs', 20, 10, 200, FALSE, 0) RETURNING saleid INTO v_sale;
        INSERT INTO poultrypayments (farmid, saleid, amount, paymentdate, status, paymentgroupid)
        VALUES (a, v_sale, 40, d, 'Posted', gen_random_uuid());

        INSERT INTO expense (farmid, userid, expensedate, category, amount, amountpaid, paymentmethod)
        VALUES (a::uuid, '__333__', d, 'Utilities', 30, NULL, 'Cash'),
               (a::uuid, '__333__', d, 'Repairs', 50, 20, 'Cash'),
               (a::uuid, '__333__', d, 'Depreciation', 15, NULL, 'NonCash');

        ws := public.sppoultrydailyclosing_workspace(a, d, t_day);
        IF (ws->'sales'->>'revenue')::numeric <> 300 OR (ws->'sales'->>'cashSales')::numeric <> 100
           OR (ws->'sales'->>'creditSales')::numeric <> 200 OR (ws->'sales'->>'paymentsReceived')::numeric <> 40
           OR (ws->'sales'->>'receivablesChange')::numeric <> 160 THEN
            RAISE EXCEPTION '333: sales wrong (payments must not be revenue): %', ws->'sales';
        END IF;
        IF (ws->'expenses'->>'total')::numeric <> 95 OR (ws->'expenses'->>'cash')::numeric <> 50
           OR (ws->'expenses'->>'credit')::numeric <> 30 OR (ws->'expenses'->>'nonCash')::numeric <> 15 THEN
            RAISE EXCEPTION '333: expense classification wrong: %', ws->'expenses';
        END IF;
        -- Cash must be exactly what the Cash Flow report says for that day.
        SELECT * INTO r FROM public.sppoultrycashflow_summary(a, d::timestamp, (d + 1)::timestamp - interval '1 microsecond');
        IF (ws->'cash'->>'moneyIn')::numeric <> r.moneyin OR (ws->'cash'->>'moneyOut')::numeric <> r.moneyout
           OR (ws->'cash'->>'netCashFlow')::numeric <> r.netcashflow THEN
            RAISE EXCEPTION '333: cash does not match sppoultrycashflow_summary: % vs %', ws->'cash', r;
        END IF;
        -- 100 cash sale + 40 payment in; 30 + 20 paid expenses out; NonCash never moves cash.
        IF (ws->'cash'->>'moneyIn')::numeric <> 140 OR (ws->'cash'->>'moneyOut')::numeric <> 50 THEN
            RAISE EXCEPTION '333: cash totals wrong: %', ws->'cash';
        END IF;
        IF ws->'cash'->>'difference' IS NOT NULL THEN
            RAISE EXCEPTION '333: showed a cash difference with no posted count.';
        END IF;

        -- Warnings present: mortality, credit sale, day not over (23:00 local on the day).
        IF (ws->'counts'->>'blocking')::int <> 0 THEN
            RAISE EXCEPTION '333: unexpected blocker: %', ws->'checklist';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ws->'checklist') c WHERE c->>'key' = 'production.mortality' AND c->>'status' = 'Warning')
           OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ws->'checklist') c WHERE c->>'key' = 'sales.credit' AND c->>'status' = 'Warning')
           OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ws->'checklist') c WHERE c->>'key' = 'day.notover') THEN
            RAISE EXCEPTION '333: expected mortality, credit and day-not-over warnings: %', ws->'checklist';
        END IF;

        -- ---- Low feed: 70 kg left, 7 days x 40 kg used => 1.75 days -------
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, currentquantity, minimumstockalert, isactive)
        VALUES (a, 'Layer Mash', 'Feed', 70, 0, TRUE) RETURNING poultryrawmaterialitemid INTO v_item;
        INSERT INTO productionrecordfeeds (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed)
        VALUES (a, v_pr, v_item, 'Layer Mash', 280);
        ws := public.sppoultrydailyclosing_workspace(a, d, t_day);
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ws->'checklist') c
                       WHERE c->>'key' = 'inventory.lowfeed.' || v_item AND c->>'status' = 'Warning'
                         AND c->>'title' = 'Layer Mash estimated 1.8 days remaining') THEN
            RAISE EXCEPTION '333: low-feed warning missing or wrong: %', ws->'checklist';
        END IF;

        -- ---- Negative stock follows policy --------------------------------
        UPDATE poultryrawmaterialitems SET currentquantity = -5 WHERE poultryrawmaterialitemid = v_item;
        ws := public.sppoultrydailyclosing_workspace(a, d, t_day);
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ws->'checklist') c WHERE c->>'key' = 'inventory.negative' AND c->>'status' = 'Warning') THEN
            RAISE EXCEPTION '333: negative stock should warn by default.';
        END IF;
        UPDATE poultryrawmaterialitems SET currentquantity = 70 WHERE poultryrawmaterialitemid = v_item;

        -- ---- Impossible bird count blocks ---------------------------------
        UPDATE productionrecords SET mortality = 2000 WHERE id = v_pr;
        ws := public.sppoultrydailyclosing_workspace(a, d, t_day);
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(ws->'checklist') c WHERE c->>'key' = 'production.birdcounts' AND c->>'status' = 'Blocking') THEN
            RAISE EXCEPTION '333: more deaths than birds must block.';
        END IF;
        UPDATE productionrecords SET mortality = 3 WHERE id = v_pr;

        -- ---- Close (warnings do not block) --------------------------------
        SELECT * INTO r FROM public.sppoultrydailyclosing_close(a, d, 'owner', 'All good', t_day);
        v_id := r.poultrydailyclosingid;
        IF r.closeversion <> 1 OR r.warningcount < 3 THEN
            RAISE EXCEPTION '333: close result wrong: %', r;
        END IF;
        SELECT * INTO r FROM public.sppoultrydailyclosing_statusfordate(a, d);
        IF r.closingstatus <> 'Closed' OR r.closedby <> 'owner' THEN
            RAISE EXCEPTION '333: status after close wrong: %', r;
        END IF;
        SELECT closingsnapshot INTO snap FROM poultrydailyclosings WHERE poultrydailyclosingid = v_id;
        IF (snap->'sales'->>'revenue')::numeric <> 300 THEN
            RAISE EXCEPTION '333: snapshot not stored.';
        END IF;

        -- ---- Duplicate close refused --------------------------------------
        BEGIN
            PERFORM * FROM public.sppoultrydailyclosing_close(a, d, 'owner', NULL, t_day);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: closed the same day twice.';
        EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
        END;

        -- ---- Correction after close: live moves, snapshot does not --------
        INSERT INTO sale (farmid, userid, saledate, product, quantity, unitprice, totalamount, paid, amountpaid)
        VALUES (a, '__333__', d, 'Eggs', 5, 10, 50, TRUE, 0);
        ws2 := public.sppoultrydailyclosing_workspace(a, d, t_day);
        SELECT closingsnapshot INTO snap FROM poultrydailyclosings WHERE poultrydailyclosingid = v_id;
        IF (ws2->'sales'->>'revenue')::numeric <> 350 OR (snap->'sales'->>'revenue')::numeric <> 300 THEN
            RAISE EXCEPTION '333: state at closing vs current state wrong (live %, snapshot %).',
                ws2->'sales'->>'revenue', snap->'sales'->>'revenue';
        END IF;

        -- ...and the closing REPORTS (getall / getbyid) keep the day as closed.
        SELECT * INTO r FROM public.sppoultrydailyclosing_getbyid(v_id, a);
        IF r.totalincome <> 300 OR r.status <> 'Approved' THEN
            RAISE EXCEPTION '333: getbyid should report the closed day as closed (300), got % (%).', r.totalincome, r.status;
        END IF;
        IF (SELECT lt.totalincome FROM public.fnpoultrydailyclosing_livetotals(a, d) lt) <> 350 THEN
            RAISE EXCEPTION '333: live totals should include the late sale.';
        END IF;
        IF (SELECT g.totalincome FROM public.sppoultrydailyclosing_getall(a) g WHERE g.poultrydailyclosingid = v_id) <> 300 THEN
            RAISE EXCEPTION '333: getall should report the closed day as closed.';
        END IF;

        -- ---- Recreate and delete refuse a closed day ----------------------
        BEGIN
            PERFORM public.sppoultrydailyclosing_recreate(v_id, a);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: recreated a closed day.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Reopen needs a reason ----------------------------------------
        BEGIN
            PERFORM public.sppoultrydailyclosing_reopen(v_id, a, '   ', 'owner');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: reopened without a reason.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        -- ...and another company cannot reopen it.
        PERFORM 1;
        BEGIN
            PERFORM public.sppoultrydailyclosing_reopen(v_id, b, 'not mine', 'intruder');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: company B reopened company A''s day.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        PERFORM public.sppoultrydailyclosing_reopen(v_id, a, 'Late egg sale', 'owner');
        SELECT * INTO r FROM public.sppoultrydailyclosing_getfordate(a, d);
        IF r.status <> 'Draft' OR r.lastreopenreason <> 'Late egg sale' OR r.closingsnapshot IS NULL THEN
            RAISE EXCEPTION '333: reopen lost the reason or the snapshot: %', r;
        END IF;
        -- An open day reports live again, late sale included.
        IF (SELECT g.totalincome FROM public.sppoultrydailyclosing_getbyid(v_id, a) g) <> 350 THEN
            RAISE EXCEPTION '333: a reopened day should report live figures.';
        END IF;

        BEGIN
            PERFORM public.sppoultrydailyclosing_delete(v_id, a);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: deleted a day that had been closed.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Re-close: version 2, and the first close's snapshot survives --
        SELECT * INTO r FROM public.sppoultrydailyclosing_close(a, d, 'owner', NULL, t_day);
        IF r.closeversion <> 2 THEN
            RAISE EXCEPTION '333: re-close should be version 2, got %.', r.closeversion;
        END IF;
        SELECT count(*) INTO v_n FROM poultrydailyclosingevents WHERE farmid = a AND eventtype = 'Closed';
        IF v_n <> 2 THEN
            RAISE EXCEPTION '333: expected 2 Closed events, got %.', v_n;
        END IF;
        IF (SELECT (snapshot->'sales'->>'revenue')::numeric FROM poultrydailyclosingevents
            WHERE farmid = a AND eventtype = 'Closed' AND closeversion = 1) <> 300
           OR (SELECT (snapshot->'sales'->>'revenue')::numeric FROM poultrydailyclosingevents
               WHERE farmid = a AND eventtype = 'Closed' AND closeversion = 2) <> 350 THEN
            RAISE EXCEPTION '333: each close must keep its own snapshot.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.sppoultrydailyclosing_events(a, d) e
                       WHERE e.eventtype = 'Reopened' AND e.reason = 'Late egg sale' AND e.actor = 'owner') THEN
            RAISE EXCEPTION '333: reopen not in history with who/why.';
        END IF;

        -- ---- History is append-only ---------------------------------------
        BEGIN
            UPDATE poultrydailyclosingevents SET reason = 'edited' WHERE farmid = a;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: history could be edited.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Submitted -> Approve goes through the same guarded close ------
        -- Next day for company A: nothing recorded, so production is missing.
        INSERT INTO poultrydailyclosings (farmid, closingdate) VALUES (a, d - 1) RETURNING poultrydailyclosingid INTO v_id;
        UPDATE poultrydailyclosings SET status = 'Submitted' WHERE poultrydailyclosingid = v_id;
        BEGIN
            PERFORM public.sppoultrydailyclosing_approve(v_id, a, 'checker');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: approve bypassed the blockers.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;

        -- ---- Company isolation --------------------------------------------
        ws := public.sppoultrydailyclosing_workspace(b, d, t_day);
        IF (ws->'sales'->>'revenue')::numeric <> 0 OR (ws->'production'->>'expectedFlocks')::int <> 1
           OR (ws->'expenses'->>'total')::numeric <> 0 THEN
            RAISE EXCEPTION '333: company B sees company A''s activity: %', ws;
        END IF;
        SELECT * INTO r FROM public.sppoultrydailyclosing_statusfordate(b, d);
        IF r.closingstatus <> 'Open' OR r.workflowstatus <> 'NotStarted' THEN
            RAISE EXCEPTION '333: company B status wrong: %', r;
        END IF;

        -- ---- Timezone: at 11:30 UTC it is the 11th in Auckland ------------
        ws := public.sppoultrydailyclosing_workspace(a, NULL, t_next);
        IF (ws->>'businessDate')::date <> d + 1 THEN
            RAISE EXCEPTION '333: business date should be % at 11:30 UTC, got %.', d + 1, ws->>'businessDate';
        END IF;
        BEGIN
            PERFORM public.sppoultrydailyclosing_workspace(a, d + 1, t_day);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '333: accepted a future business date.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__333_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '333_PoultryDailyClosingControl: verified (closing reports frozen, complete day, missing production, policy, warnings, blockers, close, duplicate close, correction after close, reopen + reason, history, re-close, approve path, isolation, timezone, financial/production/cash totals).';
END $$;
