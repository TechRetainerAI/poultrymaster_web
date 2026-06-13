/* ============================================================================
   107_ClosingApprovedOnlyDedupAndProdCost.sql

   Daily-closing live aggregation fixes (James 2026-06-13):

   1. APPROVED ONLY — drafts no longer count in the closing. Production batches,
      driver returns and delivery expenses are restricted to Status = 'Approved'
      (was 'Draft','Approved'). A draft delivery is not money yet.

   2. ONE RETURN PER DELIVERY — the closing was summing EVERY driver-return row
      for a loading. Duplicates (e.g. loading #53 had 5 approved returns) were
      counted 2-5x, inflating bags sold, income and shortage. We now keep just
      the latest approved return per WaterVehicleLoadingId.

   3. CASH AT HAND now subtracts production cost too (to match the manual book).
      Income is already net of shortage (it is cash collected, not bags x price),
      so: CashAtHand = collected - credit + customerCollections
                       - rawSpend - generalExp - deliveryExp - productionCost.

   Function-only change — the closing SPs call this function, so no API redeploy
   is required. Idempotent (CREATE OR ALTER). Supersedes the body in 104.
   ============================================================================ */

CREATE OR ALTER FUNCTION dbo.fnWaterDailyClosing_LiveTotals (
    @FarmId      NVARCHAR(450),
    @ClosingDate DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH
    prod AS (
        SELECT
            BagsProduced        = ISNULL(SUM(CAST(BagsProduced - ISNULL(DamagedBags, 0) AS DECIMAL(14,3))), 0),
            TotalProductionCost = ISNULL(SUM(TotalProductionCost), 0)
        FROM dbo.WaterProductionBatches
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
          AND ProductionDate = @ClosingDate
    ),
    sale_items AS (
        SELECT BagsSold = ISNULL(SUM(CAST(si.Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterSales s
        INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE  s.FarmId = @FarmId AND s.Status NOT IN ('Cancelled')
           AND ISNULL(s.SourceType, N'') <> N'DeliveryRun'
           AND s.SaleDate >= CAST(@ClosingDate AS DATETIME2)
           AND s.SaleDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    sale_money AS (
        SELECT
            TotalIncome = ISNULL(SUM(TotalAmount), 0),
            CreditSales = ISNULL(SUM(TotalAmount - AmountPaid), 0)
        FROM   dbo.WaterSales
        WHERE  FarmId = @FarmId AND Status NOT IN ('Cancelled')
           AND ISNULL(SourceType, N'') <> N'DeliveryRun'
           AND SaleDate >= CAST(@ClosingDate AS DATETIME2)
           AND SaleDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    payments AS (
        SELECT
            CustomerCollections = ISNULL(SUM(Amount), 0),
            MoMoPayments = ISNULL(SUM(CASE WHEN PaymentMethod IN (N'Mobile Money', N'MoMo', N'Momo') THEN Amount ELSE 0 END), 0),
            BankPayments = ISNULL(SUM(CASE WHEN PaymentMethod IN (N'Bank', N'Bank Transfer', N'Transfer') THEN Amount ELSE 0 END), 0)
        FROM   dbo.WaterPayments
        WHERE  FarmId = @FarmId
           AND ISNULL(SourceType, N'') <> N'DeliveryRun'
           AND PaymentDate >= CAST(@ClosingDate AS DATETIME2)
           AND PaymentDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    -- APPROVED returns for the day, ranked so we keep ONE row per loading
    -- (latest approved). This is what kills the duplicate double-counting.
    ranked_returns AS (
        SELECT
            WaterDriverReturnId, WaterVehicleLoadingId,
            BagsReturned, BagsDamaged, BagsSold,
            CashCollected, MoMoCollected, BankCollected, CreditSalesAmount, ShortageAmount,
            rn = ROW_NUMBER() OVER (PARTITION BY WaterVehicleLoadingId ORDER BY WaterDriverReturnId DESC)
        FROM   dbo.WaterDriverReturns
        WHERE  FarmId = @FarmId AND Status = 'Approved'
           AND ReturnDate >= CAST(@ClosingDate AS DATETIME2)
           AND ReturnDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    driver_returns AS (
        SELECT
            BagsReturned      = ISNULL(SUM(CAST(BagsReturned AS DECIMAL(14,3))), 0),
            BagsDamaged       = ISNULL(SUM(CAST(BagsDamaged  AS DECIMAL(14,3))), 0),
            DriverBagsSold    = ISNULL(SUM(CAST(BagsSold AS DECIMAL(14,3))), 0),
            DriverTotalIncome = ISNULL(SUM(CashCollected + MoMoCollected + BankCollected + CreditSalesAmount), 0),
            DriverCreditSales = ISNULL(SUM(CreditSalesAmount), 0),
            DriverMoMo        = ISNULL(SUM(MoMoCollected), 0),
            DriverBank        = ISNULL(SUM(BankCollected), 0),
            DriverShortages   = ISNULL(SUM(ShortageAmount), 0)
        FROM   ranked_returns
        WHERE  rn = 1
    ),
    raw_spend AS (
        SELECT RawMaterialSpendToday = ISNULL(SUM(AmountPaid), 0)
        FROM   dbo.WaterRawMaterialPurchases
        WHERE  FarmId = @FarmId
           AND PurchaseDate >= CAST(@ClosingDate AS DATETIME2)
           AND PurchaseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    gen_exp AS (
        SELECT GeneralExpenses = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterExpenses
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
           AND ISNULL(SourceType, N'') <> N'RawMaterialPurchase'
           AND ExpenseDate >= CAST(@ClosingDate AS DATETIME2)
           AND ExpenseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    -- Only the expenses of the ONE kept return per loading (rn = 1), approved.
    delivery_exp AS (
        SELECT DeliveryExpenses = ISNULL(SUM(de.Amount), 0)
        FROM   dbo.WaterDeliveryExpenses de
        INNER  JOIN ranked_returns rr ON rr.WaterDriverReturnId = de.WaterDriverReturnId AND rr.rn = 1
        WHERE  de.IsApproved = 1
    ),
    closing_stock AS (
        SELECT ClosingStockBags = ISNULL(SUM(CAST(Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterStockTransactions WHERE FarmId = @FarmId
    )
    SELECT
        prod.BagsProduced,
        prod.TotalProductionCost,
        BagsSold     = sale_items.BagsSold + driver_returns.DriverBagsSold,
        TotalIncome  = sale_money.TotalIncome + driver_returns.DriverTotalIncome,
        CreditSales  = sale_money.CreditSales + driver_returns.DriverCreditSales,
        payments.CustomerCollections,
        driver_returns.BagsReturned,
        driver_returns.BagsDamaged,
        DriverShortagesTotal = driver_returns.DriverShortages,
        MoMoBalance  = driver_returns.DriverMoMo + payments.MoMoPayments,
        BankBalance  = driver_returns.DriverBank + payments.BankPayments,
        raw_spend.RawMaterialSpendToday,
        closing_stock.ClosingStockBags,
        TotalExpenses = prod.TotalProductionCost + raw_spend.RawMaterialSpendToday
                        + gen_exp.GeneralExpenses + delivery_exp.DeliveryExpenses,
        -- Match the manual book: subtract production cost as well. Income is
        -- already net of shortage (it is cash collected), so shortage is not
        -- subtracted again here.
        CashAtHand    = (sale_money.TotalIncome + driver_returns.DriverTotalIncome)
                        - (sale_money.CreditSales + driver_returns.DriverCreditSales)
                        + payments.CustomerCollections
                        - raw_spend.RawMaterialSpendToday
                        - gen_exp.GeneralExpenses
                        - delivery_exp.DeliveryExpenses
                        - prod.TotalProductionCost
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN driver_returns
    CROSS  JOIN raw_spend
    CROSS  JOIN gen_exp
    CROSS  JOIN delivery_exp
    CROSS  JOIN closing_stock
);
GO
