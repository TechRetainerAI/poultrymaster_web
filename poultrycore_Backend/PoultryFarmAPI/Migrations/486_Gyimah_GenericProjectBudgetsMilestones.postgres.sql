-- 486: Projects & Contracts -- budgets, milestones and linking older
--      transactions.
--
-- 1. genericprojectbudgetlines -- one planned amount per category per budget
--    version. Saving a budget makes a new version; older versions stay for the
--    record. Categories: Revenue, Materials, Labor, Transport, OtherDirect,
--    Overhead, Contingency.
--    genericexpensecategories.projectbudgetcategory says which budget line an
--    expense category counts against (NULL = Other direct, or Overhead when
--    the expense was assigned as overhead).
--    Budget vs actual is shown on three explicit bases, because they differ:
--      Committed  -- purchases and expenses approved for the project (value)
--      Cash       -- money actually paid out for it
--      Recognised -- cost in the project P&L (cost of goods SOLD, not bought)
--    Over budget is a warning, never a block.
-- 2. genericprojectmilestones -- plain progress tracking. Completing a
--    milestone posts nothing: it does not earn revenue or record a payment.
-- 3. spgenericproject_linkcandidates / _linkpreview / _link -- attribute
--    transactions recorded before the project existed. Nothing is re-posted;
--    company totals do not move; each link is an allocation with reason
--    'Linked older transaction' so it shows in the history.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Budgets
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericprojectbudgetlines (
    genericprojectbudgetlineid serial PRIMARY KEY,
    farmid            text          NOT NULL,
    genericprojectid  integer       NOT NULL REFERENCES genericprojects (genericprojectid),
    version           integer       NOT NULL,
    category          text          NOT NULL CHECK (category IN (
                          'Revenue', 'Materials', 'Labor', 'Transport', 'OtherDirect', 'Overhead', 'Contingency')),
    plannedamount     numeric(18,2) NOT NULL CHECK (plannedamount >= 0),
    effectivedate     date          NOT NULL DEFAULT ((now() at time zone 'utc')::date),
    notes             text          NULL,
    createdby         text          NULL,
    createdat         timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    UNIQUE (genericprojectid, version, category)
);

ALTER TABLE genericexpensecategories
    ADD COLUMN IF NOT EXISTS projectbudgetcategory text NULL
        CHECK (projectbudgetcategory IS NULL OR projectbudgetcategory IN
               ('Materials', 'Labor', 'Transport', 'OtherDirect', 'Overhead'));
COMMENT ON COLUMN genericexpensecategories.projectbudgetcategory IS
    '486: which project budget line this expense category counts against (NULL = Other direct).';

-- p_lines: [{category, plannedAmount, notes?}] -- the whole budget; makes a new version.
CREATE OR REPLACE FUNCTION public.spgenericproject_savebudget(
    p_farmid text, p_projectid integer, p_lines jsonb, p_effectivedate date, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_version integer; v_prj genericprojects; v_total numeric;
BEGIN
    PERFORM fngenericproject_assertenabled(p_farmid);
    v_prj := fngenericproject_require(p_farmid, p_projectid);
    IF v_prj.status = 'Archived' THEN
        RAISE EXCEPTION 'This project is archived. Restore it before changing its budget.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(p_lines) <> 'array' THEN
        RAISE EXCEPTION 'Budget lines must be a list.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) x
               WHERE x->>'category' NOT IN ('Revenue', 'Materials', 'Labor', 'Transport', 'OtherDirect', 'Overhead', 'Contingency')) THEN
        RAISE EXCEPTION 'Budget categories are Revenue, Materials, Labor, Transport, Other direct, Overhead and Contingency.'
            USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) x WHERE COALESCE((x->>'plannedAmount')::numeric, 0) < 0) THEN
        RAISE EXCEPTION 'Budget amounts cannot be negative.' USING ERRCODE = 'P0001';
    END IF;
    IF (SELECT count(*) <> count(DISTINCT x->>'category') FROM jsonb_array_elements(p_lines) x) THEN
        RAISE EXCEPTION 'Each budget category can appear only once.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('genericproject_budget:' || p_projectid));
    SELECT COALESCE(max(version), 0) + 1 INTO v_version FROM genericprojectbudgetlines WHERE genericprojectid = p_projectid;

    INSERT INTO genericprojectbudgetlines (farmid, genericprojectid, version, category, plannedamount, effectivedate, notes, createdby)
    SELECT p_farmid, p_projectid, v_version, x->>'category', COALESCE((x->>'plannedAmount')::numeric, 0),
           COALESCE(p_effectivedate, (now() at time zone 'utc')::date), NULLIF(btrim(x->>'notes'), ''), p_by
    FROM jsonb_array_elements(p_lines) x;

    -- Keep the register's "approved budget" in step with the cost lines.
    SELECT sum(plannedamount) INTO v_total FROM genericprojectbudgetlines
     WHERE genericprojectid = p_projectid AND version = v_version AND category <> 'Revenue';
    UPDATE genericprojects SET approvedbudget = v_total, updatedby = p_by, updatedat = (now() at time zone 'utc')
     WHERE genericprojectid = p_projectid;
    RETURN v_version;
