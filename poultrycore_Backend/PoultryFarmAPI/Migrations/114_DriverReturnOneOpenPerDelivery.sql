/* ============================================================================
   114_DriverReturnOneOpenPerDelivery.sql

   Block duplicate driver returns at the source (James 2026-06-15): only one
   open (Draft/Approved) return per vehicle loading. The check lives INSIDE the
   SP — the app login has EXECUTE on procs only (no direct table SELECT), so it
   cannot be an ad-hoc query in the service layer.

   This re-creates spWaterDriverReturn_Insert (verbatim from migration 064) with
   the guard added right after the "loading exists" check. Idempotent.
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Insert
    @FarmId NVARCHAR(450),
    @WaterVehicleLoadingId INT,
    @ReturnDate DATETIME2 = NULL,
    @BagsSold INT,
    @BagsReturned INT,
    @BagsDamaged INT = 0,
    @MissingBags INT = 0,
    @CashCollected DECIMAL(14,2) = 0,
    @MoMoCollected DECIMAL(14,2) = 0,
    @BankCollected DECIMAL(14,2) = 0,
    @CreditSalesAmount DECIMAL(14,2) = 0,
    @CashReturnedByDriver DECIMAL(14,2) = 0,
    @ApprovedDeliveryExpenses DECIMAL(14,2) = 0,
    @ReconciledByStaffId INT = NULL,
    @Notes NVARCHAR(1000) = NULL,
    @CreatedBy NVARCHAR(450) = NULL,
    -- New: per-product reconciliation.
    --   [{ "waterProductId":1, "bagsSold":600, "bagsReturned":45,
    --      "bagsDamaged":5, "unitPrice":30, "notes":null }]
    @ItemsJson NVARCHAR(MAX) = NULL,
    -- New: customer breakdown.
    --   [{ "waterCustomerId":7, "customerLabel":null, "cashPaid":2000,
    --      "moMoPaid":500, "bankPaid":0, "creditAmount":500, "notes":null,
    --      "items":[{"waterProductId":1,"quantity":100,"unitPrice":30}, ...] }]
    @CustomerSalesJson NVARCHAR(MAX) = NULL,
    -- New: delivery expenses.
    --   [{ "expenseCategory":"Fuel", "amount":50, "description":null,
    --      "isApproved":true, "notes":null }]
    @ExpensesJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BagsLoaded INT;
    SELECT @BagsLoaded = BagsLoaded FROM dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
    IF @BagsLoaded IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @WaterVehicleLoadingId); RETURN; END

    -- One open return per delivery: block a second Draft/Approved return for
    -- the same loading (operators created duplicate Drafts, e.g. delivery #68).
    IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturns
               WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId
                 AND Status IN ('Draft', 'Approved'))
    BEGIN
        RAISERROR('A return already exists for this delivery. Edit or cancel the existing return before recording a new one.', 16, 1);
        RETURN;
    END

    IF (@BagsSold + @BagsReturned + @BagsDamaged + @MissingBags) <> @BagsLoaded
    BEGIN
        RAISERROR('Bag accounting does not balance: %d sold + %d returned + %d damaged + %d missing != %d loaded.',
                  16, 1, @BagsSold, @BagsReturned, @BagsDamaged, @MissingBags, @BagsLoaded);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterDriverReturns (
        FarmId, WaterVehicleLoadingId, ReturnDate, BagsSold, BagsReturned, BagsDamaged,
        MissingBags, CashCollected, MoMoCollected, BankCollected, CreditSalesAmount,
        CashReturnedByDriver, ApprovedDeliveryExpenses,
        ReconciledByStaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterVehicleLoadingId, ISNULL(@ReturnDate, SYSUTCDATETIME()),
        @BagsSold, @BagsReturned, @BagsDamaged, @MissingBags,
        @CashCollected, @MoMoCollected, @BankCollected, @CreditSalesAmount,
        @CashReturnedByDriver, @ApprovedDeliveryExpenses,
        @ReconciledByStaffId, 'Draft', @Notes, @CreatedBy
    );
    DECLARE @ReturnId INT = CAST(SCOPE_IDENTITY() AS INT);

    -- Per-product reconciliation rows.
    IF @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2
    BEGIN
        ;WITH src AS (
            SELECT j.WaterProductId, j.BagsSold, j.BagsReturned, j.BagsDamaged, j.UnitPrice, j.Notes
            FROM OPENJSON(@ItemsJson)
            WITH (
                WaterProductId  INT             '$.waterProductId',
                BagsSold        INT             '$.bagsSold',
                BagsReturned    INT             '$.bagsReturned',
                BagsDamaged     INT             '$.bagsDamaged',
                UnitPrice       DECIMAL(14,2)   '$.unitPrice',
                Notes           NVARCHAR(300)   '$.notes'
            ) j
        )
        INSERT INTO dbo.WaterDriverReturnItems
            (WaterDriverReturnId, WaterProductId, BagsLoaded, BagsSold, BagsReturned, BagsDamaged, UnitPrice, Notes)
        SELECT  @ReturnId,
                src.WaterProductId,
                ISNULL(li.BagsLoaded, 0),
                ISNULL(src.BagsSold, 0),
                ISNULL(src.BagsReturned, 0),
                ISNULL(src.BagsDamaged, 0),
                ISNULL(src.UnitPrice, li.UnitPrice),
                src.Notes
        FROM    src
        LEFT JOIN dbo.WaterVehicleLoadingItems li
               ON li.WaterVehicleLoadingId = @WaterVehicleLoadingId
              AND li.WaterProductId        = src.WaterProductId
        WHERE   src.WaterProductId IS NOT NULL;
    END

    -- Customer breakdown rows + items.
    IF @CustomerSalesJson IS NOT NULL AND LEN(@CustomerSalesJson) > 2
    BEGIN
        DECLARE @cs TABLE (
            Idx INT IDENTITY(1,1) PRIMARY KEY,
            NewId INT NULL,
            WaterCustomerId INT NULL,
            CustomerLabel   NVARCHAR(150),
            CashPaid        DECIMAL(14,2),
            MoMoPaid        DECIMAL(14,2),
            BankPaid        DECIMAL(14,2),
            CreditAmount    DECIMAL(14,2),
            Notes           NVARCHAR(500),
            ItemsJson       NVARCHAR(MAX)
        );

        INSERT INTO @cs (WaterCustomerId, CustomerLabel, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes, ItemsJson)
        SELECT j.WaterCustomerId, j.CustomerLabel,
               ISNULL(j.CashPaid, 0), ISNULL(j.MoMoPaid, 0),
               ISNULL(j.BankPaid, 0), ISNULL(j.CreditAmount, 0),
               j.Notes, j.ItemsJson
        FROM OPENJSON(@CustomerSalesJson)
        WITH (
            WaterCustomerId INT             '$.waterCustomerId',
            CustomerLabel   NVARCHAR(150)   '$.customerLabel',
            CashPaid        DECIMAL(14,2)   '$.cashPaid',
            MoMoPaid        DECIMAL(14,2)   '$.moMoPaid',
            BankPaid        DECIMAL(14,2)   '$.bankPaid',
            CreditAmount    DECIMAL(14,2)   '$.creditAmount',
            Notes           NVARCHAR(500)   '$.notes',
            ItemsJson       NVARCHAR(MAX)   '$.items' AS JSON
        ) j;

        -- Rename locals with @row prefix to avoid collisions with the SP's
        -- own @Notes / @ItemsJson parameters (SQL Server is case-insensitive
        -- about variable names).
        DECLARE @rowIdx INT = 1, @rowMax INT = (SELECT MAX(Idx) FROM @cs);
        DECLARE @rowCust INT, @rowLabel NVARCHAR(150),
                @rowCash DECIMAL(14,2), @rowMomo DECIMAL(14,2),
                @rowBank DECIMAL(14,2), @rowCredit DECIMAL(14,2),
                @rowNotes NVARCHAR(500), @rowItemsJson NVARCHAR(MAX),
                @rowTotalAmt DECIMAL(14,2), @newSaleId INT;

        WHILE @rowIdx <= @rowMax
        BEGIN
            SELECT @rowCust = WaterCustomerId, @rowLabel = CustomerLabel,
                   @rowCash = CashPaid, @rowMomo = MoMoPaid, @rowBank = BankPaid,
                   @rowCredit = CreditAmount, @rowNotes = Notes, @rowItemsJson = ItemsJson
            FROM   @cs WHERE Idx = @rowIdx;

            SET @rowTotalAmt = 0;
            IF @rowItemsJson IS NOT NULL AND LEN(@rowItemsJson) > 2
            BEGIN
                SELECT @rowTotalAmt = ISNULL(SUM(CAST(ji.Quantity AS DECIMAL(14,2)) * ji.UnitPrice), 0)
                FROM OPENJSON(@rowItemsJson)
                WITH (
                    WaterProductId  INT             '$.waterProductId',
                    Quantity        INT             '$.quantity',
                    UnitPrice       DECIMAL(14,2)   '$.unitPrice'
                ) ji;
            END

            INSERT INTO dbo.WaterDriverReturnCustomerSales
                (WaterDriverReturnId, WaterCustomerId, CustomerLabel,
                 TotalAmount, CashPaid, MoMoPaid, BankPaid, CreditAmount, Notes)
            VALUES (@ReturnId, @rowCust, @rowLabel, @rowTotalAmt,
                    @rowCash, @rowMomo, @rowBank, @rowCredit, @rowNotes);

            SET @newSaleId = CAST(SCOPE_IDENTITY() AS INT);
            UPDATE @cs SET NewId = @newSaleId WHERE Idx = @rowIdx;

            IF @rowItemsJson IS NOT NULL AND LEN(@rowItemsJson) > 2
            BEGIN
                INSERT INTO dbo.WaterDriverReturnCustomerSaleItems
                    (WaterDriverReturnCustomerSaleId, WaterProductId, Quantity, UnitPrice)
                SELECT @newSaleId, ji.WaterProductId, ji.Quantity, ji.UnitPrice
                FROM OPENJSON(@rowItemsJson)
                WITH (
                    WaterProductId  INT             '$.waterProductId',
                    Quantity        INT             '$.quantity',
                    UnitPrice       DECIMAL(14,2)   '$.unitPrice'
                ) ji
                WHERE ji.WaterProductId IS NOT NULL AND ji.Quantity > 0;
            END

            SET @rowIdx = @rowIdx + 1;
        END
    END

    -- Delivery expenses.
    IF @ExpensesJson IS NOT NULL AND LEN(@ExpensesJson) > 2
    BEGIN
        INSERT INTO dbo.WaterDeliveryExpenses
            (FarmId, WaterDriverReturnId, WaterVehicleLoadingId, ExpenseCategory,
             Amount, Description, IsApproved, Notes, CreatedBy)
        SELECT @FarmId, @ReturnId, @WaterVehicleLoadingId,
               ISNULL(NULLIF(j.ExpenseCategory, N''), N'Other'),
               ISNULL(j.Amount, 0), j.Description,
               ISNULL(j.IsApproved, 1), j.Notes, @CreatedBy
        FROM OPENJSON(@ExpensesJson)
        WITH (
            ExpenseCategory NVARCHAR(40)    '$.expenseCategory',
            Amount          DECIMAL(14,2)   '$.amount',
            Description     NVARCHAR(500)   '$.description',
            IsApproved      BIT             '$.isApproved',
            Notes           NVARCHAR(500)   '$.notes'
        ) j;
    END

    COMMIT TRANSACTION;

    SELECT @ReturnId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Insert TO [Techretainer];
GO
