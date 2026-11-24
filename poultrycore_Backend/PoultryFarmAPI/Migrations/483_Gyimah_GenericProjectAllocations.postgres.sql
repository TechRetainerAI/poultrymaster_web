-- 483: Projects & Contracts -- attributing existing transactions to projects.
--
-- genericprojectallocations says "this share of that transaction (or line)
-- belongs to that project". It stores a SHARE (0 < share <= 1), never a copied
-- amount: a project's amount is always share x the transaction's current
-- amount, so an edit, cancellation or reversal of the source flows through by
-- itself and nothing can drift. Whatever share is not given to a project
-- belongs to "General company activity" -- there is no fake General project.
--
-- Allocation never creates a sale, purchase, expense, payment, stock movement
-- or cash transaction. It only labels one that already exists.
--
-- What can be attributed (sourcetype -> sourceid / sourcelineid):
--   SaleLine        genericsales.genericsaleid / genericsaleitems.genericsaleitemid
--   PurchaseLine    genericpurchases.genericpurchaseid / genericpurchaseitems.genericpurchaseitemid
--   Expense         genericexpenses.genericexpenseid
--   OwnerEntry      genericownercontributiondraws.genericownerentryid
--   Loan            "GenericLoans"."GenericLoanId"  (proceeds, repayments, interest, fees)
--   PayrollRun      genericpayrollruns.genericpayrollrunid
--   CapitalAsset    genericcapitalassets.genericcapitalassetid (costs + depreciation)
--   CustomerPayment genericcustomerpayments.genericcustomerpaymentid -- ONLY the part
--                   not applied to any sale (a designated customer advance)
--   SupplierPayment genericsupplierpayments.genericsupplierpaymentid -- ONLY the part
--                   not applied to any purchase/expense (a designated supplier advance)
-- Everything else is DERIVED, never tagged twice: a customer payment applied to a
-- sale follows the sale's lines, a supplier payment follows the purchase or
-- expense it paid, depreciation follows its asset, a sale's cost of goods sold
-- follows its lines.
--
-- Changes are append-only: a new assignment supersedes the active rows (status
-- 'Superseded', supersededat/by, reason) and inserts new ones, so the history
-- reads "moved from A to B, by whom, when, why". Re-sending the same split is a
-- no-op (safe to retry). One advisory lock per source serialises concurrent
-- changes.

BEGIN;

CREATE TABLE IF NOT EXISTS genericprojectallocations (
    genericprojectallocationid serial PRIMARY KEY,
    farmid             text          NOT NULL,
    genericprojectid   integer       NOT NULL REFERENCES genericprojects (genericprojectid),
    sourcetype         text          NOT NULL CHECK (sourcetype IN (
                           'SaleLine', 'PurchaseLine', 'Expense', 'OwnerEntry', 'Loan', 'PayrollRun',
                           'CapitalAsset', 'CustomerPayment', 'SupplierPayment')),
    sourceid           integer       NOT NULL,
    sourcelineid       integer       NULL,
    share              numeric(9,6)  NOT NULL CHECK (share > 0 AND share <= 1),
    -- What the user typed, for display only ("40 of 100 chairs", "GHC 6,000").
    basis              text          NOT NULL DEFAULT 'Share' CHECK (basis IN ('Share', 'Amount', 'Quantity')),
    enteredvalue       numeric(18,4) NULL,
    costclass          text          NOT NULL DEFAULT 'Direct' CHECK (costclass IN (
                           'Direct', 'Shared', 'Overhead', 'Selling', 'Financing', 'Capital')),
    status             text          NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Superseded')),
    reason             text          NULL,
    changegroup        uuid          NOT NULL,
    createdby          text          NULL,
    createdat          timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    supersededby       text          NULL,
    supersededat       timestamp     NULL,
    supersededreason   text          NULL,
    CHECK ((sourcetype IN ('SaleLine', 'PurchaseLine')) = (sourcelineid IS NOT NULL))
);