END
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_setexpensecategorybudget(
    p_farmid text, p_categoryid integer, p_budgetcategory text, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF p_budgetcategory IS NOT NULL AND p_budgetcategory NOT IN ('Materials', 'Labor', 'Transport', 'OtherDirect', 'Overhead') THEN
        RAISE EXCEPTION 'Choose Materials, Labor, Transport, Other direct or Overhead.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE genericexpensecategories SET projectbudgetcategory = p_budgetcategory, updatedat = (now() at time zone 'utc')
     WHERE genericexpensecategoryid = p_categoryid AND farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That expense category was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- Actual spend per budget category for one project, on all three bases.
CREATE OR REPLACE FUNCTION public.fngenericproject_budgetactuals(p_farmid text, p_projectid integer)
RETURNS TABLE(category text, committed numeric, cash numeric, recognised numeric)
LANGUAGE sql STABLE AS $f$
    WITH ks AS (SELECT * FROM fngenericproject_keyshares(p_farmid) WHERE projectid = p_projectid AND productid IS NULL),
    expcat AS (
        -- Budget line of each expense attributed to this project.
        SELECT e.genericexpenseid, e.amount, e.amountpaid, k.share,
               COALESCE(c.projectbudgetcategory,
                        CASE WHEN k.costclass = 'Overhead' THEN 'Overhead'
                             WHEN e.sourcetype = 'GenericPayrollRun' THEN 'Labor'
                             ELSE 'OtherDirect' END) AS category
        FROM ks k JOIN genericexpenses e ON k.keytype = 'Expense' AND e.genericexpenseid = k.keyid
        LEFT JOIN genericexpensecategories c ON c.genericexpensecategoryid = e.genericexpensecategoryid
        WHERE e.farmid = p_farmid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
    ), committed AS (
        SELECT 'Materials'::text AS category, sum(amount) AS amount
        FROM fngenericproject_purchases(p_farmid, NULL, NULL) WHERE projectid = p_projectid
        UNION ALL
        SELECT category, sum(round(amount * share, 2)) FROM expcat GROUP BY 1
        UNION ALL
        SELECT 'Labor', sum(round(r.totalgrosspay * k.share, 2))
        FROM ks k JOIN genericpayrollruns r ON k.keytype = 'PayrollRun' AND r.genericpayrollrunid = k.keyid
        WHERE r.farmid = p_farmid AND r.status IN ('Approved', 'Paid') AND NOT coalesce(r.isdeleted, false)
          AND NOT EXISTS (SELECT 1 FROM genericexpenses e WHERE e.farmid = p_farmid AND e.sourcetype = 'GenericPayrollRun'
                          AND e.sourceid = r.genericpayrollrunid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false))
    ), cash AS (
        -- Money paid: purchases (when bought or later through the supplier)
        -- count as Materials; expenses paid count against their own line.
        SELECT CASE WHEN c.category IN ('Purchases paid when bought') THEN 'Materials'
                    WHEN c.category = 'Wages paid' THEN 'Labor'
                    WHEN c.category = 'Expenses paid' THEN COALESCE(
                         (SELECT x.category FROM expcat x WHERE x.genericexpenseid = c.sourceid), 'OtherDirect')
                    ELSE NULL END AS category,
               -c.amount AS amount
        FROM fngenericproject_cash(p_farmid, DATE '1900-01-01', DATE '2999-12-31') c
        WHERE c.projectid = p_projectid AND c.category IN ('Purchases paid when bought', 'Wages paid', 'Expenses paid')
        UNION ALL
        -- Supplier payments: each allocation goes to the document it paid.
        SELECT CASE WHEN sa.documenttype = 'Purchase' THEN 'Materials'
                    ELSE COALESCE((SELECT x.category FROM expcat x WHERE x.genericexpenseid = sa.documentid), 'OtherDirect') END,
               round(sa.amountapplied * k.share, 2) * CASE WHEN sa.status = 'Posted' THEN 1 ELSE 0 END
        FROM supplierpaymentallocation sa
        JOIN genericsupplierpayments sp ON sp.genericsupplierpaymentid = sa.paymentid AND sp.farmid = p_farmid
        JOIN ks k ON k.keytype = sa.documenttype AND k.keyid = sa.documentid
        WHERE sa.module = 'generic' AND sa.farmid = p_farmid AND sa.documenttype IN ('Purchase', 'Expense')
          AND COALESCE(sa.fromcredit, false) = false
    ), recognised AS (
        SELECT CASE WHEN x.section = 'direct' THEN 'Materials'
                    WHEN x.keytype = 'PayrollRun' THEN 'Labor'
                    WHEN x.keytype = 'Expense' THEN COALESCE(
                         (SELECT e.category FROM expcat e WHERE e.genericexpenseid = x.keyid), 'OtherDirect')
                    WHEN x.section = 'revenue' THEN 'Revenue'
                    ELSE NULL END AS category,
               x.amount
        FROM fngenericproject_pnl(p_farmid, DATE '1900-01-01', DATE '2999-12-31') x
        WHERE x.projectid = p_projectid AND x.section IN ('revenue', 'direct', 'operating', 'other')
          AND NOT (x.section = 'other' AND x.line <> 'Depreciation')
    ), cats(category, sortorder) AS (
        VALUES ('Revenue', 0), ('Materials', 1), ('Labor', 2), ('Transport', 3), ('OtherDirect', 4), ('Overhead', 5), ('Contingency', 6)
    )
    SELECT c.category,
           COALESCE((SELECT sum(amount) FROM committed m WHERE m.category = c.category), 0),
           COALESCE((SELECT sum(amount) FROM cash m WHERE m.category = c.category), 0),
           COALESCE((SELECT sum(amount) FROM recognised m WHERE m.category = c.category), 0)
    FROM cats c ORDER BY c.sortorder;
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_budget(p_farmid text, p_projectid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_version integer; v_lines jsonb; v_alerts jsonb;
BEGIN
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    SELECT max(version) INTO v_version FROM genericprojectbudgetlines WHERE genericprojectid = p_projectid;

    WITH a AS (SELECT * FROM fngenericproject_budgetactuals(p_farmid, p_projectid)),
    b AS (SELECT category, plannedamount, notes FROM genericprojectbudgetlines
          WHERE genericprojectid = p_projectid AND version = v_version)
    SELECT jsonb_agg(jsonb_build_object(
               'category', a.category,
               'planned', b.plannedamount,
               'notes', b.notes,
               'committed', a.committed, 'cash', a.cash, 'recognised', a.recognised,
               'varianceCommitted', CASE WHEN b.plannedamount IS NULL THEN NULL
                                         WHEN a.category = 'Revenue' THEN a.committed - b.plannedamount
                                         ELSE b.plannedamount - a.committed END,
               'varianceCash', CASE WHEN b.plannedamount IS NULL OR a.category = 'Revenue' THEN NULL ELSE b.plannedamount - a.cash END,
               'varianceRecognised', CASE WHEN b.plannedamount IS NULL THEN NULL
                                          WHEN a.category = 'Revenue' THEN a.recognised - b.plannedamount
                                          ELSE b.plannedamount - a.recognised END)),
           COALESCE(jsonb_agg(jsonb_build_object('category', a.category,
               'overBy', a.committed - b.plannedamount,
               'message', CASE a.category WHEN 'OtherDirect' THEN 'Other direct costs' WHEN 'Labor' THEN 'Labour'
                                          ELSE a.category END
                          || ' spending has exceeded its approved budget by '
                          || to_char(a.committed - b.plannedamount, 'FM999G999G999G990D00') || '.')
               ) FILTER (WHERE a.category NOT IN ('Revenue', 'Contingency') AND b.plannedamount IS NOT NULL
                               AND a.committed > b.plannedamount), '[]'::jsonb)
      INTO v_lines, v_alerts
      FROM a LEFT JOIN b ON b.category = a.category;

    RETURN jsonb_build_object(
        'version', v_version,
        'effectiveDate', (SELECT max(effectivedate) FROM genericprojectbudgetlines WHERE genericprojectid = p_projectid AND version = v_version),
        'lines', COALESCE(v_lines, '[]'::jsonb),
        'alerts', v_alerts,
        'totalPlannedCost', (SELECT sum(plannedamount) FROM genericprojectbudgetlines
                             WHERE genericprojectid = p_projectid AND version = v_version AND category <> 'Revenue'),
        'versions', COALESCE((SELECT jsonb_agg(jsonb_build_object('version', version, 'createdBy', createdby, 'createdAt', createdat,
                                        'total', total) ORDER BY version DESC)
                              FROM (SELECT version, max(createdby) AS createdby, max(createdat) AS createdat,
                                           sum(plannedamount) FILTER (WHERE category <> 'Revenue') AS total
                                    FROM genericprojectbudgetlines WHERE genericprojectid = p_projectid GROUP BY version) v), '[]'::jsonb));
END
$f$;

-- ---------------------------------------------------------------------------
-- 2. Milestones
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericprojectmilestones (
    genericprojectmilestoneid serial PRIMARY KEY,
    farmid            text          NOT NULL,
    genericprojectid  integer       NOT NULL REFERENCES genericprojects (genericprojectid),
    name              text          NOT NULL,
    description       text          NULL,
    planneddate       date          NULL,
    completeddate     date          NULL,
    status            text          NOT NULL DEFAULT 'Planned'
                                    CHECK (status IN ('Planned', 'InProgress', 'Completed', 'Missed', 'Cancelled')),
    responsiblestaffid integer      NULL,
    amount            numeric(18,2) NULL CHECK (amount IS NULL OR amount >= 0),
    billingreference  text          NULL,
    notes             text          NULL,
    sortorder         integer       NOT NULL DEFAULT 0,
    isdeleted         boolean       NOT NULL DEFAULT FALSE,
    createdby         text          NULL,
    createdat         timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby         text          NULL,
    updatedat         timestamp     NULL
);
CREATE INDEX IF NOT EXISTS ix_genericprojectmilestones_project
    ON genericprojectmilestones (genericprojectid) WHERE NOT isdeleted;

CREATE OR REPLACE FUNCTION public.spgenericproject_savemilestone(
    p_farmid text, p_projectid integer, p_milestone jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id     integer := NULLIF(p_milestone->>'milestoneId', '')::int;
    v_name   text := btrim(COALESCE(p_milestone->>'name', ''));
    v_status text := COALESCE(NULLIF(p_milestone->>'status', ''), 'Planned');
    v_done   date := NULLIF(p_milestone->>'completedDate', '')::date;
    v_staff  integer := NULLIF(p_milestone->>'responsibleStaffId', '')::int;
BEGIN
    PERFORM fngenericproject_assertenabled(p_farmid);
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    IF v_name = '' THEN
        RAISE EXCEPTION 'Give the milestone a name.' USING ERRCODE = 'P0001';
    END IF;
    IF v_status NOT IN ('Planned', 'InProgress', 'Completed', 'Missed', 'Cancelled') THEN
        RAISE EXCEPTION 'Milestone status must be Planned, In progress, Completed, Missed or Cancelled.' USING ERRCODE = 'P0001';
    END IF;
    IF v_status = 'Completed' AND v_done IS NULL THEN v_done := (now() at time zone 'utc')::date; END IF;
    IF v_status <> 'Completed' THEN v_done := NULL; END IF;
    IF v_staff IS NOT NULL AND NOT EXISTS (SELECT 1 FROM genericstaff WHERE farmid = p_farmid AND genericstaffid = v_staff) THEN
        RAISE EXCEPTION 'That staff member was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE((p_milestone->>'amount')::numeric, 0) < 0 THEN
        RAISE EXCEPTION 'The amount cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO genericprojectmilestones (farmid, genericprojectid, name, description, planneddate, completeddate, status,
                                              responsiblestaffid, amount, billingreference, notes, sortorder, createdby)
        VALUES (p_farmid, p_projectid, v_name, NULLIF(btrim(p_milestone->>'description'), ''),
                NULLIF(p_milestone->>'plannedDate', '')::date, v_done, v_status, v_staff,
                NULLIF(p_milestone->>'amount', '')::numeric, NULLIF(btrim(p_milestone->>'billingReference'), ''),
                NULLIF(btrim(p_milestone->>'notes'), ''),
                COALESCE((SELECT max(sortorder) + 1 FROM genericprojectmilestones WHERE genericprojectid = p_projectid), 0), p_by)
        RETURNING genericprojectmilestoneid INTO v_id;
    ELSE
        UPDATE genericprojectmilestones SET
            name = v_name, description = NULLIF(btrim(p_milestone->>'description'), ''),
            planneddate = NULLIF(p_milestone->>'plannedDate', '')::date, completeddate = v_done, status = v_status,
            responsiblestaffid = v_staff, amount = NULLIF(p_milestone->>'amount', '')::numeric,
            billingreference = NULLIF(btrim(p_milestone->>'billingReference'), ''),
            notes = NULLIF(btrim(p_milestone->>'notes'), ''), updatedby = p_by, updatedat = (now() at time zone 'utc')
        WHERE genericprojectmilestoneid = v_id AND genericprojectid = p_projectid AND farmid = p_farmid AND NOT isdeleted;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That milestone was not found.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_deletemilestone(
    p_farmid text, p_projectid integer, p_milestoneid integer, p_by text)
 RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE genericprojectmilestones SET isdeleted = TRUE, updatedby = p_by, updatedat = (now() at time zone 'utc')
     WHERE genericprojectmilestoneid = p_milestoneid AND genericprojectid = p_projectid AND farmid = p_farmid AND NOT isdeleted;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That milestone was not found.' USING ERRCODE = 'P0001';
    END IF;
END
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_milestones(p_farmid text, p_projectid integer)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'milestoneId', m.genericprojectmilestoneid, 'name', m.name, 'description', m.description,
            'plannedDate', m.planneddate, 'completedDate', m.completeddate, 'status', m.status,
            'isLate', m.status IN ('Planned', 'InProgress') AND m.planneddate < (now() at time zone 'utc')::date,
            'responsibleStaffId', m.responsiblestaffid,
            'responsibleName', (SELECT btrim(concat_ws(' ', s.firstname, s.lastname)) FROM genericstaff s
                                WHERE s.genericstaffid = m.responsiblestaffid),
            'amount', m.amount, 'billingReference', m.billingreference, 'notes', m.notes)
            ORDER BY m.planneddate NULLS LAST, m.sortorder, m.genericprojectmilestoneid)
        FROM genericprojectmilestones m
        WHERE m.genericprojectid = p_projectid AND m.farmid = p_farmid AND NOT m.isdeleted), '[]'::jsonb);
