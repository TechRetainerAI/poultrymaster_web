-- 471: Livestock Expenses list shows every cost, like the poultry Expenses page.
--
-- Until now splivestockexpense_list (462) read only typed-in expenses and the
-- 'Expense' lines of a purchase, so buying feed, buying animals, feed used on
-- daily records, pay runs, loan interest and depreciation never reached
-- /livestock-expenses (the P&L counted them from their own ledgers).
--
-- Poultry writes a row into its one expense table from each workflow, tagged
-- with a sourceType. Livestock already keeps each workflow in its own ledger,
-- so this file READS those ledgers instead of copying rows -- nothing is
-- written, nothing can be counted twice, and the P&L is unchanged.
--
-- Every row now says:
--   source    Paid | Bill | Purchase | Batch | Animal | StockUsed | StockLost
--             | PayRun | LoanInterest | Depreciation
--   costKind  Spent  -- money went out, or is owed (expense, bill, pay, interest)
--             Bought -- stock or animals bought (paid or owed)
--             Used   -- stock that was already bought, now used or lost; no new
--                       payment (poultry's "inventory cost recognition")
--             NonCash -- depreciation
-- plus paid / owed / payStatus for anything bought from a supplier, and
-- sourceId + link fields so the page can open where the row came from.
-- Only 'Paid' rows can be reversed from the Expenses page.
--
-- Filters unchanged: {from, to, category, groupId}, plus optional costKind.
-- Safe to re-run.

BEGIN;

CREATE OR REPLACE FUNCTION public.splivestockexpense_list(p_farmid text, p_filter jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH prm AS (
        SELECT NULLIF(p_filter->>'from', '')::date AS dfrom,
               NULLIF(p_filter->>'to', '')::date   AS dto
    ),
    pur AS (   -- purchases with what has been paid on them
        SELECT p.*, fnlivestock_purchasepaid(p.purchaseid) AS paid, s.name AS suppliername
        FROM livestockpurchases p LEFT JOIN supplier s ON s.supplierid = p.supplierid
        WHERE p.farmid = p_farmid
    ),
    x AS (
        -- 1. Typed-in expenses, paid from a cash account.
        SELECT 'Paid' AS source, 'Spent' AS costkind, e.expenseid AS id, e.expenseid AS sourceid, e.expensedate AS d,
               e.category, e.description, e.amount, e.groupid, a.name AS accountname, e.paidto AS payee, e.reference,
               NULL::int AS purchaseid, NULL::numeric AS paid, NULL::numeric AS owed, 'Paid' AS paystatus,
               e.createdby, e.reversedat, e.reversereason
        FROM livestockexpenses e JOIN livestockcashaccounts a ON a.accountid = e.accountid
        WHERE e.farmid = p_farmid

        UNION ALL
        -- 2. Purchase lines: stock, animals and bills. Paid / owed is the
        --    purchase's, shared out over its lines by value.
        SELECT CASE l.linetype WHEN 'Expense' THEN 'Bill' ELSE 'Purchase' END,
               CASE l.linetype WHEN 'Expense' THEN 'Spent' ELSE 'Bought' END,
               l.lineid, p.purchaseid, p.purchasedate,
               CASE l.linetype WHEN 'Item' THEN i.category WHEN 'Animals' THEN 'Animals' ELSE l.expensecategory END,
               CASE l.linetype
                    WHEN 'Item' THEN i.name || ' · ' || trim(to_char(l.quantity, 'FM999999990.###')) || COALESCE(' ' || i.unit, '')
                    WHEN 'Animals' THEN COALESCE(sp.name, 'Animals') || ' · ' || trim(to_char(l.quantity, 'FM999999990')) || ' head'
                         || COALESCE(' (' || b.batchcode || ')', '')
                    ELSE l.description END,
               l.linetotal,
               CASE l.linetype WHEN 'Expense' THEN l.groupid END,
               NULL, p.suppliername, p.reference, p.purchaseid,
               round(CASE WHEN p.total > 0 THEN p.paid * l.linetotal / p.total ELSE 0 END, 2),
               CASE WHEN p.reversedat IS NULL THEN round(CASE WHEN p.total > 0 THEN (p.total - p.paid) * l.linetotal / p.total ELSE 0 END, 2) ELSE 0 END,
               CASE WHEN p.reversedat IS NOT NULL THEN 'Reversed' WHEN p.paid >= p.total THEN 'Paid'
                    WHEN p.paid > 0 THEN 'PartPaid' ELSE 'Unpaid' END,
               p.createdby, p.reversedat, p.reversereason
        FROM livestockpurchaselines l JOIN pur p ON p.purchaseid = l.purchaseid
        LEFT JOIN livestockitems i ON i.itemid = l.itemid
        LEFT JOIN livestockbatches b ON b.batchid = l.batchid
        LEFT JOIN livestockspecies sp ON sp.speciescode = b.speciescode

        UNION ALL
        -- 3. Animals bought and entered on the batch itself, not through a
        --    purchase (no payment recorded for them).
        SELECT 'Batch', 'Bought', b.batchid, b.batchid, b.intakedate, 'Animals',
               COALESCE(sp.name, 'Animals') || ' · ' || b.quantity || ' head (' || b.batchcode || ')',
               COALESCE(b.totalcost, b.costperhead * b.quantity), NULL, NULL, s.name, b.batchcode, NULL,
               NULL, NULL, 'NotRecorded', b.createdby, NULL::timestamp, NULL
        FROM livestockbatches b LEFT JOIN livestockspecies sp ON sp.speciescode = b.speciescode
        LEFT JOIN supplier s ON s.supplierid = b.supplierid
        WHERE b.farmid = p_farmid AND b.purchaseid IS NULL AND NOT COALESCE(b.isdeleted, FALSE)
          AND COALESCE(b.totalcost, b.costperhead * b.quantity, 0) > 0

        UNION ALL
        -- 4. Tagged animals bought one by one (a price, no batch).
        SELECT 'Animal', 'Bought', a.animalid, a.animalid, COALESCE(a.acquireddate, a.createdat::date), 'Animals',
               COALESCE(sp.name, 'Animal') || ' · ' || COALESCE(a.tagnumber, a.name, '#' || a.animalid),
               a.purchasecost, a.groupid, NULL, NULL, NULL, NULL,
               NULL, NULL, 'NotRecorded', a.createdby, NULL::timestamp, NULL
        FROM livestockanimals a LEFT JOIN livestockspecies sp ON sp.speciescode = a.speciescode
        WHERE a.farmid = p_farmid AND NOT a.isdeleted AND COALESCE(a.purchasecost, 0) > 0
          AND EXISTS (SELECT 1 FROM livestockheadmovements m WHERE m.animalid = a.animalid AND m.movementtype = 'Intake'
                      AND m.reversedat IS NULL AND m.batchid IS NULL)

        UNION ALL
        -- 5. Stock used on daily records, treatments and health records: one
        --    row per record and kind of stock. Already bought -- not a new bill.
        SELECT 'StockUsed', 'Used', min(m.movementid), m.sourceid, m.movementdate, i.category,
               CASE m.sourcetype WHEN 'ProductionRecord' THEN 'Daily record' WHEN 'TreatmentDay' THEN 'Treatment'
                    ELSE 'Health record' END || ': ' || string_agg(DISTINCT i.name, ', '),
               -SUM(m.totalcost), m.groupid, NULL, NULL, m.sourcetype, NULL,
               NULL, NULL, NULL, min(m.createdby), NULL::timestamp, NULL
        FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
        WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Usage'
          AND m.sourcetype IN ('ProductionRecord', 'TreatmentDay', 'HealthRecord')
        GROUP BY m.sourcetype, m.sourceid, m.movementdate, m.groupid, i.category
        HAVING -SUM(m.totalcost) > 0

        UNION ALL
        -- 6. Stock lost (spoiled, expired, stolen ...).
        SELECT 'StockLost', 'Used', m.movementid, m.movementid, m.movementdate, i.category,
               i.name || ' lost' || COALESCE(' (' || m.lossreason || ')', '') || COALESCE(': ' || m.notes, ''),
               -m.totalcost, m.groupid, NULL, NULL, NULL, NULL,
               NULL, NULL, NULL, m.createdby, NULL::timestamp, NULL
        FROM livestockstockmovements m JOIN livestockitems i ON i.itemid = m.itemid
        WHERE m.farmid = p_farmid AND m.reversedat IS NULL AND m.movementtype = 'Loss' AND m.totalcost < 0

        UNION ALL
        -- 7. Pay runs: gross pay of everyone on the run.
        SELECT 'PayRun', 'Spent', r.runid, r.runid, r.paydate, 'Staff pay',
               'Pay run ' || to_char(r.periodstart, 'DD Mon') || ' – ' || to_char(r.periodend, 'DD Mon YYYY')
                   || ' · ' || count(l.lineid) || ' staff',
               SUM(l.gross), NULL, a.name, NULL, NULL, NULL,
               NULL, NULL, 'Paid', r.createdby, r.reversedat, r.reversereason
        FROM livestockpayruns r JOIN livestockpaylines l ON l.runid = r.runid
        JOIN livestockcashaccounts a ON a.accountid = r.accountid
        WHERE r.farmid = p_farmid
        GROUP BY r.runid, a.name
        HAVING SUM(l.gross) > 0

        UNION ALL
        -- 8. Loan interest (the principal is paying back, not a cost).
        SELECT 'LoanInterest', 'Spent', r.repaymentid, lo.loanid, r.repaydate, 'Loan interest',
               'Interest to ' || lo.lender, r.interest, NULL, a.name, lo.lender, NULL, NULL,
               NULL, NULL, 'Paid', r.createdby, r.reversedat, r.reversereason
        FROM livestockloanrepayments r JOIN livestockloans lo ON lo.loanid = r.loanid
        JOIN livestockcashaccounts a ON a.accountid = r.accountid
        WHERE lo.farmid = p_farmid AND r.interest > 0

        UNION ALL
        -- 9. Depreciation, one row per asset per month (to the chosen end date,
        --    never past today). No money moves.
        SELECT 'Depreciation', 'NonCash', ast.assetid, ast.assetid, mo.mend, 'Depreciation',
               ast.name || ' · ' || to_char(mo.mstart, 'Mon YYYY'),
               fnlivestock_depreciation(ast.assetid, mo.mstart, mo.mend), NULL, NULL, NULL, NULL, NULL,
               NULL, NULL, NULL, ast.createdby, NULL::timestamp, NULL
        FROM livestockassets ast CROSS JOIN prm
        CROSS JOIN LATERAL (
            SELECT GREATEST(gs::date, ast.acquireddate, COALESCE(prm.dfrom, ast.acquireddate)) AS mstart,
                   LEAST((gs + interval '1 month - 1 day')::date, COALESCE(prm.dto, current_date), current_date) AS mend
            FROM generate_series(date_trunc('month', GREATEST(ast.acquireddate, COALESCE(prm.dfrom, ast.acquireddate))),
                                 date_trunc('month', LEAST(COALESCE(prm.dto, current_date), current_date)),
                                 interval '1 month') gs
        ) mo
        WHERE ast.farmid = p_farmid AND ast.reversedat IS NULL AND ast.usefulmonths IS NOT NULL AND mo.mend >= mo.mstart
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'source', x.source, 'costKind', x.costkind, 'id', x.id, 'sourceId', x.sourceid, 'date', x.d,
        'category', x.category, 'description', x.description, 'amount', x.amount,
        'groupId', x.groupid, 'groupName', g.name, 'accountName', x.accountname, 'payee', x.payee, 'reference', x.reference,
        'purchaseId', x.purchaseid, 'paid', x.paid, 'owed', x.owed, 'payStatus', x.paystatus,
        'createdBy', x.createdby, 'reversedAt', x.reversedat, 'reverseReason', x.reversereason)
        ORDER BY x.d DESC, x.source, x.id DESC), '[]'::jsonb)
    FROM x CROSS JOIN prm LEFT JOIN livestockgroups g ON g.groupid = x.groupid
    WHERE x.amount > 0
      AND (prm.dfrom IS NULL OR x.d >= prm.dfrom)
      AND (prm.dto IS NULL OR x.d <= prm.dto)
      AND (NULLIF(p_filter->>'category', '') IS NULL OR x.category = p_filter->>'category')
      AND (NULLIF(p_filter->>'costKind', '') IS NULL OR x.costkind = p_filter->>'costKind')
      AND (NULLIF(p_filter->>'groupId', '') IS NULL OR x.groupid = (p_filter->>'groupId')::int);
$f$;

COMMIT;