-- At most one active row per project per source line.
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericprojectallocations_active
    ON genericprojectallocations (farmid, sourcetype, sourceid, COALESCE(sourcelineid, 0), genericprojectid)
    WHERE status = 'Active';
CREATE INDEX IF NOT EXISTS ix_genericprojectallocations_source
    ON genericprojectallocations (farmid, sourcetype, sourceid);
CREATE INDEX IF NOT EXISTS ix_genericprojectallocations_project
    ON genericprojectallocations (farmid, genericprojectid) WHERE status = 'Active';

-- ---------------------------------------------------------------------------
-- The source's own size, used to turn an amount or quantity into a share and
-- to prove the source exists in THIS company. Returns NULL when not found.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproject_sourcesize(
    p_farmid text, p_sourcetype text, p_sourceid integer, p_lineid integer,
    OUT amount numeric, OUT quantity numeric, OUT label text)
 LANGUAGE plpgsql STABLE AS $f$
BEGIN
    CASE p_sourcetype
    WHEN 'SaleLine' THEN
        SELECT i.linetotal, i.quantity,
               coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) || ' — ' || coalesce(i.description, 'line')
          INTO amount, quantity, label
          FROM genericsaleitems i JOIN genericsales s ON s.genericsaleid = i.genericsaleid
         WHERE i.genericsaleitemid = p_lineid AND i.genericsaleid = p_sourceid AND s.farmid = p_farmid;
    WHEN 'PurchaseLine' THEN
        SELECT i.linetotal, i.quantity,
               coalesce(nullif(p.invoicenumber, ''), 'Purchase #' || p.genericpurchaseid) || ' — '
                 || coalesce(i.description, pr.productname, 'line')
          INTO amount, quantity, label
          FROM genericpurchaseitems i JOIN genericpurchases p ON p.genericpurchaseid = i.genericpurchaseid
          LEFT JOIN genericproducts pr ON pr.genericproductid = i.genericproductid
         WHERE i.genericpurchaseitemid = p_lineid AND i.genericpurchaseid = p_sourceid AND p.farmid = p_farmid;
    WHEN 'Expense' THEN
        SELECT e.amount, NULL, 'Expense #' || e.genericexpenseid || ' — ' || coalesce(e.description, e.paidto, '')
          INTO amount, quantity, label
          FROM genericexpenses e WHERE e.genericexpenseid = p_sourceid AND e.farmid = p_farmid;
    WHEN 'OwnerEntry' THEN
        SELECT o.amount, NULL, 'Owner ' || lower(o.entrytype) || ' ' || coalesce(o.referenceno, '#' || o.genericownerentryid)
          INTO amount, quantity, label
          FROM genericownercontributiondraws o WHERE o.genericownerentryid = p_sourceid AND o.farmid = p_farmid;
    WHEN 'Loan' THEN
        SELECT l."AmountReceived", NULL, 'Loan ' || coalesce(l."LoanNumber", '#' || l."GenericLoanId") || ' — ' || coalesce(l."LenderName", '')
          INTO amount, quantity, label
          FROM "GenericLoans" l WHERE l."GenericLoanId" = p_sourceid AND l."FarmId" = p_farmid;
    WHEN 'PayrollRun' THEN
        SELECT r.totalgrosspay, NULL, 'Payroll #' || r.genericpayrollrunid || ' (' || r.periodstart || ' to ' || r.periodend || ')'
          INTO amount, quantity, label
          FROM genericpayrollruns r WHERE r.genericpayrollrunid = p_sourceid AND r.farmid = p_farmid;
    WHEN 'CapitalAsset' THEN
        SELECT COALESCE((SELECT sum(c.amount) FROM genericcapitalassetcosts c
                         WHERE c.genericcapitalassetid = a.genericcapitalassetid AND c.status = 'Posted'), 0),
               NULL, 'Asset ' || a.assetnumber || ' — ' || a.assetname
          INTO amount, quantity, label
          FROM genericcapitalassets a WHERE a.genericcapitalassetid = p_sourceid AND a.farmid = p_farmid;
    WHEN 'CustomerPayment' THEN
        SELECT p.amount, NULL, 'Customer payment #' || p.genericcustomerpaymentid
          INTO amount, quantity, label
          FROM genericcustomerpayments p WHERE p.genericcustomerpaymentid = p_sourceid AND p.farmid = p_farmid;
    WHEN 'SupplierPayment' THEN
        SELECT p.amount, NULL, 'Supplier payment #' || p.genericsupplierpaymentid
          INTO amount, quantity, label
          FROM genericsupplierpayments p WHERE p.genericsupplierpaymentid = p_sourceid AND p.farmid = p_farmid;
    ELSE
        RAISE EXCEPTION 'Transactions of type "%" cannot be assigned to a project.', p_sourcetype USING ERRCODE = 'P0001';
    END CASE;
