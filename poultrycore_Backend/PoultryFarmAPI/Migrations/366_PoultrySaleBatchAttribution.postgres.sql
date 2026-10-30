-- =============================================================================
-- 366_PoultrySaleBatchAttribution.postgres.sql
--
-- Purpose
-- -------
-- New Sale gets a Batch field before Flock: Customer | Sale Date | Batch | Flock.
-- Both are OPTIONAL attribution -- eggs are often pooled from several flocks.
-- They are reporting fields only: stock still comes from the sale lines.
--
--   sale.batchid            new, nullable (mainflockbatch.batchid)
--   trg_sale_batch          on every insert / flock or batch change:
--                             a flock fills in its own batch (flock.batchid);
--                             a batch that does not match the flock is refused;
--                             a batch from another farm is refused.
--                           So every path that writes a sale (Add Sale, the
--                           split, driver returns, closeout) is covered without
--                           changing their signatures.
--   sppoultrysale_setbatch  the API's call for a sale attributed to a batch
--                           with no single flock, in the sale's own transaction.
--
-- Old sales are NOT backfilled (a posted sale is not rewritten); readers can
-- fall back to the flock's batch.
--
-- Deploy order: this migration, then the API, then the web app. The new API
-- calls sppoultrysale_setbatch only when a batch is chosen.
-- =============================================================================
BEGIN;

ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS batchid integer;
CREATE INDEX IF NOT EXISTS ix_sale_batch ON public.sale (farmid, batchid) WHERE batchid IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fnsale_batchattribution()
RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE
    v_flockbatch integer;
BEGIN
    -- A new flock on an existing sale re-derives the batch.
    IF TG_OP = 'UPDATE' AND NEW.flockid IS DISTINCT FROM OLD.flockid
       AND NEW.batchid IS NOT DISTINCT FROM OLD.batchid THEN
        NEW.batchid := NULL;
    END IF;

    IF COALESCE(NEW.flockid, 0) <> 0 THEN
        SELECT f.batchid INTO v_flockbatch
        FROM   public.flock f
        WHERE  f.flockid = NEW.flockid AND f.farmid::text = NEW.farmid::text;
        IF v_flockbatch IS NOT NULL THEN
            IF NEW.batchid IS NULL THEN
                NEW.batchid := v_flockbatch;
            ELSIF NEW.batchid <> v_flockbatch THEN
                RAISE EXCEPTION 'That flock is not in the chosen batch. Choose a flock from the batch, or All flocks.';
            END IF;
        END IF;
    END IF;

    IF NEW.batchid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.mainflockbatch b
        WHERE  b.batchid = NEW.batchid AND b.farmid::text = NEW.farmid::text) THEN
        RAISE EXCEPTION 'That batch does not belong to this farm.';
    END IF;
    RETURN NEW;
END
$f$;

DROP TRIGGER IF EXISTS trg_sale_batch ON public.sale;
CREATE TRIGGER trg_sale_batch
    BEFORE INSERT OR UPDATE OF flockid, batchid ON public.sale
    FOR EACH ROW EXECUTE FUNCTION public.fnsale_batchattribution();

CREATE OR REPLACE FUNCTION public.sppoultrysale_setbatch(p_farmid text, p_saleids integer[], p_batchid integer)
RETURNS void LANGUAGE sql AS $f$
    -- trg_sale_batch checks the batch against the farm and the sale's flock.
    UPDATE public.sale s
    SET    batchid = p_batchid
    WHERE  s.farmid = p_farmid AND s.saleid = ANY(p_saleids)
      AND  s.batchid IS DISTINCT FROM p_batchid;
$f$;

-- ---------------------------------------- posted guard: batch is attribution --
-- The sale's own transaction may still set it (poultry.sale_fresh returns
-- early above this check); afterwards it is as fixed as the flock.
DO $$
DECLARE
    v_def text := replace(pg_get_functiondef('public.trg_sale_postedguard_fn'::regproc), chr(13), '');
    v_old text := '       OR NEW.flockid      IS DISTINCT FROM OLD.flockid' || chr(10);
    v_new text := '       OR NEW.flockid      IS DISTINCT FROM OLD.flockid' || chr(10)
               || '       OR NEW.batchid      IS DISTINCT FROM OLD.batchid   -- 366' || chr(10);
BEGIN
    IF position('OLD.batchid' IN v_def) > 0 THEN
        RAISE NOTICE '366: posted guard already covers batchid, skipped';
    ELSIF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
        RAISE EXCEPTION '366: posted guard anchor not found exactly once';
    ELSE
        EXECUTE replace(v_def, v_old, v_new);
        RAISE NOTICE '366: posted guard now covers batchid';
    END IF;
END $$;

-- ------------------------------------------------ readers return the batch --
-- spsale_getall / _getbyid / _getbyflock: batchid appended to their result,
-- rebuilt from the LIVE bodies. An old sale with no batch of its own shows
-- its flock's batch.
DO $$
DECLARE
    v_fn   text;
    v_oid  oid;
    v_args text;
    v_def  text;
    v_ret  text := 'correctedbysaleid integer, linecount integer, salelines text)';
    v_sel  text := 'fnpoultrysale_lines(s.saleid)::text' || chr(10) || '    FROM   sale s';
BEGIN
    FOREACH v_fn IN ARRAY ARRAY['spsale_getall', 'spsale_getbyid', 'spsale_getbyflock'] LOOP
        SELECT p.oid, pg_get_function_identity_arguments(p.oid) INTO v_oid, v_args
        FROM   pg_proc p WHERE p.proname = v_fn AND p.pronamespace = 'public'::regnamespace;
        v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
        IF position('batchid integer)' IN v_def) > 0 THEN
            RAISE NOTICE '366: % already returns batchid, skipped', v_fn;
            CONTINUE;
        END IF;
        IF (length(v_def) - length(replace(v_def, v_ret, ''))) / length(v_ret) <> 1
           OR (length(v_def) - length(replace(v_def, v_sel, ''))) / length(v_sel) <> 1 THEN
            RAISE EXCEPTION '366: anchors for % not found exactly once', v_fn;
        END IF;
        v_def := replace(v_def, v_ret, 'correctedbysaleid integer, linecount integer, salelines text, batchid integer)');
        v_def := replace(v_def, v_sel,
            'fnpoultrysale_lines(s.saleid)::text,' || chr(10)
            || '           -- 366: the sale''s batch, else its flock''s' || chr(10)
            || '           COALESCE(s.batchid, (SELECT f.batchid FROM flock f' || chr(10)
            || '                                WHERE f.flockid = s.flockid AND f.farmid = s.farmid))' || chr(10)
            || '    FROM   sale s');
        EXECUTE format('DROP FUNCTION public.%I(%s)', v_fn, v_args);
        EXECUTE v_def;
        RAISE NOTICE '366: % now returns batchid', v_fn;
    END LOOP;
END $$;

COMMIT;
