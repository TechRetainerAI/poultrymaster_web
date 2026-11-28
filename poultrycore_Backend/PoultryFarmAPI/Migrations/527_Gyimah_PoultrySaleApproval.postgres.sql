-- =============================================================================
-- 527_Gyimah_PoultrySaleApproval.postgres.sql (written as 522; renumbered after dev took 522-526)
--
-- Poultry sales get an approval step (decided 2026-11-28).
--
--   * A sale entered by someone WITHOUT poultry.sales.approve (and not the
--     owner) waits for approval instead of posting.
--   * Owners and staff holding poultry.sales.approve post straight away, as
--     today.
--   * One switch per poultry company, "Sales by staff need approval",
--     ON unless the company turns it off (no row = on).
--   * A waiting sale can be edited (by the person who entered it or an
--     approver), approved, rejected with a reason, or withdrawn. A rejected
--     sale can be edited and sent again.
--
-- How: a waiting sale is NOT a sale row. It is the request exactly as the form
-- (web or mobile) sent it, kept in poultrypendingsales. Approving it runs the
-- same posting code as today (SaleService.Insert / CreateGroup), as the person
-- who entered it, so stock, eggs, cash, customer credit, part payments and
-- correction links behave exactly as an ordinary sale. Nothing that reads
-- sales -- reports, P&L, cash flow, bird counts, Daily Closing -- sees a
-- waiting sale, so none of them change.
--
-- Approving is claimed first (Waiting -> Approving) so two approvers cannot
-- post the same sale twice; a failed post puts it back to Waiting with the
-- reason. Idempotent.
-- =============================================================================

BEGIN;

-- ------------------------------------------------------------- settings -----
CREATE TABLE IF NOT EXISTS public.poultrysalessettings (
    farmid        text PRIMARY KEY,
    needapproval  boolean NOT NULL DEFAULT TRUE,
    updatedby     text NULL,
    updatedat     timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc')
);

CREATE OR REPLACE FUNCTION public.fnpoultrysales_needapproval(p_farmid text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT s.needapproval FROM poultrysalessettings s WHERE s.farmid = p_farmid), TRUE);
$$;

CREATE OR REPLACE FUNCTION public.sppoultrysalessettings_set(p_farmid text, p_needapproval boolean, p_by text)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO poultrysalessettings (farmid, needapproval, updatedby, updatedat)
    VALUES (p_farmid, p_needapproval, p_by, now() at time zone 'utc')
    ON CONFLICT (farmid) DO UPDATE
        SET needapproval = EXCLUDED.needapproval, updatedby = EXCLUDED.updatedby, updatedat = EXCLUDED.updatedat;
    RETURN p_needapproval;
END $$;

-- -------------------------------------------------------- waiting sales -----
CREATE TABLE IF NOT EXISTS public.poultrypendingsales (
    pendingsaleid    serial PRIMARY KEY,
    farmid           text NOT NULL,
    -- 'single' = POST api/Sale body (SaleModel); 'group' = POST api/Sale/group body.
    kind             text NOT NULL CHECK (kind IN ('single', 'group')),
    payload          jsonb NOT NULL,
    -- Copied out of the payload for the list; the payload is what is posted.
    saledate         timestamp without time zone NULL,
    customername     text NULL,
    summary          text NULL,
    totalamount      numeric(18,2) NOT NULL DEFAULT 0,
    linecount        integer NOT NULL DEFAULT 1,
    status           text NOT NULL DEFAULT 'Waiting'
                     CHECK (status IN ('Waiting', 'Approving', 'Approved', 'Rejected', 'Withdrawn')),
    submittedby      text NOT NULL,
    submittedat      timestamp without time zone NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby        text NULL,
    updatedat        timestamp without time zone NULL,
    decidedby        text NULL,
    decidedat        timestamp without time zone NULL,
    rejectionreason  text NULL,
    lasterror        text NULL,
    postedsaleid     integer NULL,
    postedsalelabel  text NULL
);
CREATE INDEX IF NOT EXISTS ix_poultrypendingsales_farm_status ON public.poultrypendingsales (farmid, status);

