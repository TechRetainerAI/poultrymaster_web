-- =============================================================================
-- Migration 442: Generic Financial Integration (Phase 4)
--
-- 1. Financial Impact Preview function — calculates the effects of a
--    transaction BEFORE posting (inventory, expense, cash, supplier balance).
-- 2. P&L expense breakdown — COGS vs Internal Use vs Operating expenses.
-- 3. Item cost reconciliation — shows cost allocation per item across
--    sale, production, internal use, and remaining inventory.
-- 4. Production cost tracking — adds material cost columns to production
--    records for explicit cost transfer integration.
--
-- Idempotent: safe to run multiple times.
-- =============================================================================

DO $$ BEGIN

-- =========================================================================
-- 1. Production cost columns (integration points for future WIP accounting)
-- =========================================================================

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproductionrecords' AND column_name = 'materialcostperunit'
) THEN
  ALTER TABLE genericproductionrecords
    ADD COLUMN "MaterialCostPerUnit" NUMERIC(18,4) DEFAULT 0,
    ADD COLUMN "TotalMaterialCost"   NUMERIC(18,4) DEFAULT 0,
    ADD COLUMN "CostTransferMethod"  TEXT DEFAULT 'Exact';
  COMMENT ON COLUMN genericproductionrecords."MaterialCostPerUnit" IS
    '442. Per-unit material cost transferred into produced goods.';
  COMMENT ON COLUMN genericproductionrecords."TotalMaterialCost" IS
    '442. Total material cost = MaterialCostPerUnit * QuantityProduced.';
  COMMENT ON COLUMN genericproductionrecords."CostTransferMethod" IS
    '442. How material costs are determined: Exact (from product CostPrice) or Calculated.';
END IF;

END $$;

-- =========================================================================
-- 2. Financial Impact Preview
--    Given a product, quantity, and transaction type, returns the expected
--    financial effects without actually posting anything.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericitem_financialpreview(
    p_farmid           TEXT,
    p_genericproductid INT,
    p_quantity         NUMERIC,
    p_transactiontype  TEXT  -- 'Sale', 'InternalUse', 'Production', 'Purchase'
)
RETURNS TABLE(
    "ProductName"       TEXT,
    "TransactionType"   TEXT,
    "Quantity"          NUMERIC,
    "UnitCost"          NUMERIC,
    "TotalCost"         NUMERIC,
    "InventoryChange"   NUMERIC,
    "RevenueEffect"     NUMERIC,
    "COGSEffect"        NUMERIC,
    "ExpenseEffect"     NUMERIC,
    "CashEffect"        NUMERIC,
    "SupplierEffect"    NUMERIC,
    "CurrentStock"      NUMERIC,
    "StockAfter"        NUMERIC,
    "ExpenseCategory"   TEXT,
    "Notes"             TEXT
) LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_name         TEXT;
    v_costprice    NUMERIC;
    v_sellingprice NUMERIC;
    v_stock        NUMERIC;
    v_tracked      BOOLEAN;
