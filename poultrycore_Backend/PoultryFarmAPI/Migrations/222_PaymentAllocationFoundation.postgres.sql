-- =============================================================================
-- 222_PaymentAllocationFoundation.postgres.sql
--
-- Purpose
-- -------
-- The shared spine for Customer Balances and Supplier Balances: a record of
-- WHICH DOCUMENT each payment was applied to, and for how much.
--
-- Today no module has one. Poultry and Water force one payment onto exactly one
-- sale (poultrypayments.saleid is NOT NULL). Generic lets a payment float at the
-- customer/supplier level with a linkedsaleid/linkedpurchaseid column that is
-- written by _Insert and read by nothing at all -- so an approved Generic
-- payment moves currentbalance and cash but leaves every invoice showing its
-- original unpaid balance.
--
-- Without allocation there is no way to take GHC 700 from Ama Store and say
-- "GHC 200 of that cleared sale S001 and GHC 500 went against S014". That
-- sentence is the whole feature.
--
-- Design
-- ------
-- ONE pair of tables with a `module` discriminator, not six near-identical
-- tables. Allocation is genuinely module-agnostic -- an amount, a document, a
-- before and an after -- and the three modules' sale/purchase tables are the
-- only thing that differs. The discriminator carries what a foreign key cannot.
--
-- There is deliberately NO FK to sale/watersales/genericsales. A real FK would
-- need three nullable columns and three constraints, and the module+id pair is
-- already unique per row. Referential integrity is enforced in the recording
-- functions, which verify the document belongs to the farm AND the party before
-- writing anything.
--
-- Append-only. A payment is never deleted; it is marked Reversed and its
-- allocations are marked Reversed alongside it, so `status = 'Posted'` is the
-- only filter any balance query needs.
--
-- Scope of this file
-- ------------------
-- Tables + the poultry backfill + the poultry IAM catalog rows. Water and
-- Generic get their own migrations (224, 225) once the poultry side is proven;
-- their catalog keys are NOT seeded here, because a permission that appears in
-- the roles UI before its page exists is a support ticket waiting to happen.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Allocation tables.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customerpaymentallocation (
    allocationid       serial        PRIMARY KEY,
    farmid             text          NOT NULL,
    -- poultry | water | generic
    module             text          NOT NULL,
    -- poultrypayments.poultrypaymentid | waterpayments.waterpaymentid
    -- | genericcustomerpayments.genericcustomerpaymentid
    paymentid          integer       NOT NULL,
    -- sale.saleid | watersales.watersaleid | genericsales.genericsaleid
    saleid             integer       NOT NULL,
    amountapplied      numeric(14,2) NOT NULL CHECK (amountapplied > 0),
    salebalancebefore  numeric(14,2) NOT NULL,
    salebalanceafter   numeric(14,2) NOT NULL,
    -- Posted | Reversed
    status             text          NOT NULL DEFAULT 'Posted',
    createdby          text          NULL,
    createdat          timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby         text          NULL,
    reversedat         timestamp     NULL,
    reversalreason     text          NULL
);

CREATE TABLE IF NOT EXISTS supplierpaymentallocation (
    allocationid           serial        PRIMARY KEY,
    farmid                 text          NOT NULL,
    module                 text          NOT NULL,
    -- poultrysupplierpayments | watersupplierpayments | genericsupplierpayments
    paymentid              integer       NOT NULL,
    -- Poultry payables span two document tables, so the id alone is ambiguous:
    -- RawMaterialPurchase | FlockBatch | Purchase
    documenttype           text          NOT NULL,
    documentid             integer       NOT NULL,
    amountapplied          numeric(14,2) NOT NULL CHECK (amountapplied > 0),
    documentbalancebefore  numeric(14,2) NOT NULL,
    documentbalanceafter   numeric(14,2) NOT NULL,
    status                 text          NOT NULL DEFAULT 'Posted',
    createdby              text          NULL,
    createdat              timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby             text          NULL,
    reversedat             timestamp     NULL,
    reversalreason         text          NULL
);

-- One payment can touch a given document at most once; a second application is
-- an edit of the same allocation row, not a new one. This is also what makes the
-- backfill below re-runnable.
CREATE UNIQUE INDEX IF NOT EXISTS ux_customerpaymentallocation_payment_sale
    ON customerpaymentallocation (module, paymentid, saleid);
CREATE UNIQUE INDEX IF NOT EXISTS ux_supplierpaymentallocation_payment_doc
    ON supplierpaymentallocation (module, paymentid, documenttype, documentid);

-- The hot path: "what is still open for this farm", so the partial index on
-- Posted keeps reversed history out of every balance scan.
CREATE INDEX IF NOT EXISTS ix_customerpaymentallocation_doc
    ON customerpaymentallocation (farmid, module, saleid) WHERE status = 'Posted';