DROP FUNCTION IF EXISTS public.sppoultrypendingsale_list(text, text);
CREATE FUNCTION public.sppoultrypendingsale_list(p_farmid text, p_status text DEFAULT NULL)
RETURNS TABLE (pendingsaleid integer, kind text, payload jsonb, saledate timestamp without time zone,
               customername text, summary text, totalamount numeric, linecount integer, status text,
               submittedby text, submittedbyname text, submittedat timestamp without time zone,
               updatedat timestamp without time zone, decidedby text, decidedbyname text,
               decidedat timestamp without time zone, rejectionreason text, lasterror text,
               postedsaleid integer, postedsalelabel text)
LANGUAGE sql STABLE AS $$
    SELECT p.pendingsaleid, p.kind, p.payload, p.saledate, p.customername, p.summary, p.totalamount,
           p.linecount, p.status, p.submittedby, su.username, p.submittedat, p.updatedat,
           p.decidedby, du.username, p.decidedat, p.rejectionreason, p.lasterror,
           p.postedsaleid, p.postedsalelabel
    FROM   poultrypendingsales p
    LEFT   JOIN aspnetusers su ON su.id = p.submittedby
    LEFT   JOIN aspnetusers du ON du.id = p.decidedby
    WHERE  p.farmid = p_farmid
      AND  (p_status IS NULL OR p.status = p_status
            -- "Waiting" on the page includes one mid-approval.
            OR (p_status = 'Waiting' AND p.status = 'Approving'))
    ORDER  BY CASE WHEN p.status IN ('Waiting', 'Approving') THEN 0 ELSE 1 END,
              COALESCE(p.decidedat, p.updatedat, p.submittedat) DESC;
$$;

