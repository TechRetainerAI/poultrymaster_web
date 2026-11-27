-- =============================================================================
-- 505_Enock_GenericExpenseListReversed: the Expenses list says which expenses
-- were reversed (504) -- expensereversalid + reversalnumber -- so the page shows
-- "Reversed" instead of "Cancelled". Rebuilt from the live body; read-only list.
-- =============================================================================

DROP FUNCTION IF EXISTS public.spgenericexpense_getall(text, text, timestamp without time zone, timestamp without time zone);
CREATE FUNCTION public.spgenericexpense_getall(p_farmid text, p_status text DEFAULT NULL::text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(genericexpenseid integer, farmid text, expensedate timestamp without time zone, genericexpensecategoryid integer, categoryname text, genericsupplierid integer, suppliername text, description text, amount numeric, paidto text, paymentmethod text, genericcashaccountid integer, cashaccountname text, receipturl text, branchid integer, staffid integer, status text, notes text, createdby text, approvedby text, approvedat timestamp without time zone, rejectionreason text, createdat timestamp without time zone, updatedat timestamp without time zone, amountpaid numeric, duedate date, paymentstatus text, sourcetype text, paymentsapplied numeric, expensereversalid integer, reversalnumber text)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.genericexpenseid, e.farmid::text, e.expensedate,
           e.genericexpensecategoryid, c.name::text,
           e.genericsupplierid, s.suppliername::text,
           e.description::text, e.amount, e.paidto::text, e.paymentmethod::text,
           e.genericcashaccountid, ca.accountname::text, e.receipturl::text, e.branchid, e.staffid,
           e.status::text, e.notes::text, e.createdby::text, e.approvedby::text, e.approvedat,
           e.rejectionreason::text, e.createdat, e.updatedat,
           -- resolved: NULL means paid in full (248)
           COALESCE(e.amountpaid, e.amount), e.duedate, e.paymentstatus, e.sourcetype,
           -- what supplier payments have applied (money is locked while > 0)
           COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                     WHERE sa.farmid = e.farmid AND sa.module = 'generic' AND sa.documenttype = 'Expense'
                       AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted'), 0)::numeric
           , e.expensereversalid, er.reversalnumber::text   -- 505
    FROM   genericexpenses e
    INNER  JOIN genericexpensecategories c ON c.genericexpensecategoryid = e.genericexpensecategoryid
    LEFT   JOIN genericsuppliers s ON s.genericsupplierid = e.genericsupplierid
    LEFT   JOIN genericcashaccounts ca ON ca.genericcashaccountid = e.genericcashaccountid
    LEFT   JOIN genericexpensereversals er ON er.expensereversalid = e.expensereversalid   -- 505
    WHERE  e.farmid = p_farmid AND e.isdeleted = FALSE
       AND (p_status   IS NULL OR e.status = p_status)
       AND (p_fromdate IS NULL OR e.expensedate >= p_fromdate)
       AND (p_todate   IS NULL OR e.expensedate <= p_todate)
    ORDER  BY e.expensedate DESC, e.genericexpenseid DESC;
END
$function$;
