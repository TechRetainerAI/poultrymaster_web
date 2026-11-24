-- =============================================================================
-- 484_Enock_GenericSalesListReversed.postgres.sql
--
-- The Generic Sales list shows a reversed sale as "Reversed", not "Cancelled".
--
-- 483 reverses a sale by setting status 'Cancelled' + salereversalid (no new
-- status, so every reader that counts 'Approved' keeps working). The list
-- function did not return salereversalid, so a reversed sale and a cancelled
-- draft looked the same. This adds it as the LAST column (the API reads by
-- column name) and teaches the status filter two words:
--
--   p_status = 'Reversed'   reversed sales only
--   p_status = 'Cancelled'  cancelled sales that were NOT reversed (drafts)
--
-- Reader only: no table or data changes. Needs 483 (salereversalid).
-- A changed RETURNS TABLE cannot be CREATE OR REPLACEd, so drop it first;
-- nothing else in the database calls it.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = 'genericsales' AND column_name = 'salereversalid') THEN
    RAISE EXCEPTION '484 needs 483_Enock_GenericSaleReversal (genericsales.salereversalid) first.';
  END IF;
END $$;

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
  salereversalid integer
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
           s.salereversalid
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