END
$f$;

-- ---------------------------------------------------------------------------
-- Set the projects for one source (line). p_splits is a JSON array of
--   {projectId, share? | amount? | quantity?, costClass?}
-- An empty array means "all General company activity". The shares of one
-- source never add up to more than 1. Returns the number of active rows.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_allocate(
    p_farmid text, p_sourcetype text, p_sourceid integer, p_lineid integer,
    p_splits jsonb, p_reason text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_size     record;
    v_new      jsonb := '[]'::jsonb;
    v_old      jsonb;
    v_total    numeric := 0;
    v_share    numeric;
    v_basis    text;
    v_entered  numeric;
    v_class    text;
    v_pid      integer;
    v_status   text;
    v_group    uuid := gen_random_uuid();
    s          jsonb;
    v_now      timestamp := (now() at time zone 'utc');
BEGIN
    IF p_splits IS NULL OR jsonb_typeof(p_splits) <> 'array' THEN
        RAISE EXCEPTION 'Project split must be a list.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('genericproject_alloc:' || p_farmid || ':' || p_sourcetype
                                           || ':' || p_sourceid || ':' || COALESCE(p_lineid, 0)));

    IF p_sourcetype IN ('SaleLine', 'PurchaseLine') AND p_lineid IS NULL THEN
        RAISE EXCEPTION 'Choose the line to assign.' USING ERRCODE = 'P0001';
    END IF;
    IF p_sourcetype NOT IN ('SaleLine', 'PurchaseLine') THEN p_lineid := NULL; END IF;

    SELECT * INTO v_size FROM fngenericproject_sourcesize(p_farmid, p_sourcetype, p_sourceid, p_lineid);
    IF v_size.label IS NULL THEN
        RAISE EXCEPTION 'That transaction was not found in this company.' USING ERRCODE = 'P0001';
    END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(p_splits) LOOP
        v_pid := NULLIF(s->>'projectId', '')::int;
        IF v_pid IS NULL THEN CONTINUE; END IF;          -- "General" rows are implicit
        SELECT status INTO v_status FROM genericprojects WHERE genericprojectid = v_pid AND farmid = p_farmid;
        IF v_status IS NULL THEN
            RAISE EXCEPTION 'That project or contract was not found in this company.' USING ERRCODE = 'P0001';
        END IF;
        IF v_status = 'Archived' THEN
            RAISE EXCEPTION 'An archived project cannot receive transactions. Restore it first.' USING ERRCODE = 'P0001';
        END IF;

        IF NULLIF(s->>'share', '') IS NOT NULL THEN
            v_share := (s->>'share')::numeric; v_basis := 'Share'; v_entered := v_share;
        ELSIF NULLIF(s->>'quantity', '') IS NOT NULL THEN
            v_entered := (s->>'quantity')::numeric; v_basis := 'Quantity';
            IF COALESCE(v_size.quantity, 0) <= 0 THEN
                RAISE EXCEPTION 'This transaction has no quantity to split. Split it by amount instead.' USING ERRCODE = 'P0001';
            END IF;
            v_share := v_entered / v_size.quantity;
        ELSIF NULLIF(s->>'amount', '') IS NOT NULL THEN
            v_entered := (s->>'amount')::numeric; v_basis := 'Amount';
            IF COALESCE(v_size.amount, 0) = 0 THEN
                RAISE EXCEPTION 'This transaction has no amount to split.' USING ERRCODE = 'P0001';
            END IF;
            v_share := v_entered / abs(v_size.amount);
        ELSE
            v_share := 1; v_basis := 'Share'; v_entered := 1;
        END IF;
        v_share := round(v_share, 6);
        IF v_share <= 0 THEN
            RAISE EXCEPTION 'Each project''s part must be more than zero.' USING ERRCODE = 'P0001';
        END IF;
        v_class := COALESCE(NULLIF(s->>'costClass', ''), 'Direct');
        IF v_class NOT IN ('Direct', 'Shared', 'Overhead', 'Selling', 'Financing', 'Capital') THEN
            RAISE EXCEPTION 'Cost class "%" is not one of Direct, Shared, Overhead, Selling, Financing or Capital.', v_class
                USING ERRCODE = 'P0001';
        END IF;
        IF v_new @> jsonb_build_array(jsonb_build_object('projectId', v_pid)) THEN
            RAISE EXCEPTION 'The same project appears twice in this split.' USING ERRCODE = 'P0001';
        END IF;
        v_total := v_total + v_share;
        v_new := v_new || jsonb_build_array(jsonb_build_object(
                     'projectId', v_pid, 'share', v_share, 'basis', v_basis, 'entered', v_entered, 'costClass', v_class));
    END LOOP;

    IF v_total > 1.000001 THEN
        RAISE EXCEPTION 'The projects'' parts add up to more than the whole transaction (% %%). Reduce them so nothing is counted twice.',
            round(v_total * 100, 2) USING ERRCODE = 'P0001';
    END IF;

    -- Same as what is there already? Then this is a retry: do nothing.
    SELECT COALESCE(jsonb_agg(jsonb_build_object('projectId', a.genericprojectid, 'share', a.share, 'costClass', a.costclass)
                              ORDER BY a.genericprojectid), '[]'::jsonb)
      INTO v_old
      FROM genericprojectallocations a
     WHERE a.farmid = p_farmid AND a.sourcetype = p_sourcetype AND a.sourceid = p_sourceid
       AND COALESCE(a.sourcelineid, 0) = COALESCE(p_lineid, 0) AND a.status = 'Active';
    IF v_old = (SELECT COALESCE(jsonb_agg(jsonb_build_object('projectId', (x->>'projectId')::int,
                                                            'share', (x->>'share')::numeric(9,6),
                                                            'costClass', x->>'costClass')
                                          ORDER BY (x->>'projectId')::int), '[]'::jsonb)
                FROM jsonb_array_elements(v_new) x) THEN
        RETURN jsonb_array_length(v_new);
    END IF;

    -- Any real change needs the module on: switched off means "no new project
    -- assignment" until it is switched back on.
    PERFORM fngenericproject_assertenabled(p_farmid);

    UPDATE genericprojectallocations a
       SET status = 'Superseded', supersededby = p_by, supersededat = v_now,
           supersededreason = NULLIF(btrim(p_reason), '')
     WHERE a.farmid = p_farmid AND a.sourcetype = p_sourcetype AND a.sourceid = p_sourceid
       AND COALESCE(a.sourcelineid, 0) = COALESCE(p_lineid, 0) AND a.status = 'Active';

    INSERT INTO genericprojectallocations (farmid, genericprojectid, sourcetype, sourceid, sourcelineid, share,
                                           basis, enteredvalue, costclass, reason, changegroup, createdby, createdat)
    SELECT p_farmid, (x->>'projectId')::int, p_sourcetype, p_sourceid, p_lineid, (x->>'share')::numeric,
           x->>'basis', (x->>'entered')::numeric, x->>'costClass', NULLIF(btrim(p_reason), ''), v_group, p_by, v_now
    FROM jsonb_array_elements(v_new) x;

    RETURN jsonb_array_length(v_new);