END
$f$;

-- ---------------------------------------------------------------------------
-- 3. Linking older transactions
-- ---------------------------------------------------------------------------
-- p_filter: {documentType: Sale|Purchase|Expense|OwnerEntry|Loan|PayrollRun|CapitalAsset,
--            from, to, search, partyId, onlyUnassigned (default true)}
CREATE OR REPLACE FUNCTION public.spgenericproject_linkcandidates(p_farmid text, p_filter jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_type   text := COALESCE(p_filter->>'documentType', 'Sale');
    v_from   date := COALESCE(NULLIF(p_filter->>'from', '')::date, DATE '1900-01-01');
    v_to     date := COALESCE(NULLIF(p_filter->>'to', '')::date, DATE '2999-12-31');
    v_search text := NULLIF(btrim(COALESCE(p_filter->>'search', '')), '');
    v_party  integer := NULLIF(p_filter->>'partyId', '')::int;
    v_only   boolean := COALESCE((p_filter->>'onlyUnassigned')::boolean, TRUE);
    v_st     text := CASE v_type WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE v_type END;
    v_rows   jsonb;
BEGIN
    WITH docs AS (
        SELECT s.genericsaleid AS id, s.saledate::date AS day,
               coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) AS ref,
               c.customername AS party, s.totalamount AS amount, s.status,
               (SELECT string_agg(i.description, ', ') FROM genericsaleitems i WHERE i.genericsaleid = s.genericsaleid) AS detail
        FROM genericsales s LEFT JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid AND c.farmid = s.farmid
        WHERE v_type = 'Sale' AND s.farmid = p_farmid AND NOT coalesce(s.isdeleted, false) AND s.status <> 'Draft'
          AND (v_party IS NULL OR s.genericcustomerid = v_party)
        UNION ALL
        SELECT p.genericpurchaseid, p.purchasedate::date, coalesce(nullif(p.invoicenumber, ''), 'Purchase #' || p.genericpurchaseid),
               sp.suppliername, p.totalamount, p.status,
               (SELECT string_agg(coalesce(i.description, g.productname), ', ') FROM genericpurchaseitems i
                LEFT JOIN genericproducts g ON g.genericproductid = i.genericproductid WHERE i.genericpurchaseid = p.genericpurchaseid)
        FROM genericpurchases p LEFT JOIN genericsuppliers sp ON sp.genericsupplierid = p.genericsupplierid
        WHERE v_type = 'Purchase' AND p.farmid = p_farmid AND NOT coalesce(p.isdeleted, false) AND p.status <> 'Draft'
          AND (v_party IS NULL OR p.genericsupplierid = v_party)
        UNION ALL
        SELECT e.genericexpenseid, e.expensedate::date, 'Expense #' || e.genericexpenseid,
               coalesce(sp.suppliername, e.paidto), e.amount, e.status, e.description
        FROM genericexpenses e LEFT JOIN genericsuppliers sp ON sp.genericsupplierid = e.genericsupplierid
        WHERE v_type = 'Expense' AND e.farmid = p_farmid AND NOT coalesce(e.isdeleted, false)
          AND (v_party IS NULL OR e.genericsupplierid = v_party)
        UNION ALL
        SELECT o.genericownerentryid, o.entrydate::date, coalesce(o.referenceno, 'Owner entry #' || o.genericownerentryid),
               o.ownername, o.amount, o.status, 'Owner ' || lower(o.entrytype)
        FROM genericownercontributiondraws o WHERE v_type = 'OwnerEntry' AND o.farmid = p_farmid
        UNION ALL
        SELECT l."GenericLoanId", l."LoanDate"::date, coalesce(l."LoanNumber", 'Loan #' || l."GenericLoanId"),
               l."LenderName", l."AmountReceived", l."Status", l."Notes"
        FROM "GenericLoans" l WHERE v_type = 'Loan' AND l."FarmId" = p_farmid
        UNION ALL
        SELECT r.genericpayrollrunid, coalesce(r.paydate, r.periodend), 'Payroll #' || r.genericpayrollrunid,
               NULL, r.totalgrosspay, r.status, concat('Pay period ', r.periodstart, ' to ', r.periodend)
        FROM genericpayrollruns r WHERE v_type = 'PayrollRun' AND r.farmid = p_farmid AND NOT coalesce(r.isdeleted, false)
        UNION ALL
        SELECT a.genericcapitalassetid, a.acquisitiondate, 'Asset ' || a.assetnumber, NULL,
               (SELECT sum(c.amount) FROM genericcapitalassetcosts c WHERE c.genericcapitalassetid = a.genericcapitalassetid AND c.status = 'Posted'),
               a.status, a.assetname
        FROM genericcapitalassets a WHERE v_type = 'CapitalAsset' AND a.farmid = p_farmid
    ), tagged AS (
        SELECT a.sourceid, jsonb_agg(DISTINCT jsonb_build_object('projectId', a.genericprojectid,
                   'label', p.projectnumber || ' — ' || p.name)) AS projects
        FROM genericprojectallocations a JOIN genericprojects p ON p.genericprojectid = a.genericprojectid
        WHERE a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = v_st
        GROUP BY a.sourceid
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'documentType', v_type, 'documentId', d.id, 'date', d.day, 'ref', d.ref, 'party', d.party,
               'amount', d.amount, 'status', d.status, 'detail', d.detail,
               'projects', COALESCE(t.projects, '[]'::jsonb))
               ORDER BY d.day DESC, d.id DESC), '[]'::jsonb)
      INTO v_rows
      FROM (SELECT * FROM docs WHERE day >= v_from AND day <= v_to
              AND (v_search IS NULL OR ref ILIKE '%' || v_search || '%' OR party ILIKE '%' || v_search || '%'
                   OR detail ILIKE '%' || v_search || '%')
            ORDER BY day DESC, id DESC LIMIT 500) d
      LEFT JOIN tagged t ON t.sourceid = d.id
     WHERE NOT v_only OR t.sourceid IS NULL;
    RETURN v_rows;
