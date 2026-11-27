-- 502: Projects & Contracts -- project labels also say HOW MUCH of a record each
--      project has.
--
-- spgenericproject_labels returned only which projects a record belongs to, so
-- a loan split 50/50 between two contracts showed two names and no split; the
-- split was visible only by opening Edit. Each project entry now also carries
-- "share" (0..1):
--   * one-amount records (Expense, OwnerEntry, Loan, PayrollRun, CapitalAsset,
--     InternalUsage, EmployeeLoan, CustomerCredit, RecurringTemplate): the
--     stored share;
--   * payments: the derived cash share (unchanged source);
--   * sales / purchases (split per LINE) and deferred lots: null -- a line's
--     share is not a share of the whole document, so none is claimed.
-- Which projects are returned is unchanged; only the extra field is new.
-- Read only.

BEGIN;

CREATE OR REPLACE FUNCTION public.spgenericproject_labels(p_farmid text, p_sourcetype text, p_ids integer[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (
        -- Stored tags (unchanged from 483) for every type except payments.
        SELECT a.sourceid, a.genericprojectid,
               CASE WHEN a.sourcetype IN ('SaleLine', 'PurchaseLine') THEN NULL ELSE a.share END AS share
        FROM genericprojectallocations a
        WHERE p_sourcetype NOT IN ('CustomerPayment', 'SupplierPayment', 'DeferredLot')
          AND a.farmid = p_farmid AND a.status = 'Active'
          AND a.sourcetype = CASE p_sourcetype WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE p_sourcetype END
          AND (p_ids IS NULL OR a.sourceid = ANY (p_ids))
        UNION ALL
        -- Payments: what they paid follows the documents, the rest the advance.
        SELECT k.keyid, k.projectid, k.share
        FROM fngenericproject_keyshares(p_farmid) k
        WHERE p_sourcetype IN ('CustomerPayment', 'SupplierPayment')
          AND k.keytype = p_sourcetype || 'Cash'
          AND k.share > 0
          AND (p_ids IS NULL OR k.keyid = ANY (p_ids))
        UNION ALL
        -- 501: a deferred-cost lot is a stock-in movement; a purchase lot belongs
        -- to the projects of its purchase's lines for that product. Other lots
        -- (opening stock, adjustments, production) are General.
        SELECT m.genericstockmovementid, a.genericprojectid, NULL::numeric
        FROM genericstockmovements m
        JOIN genericpurchaseitems i ON i.genericpurchaseid = m.referenceid AND i.genericproductid = m.genericproductid
        JOIN genericprojectallocations a ON a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'PurchaseLine'
             AND a.sourceid = i.genericpurchaseid AND a.sourcelineid = i.genericpurchaseitemid
        WHERE p_sourcetype = 'DeferredLot' AND m.farmid = p_farmid AND m.referencetype = 'Purchase'
          AND (p_ids IS NULL OR m.genericstockmovementid = ANY (p_ids))
    ), per AS (
        -- One entry per (record, project). A share is only given when every row
        -- behind it has one.
        SELECT a.sourceid, a.genericprojectid,
               CASE WHEN bool_or(a.share IS NULL) THEN NULL ELSE round(sum(a.share), 6) END AS share
        FROM a GROUP BY a.sourceid, a.genericprojectid
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceId', x.sourceid, 'projects', x.projects)), '[]'::jsonb)
    FROM (SELECT per.sourceid,
                 jsonb_agg(jsonb_build_object('projectId', per.genericprojectid,
                                              'label', p.projectnumber || ' — ' || p.name,
                                              'share', per.share)
                           ORDER BY p.projectnumber) AS projects
          FROM per JOIN genericprojects p ON p.genericprojectid = per.genericprojectid
          GROUP BY per.sourceid) x;
$function$;

COMMIT;
