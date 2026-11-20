-- 441: Batch Bird Count measured against the COUNT DATE, and its own permission.
--
-- 1. The count date.  440 worked out each flock's change against its birds
--    TODAY.  Counted yesterday, with today's deaths already entered, that
--    counted today's deaths twice (counted 861 yesterday, 5 died today:
--    today is 856, but 440 set it to 861).
--    fnflock_birdsendofday gives a flock's birds at the END of a date: today's
--    birds with everything dated after that day rolled back -- deaths on later
--    production records and later bird sales added back, later bird count
--    corrections taken off.  Checked against fnflock_birdpositionasof on every
--    open flock's last three record dates: the same figure wherever the flock
--    has no corrections; where it has, this one dates a correction to the day it
--    was made, not to the record it was written onto.
--    The change (counted - birds on the count date) is still posted through
--    sppoultrymanualmovement_post, which adds it to the latest record, so today
--    = counted - what happened since the count.  A second count for the same
--    date sees the first one (it is dated that day) and changes nothing more.
--    sppoultrybirdcount_sheet: the open flocks of a batch with their birds on
--    the count date and now, for the page.
--
-- 2. Permission.  Its own resource, poultry.bird-count, so setting the birds of
--    a whole batch is not simply "can add a stock movement":
--      view   -- open the page   (every role / user that holds poultry.stock.view)
--      create -- save a count    (Owner, Company Admin, Organization Admin and
--                                Manager only: Data Entry and Storekeeper can
--                                edit stock, but resetting a whole batch's birds
--                                is a manager's call; grant it in IAM to anyone
--                                else.  A user's Deny on poultry.stock.edit
--                                carries over as a Deny.)
--    The API maps api/Poultry/stock/bird-count to it (IamPermissionMap); the web
--    app shows the Tools row and the button only to holders.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1a. A flock's birds at the end of a date.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnflock_birdsendofday(p_farmid text, p_flockid integer, p_date date)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT GREATEST(
             bp.currentlivebirds
           + COALESCE((SELECT SUM(COALESCE(r.mortality, 0)) FROM productionrecords r
                       WHERE r.farmid = p_farmid AND r.flockid = p_flockid AND r.date::date > p_date), 0)::int
           + COALESCE((SELECT ROUND(SUM(sa.quantity)) FROM sale sa
                       WHERE sa.farmid = p_farmid AND sa.flockid = p_flockid AND sa.status = 'Posted'
                         AND public.fnpoultrysale_isbirdsale(sa.product) AND sa.saledate::date > p_date), 0)::int
           - COALESCE((SELECT SUM(a.quantity) FROM poultrybirdadjustments a
                       WHERE a.farmid = p_farmid AND a.flockid = p_flockid AND a.scope = 'Flock'
                         AND a.adjustmentdate > p_date), 0)::int,
           0)
    FROM   public.fnflock_birdposition(p_farmid, p_flockid) bp;
$function$;