CREATE INDEX IF NOT EXISTS ix_supplierpaymentallocation_doc
    ON supplierpaymentallocation (farmid, module, documenttype, documentid) WHERE status = 'Posted';
CREATE INDEX IF NOT EXISTS ix_customerpaymentallocation_payment
    ON customerpaymentallocation (farmid, module, paymentid);
CREATE INDEX IF NOT EXISTS ix_supplierpaymentallocation_payment
    ON supplierpaymentallocation (farmid, module, paymentid);

-- -----------------------------------------------------------------------------
-- 2. Payment terms -> derived due dates.
-- -----------------------------------------------------------------------------
-- No sale or purchase in ANY module carries a due date, which is why the
-- existing poultry customer-balance report hardcodes overdueamount = NULL and
-- pushes a warning saying so. Rather than add a duedate column to five document
-- tables (and then have to keep it correct through every edit), terms live on
-- the PARTY and the due date is derived: documentdate + paymenttermsdays.
--
-- 0 means due on the day of sale, which is the correct default for a cash
-- business -- anything unpaid is immediately overdue, which is exactly what the
-- owner wants to see on a collections page.
--
-- Generic already has paymenttermsdays on its customers and suppliers.
ALTER TABLE customer ADD COLUMN IF NOT EXISTS paymenttermsdays integer NOT NULL DEFAULT 0;
ALTER TABLE supplier ADD COLUMN IF NOT EXISTS paymenttermsdays integer NOT NULL DEFAULT 0;

-- -----------------------------------------------------------------------------
-- 3. Reversal support on the existing poultry payment table.
-- -----------------------------------------------------------------------------
-- poultrypayments has no status and no reversal columns -- a payment recorded in
-- error can only be fixed by deleting the row, which loses the audit trail. The
-- house pattern (poultryinternalusage, genericcashtransactions) is append-only
-- with a status flag, so match it.
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS status         text      NOT NULL DEFAULT 'Posted';
-- SaleEntry (recorded from the Sales page) | CustomerBalances (from the balances page)
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS sourcetype     text      NOT NULL DEFAULT 'SaleEntry';
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS customerid     integer   NULL;
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS poultrycashaccountid integer NULL;
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS reversedby     text      NULL;
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS reversedat     timestamp NULL;
ALTER TABLE poultrypayments ADD COLUMN IF NOT EXISTS reversalreason text      NULL;

CREATE INDEX IF NOT EXISTS ix_poultrypayments_farm_customer
    ON poultrypayments (farmid, customerid) WHERE status = 'Posted';

-- -----------------------------------------------------------------------------
-- 4. Backfill: every existing poultry payment becomes an allocation.
-- -----------------------------------------------------------------------------
-- Without this, the balance pages would show correct totals (they read
-- sale.amountpaid) but an empty payment history, and fnbalanceaudit would flag
-- every sale on day one. poultrypayments is already strictly 1 payment -> 1
-- sale, so the mapping is exact; only the before/after pair has to be
-- reconstructed, which is a running total in payment order.
INSERT INTO customerpaymentallocation
    (farmid, module, paymentid, saleid, amountapplied,
     salebalancebefore, salebalanceafter, status, createdby, createdat)
SELECT o.farmid, 'poultry', o.poultrypaymentid, o.saleid, o.amount,
       (o.totalamount - o.priorpaid)::numeric(14,2),
       (o.totalamount - o.priorpaid - o.amount)::numeric(14,2),
       'Posted', o.createdby, o.createddate