END
$f$;

-- What linking these documents would add to the project (before and after),
-- without changing anything. p_items: [{documentType, documentId}]
CREATE OR REPLACE FUNCTION public.spgenericproject_linkpreview(p_farmid text, p_projectid integer, p_items jsonb)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_before jsonb; v_add jsonb;
BEGIN
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    v_before := spgenericproject_summary(p_farmid, ARRAY[p_projectid], NULL, NULL) -> 0;
    WITH it AS (
        SELECT x->>'documentType' AS dt, (x->>'documentId')::int AS id FROM jsonb_array_elements(p_items) x
    ), lines AS (
        -- Same P&L rows the engine would attribute, at share 1, minus what is
        -- already this project's.
        SELECT l.section, l.amount
             * (1 - COALESCE((SELECT sum(k.share) FROM fngenericproject_keyshares(p_farmid) k
                              WHERE k.projectid = p_projectid AND k.keytype = l.keytype AND k.keyid = l.keyid
                                AND (l.keytype <> 'SaleProduct' OR k.productid IS NOT DISTINCT FROM l.productid)), 0)) AS amount
        FROM fngenericpnl_lines(p_farmid, DATE '1900-01-01', DATE '2999-12-31') l
        JOIN it ON (it.dt = 'Sale' AND l.keytype IN ('Sale', 'SaleProduct') AND l.keyid = it.id)
                OR (it.dt <> 'Sale' AND l.keytype = it.dt AND l.keyid = it.id)
    )
    SELECT jsonb_build_object(
        'revenue', COALESCE(sum(amount) FILTER (WHERE section = 'revenue'), 0),
        'costs', COALESCE(sum(amount) FILTER (WHERE section IN ('direct', 'operating', 'other')), 0),
        'ownerFunding', COALESCE(sum(amount) FILTER (WHERE section = 'owner'), 0),
        'purchaseValue', COALESCE((SELECT sum(p.totalamount) FROM genericpurchases p JOIN it ON it.dt = 'Purchase'
                                   AND it.id = p.genericpurchaseid WHERE p.farmid = p_farmid AND p.status = 'Approved'), 0))
      INTO v_add FROM lines;
    RETURN jsonb_build_object('before', v_before, 'adds', v_add,
        'note', 'Linking only labels these transactions. Company totals do not change and nothing is posted again.');
