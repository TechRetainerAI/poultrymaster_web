/* ============================================================================
   109_ClosingCashAddCollectionsNotIncome.sql

   Cash at hand = (Total income - Credit sales) + Customer collections
                  - Total expenses.                       (James 2026-06-13)

   Context: customer/walk-in cash payments that are NOT tied to a counted sale
   (WaterPayments with SourceType <> 'DeliveryRun') are real cash in the drawer
   but are NOT part of Total income. Migration 108 dropped them, which
   UNDER-counted physical cash (Great Favour 2026-06-12 had 88+50+22 = 160 of
   walk-in cash that vanished). This restores them to cash WITHOUT putting them
   in Total income (they show on their own "Customer collections" tile).

   Net: Great Favour 2026-06-12 -> 5,544 - 0 + 160 - 1,810 = 3,894.

   Everything else unchanged from 107/108 (approved-only, one return per
   delivery, production cost inside Total expenses). Function-only; no API
   redeploy. Idempotent (CREATE OR ALTER).
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
        -- Cash = (income - credit) + customer collections - total expenses.
        -- Collections are real cash NOT included in Total income, so they are
        -- added here; credit is excluded (uncollected); production cost is part
        -- of Total expenses.
        CashAtHand    = (sale_money.TotalIncome + driver_returns.DriverTotalIncome)
                        - (sale_money.CreditSales + driver_returns.DriverCreditSales)
                        + payments.CustomerCollections
                        - (prod.TotalProductionCost + raw_spend.RawMaterialSpendToday
                           + gen_exp.GeneralExpenses + delivery_exp.DeliveryExpenses)
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