END
$f$;

-- ---------------------------------------------------------------------------
-- Whole-document helper: give every line of a sale or purchase (or the whole
-- of any other source) to one project, or to General when p_projectid is NULL.
-- Used by "Related project" on a form header.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_allocatedocument(
    p_farmid text, p_documenttype text, p_documentid integer, p_projectid integer,
    p_costclass text, p_reason text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_splits jsonb := CASE WHEN p_projectid IS NULL THEN '[]'::jsonb
                           ELSE jsonb_build_array(jsonb_build_object('projectId', p_projectid, 'share', 1,
                                                                     'costClass', COALESCE(p_costclass, 'Direct'))) END;
    v_line integer; v_n integer := 0;
BEGIN
    IF p_documenttype IN ('Sale', 'SaleLine') THEN
        IF NOT EXISTS (SELECT 1 FROM genericsales WHERE genericsaleid = p_documentid AND farmid = p_farmid) THEN
            RAISE EXCEPTION 'That sale was not found in this company.' USING ERRCODE = 'P0001';
        END IF;
        FOR v_line IN SELECT genericsaleitemid FROM genericsaleitems WHERE genericsaleid = p_documentid ORDER BY 1 LOOP
            v_n := v_n + spgenericproject_allocate(p_farmid, 'SaleLine', p_documentid, v_line, v_splits, p_reason, p_by);
        END LOOP;
    ELSIF p_documenttype IN ('Purchase', 'PurchaseLine') THEN
        IF NOT EXISTS (SELECT 1 FROM genericpurchases WHERE genericpurchaseid = p_documentid AND farmid = p_farmid) THEN
            RAISE EXCEPTION 'That purchase was not found in this company.' USING ERRCODE = 'P0001';
        END IF;
        FOR v_line IN SELECT genericpurchaseitemid FROM genericpurchaseitems WHERE genericpurchaseid = p_documentid ORDER BY 1 LOOP
            v_n := v_n + spgenericproject_allocate(p_farmid, 'PurchaseLine', p_documentid, v_line, v_splits, p_reason, p_by);
        END LOOP;
    ELSE
        v_n := spgenericproject_allocate(p_farmid, p_documenttype, p_documentid, NULL, v_splits, p_reason, p_by);
    END IF;
    RETURN v_n;
END
$f$;

-- ---------------------------------------------------------------------------
-- Line-by-line from a save: p_lines is an array, in the same order as the
-- document's lines, of split arrays (or null = General). Used after an edit
-- that re-creates the lines with new ids.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_allocatelines(
    p_farmid text, p_documenttype text, p_documentid integer, p_lines jsonb, p_reason text, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE v_ids integer[]; v_n integer := 0; i integer; v_type text;
BEGIN
    IF p_documenttype IN ('Sale', 'SaleLine') THEN
        v_type := 'SaleLine';
        SELECT array_agg(genericsaleitemid ORDER BY genericsaleitemid) INTO v_ids
          FROM genericsaleitems i JOIN genericsales s USING (genericsaleid)
         WHERE i.genericsaleid = p_documentid AND s.farmid = p_farmid;
    ELSIF p_documenttype IN ('Purchase', 'PurchaseLine') THEN
        v_type := 'PurchaseLine';
        SELECT array_agg(genericpurchaseitemid ORDER BY genericpurchaseitemid) INTO v_ids
          FROM genericpurchaseitems i JOIN genericpurchases p USING (genericpurchaseid)
         WHERE i.genericpurchaseid = p_documentid AND p.farmid = p_farmid;
    ELSE
        RAISE EXCEPTION 'Only sales and purchases have lines.' USING ERRCODE = 'P0001';
    END IF;
    IF v_ids IS NULL THEN
        RAISE EXCEPTION 'That document was not found in this company.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) <> array_length(v_ids, 1) THEN
        RAISE EXCEPTION 'The project split has % line(s) but the document has %.',
            COALESCE(jsonb_array_length(p_lines), 0), array_length(v_ids, 1) USING ERRCODE = 'P0001';
    END IF;
    FOR i IN 1 .. array_length(v_ids, 1) LOOP
        v_n := v_n + spgenericproject_allocate(p_farmid, v_type, p_documentid, v_ids[i],
                       COALESCE(NULLIF(p_lines->(i - 1), 'null'::jsonb), '[]'::jsonb), p_reason, p_by);
    END LOOP;
    RETURN v_n;
END
$f$;

-- ---------------------------------------------------------------------------
-- Attach projects to a document in the SAME statement that saved it, so the
-- save and its project split commit or fail together. The C# services wrap
-- the existing insert/update call:
--   SELECT spgenericproject_attach(farm, 'Sale', x.id, projects, by)
--   FROM (SELECT spgenericsale_insert(...) AS id) x
-- No existing function changes its signature.
--
-- p_projects:
--   NULL                       -> nothing asked. After an edit that re-created
--                                 a sale's / purchase's lines, the old lines'
--                                 projects move to the new lines by position
--                                 (or are retired if the line count changed).
--   {"projectId": n|null, "costClass"?}  -> the whole document to one project
--                                 (null = General company activity)
--   {"lines": [splits|null, ...]}        -> per line, in line order
--   {"splits": [...]}                    -> one split for a non-line document
-- Returns p_documentid so the caller still gets its id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_attach(
    p_farmid text, p_documenttype text, p_documentid integer, p_projects jsonb, p_by text)
 RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_st   text := CASE p_documenttype WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE p_documenttype END;
    v_old  record;
    v_new  integer[];
    v_oldl integer[];
    i      integer;
BEGIN
    IF p_documentid IS NULL THEN RETURN NULL; END IF;

    IF v_st IN ('SaleLine', 'PurchaseLine') THEN
        -- Lines that no longer exist (an edit replaced them).
        SELECT array_agg(DISTINCT a.sourcelineid ORDER BY a.sourcelineid) INTO v_oldl
          FROM genericprojectallocations a
         WHERE a.farmid = p_farmid AND a.sourcetype = v_st AND a.sourceid = p_documentid AND a.status = 'Active'
           AND NOT EXISTS (SELECT 1 FROM genericsaleitems si WHERE v_st = 'SaleLine' AND si.genericsaleitemid = a.sourcelineid
                                                               AND si.genericsaleid = p_documentid)
           AND NOT EXISTS (SELECT 1 FROM genericpurchaseitems pi WHERE v_st = 'PurchaseLine' AND pi.genericpurchaseitemid = a.sourcelineid
                                                                   AND pi.genericpurchaseid = p_documentid);
        IF v_oldl IS NOT NULL THEN
            IF v_st = 'SaleLine' THEN
                SELECT array_agg(genericsaleitemid ORDER BY genericsaleitemid) INTO v_new
                  FROM genericsaleitems WHERE genericsaleid = p_documentid;
            ELSE
                SELECT array_agg(genericpurchaseitemid ORDER BY genericpurchaseitemid) INTO v_new
                  FROM genericpurchaseitems WHERE genericpurchaseid = p_documentid;
            END IF;
            -- Same number of lines and nothing new asked: carry each line's
            -- projects over by position. Anything else: retire the old rows.
            IF p_projects IS NULL AND array_length(v_new, 1) = array_length(v_oldl, 1) THEN
                FOR i IN 1 .. array_length(v_new, 1) LOOP
                    UPDATE genericprojectallocations SET sourcelineid = v_new[i]
                     WHERE farmid = p_farmid AND sourcetype = v_st AND sourceid = p_documentid
                       AND sourcelineid = v_oldl[i] AND status = 'Active';
                END LOOP;
            ELSE
                UPDATE genericprojectallocations
                   SET status = 'Superseded', supersededby = p_by, supersededat = (now() at time zone 'utc'),
                       supersededreason = 'Line replaced when the document was edited'
                 WHERE farmid = p_farmid AND sourcetype = v_st AND sourceid = p_documentid
                   AND sourcelineid = ANY (v_oldl) AND status = 'Active';
            END IF;
        END IF;
    END IF;

    IF p_projects IS NULL OR jsonb_typeof(p_projects) = 'null' THEN
        RETURN p_documentid;
    END IF;

    IF p_projects ? 'lines' THEN
        PERFORM spgenericproject_allocatelines(p_farmid, p_documenttype, p_documentid, p_projects->'lines', NULL, p_by);
    ELSIF p_projects ? 'splits' THEN
        PERFORM spgenericproject_allocate(p_farmid, v_st, p_documentid, NULL, p_projects->'splits', NULL, p_by);
    ELSIF p_projects ? 'projectId' THEN
        PERFORM spgenericproject_allocatedocument(p_farmid, p_documenttype, p_documentid,
                    NULLIF(p_projects->>'projectId', '')::int, NULLIF(p_projects->>'costClass', ''), NULL, p_by);
    END IF;
    RETURN p_documentid;
END
$f$;

-- ---------------------------------------------------------------------------
-- Read: active split + full history for one document (all its lines).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_allocations_get(
    p_farmid text, p_sourcetype text, p_sourceid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH t AS (
        SELECT CASE p_sourcetype WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE p_sourcetype END AS st
    ), rows AS (
        SELECT a.*, p.projectnumber, p.name AS projectname
        FROM genericprojectallocations a JOIN genericprojects p ON p.genericprojectid = a.genericprojectid
        CROSS JOIN t
        WHERE a.farmid = p_farmid AND a.sourcetype = t.st AND a.sourceid = p_sourceid
    )
    SELECT jsonb_build_object(
        'sourceType', (SELECT st FROM t), 'sourceId', p_sourceid,
        'active', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                     'lineId', r.sourcelineid, 'projectId', r.genericprojectid,
                     'projectLabel', r.projectnumber || ' — ' || r.projectname,
                     'share', r.share, 'basis', r.basis, 'enteredValue', r.enteredvalue,
                     'costClass', r.costclass, 'createdBy', r.createdby, 'createdAt', r.createdat)
                   ORDER BY r.sourcelineid NULLS FIRST, r.genericprojectid)
                   FROM rows r WHERE r.status = 'Active'), '[]'::jsonb),
        'history', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                     'lineId', r.sourcelineid, 'projectId', r.genericprojectid,
                     'projectLabel', r.projectnumber || ' — ' || r.projectname,
                     'share', r.share, 'costClass', r.costclass, 'status', r.status,
                     'reason', r.reason, 'createdBy', r.createdby, 'createdAt', r.createdat,
                     'supersededBy', r.supersededby, 'supersededAt', r.supersededat,
                     'supersededReason', r.supersededreason)
                   ORDER BY r.createdat DESC, r.genericprojectallocationid DESC)
                   FROM rows r), '[]'::jsonb));
$f$;

-- For lists: the project label(s) of many documents at once, e.g. the sales
-- list's "Project" column. p_ids NULL = every document of that type.
-- Returns [{sourceId, projects:[{projectId,label,share}], partial}] where
-- partial = some of it is still General.
CREATE OR REPLACE FUNCTION public.spgenericproject_labels(
    p_farmid text, p_sourcetype text, p_ids integer[])
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH a AS (
        SELECT a.sourceid, a.genericprojectid, p.projectnumber || ' — ' || p.name AS label,
               a.sourcelineid, a.share
        FROM genericprojectallocations a JOIN genericprojects p ON p.genericprojectid = a.genericprojectid
        WHERE a.farmid = p_farmid AND a.status = 'Active'
          AND a.sourcetype = CASE p_sourcetype WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE p_sourcetype END
          AND (p_ids IS NULL OR a.sourceid = ANY (p_ids))
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceId', x.sourceid, 'projects', x.projects)), '[]'::jsonb)
    FROM (SELECT sourceid,
                 jsonb_agg(DISTINCT jsonb_build_object('projectId', genericprojectid, 'label', label)) AS projects
          FROM a GROUP BY sourceid) x;
$f$;

COMMIT;