CREATE OR REPLACE FUNCTION public.sppoultrypendingsale_submit(
    p_farmid text, p_kind text, p_payload jsonb, p_saledate timestamp without time zone,
    p_customername text, p_summary text, p_totalamount numeric, p_linecount integer, p_by text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
    INSERT INTO poultrypendingsales (farmid, kind, payload, saledate, customername, summary,
                                     totalamount, linecount, submittedby)
    VALUES (p_farmid, p_kind, p_payload, p_saledate, NULLIF(trim(p_customername), ''), p_summary,
            COALESCE(p_totalamount, 0), GREATEST(COALESCE(p_linecount, 1), 1), p_by)
    RETURNING pendingsaleid INTO v_id;
    RETURN v_id;
END $$;

-- Edit a waiting (or rejected) sale. A rejected one edited goes back to Waiting.
CREATE OR REPLACE FUNCTION public.sppoultrypendingsale_update(
    p_pendingsaleid integer, p_farmid text, p_kind text, p_payload jsonb,
    p_saledate timestamp without time zone, p_customername text, p_summary text,
    p_totalamount numeric, p_linecount integer, p_by text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
    SELECT p.status INTO v_status FROM poultrypendingsales p
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'This sale is no longer waiting for approval.'; END IF;
    IF v_status NOT IN ('Waiting', 'Rejected') THEN
        RAISE EXCEPTION 'This sale is % and can no longer be changed.', lower(v_status);
    END IF;
    UPDATE poultrypendingsales p
    SET    kind = p_kind, payload = p_payload, saledate = p_saledate,
           customername = NULLIF(trim(p_customername), ''), summary = p_summary,
           totalamount = COALESCE(p_totalamount, 0), linecount = GREATEST(COALESCE(p_linecount, 1), 1),
           status = 'Waiting', rejectionreason = NULL, lasterror = NULL,
           decidedby = NULL, decidedat = NULL,
           updatedby = p_by, updatedat = now() at time zone 'utc'
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid;
END $$;

-- Claim for approval. A claim older than 10 minutes is treated as abandoned
-- (the API died mid-post) and may be claimed again; the group path is
-- idempotent on its request key, so a repeat cannot post twice.
DROP FUNCTION IF EXISTS public.sppoultrypendingsale_claim(integer, text, text);
CREATE FUNCTION public.sppoultrypendingsale_claim(p_pendingsaleid integer, p_farmid text, p_by text)
RETURNS TABLE (kind text, payload jsonb, submittedby text)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    SELECT p.* INTO r FROM poultrypendingsales p
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid FOR UPDATE;
    IF r.pendingsaleid IS NULL THEN RAISE EXCEPTION 'Waiting sale #% was not found.', p_pendingsaleid; END IF;
    IF r.status = 'Approving' AND r.decidedat > (now() at time zone 'utc') - interval '10 minutes' THEN
        RAISE EXCEPTION 'This sale is already being approved.';
    END IF;
    IF r.status NOT IN ('Waiting', 'Approving') THEN
        RAISE EXCEPTION 'This sale is % and cannot be approved.', lower(r.status);
    END IF;
    UPDATE poultrypendingsales p
    SET    status = 'Approving', decidedby = p_by, decidedat = now() at time zone 'utc', lasterror = NULL
    WHERE  p.pendingsaleid = p_pendingsaleid;
    RETURN QUERY SELECT r.kind, r.payload, r.submittedby;
END $$;

CREATE OR REPLACE FUNCTION public.sppoultrypendingsale_markapproved(
    p_pendingsaleid integer, p_farmid text, p_saleid integer, p_label text, p_by text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE poultrypendingsales p
    SET    status = 'Approved', postedsaleid = p_saleid, postedsalelabel = p_label,
           decidedby = p_by, decidedat = now() at time zone 'utc', lasterror = NULL
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid AND p.status = 'Approving';
END $$;

-- The post failed (not enough stock, a closed day …): back to Waiting, saying why.
CREATE OR REPLACE FUNCTION public.sppoultrypendingsale_release(p_pendingsaleid integer, p_farmid text, p_error text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE poultrypendingsales p
    SET    status = 'Waiting', decidedby = NULL, decidedat = NULL, lasterror = p_error
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid AND p.status = 'Approving';
END $$;

CREATE OR REPLACE FUNCTION public.sppoultrypendingsale_reject(
    p_pendingsaleid integer, p_farmid text, p_reason text, p_by text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
    IF NULLIF(trim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'Give a reason for rejecting this sale.'; END IF;
    SELECT p.status INTO v_status FROM poultrypendingsales p
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid FOR UPDATE;
    IF v_status IS DISTINCT FROM 'Waiting' THEN
        RAISE EXCEPTION 'Only a sale waiting for approval can be rejected.';
    END IF;
    UPDATE poultrypendingsales p
    SET    status = 'Rejected', rejectionreason = trim(p_reason),
           decidedby = p_by, decidedat = now() at time zone 'utc'
    WHERE  p.pendingsaleid = p_pendingsaleid;
END $$;

CREATE OR REPLACE FUNCTION public.sppoultrypendingsale_withdraw(p_pendingsaleid integer, p_farmid text, p_by text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
    SELECT p.status INTO v_status FROM poultrypendingsales p
    WHERE  p.pendingsaleid = p_pendingsaleid AND p.farmid = p_farmid FOR UPDATE;
    IF v_status NOT IN ('Waiting', 'Rejected') OR v_status IS NULL THEN
        RAISE EXCEPTION 'Only a waiting or rejected sale can be withdrawn.';
    END IF;
    UPDATE poultrypendingsales p
    SET    status = 'Withdrawn', decidedby = p_by, decidedat = now() at time zone 'utc'
    WHERE  p.pendingsaleid = p_pendingsaleid;
END $$;

COMMIT;