-- ---------------------------------------------------------------------------
-- 1b. The count sheet: a batch's open flocks, birds on the count date and now.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrybirdcount_sheet(p_farmid text, p_batchid integer, p_date date)
 RETURNS TABLE(flockid integer, flockname text, startdate date, birdsondate integer, birdsnow integer, hasproductionrecord boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT f.flockid, f.name::text, f.startdate::date,
           CASE WHEN f.startdate::date > COALESCE(p_date, public.fncompany_businessdate(p_farmid)) THEN NULL
                ELSE public.fnflock_birdsendofday(p_farmid, f.flockid, COALESCE(p_date, public.fncompany_businessdate(p_farmid))) END,
           bp.currentlivebirds,
           bp.productionrecordcount > 0
    FROM   flock f
    CROSS  JOIN LATERAL public.fnflock_birdposition(p_farmid, f.flockid) bp
    WHERE  f.farmid = p_farmid AND f.batchid = p_batchid
      AND  NOT COALESCE(f.isdeleted, FALSE) AND f.closeddate IS NULL
    ORDER  BY f.name, f.flockid;
$function$;

-- ---------------------------------------------------------------------------
-- 1c. The save, now against the birds on the count date.  currentBirds in a
--     line is the birds ON THE COUNT DATE the page showed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrymanualmovement_bulkbirdcount(
    p_farmid        text,
    p_batchid       integer,
    p_effectivedate date,
    p_lines         jsonb,        -- [{ "flockId": 1, "countedBirds": 861, "currentBirds": 900 }]
    p_note          text DEFAULT NULL,
    p_requestkey    text DEFAULT NULL,
    p_by            text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_key      text := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    v_note     text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_date     date := COALESCE(p_effectivedate, public.fncompany_businessdate(p_farmid));
    v_birds    integer;
    v_batch    record;
    v_line     jsonb;
    v_flockid  integer;
    v_counted  numeric;
    v_shown    numeric;
    v_flock    record;
    v_then     integer;
    v_change   integer;
    v_res      jsonb;
    v_out      jsonb := '[]'::jsonb;
    v_before   integer := 0;
    v_after    integer := 0;
    v_posted   integer := 0;
    v_seen     integer[] := ARRAY[]::integer[];
BEGIN
    -- The same save sent twice (double click, retry) returns what it posted.
    IF v_key IS NOT NULL AND EXISTS (
        SELECT 1 FROM poultrymanualstockmovements m
        WHERE  m.farmid = p_farmid AND m.requestkey LIKE v_key || ':%') THEN
        RETURN jsonb_build_object('repeated', TRUE, 'movements',
            (SELECT COALESCE(jsonb_agg(jsonb_build_object('flockId', m.flockid, 'movementNo', m.movementno,
                                                           'change', m.quantity) ORDER BY m.movementid), '[]'::jsonb)
             FROM poultrymanualstockmovements m
             WHERE m.farmid = p_farmid AND m.requestkey LIKE v_key || ':%'));
    END IF;

    SELECT b.batchid, b.batchcode INTO v_batch FROM mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose the batch.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date > public.fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'The count date (%) is in the future.', v_date USING ERRCODE = 'P0001';
    END IF;
    IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
        RAISE EXCEPTION 'Enter the counted birds for at least one flock.' USING ERRCODE = 'P0001';
    END IF;

    SELECT p.poultryproductid INTO v_birds FROM poultryproducts p
    WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) OR p.name = 'Birds') AND p.systemrole IS NULL
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid LIMIT 1;
    IF v_birds IS NULL THEN
        RAISE EXCEPTION 'This company has no Birds item yet.' USING ERRCODE = 'P0001';
    END IF;

    -- One count at a time per farm, so two people cannot both apply a change.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-msm:' || p_farmid));

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        v_flockid := NULLIF(v_line->>'flockId', '')::integer;
        v_counted := NULLIF(v_line->>'countedBirds', '')::numeric;
        v_shown   := NULLIF(v_line->>'currentBirds', '')::numeric;
        CONTINUE WHEN v_counted IS NULL;            -- a flock left blank is not counted

        IF v_flockid IS NULL THEN
            RAISE EXCEPTION 'Every counted line needs its flock.' USING ERRCODE = 'P0001';
        END IF;
        IF v_flockid = ANY (v_seen) THEN
            RAISE EXCEPTION 'A flock is listed twice.' USING ERRCODE = 'P0001';
        END IF;
        v_seen := v_seen || v_flockid;

        SELECT f.flockid, f.name::text AS name, f.batchid, f.startdate::date AS startdate INTO v_flock FROM flock f
        WHERE  f.flockid = v_flockid AND f.farmid = p_farmid AND NOT f.isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That flock does not belong to this company.' USING ERRCODE = 'P0001';
        END IF;
        IF v_flock.batchid IS DISTINCT FROM p_batchid THEN
            RAISE EXCEPTION 'Flock "%" is not part of batch %.', v_flock.name, v_batch.batchcode USING ERRCODE = 'P0001';
        END IF;
        IF v_counted < 0 OR v_counted <> trunc(v_counted) THEN
            RAISE EXCEPTION 'Flock "%": the counted birds must be a whole number, 0 or more.', v_flock.name USING ERRCODE = 'P0001';
        END IF;
        IF v_flock.startdate IS NOT NULL AND v_date < v_flock.startdate THEN
            RAISE EXCEPTION 'Flock "%" started on %, so it had no birds on %.', v_flock.name, v_flock.startdate, v_date
                USING ERRCODE = 'P0001';
        END IF;

        -- 441: the birds at the end of the count date, not today.
        v_then := public.fnflock_birdsendofday(p_farmid, v_flockid, v_date);
        IF v_shown IS NOT NULL AND v_shown <> v_then THEN
            RAISE EXCEPTION 'Flock "%" had % birds on %, not % as shown. Reload and enter the count again.',
                  v_flock.name, v_then, v_date, trim_scale(v_shown) USING ERRCODE = 'P0001';
        END IF;

        v_change := v_counted::integer - v_then;
        v_before := v_before + v_then;
        v_after  := v_after + v_counted::integer;

        IF v_change <> 0 THEN
            v_res := sppoultrymanualmovement_post(
                p_farmid => p_farmid, p_poultryproductid => v_birds, p_rawmaterialitemid => NULL,
                p_movementtype => CASE WHEN v_change > 0 THEN 'Increase' ELSE 'Decrease' END,
                p_quantity => abs(v_change), p_unitcost => NULL, p_batchid => p_batchid, p_flockid => v_flockid,
                p_effectivedate => v_date, p_reason => 'Stock Count Correction', p_disposition => NULL,
                p_note => concat_ws(' - ', 'Batch bird count: ' || v_counted::integer || ' counted on '
                                          || to_char(v_date, 'DD Mon YYYY') || ', was ' || v_then, v_note),
                p_requestkey => CASE WHEN v_key IS NOT NULL THEN v_key || ':' || v_flockid END,
                p_by => p_by, p_scope => 'Flock');
            v_posted := v_posted + 1;
        ELSE
            v_res := NULL;
        END IF;

        v_out := v_out || jsonb_build_object(
            'flockId', v_flockid, 'flockName', v_flock.name, 'before', v_then,
            'counted', v_counted::integer, 'change', v_change, 'movementNo', v_res->>'movementNo');
    END LOOP;

    IF v_posted = 0 THEN
        RAISE EXCEPTION 'Every count matches the birds on that date, so there is nothing to adjust.' USING ERRCODE = 'P0001';
    END IF;

    RETURN jsonb_build_object(
        'repeated', FALSE, 'batchId', p_batchid, 'countDate', v_date, 'posted', v_posted,
        'totalBefore', v_before, 'totalAfter', v_after, 'movements', v_out,
        'farmLiveBirds', fnpoultry_farmlivebirds(p_farmid));