END
$f$;

-- Apply: give each document wholly to the project. Documents already split
-- across projects are refused (change them one by one instead).
CREATE OR REPLACE FUNCTION public.spgenericproject_link(
    p_farmid text, p_projectid integer, p_items jsonb, p_reason text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE x jsonb; v_n integer := 0; v_dt text; v_id integer; v_st text;
BEGIN
    PERFORM fngenericproject_assertenabled(p_farmid);
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    FOR x IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_dt := x->>'documentType'; v_id := (x->>'documentId')::int;
        v_st := CASE v_dt WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE v_dt END;
        IF EXISTS (SELECT 1 FROM genericprojectallocations a WHERE a.farmid = p_farmid AND a.status = 'Active'
                   AND a.sourcetype = v_st AND a.sourceid = v_id AND a.genericprojectid <> p_projectid) THEN
            RAISE EXCEPTION '% #% already belongs to another project. Change it from its own page.', v_dt, v_id
                USING ERRCODE = 'P0001';
        END IF;
        PERFORM spgenericproject_allocatedocument(p_farmid, v_dt, v_id, p_projectid,
            CASE WHEN v_dt IN ('OwnerEntry', 'Loan') THEN 'Financing' WHEN v_dt = 'CapitalAsset' THEN 'Capital' ELSE 'Direct' END,
            COALESCE(NULLIF(btrim(p_reason), ''), 'Linked older transaction'), p_by);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END
$f$;

-- ---------------------------------------------------------------------------
-- 4. Comparison (summary + budget variance + data warnings)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_compare(p_farmid text, p_projectids integer[], p_from date, p_to date)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_rows jsonb; v_general jsonb;
BEGIN
    SELECT jsonb_agg(s || jsonb_build_object(
               'budgetVariance', CASE WHEN (s->>'approvedBudget') IS NULL THEN NULL
                                      ELSE (s->>'approvedBudget')::numeric - (s->>'totalCosts')::numeric
                                           - (s->>'purchaseValue')::numeric + (s->>'costOfGoodsSold')::numeric END,
               'warnings', to_jsonb(array_remove(ARRAY[
                    CASE WHEN (s->>'purchaseValue')::numeric > 0 AND (s->>'revenue')::numeric = 0
                         THEN 'Goods bought but nothing sold yet' END,
                    CASE WHEN (s->>'revenue')::numeric > 0 AND (s->>'directCosts')::numeric = 0
                         THEN 'Revenue with no cost of goods — check the sale lines' END,
                    CASE WHEN (s->>'overdueReceivable')::numeric > 0 THEN 'Customer payment overdue' END,
                    CASE WHEN (s->>'workingCapitalExposure')::numeric > 0 THEN 'Using more cash than it has brought in' END
               ], NULL))))
      INTO v_rows
      FROM jsonb_array_elements(spgenericproject_summary(p_farmid, p_projectids, p_from, p_to)) s
     WHERE (s->>'projectId') IS NOT NULL;

    -- The General row says how much of the company is not on any project.
    SELECT s INTO v_general FROM jsonb_array_elements(spgenericproject_summary(p_farmid, NULL, p_from, p_to)) s
     WHERE (s->>'projectId') IS NULL;
    RETURN jsonb_build_object('projects', COALESCE(v_rows, '[]'::jsonb), 'general', v_general);
END
$f$;

COMMIT;