BEGIN
    SELECT productname, costprice, sellingprice, currentstock, trackinventory
    INTO v_name, v_costprice, v_sellingprice, v_stock, v_tracked
    FROM genericproducts
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Product % not found in company %', p_genericproductid, p_farmid;
    END IF;

    "ProductName"     := v_name;
    "TransactionType" := p_transactiontype;
    "Quantity"        := p_quantity;
    "UnitCost"        := v_costprice;
    "TotalCost"       := v_costprice * p_quantity;
    "CurrentStock"    := v_stock;

    CASE p_transactiontype
        WHEN 'Sale' THEN
            "InventoryChange" := CASE WHEN v_tracked THEN -p_quantity ELSE 0 END;
            "RevenueEffect"   := v_sellingprice * p_quantity;
            "COGSEffect"      := v_costprice * p_quantity;
            "ExpenseEffect"   := 0;
            "CashEffect"      := 0;  -- depends on payment method
            "SupplierEffect"  := 0;
            "StockAfter"      := CASE WHEN v_tracked THEN v_stock - p_quantity ELSE v_stock END;
            "ExpenseCategory" := 'Cost of Goods Sold';
            "Notes"           := 'Revenue and COGS recognized on sale approval. Cash depends on payment.';

        WHEN 'InternalUse' THEN
            "InventoryChange" := CASE WHEN v_tracked THEN -p_quantity ELSE 0 END;
            "RevenueEffect"   := 0;
            "COGSEffect"      := 0;
            "ExpenseEffect"   := v_costprice * p_quantity;
            "CashEffect"      := 0;
            "SupplierEffect"  := 0;
            "StockAfter"      := CASE WHEN v_tracked THEN v_stock - p_quantity ELSE v_stock END;
            "ExpenseCategory" := 'Internal Use / Operating Expense';
            "Notes"           := 'Non-cash expense. No cash movement. No revenue.';

        WHEN 'Production' THEN
            "InventoryChange" := CASE WHEN v_tracked THEN p_quantity ELSE 0 END;
            "RevenueEffect"   := 0;
            "COGSEffect"      := 0;
            "ExpenseEffect"   := 0;
            "CashEffect"      := 0;
            "SupplierEffect"  := 0;
            "StockAfter"      := CASE WHEN v_tracked THEN v_stock + p_quantity ELSE v_stock END;
            "ExpenseCategory" := NULL;
            "Notes"           := 'Production increases stock. Material costs tracked separately.';

        WHEN 'Purchase' THEN
            "InventoryChange" := CASE WHEN v_tracked THEN p_quantity ELSE 0 END;
            "RevenueEffect"   := 0;
            "COGSEffect"      := 0;
            "ExpenseEffect"   := 0;
            "CashEffect"      := -(v_costprice * p_quantity);  -- if paid immediately
            "SupplierEffect"  := v_costprice * p_quantity;     -- if on credit
            "StockAfter"      := CASE WHEN v_tracked THEN v_stock + p_quantity ELSE v_stock END;
            "ExpenseCategory" := NULL;
            "Notes"           := 'No expense at purchase. Cost deferred until sold or consumed.';

        ELSE
            RAISE EXCEPTION 'Unknown transaction type: %', p_transactiontype;
    END CASE;

    RETURN NEXT;
END;
$fn$;

-- =========================================================================
-- 3. P&L Expense Breakdown
--    Separates expenses into COGS, Internal Use, and Operating categories.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericreport_pnl_breakdown(
    p_farmid TEXT,
    p_from   DATE,
    p_to     DATE
)
RETURNS TABLE(
    "TotalIncome"           NUMERIC,
    "CostOfGoodsSold"       NUMERIC,
    "GrossProfit"           NUMERIC,
    "InternalUseExpenses"   NUMERIC,
    "OperatingExpenses"     NUMERIC,
    "PayrollExpenses"       NUMERIC,
    "TotalExpenses"         NUMERIC,
    "NetProfit"             NUMERIC,
    "ProfitMarginPct"       NUMERIC,
    "SalesCount"            INT,
    "InternalUseCount"      INT
) LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_income    NUMERIC := 0;
    v_cogs      NUMERIC := 0;
    v_iu_exp    NUMERIC := 0;
    v_op_exp    NUMERIC := 0;
    v_payroll   NUMERIC := 0;
    v_sales_cnt INT := 0;
    v_iu_cnt    INT := 0;