END
$function$;

-- ---------------------------------------------------------------------------
-- 2. Permission: poultry.bird-count.view / .create.
-- ---------------------------------------------------------------------------
DO $iam$
DECLARE
    v_added_keys  integer := 0;
    v_added_roles integer := 0;
    v_added_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '441: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.bird-count.' || a.action, 'poultry', 'bird-count', a.action,
           'Flock & Birds', 'Batch Bird Count',
           'Setting every flock of a batch to the birds counted in its pens, in one '
           || 'save. Each flock''s difference is posted as a Stock Count Correction.',
           'Poultry', FALSE, 12
    FROM (VALUES ('view'), ('create')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_added_keys = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, 'poultry.bird-count.view'
        FROM   iamrolepermissions rp
        WHERE  rp.permissionkey = 'poultry.stock.view'
        UNION
        SELECT r.roleid, 'poultry.bird-count.create'
        FROM   iamroles r
        WHERE  r.rolekey IN ('sys-owner', 'sys-company-admin', 'sys-org-admin', 'sys-manager')
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- Farm-scoped and carrying an effect; copied verbatim so a Deny stays a Deny.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 441',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('poultry.stock.view', 'poultry.bird-count.view',   NULL),
                  ('poultry.stock.edit', 'poultry.bird-count.create', 'Deny')
               ) AS m(old_key, new_key, only_effect) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (m.only_effect IS NULL OR up.effect = m.only_effect)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '441: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;
