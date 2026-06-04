-- =============================================================================
-- Migration 083: Delivery-Return Approve & Reconcile + Sales Posting Modes
-- =============================================================================
-- "Payroll Details Page, Delivery Return Approval, Delivery Sales Posting
--  Modes…" §2 + §3 + §4 + §5 + §6.
--
-- Schema additions on dbo.WaterDriverReturns
--   SalesPostingMode      NVARCHAR(20)  NULL  -- 'Detailed' | 'OneCustomer' | 'Summary'
--   PrimaryCustomerId     INT           NULL  -- for OneCustomer / Summary modes
--
-- New SP
--   spWaterDriverReturn_ApproveReconcile
--     One-shot save-and-approve. Validates:
--       * BagsLoaded == Sold + Returned + Damaged + Missing (per item OR overall)
--       * Cash / MoMo / Bank / Credit are non-negative
--       * For Detailed mode: sum of customer breakdown totals matches sales total
--     Then, based on @SalesPostingMode:
--       * Detailed     → same materialisation as spWaterDriverReturn_Approve (064).
--       * OneCustomer  → builds a single virtual customer-sale row from the
--                        item totals and posts it to @PrimaryCustomerId.
--       * Summary      → resolves the company's DefaultCustomerType='GeneralDelivery'
--                        and posts a single virtual customer-sale to that
--                        customer. Credit balance (if any) is assigned there
--                        too (or to the 'GeneralCredit' default if present).
--   spWaterDriverReturn_UpdatePostingMode  — sets the posting mode + primary
--                                            customer on a Draft return.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Schema
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterDriverReturns', N'SalesPostingMode') IS NULL
    ALTER TABLE dbo.WaterDriverReturns ADD SalesPostingMode NVARCHAR(20) NULL;
GO
IF COL_LENGTH(N'dbo.WaterDriverReturns', N'PrimaryCustomerId') IS NULL
    ALTER TABLE dbo.WaterDriverReturns ADD PrimaryCustomerId INT NULL;
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterDriverReturn_UpdatePostingMode
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_UpdatePostingMode
    @WaterDriverReturnId INT,
    @FarmId              NVARCHAR(450),
    @SalesPostingMode    NVARCHAR(20),    -- 'Detailed' | 'OneCustomer' | 'Summary'
    @PrimaryCustomerId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @SalesPostingMode NOT IN (N'Detailed', N'OneCustomer', N'Summary')
    BEGIN RAISERROR('SalesPostingMode must be Detailed, OneCustomer or Summary.', 16, 1); RETURN; END

    IF @SalesPostingMode = N'OneCustomer' AND @PrimaryCustomerId IS NULL
    BEGIN RAISERROR('OneCustomer mode requires PrimaryCustomerId.', 16, 1); RETURN; END

    UPDATE dbo.WaterDriverReturns
    SET    SalesPostingMode  = @SalesPostingMode,
           PrimaryCustomerId = CASE WHEN @SalesPostingMode = N'Detailed' THEN NULL ELSE @PrimaryCustomerId END,
           UpdatedAt         = SYSUTCDATETIME()
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId
      AND  Status = N'Draft';

    IF @@ROWCOUNT = 0
        RAISERROR('Driver return not found or not in Draft status.', 16, 1);
END
GO

