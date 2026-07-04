-- =============================================================================
-- Migration 136: Production Records increase egg inventory + create stock movement
-- =============================================================================
-- Doc 1 section 4d + 5. The Poultry Production Records page (ProductionRecord
-- controller -> spProductionRecord_*) previously posted only BIRD mortality
-- stock (migration 134); it never touched EGG inventory, so recording daily
-- production did not increase the egg finished-product stock and created no
-- stock movement. This wires spProductionRecord_Insert/_Update/_Delete to the
-- existing idempotent helper spPoultryEggStock_SyncForProduction (migration 131)
-- so good eggs (TotalProduction - Broken - Lost) increase the default egg
-- product and write a 'Production' row into PoultryStockTransactions.
--
-- Signatures are unchanged (the C# service keeps working); only the bodies gain
-- the egg-sync EXEC. Idempotent: the helper deletes any prior Production txn for
-- the record before re-inserting, so edits re-sync and deletes remove it.
-- Mirrors the exact bodies from migration 134 and only adds the egg-sync calls.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Insert]
    @FarmId NVARCHAR(100), @CreatedBy NVARCHAR(100), @UserId NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT,
    @Date DATE, @NoOfBirds INT, @Mortality INT, @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL,
    @Production9AM INT, @Production12PM INT, @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL,
    @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL, @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL, @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[ProductionRecords] (FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date], NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication, Production9AM, Production12PM, Production4PM, TotalProduction, FlockId, BrokenEggs, Notes, EggCount, EggGrade, MeatyEggs, SoftEggs, LostEggs, CreatedAt)
    VALUES (@FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date, @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication, @Production9AM, @Production12PM, @Production4PM, @TotalProduction, @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, @MeatyEggs, @SoftEggs, @LostEggs, GETUTCDATE());
    SET @NewId = SCOPE_IDENTITY();

    -- Bird mortality -> -birds (unchanged from migration 134)
    DECLARE @mq DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
    IF (@mq <> 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq, @NewId, N'Production mortality', @UserId;

    -- Doc 4d: good eggs increase the egg finished-product stock + stock movement.
    -- Good (sellable) = total produced minus broken and lost. Floor at 0.
    DECLARE @good INT = ISNULL(@TotalProduction,0) - ISNULL(@BrokenEggs,0) - ISNULL(@LostEggs,0);
    IF (@good < 0) SET @good = 0;
    EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @NewId, @good, NULL, @UserId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT, @UpdatedBy NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT, @Date DATE, @NoOfBirds INT, @Mortality INT,
    @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL, @Production9AM INT, @Production12PM INT,
    @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL, @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    DECLARE @FarmId NVARCHAR(100);
    SELECT @FarmId = FarmId FROM dbo.ProductionRecords WHERE Id = @RecordId;
    BEGIN TRANSACTION;
    UPDATE [dbo].[ProductionRecords]
    SET UpdatedBy=@UpdatedBy, AgeInWeeks=@AgeInWeeks, AgeInDays=@AgeInDays, [Date]=@Date, NoOfBirds=@NoOfBirds, Mortality=@Mortality,
        NoOfBirdsLeft=@NoOfBirdsLeft, FeedKg=@FeedKg, Medication=@Medication, Production9AM=@Production9AM, Production12PM=@Production12PM,
        Production4PM=@Production4PM, TotalProduction=@TotalProduction, FlockId=@FlockId, BrokenEggs=@BrokenEggs, Notes=@Notes,
        EggCount=@EggCount, EggGrade=@EggGrade, MeatyEggs=@MeatyEggs, SoftEggs=@SoftEggs, LostEggs=@LostEggs, UpdatedAt=GETUTCDATE()
    WHERE Id = @RecordId;

    IF (@FarmId IS NOT NULL)
    BEGIN
        DECLARE @mq2 DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq2, @RecordId, N'Production mortality', @UpdatedBy;

        DECLARE @good2 INT = ISNULL(@TotalProduction,0) - ISNULL(@BrokenEggs,0) - ISNULL(@LostEggs,0);
        IF (@good2 < 0) SET @good2 = 0;
        EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @RecordId, @good2, NULL, @UpdatedBy;
    END
    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Delete]
    @RecordId INT, @UserId NVARCHAR(100), @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    -- Reverse both bird mortality and egg-production stock for this record.
    EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', 0, @RecordId, NULL, @UserId;
    EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @RecordId, 0, NULL, @UserId;
    DELETE FROM [dbo].[ProductionRecords] WHERE Id = @RecordId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

PRINT 'Migration 136 applied: production records now increase egg inventory + write a stock movement.';
GO