FROM (
    SELECT pp.poultrypaymentid, pp.farmid, pp.saleid, pp.amount,
           pp.createdby, pp.createddate, s.totalamount,
           COALESCE(SUM(pp.amount) OVER (
               PARTITION BY pp.farmid, pp.saleid
               ORDER BY pp.paymentdate, pp.poultrypaymentid
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS priorpaid
    FROM   poultrypayments pp
    JOIN   sale s ON s.saleid = pp.saleid AND s.farmid = pp.farmid
) o
WHERE o.amount > 0
ON CONFLICT (module, paymentid, saleid) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 5. Consistency check.
-- -----------------------------------------------------------------------------
-- The single query that answers "has the allocation layer drifted from the
-- documents?". Returns nothing when healthy. Two different invariants, because
-- the two sides earn their amountpaid differently:
--
--   customer -- sale.amountpaid is RECOMPUTED as SUM(poultrypayments.amount) on
--               every payment, so allocations must match it exactly.
--   supplier -- a purchase can be part-paid at creation, before any payment
--               record exists, so allocations must never EXCEED amountpaid but
--               are not expected to equal it.
CREATE OR REPLACE FUNCTION public.fnbalanceaudit(p_farmid text, p_module text DEFAULT 'poultry')
RETURNS TABLE (
    side          text,
    documenttype  text,
    documentid    integer,
    amountpaid    numeric,
    allocated     numeric,
    difference    numeric
)
LANGUAGE sql
STABLE
AS $function$
    SELECT 'customer'::text, 'Sale'::text, s.saleid,
           s.amountpaid,
           COALESCE(a.allocated, 0),
           s.amountpaid - COALESCE(a.allocated, 0)
    FROM   sale s
    LEFT   JOIN (
        SELECT c.saleid, SUM(c.amountapplied) AS allocated
        FROM   customerpaymentallocation c
        WHERE  c.farmid = p_farmid AND c.module = p_module AND c.status = 'Posted'
        GROUP  BY c.saleid
    ) a ON a.saleid = s.saleid
    WHERE  p_module = 'poultry'
      AND  s.farmid = p_farmid
      AND  s.amountpaid <> COALESCE(a.allocated, 0)

    UNION ALL

    SELECT 'supplier'::text, 'RawMaterialPurchase'::text, pu.poultryrawmaterialpurchaseid,
           pu.amountpaid,
           COALESCE(a.allocated, 0),
           pu.amountpaid - COALESCE(a.allocated, 0)
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN (
        SELECT sa.documentid, SUM(sa.amountapplied) AS allocated
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = p_module
          AND  sa.status = 'Posted' AND sa.documenttype = 'RawMaterialPurchase'
        GROUP  BY sa.documentid
    ) a ON a.documentid = pu.poultryrawmaterialpurchaseid
    WHERE  p_module = 'poultry'
      AND  pu.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > pu.amountpaid

    UNION ALL

    SELECT 'supplier'::text, 'FlockBatch'::text, b.batchid,
           b.amountpaid,
           COALESCE(a.allocated, 0),
           b.amountpaid - COALESCE(a.allocated, 0)
    FROM   mainflockbatch b
    LEFT   JOIN (
        SELECT sa.documentid, SUM(sa.amountapplied) AS allocated
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = p_farmid AND sa.module = p_module
          AND  sa.status = 'Posted' AND sa.documenttype = 'FlockBatch'
        GROUP  BY sa.documentid
    ) a ON a.documentid = b.batchid
    WHERE  p_module = 'poultry'
      AND  b.farmid = p_farmid
      AND  COALESCE(a.allocated, 0) > b.amountpaid;
$function$;

-- -----------------------------------------------------------------------------
-- 6. IAM catalog -- the poultry keys only.
-- -----------------------------------------------------------------------------
-- Sort orders slot these next to the resources they belong beside: customers is
-- 61 and cash is 81, so balances sit at 62/63 (Sales & Customers) and the
-- supplier pair at 71/72 (Purchasing).
INSERT INTO iampermissions
    (permissionkey, module, resource, action, permissiongroup, resourcelabel, description, companytype, isdangerous, sortorder)
VALUES
    ('poultry.customer-balances.view',   'poultry', 'customer-balances', 'view',    'Sales & Customers', 'Customer Balances', 'See who owes money and the unpaid sales behind each balance.', 'Poultry', false, 62),
    ('poultry.customer-payments.create', 'poultry', 'customer-payments', 'create',  'Sales & Customers', 'Customer Balances', 'Receive a payment and allocate it across open sales.',        'Poultry', false, 62),
    ('poultry.customer-payments.reverse','poultry', 'customer-payments', 'reverse', 'Sales & Customers', 'Customer Balances', 'Reverse a posted customer payment.',                          'Poultry', true,  62),
    ('poultry.customer-statements.view', 'poultry', 'customer-statements','view',   'Sales & Customers', 'Customer Statements', 'Open a customer statement for a date range.',               'Poultry', false, 63),
    ('poultry.supplier-balances.view',   'poultry', 'supplier-balances', 'view',    'Purchasing',        'Supplier Balances', 'See who we owe and the unpaid purchases behind each balance.', 'Poultry', false, 71),
    ('poultry.supplier-payments.create', 'poultry', 'supplier-payments', 'create',  'Purchasing',        'Supplier Balances', 'Record a supplier payment and allocate it across open purchases.', 'Poultry', false, 71),
    ('poultry.supplier-payments.reverse','poultry', 'supplier-payments', 'reverse', 'Purchasing',        'Supplier Balances', 'Reverse a posted supplier payment.',                          'Poultry', true,  71),
    ('poultry.supplier-statements.view', 'poultry', 'supplier-statements','view',   'Purchasing',        'Supplier Statements', 'Open a supplier statement for a date range.',               'Poultry', false, 72)
ON CONFLICT (permissionkey) DO NOTHING;

COMMIT;