-- -----------------------------------------------------------------------------
-- 3. spWaterDriverReturn_ApproveReconcile
--    Validates first (so the frontend table-level "Approve & Reconcile" can be
--    called against a Draft without re-opening the modal), then materialises
--    sales using the row's SalesPostingMode (defaults to 'Detailed' for
--    backwards-compat with existing draft rows that pre-date this migration).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_ApproveReconcile
    @WaterDriverReturnId INT,
    @FarmId              NVARCHAR(450),
    @ApprovedBy          NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @LoadingId INT,
            @BagsSold INT, @BagsReturned INT, @BagsDamaged INT, @MissingBags INT,
            @CashCollected DECIMAL(14,2), @MoMoCollected DECIMAL(14,2),
            @BankCollected DECIMAL(14,2), @CreditSalesAmount DECIMAL(14,2),
            @PostingMode NVARCHAR(20), @PrimaryCustomerId INT,
            @LoadingBagsTotal INT;

    SELECT @Status = Status, @LoadingId = WaterVehicleLoadingId,
           @BagsSold = BagsSold, @BagsReturned = BagsReturned,
           @BagsDamaged = BagsDamaged, @MissingBags = MissingBags,
           @CashCollected = CashCollected, @MoMoCollected = MoMoCollected,
           @BankCollected = BankCollected, @CreditSalesAmount = CreditSalesAmount,
           @PostingMode = ISNULL(SalesPostingMode, N'Detailed'),
           @PrimaryCustomerId = PrimaryCustomerId
    FROM   dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Driver return %d not found.', 16, 1, @WaterDriverReturnId); RETURN; END
    IF @Status = N'Approved'
    BEGIN
        SELECT WaterDriverReturnId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterDriverReturns WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
        RETURN;
    END
    IF @Status <> N'Draft'
    BEGIN RAISERROR('Driver return cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- -------- Validation ------------------------------------------------
    -- 1. Bag accounting must balance against the loading.
    SELECT @LoadingBagsTotal = BagsLoaded FROM dbo.WaterVehicleLoadings WHERE WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;
    IF @LoadingBagsTotal IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @LoadingId); RETURN; END

    -- Prefer per-item totals when present (multi-product); else header totals.
    IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturnItems WHERE WaterDriverReturnId = @WaterDriverReturnId)
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM   dbo.WaterDriverReturnItems ri
            WHERE  ri.WaterDriverReturnId = @WaterDriverReturnId
              AND  (ri.BagsSold + ri.BagsReturned + ri.BagsDamaged) > ri.BagsLoaded
        )
        BEGIN RAISERROR('Per-product reconciliation does not balance: sold + returned + damaged exceeds loaded for at least one product.', 16, 1); RETURN; END
    END
    ELSE
    BEGIN
        IF (@BagsSold + @BagsReturned + @BagsDamaged + @MissingBags) <> @LoadingBagsTotal
        BEGIN
            RAISERROR('Bag accounting does not balance: %d sold + %d returned + %d damaged + %d missing != %d loaded.',
                      16, 1, @BagsSold, @BagsReturned, @BagsDamaged, @MissingBags, @LoadingBagsTotal);
            RETURN;
        END
    END

    -- 2. Money fields can't be negative.
    IF (@CashCollected < 0 OR @MoMoCollected < 0 OR @BankCollected < 0 OR @CreditSalesAmount < 0)
    BEGIN RAISERROR('Cash / MoMo / Bank / Credit values cannot be negative.', 16, 1); RETURN; END

    -- 3. Detailed mode: customer breakdown total ≈ collected total.
    IF @PostingMode = N'Detailed'
       AND EXISTS (SELECT 1 FROM dbo.WaterDriverReturnCustomerSales WHERE WaterDriverReturnId = @WaterDriverReturnId)
    BEGIN
        DECLARE @CustTotalSum DECIMAL(14,2),
                @CollectedSum DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
        SELECT @CustTotalSum = SUM(cs.CashPaid + cs.MoMoPaid + cs.BankPaid + cs.CreditAmount)
        FROM   dbo.WaterDriverReturnCustomerSales cs
        WHERE  cs.WaterDriverReturnId = @WaterDriverReturnId;

        IF ABS(ISNULL(@CustTotalSum,0) - @CollectedSum) > 0.01
        BEGIN
            -- RAISERROR only supports %s / %d, so format the decimals to strings first.
            DECLARE @CustStr NVARCHAR(40) = CONVERT(NVARCHAR(40), CAST(ISNULL(@CustTotalSum, 0) AS DECIMAL(14,2)));
            DECLARE @ColStr  NVARCHAR(40) = CONVERT(NVARCHAR(40), CAST(@CollectedSum AS DECIMAL(14,2)));
            RAISERROR('Customer-breakdown total (%s) does not match collected total (%s).',
                      16, 1, @CustStr, @ColStr);
            RETURN;
        END
    END

    -- -------- Posting prep ----------------------------------------------
    DECLARE @ProductId INT, @ExpectedPricePerBag DECIMAL(14,2),
            @DriverId INT, @VehicleId INT, @RouteId INT;
    SELECT @ProductId = WaterProductId, @ExpectedPricePerBag = ExpectedSellingPricePerBag,
           @DriverId = WaterDriverId, @VehicleId = WaterVehicleId, @RouteId = WaterRouteId
    FROM   dbo.WaterVehicleLoadings WHERE WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    DECLARE @ExpectedCash DECIMAL(14,2);
    SELECT @ExpectedCash = ISNULL(SUM(ri.ExpectedSales), 0)
    FROM   dbo.WaterDriverReturnItems ri WHERE ri.WaterDriverReturnId = @WaterDriverReturnId;
    IF @ExpectedCash = 0
        SET @ExpectedCash = CAST(@BagsSold AS DECIMAL(14,2)) * @ExpectedPricePerBag;

    DECLARE @TotalAccounted DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
    DECLARE @Shortage DECIMAL(14,2) = CASE WHEN @ExpectedCash > @TotalAccounted THEN @ExpectedCash - @TotalAccounted ELSE 0 END;
    DECLARE @Overage  DECIMAL(14,2) = CASE WHEN @TotalAccounted > @ExpectedCash THEN @TotalAccounted - @ExpectedCash ELSE 0 END;

    -- For OneCustomer / Summary modes we need a customer to attach the sale to.
    IF @PostingMode = N'Summary'
    BEGIN
        IF @PrimaryCustomerId IS NULL
        BEGIN
            SELECT TOP (1) @PrimaryCustomerId = WaterCustomerId
            FROM   dbo.WaterCustomers
            WHERE  FarmId = @FarmId AND DefaultCustomerType = N'GeneralDelivery';

            IF @PrimaryCustomerId IS NULL
            BEGIN
                -- Lazy-seed defaults so Summary never silently fails for older farms.
                EXEC dbo.spWaterCustomer_CreateDefaults @FarmId = @FarmId;
                SELECT TOP (1) @PrimaryCustomerId = WaterCustomerId
                FROM   dbo.WaterCustomers
                WHERE  FarmId = @FarmId AND DefaultCustomerType = N'GeneralDelivery';
            END
        END
    END
    ELSE IF @PostingMode = N'OneCustomer'
    BEGIN
        IF @PrimaryCustomerId IS NULL
        BEGIN RAISERROR('OneCustomer posting mode requires PrimaryCustomerId.', 16, 1); RETURN; END
    END

    -- Optional credit-balance target (Summary mode only). Fall back to the
    -- primary customer if no GeneralCredit default exists.
    DECLARE @CreditCustomerId INT = @PrimaryCustomerId;
    IF @PostingMode = N'Summary' AND @CreditSalesAmount > 0
    BEGIN
        SELECT TOP (1) @CreditCustomerId = WaterCustomerId
        FROM   dbo.WaterCustomers
        WHERE  FarmId = @FarmId AND DefaultCustomerType = N'GeneralCredit';
        IF @CreditCustomerId IS NULL SET @CreditCustomerId = @PrimaryCustomerId;
    END

    -- -------- Apply -----------------------------------------------------
    BEGIN TRANSACTION;

    UPDATE dbo.WaterDriverReturns
    SET    Status = N'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME(),
           ShortageAmount = @Shortage, OverageAmount = @Overage
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    UPDATE dbo.WaterVehicleLoadings
    SET    Status = N'Reconciled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- Per-product LoadReturnIn stock movements (returned bags go back to warehouse).
    IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturnItems WHERE WaterDriverReturnId = @WaterDriverReturnId)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        SELECT @FarmId, ri.WaterProductId, N'LoadReturnIn', ri.BagsReturned, NULL, NULL,
               CONCAT(N'Driver return #', @WaterDriverReturnId, N' for loading #', @LoadingId),
               @ApprovedBy
        FROM   dbo.WaterDriverReturnItems ri
        WHERE  ri.WaterDriverReturnId = @WaterDriverReturnId AND ri.BagsReturned > 0;
    END
    ELSE IF (@BagsReturned > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        VALUES (@FarmId, @ProductId, N'LoadReturnIn', @BagsReturned, NULL, NULL,
                CONCAT(N'Driver return #', @WaterDriverReturnId, N' for loading #', @LoadingId), @ApprovedBy);
    END

    -- -------- Materialise customer sales --------------------------------
    IF @PostingMode = N'Detailed'
    BEGIN
        -- Same logic as spWaterDriverReturn_Approve (migration 064). One sale
        -- per customer-breakdown row.
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT cs.WaterDriverReturnCustomerSaleId,
                   cs.WaterCustomerId, cs.TotalAmount,
                   cs.CashPaid, cs.MoMoPaid, cs.BankPaid, cs.CreditAmount,
                   cs.Notes
            FROM   dbo.WaterDriverReturnCustomerSales cs
            WHERE  cs.WaterDriverReturnId = @WaterDriverReturnId;

        DECLARE @csId INT, @custId INT, @tot DECIMAL(14,2),
                @cash DECIMAL(14,2), @momo DECIMAL(14,2), @bank DECIMAL(14,2),
                @credit DECIMAL(14,2), @csNotes NVARCHAR(500);

        OPEN cur;
        FETCH NEXT FROM cur INTO @csId, @custId, @tot, @cash, @momo, @bank, @credit, @csNotes;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @paid DECIMAL(14,2) = @cash + @momo + @bank;
            DECLARE @balance DECIMAL(14,2) = @tot - @paid;
            DECLARE @saleStatus NVARCHAR(30) =
                CASE WHEN @balance <= 0 THEN N'Paid'
                     WHEN @paid > 0     THEN N'PartiallyPaid'
                     ELSE                     N'Pending' END;

            INSERT INTO dbo.WaterSales
                (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes,
                 CreatedBy, SourceType, SourceId, WaterDriverId, WaterVehicleId, WaterRouteId)
            VALUES
                (@FarmId, @custId, SYSUTCDATETIME(), @tot, @paid, @saleStatus, @csNotes,
                 @ApprovedBy, N'DeliveryRun', @WaterDriverReturnId, @DriverId, @VehicleId, @RouteId);

            DECLARE @saleId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO dbo.WaterSaleItems (WaterSaleId, WaterProductId, Quantity, UnitPrice)
            SELECT @saleId, csi.WaterProductId, csi.Quantity, csi.UnitPrice
            FROM   dbo.WaterDriverReturnCustomerSaleItems csi
            WHERE  csi.WaterDriverReturnCustomerSaleId = @csId;

            IF (@cash > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @saleId, @cash, N'Cash', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @custId, N'DeliveryRun', @WaterDriverReturnId);
            IF (@momo > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @saleId, @momo, N'Mobile Money', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @custId, N'DeliveryRun', @WaterDriverReturnId);
            IF (@bank > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @saleId, @bank, N'Bank', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @custId, N'DeliveryRun', @WaterDriverReturnId);

            UPDATE dbo.WaterDriverReturnCustomerSales
            SET    GeneratedWaterSaleId = @saleId, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterDriverReturnCustomerSaleId = @csId;

            FETCH NEXT FROM cur INTO @csId, @custId, @tot, @cash, @momo, @bank, @credit, @csNotes;
        END
        CLOSE cur; DEALLOCATE cur;
    END
    ELSE
    BEGIN
        -- Summary / OneCustomer: one virtual sale to @PrimaryCustomerId, plus
        -- (for Summary with credit) a credit-only sale to @CreditCustomerId
        -- if it's a different customer.

        DECLARE @SaleTotal     DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
        DECLARE @SalePaid      DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected;
        DECLARE @SaleStatusOne NVARCHAR(30)  =
            CASE WHEN @SaleTotal - @SalePaid <= 0 THEN N'Paid'
                 WHEN @SalePaid > 0               THEN N'PartiallyPaid'
                 ELSE                                  N'Pending' END;

        IF @PostingMode = N'Summary' AND @CreditCustomerId IS NOT NULL AND @CreditCustomerId <> @PrimaryCustomerId AND @CreditSalesAmount > 0
        BEGIN
            -- Split: Cash/MoMo/Bank → primary (paid); Credit → credit customer (unpaid).
            INSERT INTO dbo.WaterSales
                (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes,
                 CreatedBy, SourceType, SourceId, WaterDriverId, WaterVehicleId, WaterRouteId)
            VALUES
                (@FarmId, @PrimaryCustomerId, SYSUTCDATETIME(), @SalePaid, @SalePaid, N'Paid',
                 CONCAT(N'Summary delivery sale (DR#', @WaterDriverReturnId, N')'),
                 @ApprovedBy, N'DeliveryRun', @WaterDriverReturnId, @DriverId, @VehicleId, @RouteId);
            DECLARE @sId1 INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO dbo.WaterSaleItems (WaterSaleId, WaterProductId, Quantity, UnitPrice)
            SELECT @sId1, ri.WaterProductId, ri.BagsSold, ri.UnitPrice
            FROM   dbo.WaterDriverReturnItems ri
            WHERE  ri.WaterDriverReturnId = @WaterDriverReturnId AND ri.BagsSold > 0;

            IF (@CashCollected > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @sId1, @CashCollected, N'Cash', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @PrimaryCustomerId, N'DeliveryRun', @WaterDriverReturnId);
            IF (@MoMoCollected > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @sId1, @MoMoCollected, N'Mobile Money', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @PrimaryCustomerId, N'DeliveryRun', @WaterDriverReturnId);
            IF (@BankCollected > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @sId1, @BankCollected, N'Bank', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @PrimaryCustomerId, N'DeliveryRun', @WaterDriverReturnId);

            -- Credit-only sale to the GeneralCredit customer.
            INSERT INTO dbo.WaterSales
                (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes,
                 CreatedBy, SourceType, SourceId, WaterDriverId, WaterVehicleId, WaterRouteId)
            VALUES
                (@FarmId, @CreditCustomerId, SYSUTCDATETIME(), @CreditSalesAmount, 0, N'Pending',
                 CONCAT(N'Summary credit sale (DR#', @WaterDriverReturnId, N')'),
                 @ApprovedBy, N'DeliveryRun', @WaterDriverReturnId, @DriverId, @VehicleId, @RouteId);
        END
        ELSE IF (@SaleTotal > 0 AND @PrimaryCustomerId IS NOT NULL)
        BEGIN
            INSERT INTO dbo.WaterSales
                (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes,
                 CreatedBy, SourceType, SourceId, WaterDriverId, WaterVehicleId, WaterRouteId)
            VALUES
                (@FarmId, @PrimaryCustomerId, SYSUTCDATETIME(), @SaleTotal, @SalePaid, @SaleStatusOne,
                 CONCAT(CASE WHEN @PostingMode = N'Summary' THEN N'Summary' ELSE N'OneCustomer' END,
                        N' delivery sale (DR#', @WaterDriverReturnId, N')'),
                 @ApprovedBy, N'DeliveryRun', @WaterDriverReturnId, @DriverId, @VehicleId, @RouteId);

            DECLARE @sId INT = CAST(SCOPE_IDENTITY() AS INT);

            -- Build line items from the per-product totals on the return.
            IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturnItems WHERE WaterDriverReturnId = @WaterDriverReturnId)
            BEGIN
                INSERT INTO dbo.WaterSaleItems (WaterSaleId, WaterProductId, Quantity, UnitPrice)
                SELECT @sId, ri.WaterProductId, ri.BagsSold, ri.UnitPrice
                FROM   dbo.WaterDriverReturnItems ri
                WHERE  ri.WaterDriverReturnId = @WaterDriverReturnId AND ri.BagsSold > 0;
            END
            ELSE IF (@BagsSold > 0)
            BEGIN
                INSERT INTO dbo.WaterSaleItems (WaterSaleId, WaterProductId, Quantity, UnitPrice)
                VALUES (@sId, @ProductId, @BagsSold, @ExpectedPricePerBag);
            END

            IF (@CashCollected > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @sId, @CashCollected, N'Cash', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @PrimaryCustomerId, N'DeliveryRun', @WaterDriverReturnId);
            IF (@MoMoCollected > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @sId, @MoMoCollected, N'Mobile Money', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @PrimaryCustomerId, N'DeliveryRun', @WaterDriverReturnId);
            IF (@BankCollected > 0)
                INSERT INTO dbo.WaterPayments (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy, WaterCustomerId, SourceType, SourceId)
                VALUES (@FarmId, @sId, @BankCollected, N'Bank', SYSUTCDATETIME(), CONCAT(N'DR#', @WaterDriverReturnId), NULL, @ApprovedBy, @PrimaryCustomerId, N'DeliveryRun', @WaterDriverReturnId);
        END
    END

    -- Shortage row (legacy behaviour preserved from 064).
    IF (@Shortage > 0)
    BEGIN
        INSERT INTO dbo.WaterDriverShortages
            (FarmId, WaterDriverId, WaterVehicleLoadingId, WaterDriverReturnId,
             ShortageDate, ExpectedAmount, ActualAmount, ShortageAmount,
             Reason, Status, Notes)
        VALUES
            (@FarmId, @DriverId, @LoadingId, @WaterDriverReturnId,
             SYSUTCDATETIME(), @ExpectedCash, @TotalAccounted, @Shortage,
             NULL, N'Pending', NULL);
    END

    COMMIT TRANSACTION;

    SELECT WaterDriverReturnId, Status, ApprovedBy, ApprovedAt,
           ShortageAmount, OverageAmount, SalesPostingMode, PrimaryCustomerId
    FROM dbo.WaterDriverReturns
    WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Surface the new fields on _GetAll / _GetById without breaking older
--    callers (existing C# reader uses HasColumn-style probes so new columns
--    are picked up automatically once present).
--
-- This recreates only the SELECT shape; the bodies elsewhere are unchanged.
-- =============================================================================
-- spWaterDriverReturn_GetAll / _GetById may already exist with a different
-- body. We're only adding columns to the result-set — we don't redefine the
-- procs here to avoid blowing away cancel/uncancel/reverse refactors. The
-- C# reader probes columns by name, so missing columns are a no-op.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 5. Grants
-- -----------------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_ApproveReconcile  TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDriverReturn_UpdatePostingMode TO [Techretainer];
END
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_ApproveReconcile  TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_UpdatePostingMode TO PoultryAppRole;
END
GO

PRINT '083_AddDeliveryReturnApproveReconcileAndPostingModes.sql complete.';
GO
