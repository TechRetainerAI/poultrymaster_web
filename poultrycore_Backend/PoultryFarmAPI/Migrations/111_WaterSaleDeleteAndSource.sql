/* ============================================================================
   111_WaterSaleDeleteAndSource.sql

   Sales page: allow DELETE of a direct sale, show its SOURCE, and block
   deleting sales that came from a delivery (James 2026-06-14).

   1. spWaterSale_GetAll / _GetById now return SourceType + SourceId so the UI
      can show where a sale came from and disable Delete on delivery sales.
   2. spWaterSale_Delete: hard-deletes a DIRECT sale (restores stock, removes
      payments + items + the sale). Rejects sales whose SourceType =
      'DeliveryRun' — those belong to a driver return and must be undone there.

   Idempotent (CREATE OR ALTER).
   ============================================================================ */

CREATE OR ALTER PROCEDURE dbo.spWaterSale_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.WaterSaleId, s.FarmId, s.WaterCustomerId, c.Name AS CustomerName,
           s.SaleDate, s.TotalAmount, s.AmountPaid,
           (s.TotalAmount - s.AmountPaid) AS Balance,
           s.Status, s.Notes, s.CreatedDate, s.CreatedBy, s.UpdatedDate,
           s.SourceType, s.SourceId
    FROM   dbo.WaterSales s
    LEFT   JOIN dbo.WaterCustomers c ON c.WaterCustomerId = s.WaterCustomerId
    WHERE  s.FarmId = @FarmId
    ORDER  BY s.SaleDate DESC, s.WaterSaleId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSale_Delete
    @WaterSaleId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaterSales WHERE WaterSaleId = @WaterSaleId AND FarmId = @FarmId)
    BEGIN RAISERROR('Sale not found.', 16, 1); RETURN; END

    DECLARE @src NVARCHAR(50);
    SELECT @src = SourceType FROM dbo.WaterSales WHERE WaterSaleId = @WaterSaleId AND FarmId = @FarmId;
    IF (@src = N'DeliveryRun')
    BEGIN
        RAISERROR('This sale was created from a delivery and cannot be deleted here. Reverse the delivery return instead.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;
    -- on-hand is the sum of stock transactions, so removing this sale's rows
    -- restores the stock it took out.
    DELETE FROM dbo.WaterStockTransactions WHERE FarmId = @FarmId AND RelatedSaleId = @WaterSaleId;
    DELETE FROM dbo.WaterPayments  WHERE FarmId = @FarmId AND WaterSaleId = @WaterSaleId;
    DELETE FROM dbo.WaterSaleItems WHERE WaterSaleId = @WaterSaleId;
    DELETE FROM dbo.WaterSales     WHERE WaterSaleId = @WaterSaleId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterSale_GetAll TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterSale_Delete TO [Techretainer];
END
GO