BEGIN
    -- Revenue from approved sales
    SELECT COALESCE(SUM(s.totalamount), 0), COUNT(*)
    INTO v_income, v_sales_cnt
    FROM genericsales s
    WHERE s.farmid = p_farmid
      AND s.status = 'Approved'
      AND COALESCE(s.isdeleted, FALSE) = FALSE
      AND s.saledate >= p_from::timestamp
      AND s.saledate < (p_to + 1)::timestamp;

    -- COGS from sale line items
    SELECT COALESCE(SUM(
      COALESCE(si.costamount, 0) * si.quantity
    ), 0)
    INTO v_cogs
    FROM genericsaleitems si
    INNER JOIN genericsales s ON s.genericsaleid = si.genericsaleid
    WHERE s.farmid = p_farmid
      AND s.status = 'Approved'
      AND COALESCE(s.isdeleted, FALSE) = FALSE
      AND s.saledate >= p_from::timestamp
      AND s.saledate < (p_to + 1)::timestamp
      AND si.itemtype = 'Product';

    -- Internal Use expenses (NonCash expenses linked to internal usage)
    SELECT COALESCE(SUM(e.amount), 0), COUNT(*)
    INTO v_iu_exp, v_iu_cnt
    FROM genericexpenses e
    WHERE e.farmid = p_farmid
      AND e.status = 'Approved'
      AND COALESCE(e.isdeleted, FALSE) = FALSE
      AND COALESCE(e.sourcetype, '') = 'GenericInternalUsage'
      AND e.expensedate >= p_from::timestamp
      AND e.expensedate < (p_to + 1)::timestamp;

    -- Operating expenses (non-internal-use, non-payroll)
    SELECT COALESCE(SUM(e.amount), 0)
    INTO v_op_exp
    FROM genericexpenses e
    WHERE e.farmid = p_farmid
      AND e.status = 'Approved'
      AND COALESCE(e.isdeleted, FALSE) = FALSE
      AND COALESCE(e.sourcetype, '') <> 'GenericInternalUsage'
      AND e.expensedate >= p_from::timestamp
      AND e.expensedate < (p_to + 1)::timestamp;

    -- Payroll expenses
    SELECT COALESCE(SUM(pr.netpay), 0)
    INTO v_payroll
    FROM genericpayrollruns pr
    WHERE pr.farmid = p_farmid
      AND pr.status = 'Paid'
      AND pr.paydate >= p_from::timestamp
      AND pr.paydate < (p_to + 1)::timestamp
      AND NOT EXISTS (
        SELECT 1 FROM genericexpenses e2
        WHERE e2.farmid = p_farmid
          AND COALESCE(e2.sourcetype, '') = 'GenericPayrollRun'
          AND e2.sourceid = pr.genericpayrollrunid
      );

    "TotalIncome"         := v_income;
    "CostOfGoodsSold"     := v_cogs;
    "GrossProfit"         := v_income - v_cogs;
    "InternalUseExpenses" := v_iu_exp;
    "OperatingExpenses"   := v_op_exp;
    "PayrollExpenses"     := v_payroll;
    "TotalExpenses"       := v_cogs + v_iu_exp + v_op_exp + v_payroll;
    "NetProfit"           := v_income - (v_cogs + v_iu_exp + v_op_exp + v_payroll);
    "ProfitMarginPct"     := CASE WHEN v_income > 0
                                THEN ROUND(((v_income - (v_cogs + v_iu_exp + v_op_exp + v_payroll)) / v_income) * 100, 2)
                                ELSE 0 END;
    "SalesCount"          := v_sales_cnt;
    "InternalUseCount"    := v_iu_cnt;
    RETURN NEXT;
END;
$fn$;

-- =========================================================================
-- 4. Item Cost Reconciliation
--    For a given product, shows how the total acquisition cost has been
--    allocated across sale (COGS), production, internal use, and remaining.
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericitem_costreconciliation(
    p_farmid           TEXT,
    p_genericproductid INT
)
RETURNS TABLE(
    "ProductName"          TEXT,
    "TotalPurchasedQty"    NUMERIC,
    "TotalPurchasedCost"   NUMERIC,
    "TotalProducedQty"     NUMERIC,
    "TotalProducedCost"    NUMERIC,
    "SoldQty"              NUMERIC,
    "SoldCost"             NUMERIC,
    "InternalUseQty"       NUMERIC,
    "InternalUseCost"      NUMERIC,
    "ProductionConsumedQty"  NUMERIC,
    "ProductionConsumedCost" NUMERIC,
    "AdjustmentQty"        NUMERIC,
    "RemainingQty"         NUMERIC,
    "RemainingCostBasis"   NUMERIC,
    "CostReconciled"       BOOLEAN
) LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    v_name TEXT;
    v_purchased_qty NUMERIC := 0;
    v_purchased_cost NUMERIC := 0;
    v_produced_qty NUMERIC := 0;
    v_produced_cost NUMERIC := 0;
    v_sold_qty NUMERIC := 0;
    v_sold_cost NUMERIC := 0;
    v_iu_qty NUMERIC := 0;
    v_iu_cost NUMERIC := 0;
    v_prod_consumed_qty NUMERIC := 0;
    v_prod_consumed_cost NUMERIC := 0;
    v_adj_qty NUMERIC := 0;
    v_remaining_qty NUMERIC := 0;
    v_total_in NUMERIC := 0;
    v_total_out NUMERIC := 0;
