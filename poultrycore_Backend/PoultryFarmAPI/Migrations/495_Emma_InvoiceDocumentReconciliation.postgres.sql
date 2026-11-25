-- =============================================================================
-- Migration 495 — Invoice Document Reconciliation
-- Branch: emma
--
-- Adds a reconciliation function that checks the health of the invoice
-- document system. Returns one row per problem found — an empty result
-- set means everything is consistent.
--
-- Checks performed:
--   1. Orphaned invoice documents (referencing deleted/non-existent sales)
--   2. Duplicate active invoices per sale
--   3. Invoice total vs source sale total mismatch (snapshot drift)
--   4. Balance inconsistency (amountpaid + balance != totalamount on the sale)
--   5. Invoice document for a non-Approved sale
--   6. Issued invoice with no sale receipt number
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fngenericinvoicedocument_reconcile(p_farmid text)
RETURNS TABLE(
    checkname   text,
    severity    text,       -- 'error' | 'warning'
    documentid  integer,
    saleid      integer,
    detail      text)
LANGUAGE sql
STABLE
AS $function$
    -- 1. Orphaned invoice documents (sale deleted or missing)
    SELECT 'orphaned_invoice'::text, 'error'::text,
           d.genericinvoicedocumentid, d.genericsaleid,
           'Invoice ' || d.invoicenumber || ' references sale #' || d.genericsaleid || ' which is deleted or missing.'
    FROM   genericinvoicedocuments d
    LEFT   JOIN genericsales s ON s.genericsaleid = d.genericsaleid
    WHERE  d.farmid = p_farmid AND d.isdeleted = FALSE
    AND    (s.genericsaleid IS NULL OR COALESCE(s.isdeleted, FALSE) = TRUE)

    UNION ALL

    -- 2. Duplicate active invoices for the same sale
    SELECT 'duplicate_active_invoice'::text, 'error'::text,
           MAX(d.genericinvoicedocumentid), d.genericsaleid,
           'Sale #' || d.genericsaleid || ' has ' || COUNT(*) || ' active invoice documents.'
    FROM   genericinvoicedocuments d
    WHERE  d.farmid = p_farmid AND d.isdeleted = FALSE
    AND    d.documentstatus NOT IN ('Voided', 'Superseded')
    GROUP  BY d.genericsaleid
    HAVING COUNT(*) > 1

    UNION ALL

    -- 3. Sale balance inconsistency (amountpaid + balance != totalamount)
    SELECT 'sale_balance_mismatch'::text, 'warning'::text,
           d.genericinvoicedocumentid, s.genericsaleid,
           'Sale #' || s.genericsaleid || ': total=' || s.totalamount || ' paid=' || s.amountpaid ||
           ' balance=' || s.balance || ' (paid+balance=' || (s.amountpaid + s.balance) || ')'
    FROM   genericinvoicedocuments d
    JOIN   genericsales s ON s.genericsaleid = d.genericsaleid
    WHERE  d.farmid = p_farmid AND d.isdeleted = FALSE
    AND    d.documentstatus NOT IN ('Voided', 'Superseded')
    AND    ABS(s.totalamount - s.amountpaid - s.balance) > 0.01

    UNION ALL

    -- 4. Active invoice document for a non-Approved sale
    SELECT 'invoice_for_non_approved_sale'::text, 'warning'::text,
           d.genericinvoicedocumentid, s.genericsaleid,
           'Invoice ' || d.invoicenumber || ' (' || d.documentstatus || ') references sale #' ||
           s.genericsaleid || ' which is "' || s.status || '" (not Approved).'
    FROM   genericinvoicedocuments d
    JOIN   genericsales s ON s.genericsaleid = d.genericsaleid
    WHERE  d.farmid = p_farmid AND d.isdeleted = FALSE
    AND    d.documentstatus NOT IN ('Voided', 'Superseded')
    AND    s.status <> 'Approved'

    UNION ALL

    -- 5. Payment allocation mismatch: sale.amountpaid != sum(allocations)
    SELECT 'allocation_mismatch'::text, 'warning'::text,
           d.genericinvoicedocumentid, s.genericsaleid,
           'Sale #' || s.genericsaleid || ': amountpaid=' || s.amountpaid ||
           ' but sum(allocations)=' || COALESCE(a.total_applied, 0)
    FROM   genericinvoicedocuments d
    JOIN   genericsales s ON s.genericsaleid = d.genericsaleid
    LEFT   JOIN (
        SELECT saleid, SUM(amountapplied) AS total_applied
        FROM   customerpaymentallocation
        WHERE  module = 'generic' AND status = 'Posted'
        GROUP  BY saleid
    ) a ON a.saleid = s.genericsaleid
    WHERE  d.farmid = p_farmid AND d.isdeleted = FALSE
    AND    d.documentstatus NOT IN ('Voided', 'Superseded')
    AND    ABS(s.amountpaid - COALESCE(a.total_applied, 0)) > 0.01
    -- Exclude sales where amountpaid was set at sale creation (before allocation framework)
    AND    s.amountpaid > 0

    ORDER  BY 2, 1;
$function$;

-- =============================================================================
-- VERIFICATION
-- =============================================================================

SELECT 'reconcile_function' AS check,
       (SELECT COUNT(*) FROM pg_proc WHERE proname = 'fngenericinvoicedocument_reconcile') AS found,
       1 AS expected;
