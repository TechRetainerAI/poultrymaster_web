-- =============================================================================
-- 485_Enock_GenericSaleCorrection.postgres.sql
--
-- "Correct sale" and "Edit & repost" for Generic sales -- the Water 458 model.
--
--   Correct sale    reverse the sale (483), then open New sale filled in from it
--   Edit & repost   the same New sale, later, from a sale already reversed
--
-- Either way the new sale is LINKED to the reversed one it replaces:
--   genericsales.correctssaleid  on the new sale -> the reversed sale
-- One live correction per reversed sale. "Live" = not cancelled and not
-- deleted, so if the correcting draft is cancelled the reversed sale can be
-- reposted again (Water stores the link on the reversal; a Generic sale is a
-- Draft first and drafts get cancelled, so here it is worked out instead).
--
-- No money or stock moves here: the new sale is an ordinary sale (Draft ->
-- Approve). Needs 483 (reversal) and 484 (list returns salereversalid).
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'spgenericsale_reversalget') THEN
    RAISE EXCEPTION '485 needs 483_Enock_GenericSaleReversal first.';
  END IF;
END $$;

-- ------------------------------------------------------------------ 1. schema --
ALTER TABLE public.genericsales ADD COLUMN IF NOT EXISTS correctssaleid integer NULL;
CREATE INDEX IF NOT EXISTS ix_genericsales_correctssale
    ON public.genericsales (correctssaleid) WHERE correctssaleid IS NOT NULL;

-- ------------------------------------------------- 2. the live correction --
-- The sale that corrects a reversed sale now, if any.
CREATE OR REPLACE FUNCTION public.fngenericsale_correctedby(p_farmid text, p_saleid integer)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT min(n.genericsaleid)
    FROM   genericsales n
    WHERE  n.farmid = p_farmid AND n.correctssaleid = p_saleid
      AND  n.isdeleted = FALSE AND n.status <> 'Cancelled';
$$;

-- ------------------------------------------------------------ 3. the link --
DROP FUNCTION IF EXISTS public.spgenericsale_linkcorrection(text, integer, integer, text);
CREATE FUNCTION public.spgenericsale_linkcorrection(p_farmid text, p_newsaleid integer, p_correctssaleid integer, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_prev integer;
BEGIN
    IF p_newsaleid = p_correctssaleid THEN
        RAISE EXCEPTION 'A sale cannot correct itself.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericsales s WHERE s.genericsaleid = p_newsaleid AND s.farmid = p_farmid
                   AND s.isdeleted = FALSE AND s.salereversalid IS NULL AND s.status <> 'Cancelled') THEN
        RAISE EXCEPTION 'The corrected sale was not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM genericsales s WHERE s.genericsaleid = p_correctssaleid AND s.farmid = p_farmid
                   AND s.salereversalid IS NOT NULL) THEN
        RAISE EXCEPTION 'Sale #% is not a reversed sale of this company, so nothing can be corrected from it.', p_correctssaleid
            USING ERRCODE = 'P0001';
    END IF;
    v_prev := fngenericsale_correctedby(p_farmid, p_correctssaleid);
    IF v_prev IS NOT NULL AND v_prev <> p_newsaleid THEN
        RAISE EXCEPTION 'Sale #% was already corrected by sale #%.', p_correctssaleid, v_prev USING ERRCODE = 'P0001';
    END IF;

    UPDATE genericsales s SET correctssaleid = p_correctssaleid, updatedat = (now() AT TIME ZONE 'UTC')
    WHERE  s.farmid = p_farmid AND s.genericsaleid = p_newsaleid
      AND  s.correctssaleid IS DISTINCT FROM p_correctssaleid;
END $f$;

-- ------------------------------------------- 4. the list (484 + 2 columns) --
DROP FUNCTION IF EXISTS spgenericsale_getall(text, text);
CREATE FUNCTION spgenericsale_getall(p_farmid text, p_status text DEFAULT NULL::text)
RETURNS TABLE(
  genericsaleid integer, farmid text, saledate timestamp without time zone, genericcustomerid integer,
  customername text, branchid integer, salestype text, saleschannel text, salespersonstaffid integer,
  subtotalamount numeric, discountamount numeric, taxamount numeric, totalamount numeric,
  amountpaid numeric, balance numeric, paymentstatus text, paymentmethod text,
  genericcashaccountid integer, receiptnumber text, status text, notes text, createdby text,
  approvedby text, approvedat timestamp without time zone, cancelledby text,
  cancelledat timestamp without time zone, cancellationreason text,
  createdat timestamp without time zone, updatedat timestamp without time zone,
  salereversalid integer, correctssaleid integer, correctedbysaleid integer
)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.genericsaleid, s.farmid::text, s.saledate, s.genericcustomerid,
           c.customername::text, s.branchid, s.salestype::text, s.saleschannel::text,
           s.salespersonstaffid, s.subtotalamount, s.discountamount,
           s.taxamount, s.totalamount, s.amountpaid, s.balance,
           s.paymentstatus::text, s.paymentmethod::text, s.genericcashaccountid,
           s.receiptnumber::text, s.status::text, s.notes::text,
           s.createdby::text, s.approvedby::text, s.approvedat,
           s.cancelledby::text, s.cancelledat, s.cancellationreason::text,
           s.createdat, s.updatedat,
           s.salereversalid, s.correctssaleid,
           CASE WHEN s.salereversalid IS NOT NULL THEN fngenericsale_correctedby(s.farmid, s.genericsaleid) END
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    WHERE  s.farmid = p_farmid AND s.isdeleted = FALSE
       AND (
             p_status IS NULL
          OR (p_status = 'Reversed'  AND s.salereversalid IS NOT NULL)
          OR (p_status = 'Cancelled' AND s.status = 'Cancelled' AND s.salereversalid IS NULL)
          OR (p_status NOT IN ('Reversed', 'Cancelled') AND s.status = p_status)
       )
    ORDER  BY s.saledate DESC, s.genericsaleid DESC;
END;
$function$;

-- --------------------------------- 5. the reversal record names its correction --
DROP FUNCTION IF EXISTS public.spgenericsale_reversalget(text, integer);
CREATE FUNCTION public.spgenericsale_reversalget(p_farmid text, p_saleid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'salereversalid', r.salereversalid, 'reversalNumber', r.reversalnumber, 'saleIds', jsonb_build_array(r.genericsaleid),
        'reasonCode', r.reasoncode, 'reason', r.reason, 'businessDate', r.businessdate, 'occurredAt', r.occurredat,
        'reversedBy', r.reversedby, 'paymentHandling', r.paymenthandling,
        'total', r.totalamount, 'paid', r.paidamount, 'outstanding', r.outstandingamount,
        'creditCreated', r.creditcreated, 'cashReversed', r.cashreversed, 'creditReleased', r.creditreleased,
        'correctionSaleId', fngenericsale_correctedby(r.farmid, r.genericsaleid),
        'payments', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'paymentGroupId', rp.itemkey, 'paymentNumbers', rp.paymentnumbers, 'source', rp.sourcetype,
                        'amount', rp.amount, 'action', rp.action, 'recordedAtReversal', rp.itemkey = 'AT-SALE')
                        ORDER BY rp.salereversalpaymentid)
                     FROM genericsalereversalpayments rp WHERE rp.salereversalid = r.salereversalid), '[]'::jsonb),
        'lines', r.snapshot->'lines')
    FROM genericsalereversals r
    WHERE r.farmid = p_farmid AND r.genericsaleid = p_saleid;
$$;