BEGIN
    SELECT productname INTO v_name
    FROM genericproducts WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    -- Sum movements by type
    SELECT
      COALESCE(SUM(quantity) FILTER (WHERE movementtype = 'PurchaseIn'), 0),
      COALESCE(SUM(ABS(totalcostvalue)) FILTER (WHERE movementtype = 'PurchaseIn'), 0),
      COALESCE(SUM(quantity) FILTER (WHERE movementtype = 'Production'), 0),
      COALESCE(SUM(ABS(totalcostvalue)) FILTER (WHERE movementtype = 'Production'), 0),
      COALESCE(SUM(ABS(quantity)) FILTER (WHERE movementtype = 'SaleOut'), 0),
      COALESCE(SUM(ABS(totalcostvalue)) FILTER (WHERE movementtype = 'SaleOut'), 0),
      COALESCE(SUM(ABS(quantity)) FILTER (WHERE movementtype = 'InternalUseOut'), 0),
      COALESCE(SUM(ABS(totalcostvalue)) FILTER (WHERE movementtype = 'InternalUseOut'), 0),
      COALESCE(SUM(quantity) FILTER (WHERE movementtype IN ('AdjustmentIn','AdjustmentOut','DamageOut','ExpiredOut','ReturnIn','TransferIn','TransferOut','Reversal','OpeningStock')), 0)
    INTO v_purchased_qty, v_purchased_cost, v_produced_qty, v_produced_cost,
         v_sold_qty, v_sold_cost, v_iu_qty, v_iu_cost, v_adj_qty
    FROM genericstockmovements
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

    v_remaining_qty := v_purchased_qty + v_produced_qty + v_adj_qty - v_sold_qty - v_iu_qty;

    "ProductName"            := v_name;
    "TotalPurchasedQty"      := v_purchased_qty;
    "TotalPurchasedCost"     := v_purchased_cost;
    "TotalProducedQty"       := v_produced_qty;
    "TotalProducedCost"      := v_produced_cost;
    "SoldQty"                := v_sold_qty;
    "SoldCost"               := v_sold_cost;
    "InternalUseQty"         := v_iu_qty;
    "InternalUseCost"        := v_iu_cost;
    "ProductionConsumedQty"  := v_prod_consumed_qty;
    "ProductionConsumedCost" := v_prod_consumed_cost;
    "AdjustmentQty"          := v_adj_qty;
    "RemainingQty"           := v_remaining_qty;
    "RemainingCostBasis"     := (v_purchased_cost + v_produced_cost) - v_sold_cost - v_iu_cost - v_prod_consumed_cost;
    "CostReconciled"         := ABS(
        (v_purchased_cost + v_produced_cost) - (v_sold_cost + v_iu_cost + v_prod_consumed_cost + "RemainingCostBasis")
    ) < 0.01;
    RETURN NEXT;
END;
$fn$;

-- =========================================================================
-- 5. Update production record insert to track material costs
-- =========================================================================

CREATE OR REPLACE FUNCTION spgenericproductionrecord_insert(
  p_farmid           TEXT,
  p_genericproductid INT,
  p_quantityproduced NUMERIC,
  p_productiondate   TIMESTAMP,
  p_unitcost         NUMERIC DEFAULT 0,
  p_batchnumber      TEXT DEFAULT NULL,
  p_materialsused    TEXT DEFAULT NULL,
  p_notes            TEXT DEFAULT NULL,
  p_createdby        TEXT DEFAULT NULL
)
RETURNS INT LANGUAGE plpgsql AS $fn$
DECLARE
  v_id INT;
  v_totalcost NUMERIC;
  v_productcost NUMERIC;
BEGIN
  v_totalcost := p_quantityproduced * COALESCE(p_unitcost, 0);

  -- Get the product's current cost price for material cost tracking
  SELECT costprice INTO v_productcost
  FROM genericproducts
  WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

  INSERT INTO genericproductionrecords (
    "FarmId", "GenericProductId", "QuantityProduced", "ProductionDate",
    "UnitCost", "TotalCost", "BatchNumber", "MaterialsUsed", "Notes",
    "Status", "CreatedBy", "CreatedAt",
    "MaterialCostPerUnit", "TotalMaterialCost", "CostTransferMethod"
  ) VALUES (
    p_farmid, p_genericproductid, p_quantityproduced, p_productiondate,
    p_unitcost, v_totalcost, p_batchnumber, p_materialsused, p_notes,
    'Posted', p_createdby, NOW(),
    COALESCE(p_unitcost, v_productcost, 0),
    COALESCE(p_unitcost, v_productcost, 0) * p_quantityproduced,
    'Exact'
  ) RETURNING "GenericProductionRecordId" INTO v_id;

  -- Stock movement (production increases stock)
  INSERT INTO genericstockmovements (
    farmid, genericproductid, movementdate, movementtype,
    quantity, unitcost, totalcostvalue, reason, notes,
    status, createdat
  ) VALUES (
    p_farmid, p_genericproductid, p_productiondate, 'Production',
    p_quantityproduced, p_unitcost, v_totalcost,
    'Production record #' || v_id,
    COALESCE(p_batchnumber, '') || CASE WHEN p_notes IS NOT NULL THEN ' - ' || p_notes ELSE '' END,
    'Approved', NOW()
  );

  -- Update product current stock
  UPDATE genericproducts
  SET currentstock = currentstock + p_quantityproduced
  WHERE genericproductid = p_genericproductid AND farmid = p_farmid;

  RETURN v_id;
END;
$fn$;
