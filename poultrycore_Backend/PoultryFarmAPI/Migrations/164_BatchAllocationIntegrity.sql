-- =============================================================================
-- Migration 164: Batch production allocation integrity
-- =============================================================================
-- Hardens the batch-allocation lifecycle on top of migration 156 without
-- changing the batch->flock architecture. Everything here is additive/idempotent.
--
--   §5   Duplicate flock/date guard    - Post refuses to create a second daily
--                                        production record for a flock that
--                                        already has one on the production date.
--   §8,§9 Reversal is non-terminal     - a Reversed batch can be edited,
--                                        re-allocated and reposted (a fresh
--                                        PostingVersion), instead of being locked.
--   §10-§12 Delete Allocation          - a distinct action that clears the
--                                        allocation rows (reversing first when
--                                        the batch was already posted) while
--                                        leaving the parent batch record intact.
--   §4,§23 Concurrency / idempotency   - Post / Reverse / DeleteAllocation take
--                                        an UPDLOCK+HOLDLOCK on the batch header
--                                        row inside their transaction, so two
--                                        concurrent callers serialize and the
--                                        loser sees the already-changed status
--                                        and aborts (no duplicate side-effects).
--
-- Statuses unchanged: Draft, PendingAllocation, Allocated, Posted, Reversed,
-- Cancelled. Terminal-for-edit now means Posted or Cancelled only (Reversed is
-- reopened for reallocation).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 0. Posting-version counter on the header (§9 - track posting events so a
--    repost after reversal is distinguishable from the original posting).
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.ProductionBatchRecords', 'PostingVersion') IS NULL
    ALTER TABLE dbo.ProductionBatchRecords ADD PostingVersion INT NOT NULL
        CONSTRAINT DF_PBR_PostingVersion DEFAULT (0);
GO

-- -----------------------------------------------------------------------------
-- 0b. Self-heal columns that migration 156's table definition includes but that
--     are missing on databases created from an older 156 (the CREATE TABLE guard
--     in 156 is skipped once the table exists, so later-added columns never land).
--     Without these, spProductionBatchRecord_Post/_Update fail to compile with
--     "Invalid column name 'FeedType' / 'Medication'". Idempotent.
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.ProductionBatchRecords', 'FeedType') IS NULL
    ALTER TABLE dbo.ProductionBatchRecords ADD FeedType NVARCHAR(100) NULL;
GO
IF COL_LENGTH('dbo.ProductionBatchRecords', 'Medication') IS NULL
    ALTER TABLE dbo.ProductionBatchRecords ADD Medication NVARCHAR(500) NULL;
GO

-- -----------------------------------------------------------------------------
-- 0c. Re-create spProductionBatchRecord_Insert. It writes to FeedType/Medication,
--     so on a database that was missing those columns it failed to compile when
--     migration 156 was applied (leaving Create → HTTP 500). Now that 0b has
--     guaranteed the columns, rebuild it verbatim from 156. Idempotent.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Insert
    @FarmId NVARCHAR(450), @UserId NVARCHAR(450), @CreatedBy NVARCHAR(450),
    @BatchSelectionType NVARCHAR(20), @SelectedBirdBatchId INT = NULL, @BatchName NVARCHAR(150) = NULL,
    @ProductionDate DATE, @AgeInWeeks INT = NULL, @AgeInDays INT = NULL, @AgeDisplay NVARCHAR(50) = NULL,
    @FirstPickCrates INT = NULL, @FirstPickLooseEggs INT = NULL, @FirstPickTotal INT = 0,
    @SecondPickCrates INT = NULL, @SecondPickLooseEggs INT = NULL, @SecondPickTotal INT = 0,
    @ThirdPickCrates INT = NULL, @ThirdPickLooseEggs INT = NULL, @ThirdPickTotal INT = 0,
    @FourthPickCrates INT = NULL, @FourthPickLooseEggs INT = NULL, @FourthPickTotal INT = 0,
    @BrokenEggs INT = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL, @TotalEggs INT = 0,
    @FeedKg DECIMAL(18,2) = NULL, @Deaths INT = 0, @BirdsLeft INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @FeedType NVARCHAR(100) = NULL, @Medication NVARCHAR(500) = NULL,
    @TotalFeedCost DECIMAL(14,2) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL, @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @Status NVARCHAR(30) = N'PendingAllocation', @Notes NVARCHAR(MAX) = NULL,
    @IncludedFlocksJson NVARCHAR(MAX) = NULL, @FeedsJson NVARCHAR(MAX) = NULL, @MedicationsJson NVARCHAR(MAX) = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    INSERT INTO dbo.ProductionBatchRecords (
        FarmId, UserId, BatchSelectionType, SelectedBirdBatchId, BatchName, ProductionDate,
        AgeInWeeks, AgeInDays, AgeDisplay,
        FirstPickCrates, FirstPickLooseEggs, FirstPickTotal,
        SecondPickCrates, SecondPickLooseEggs, SecondPickTotal,
        ThirdPickCrates, ThirdPickLooseEggs, ThirdPickTotal,
        FourthPickCrates, FourthPickLooseEggs, FourthPickTotal,
        BrokenEggs, MeatyEggs, SoftEggs, LostEggs, TotalEggs,
        FeedKg, Deaths, BirdsLeft, EggGrade, FeedType, Medication,
        TotalFeedCost, TotalMedicationCost, TotalCostOfProduction, Status, Notes, CreatedBy, CreatedDate)
    VALUES (
        @FarmId, @UserId, @BatchSelectionType, @SelectedBirdBatchId, @BatchName, @ProductionDate,
        @AgeInWeeks, @AgeInDays, @AgeDisplay,
        @FirstPickCrates, @FirstPickLooseEggs, ISNULL(@FirstPickTotal,0),
        @SecondPickCrates, @SecondPickLooseEggs, ISNULL(@SecondPickTotal,0),
        @ThirdPickCrates, @ThirdPickLooseEggs, ISNULL(@ThirdPickTotal,0),
        @FourthPickCrates, @FourthPickLooseEggs, ISNULL(@FourthPickTotal,0),
        @BrokenEggs, @MeatyEggs, @SoftEggs, @LostEggs, ISNULL(@TotalEggs,0),
        @FeedKg, ISNULL(@Deaths,0), @BirdsLeft, @EggGrade, @FeedType, @Medication,
        @TotalFeedCost, @TotalMedicationCost, @TotalCostOfProduction, ISNULL(@Status,N'PendingAllocation'),
        @Notes, @CreatedBy, SYSUTCDATETIME());
    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);

    EXEC dbo.spProductionBatchRecord_ReplaceChildren
         @NewId, @CreatedBy, @IncludedFlocksJson, @FeedsJson, @MedicationsJson;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- Post — validate balance + no duplicate daily flock record, then create a
-- flock-level ProductionRecord per allocation row (reusing spProductionRecord_Insert
-- so all bird/egg/raw-material side-effects are inherited), stamp provenance, and
-- mark the batch Posted. All inside one transaction; XACT_ABORT rolls back on any
-- failure. A Reversed batch may be reposted (fresh PostingVersion). The header row
-- is locked (UPDLOCK,HOLDLOCK) so concurrent posts serialize and the second aborts.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Post
    @Id INT, @FarmId NVARCHAR(450), @PostedBy NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    -- Lock the header for the duration: a concurrent Post blocks here, then sees
    -- Status = 'Posted' below and throws (idempotent - no double side-effects).
    DECLARE @UserId NVARCHAR(450), @Status NVARCHAR(30), @Date DATE;
    SELECT @UserId = UserId, @Status = Status, @Date = ProductionDate
    FROM dbo.ProductionBatchRecords WITH (UPDLOCK, HOLDLOCK)
    WHERE Id = @Id AND FarmId = @FarmId;

    IF (@Status IS NULL) THROW 51630, 'Batch production record not found.', 1;
    IF (@Status = N'Posted') THROW 51631, 'This batch has already been posted.', 1;
    IF (@Status NOT IN (N'Allocated', N'PendingAllocation', N'Reversed'))
        THROW 51632, 'Only an allocated or reversed batch can be posted.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id)
        THROW 51633, 'This batch has no allocation rows to post.', 1;

    -- ---- §5 Duplicate daily flock production guard. ----
    -- Any pre-existing ProductionRecord for an allocated flock on the same date
    -- is a genuine conflict (manual entry or another batch). Records generated by
    -- THIS batch's previous posting were hard-deleted on reversal, so they never
    -- appear here. Build a readable, 2016-safe list of the offending flock names.
    DECLARE @Conflicts NVARCHAR(MAX) =
        STUFF((SELECT N', ' + ISNULL(NULLIF(LTRIM(RTRIM(a.FlockName)), N''), CONCAT(N'Flock ', a.FlockId))
               FROM dbo.ProductionBatchAllocations a
               WHERE a.ProductionBatchRecordId = @Id
                 AND EXISTS (SELECT 1 FROM dbo.ProductionRecords pr
                             WHERE pr.FarmId = @FarmId AND pr.FlockId = a.FlockId AND pr.[Date] = @Date)
               ORDER BY a.Id
               FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'');
    IF (@Conflicts IS NOT NULL AND LEN(@Conflicts) > 0)
    BEGIN
        DECLARE @DupMsg NVARCHAR(2048) = CONCAT(
            N'Cannot post: the following flock(s) already have a production record for ',
            CONVERT(NVARCHAR(30), @Date, 107), N': ', @Conflicts,
            N'. Edit or remove the existing production record(s) before posting this allocation.');
        THROW 51637, @DupMsg, 1;
    END

    -- ---- Reconciliation: allocated egg/death totals must equal batch totals. ----
    DECLARE @bP1 INT, @bP2 INT, @bP3 INT, @bP4 INT, @bBroken INT, @bMeaty INT, @bSoft INT, @bLost INT, @bDeaths INT;
    SELECT @bP1=FirstPickTotal, @bP2=SecondPickTotal, @bP3=ThirdPickTotal, @bP4=FourthPickTotal,
           @bBroken=ISNULL(BrokenEggs,0), @bMeaty=ISNULL(MeatyEggs,0), @bSoft=ISNULL(SoftEggs,0),
           @bLost=ISNULL(LostEggs,0), @bDeaths=ISNULL(Deaths,0)
    FROM dbo.ProductionBatchRecords WHERE Id = @Id;

    DECLARE @aP1 INT, @aP2 INT, @aP3 INT, @aP4 INT, @aBroken INT, @aMeaty INT, @aSoft INT, @aLost INT, @aDeaths INT;
    SELECT @aP1=ISNULL(SUM(FirstPickEggs),0), @aP2=ISNULL(SUM(SecondPickEggs),0), @aP3=ISNULL(SUM(ThirdPickEggs),0),
           @aP4=ISNULL(SUM(FourthPickEggs),0), @aBroken=ISNULL(SUM(ISNULL(BrokenEggs,0)),0),
           @aMeaty=ISNULL(SUM(ISNULL(MeatyEggs,0)),0), @aSoft=ISNULL(SUM(ISNULL(SoftEggs,0)),0),
           @aLost=ISNULL(SUM(ISNULL(LostEggs,0)),0), @aDeaths=ISNULL(SUM(ISNULL(Deaths,0)),0)
    FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id;

    IF (@aP1<>@bP1 OR @aP2<>@bP2 OR @aP3<>@bP3 OR @aP4<>@bP4 OR @aBroken<>@bBroken
        OR @aMeaty<>@bMeaty OR @aSoft<>@bSoft OR @aLost<>@bLost OR @aDeaths<>@bDeaths)
        THROW 51634, 'Allocation does not balance against the batch egg/death totals.', 1;

    -- ---- Reconciliation: allocated feed qty per item must equal batch feed qty. ----
    IF EXISTS (
        SELECT bu.InventoryItemId
        FROM dbo.ProductionBatchFeedUsage bu
        WHERE bu.ProductionBatchRecordId = @Id
        GROUP BY bu.InventoryItemId
        HAVING ABS(SUM(bu.QuantityUsed) - ISNULL((
            SELECT SUM(afu.QuantityAllocated)
            FROM dbo.ProductionBatchAllocationFeedUsage afu
            JOIN dbo.ProductionBatchAllocations a ON a.Id = afu.ProductionBatchAllocationId
            WHERE a.ProductionBatchRecordId = @Id AND afu.InventoryItemId = bu.InventoryItemId), 0)) > 0.001)
        THROW 51635, 'Allocated feed quantities do not balance against the batch feed totals.', 1;

    -- ---- Reconciliation: allocated medication qty per item must equal batch. ----
    IF EXISTS (
        SELECT bu.InventoryItemId
        FROM dbo.ProductionBatchMedicationUsage bu
        WHERE bu.ProductionBatchRecordId = @Id
        GROUP BY bu.InventoryItemId
        HAVING ABS(SUM(bu.QuantityUsed) - ISNULL((
            SELECT SUM(amu.QuantityAllocated)
            FROM dbo.ProductionBatchAllocationMedicationUsage amu
            JOIN dbo.ProductionBatchAllocations a ON a.Id = amu.ProductionBatchAllocationId
            WHERE a.ProductionBatchRecordId = @Id AND amu.InventoryItemId = bu.InventoryItemId), 0)) > 0.001)
        THROW 51636, 'Allocated medication quantities do not balance against the batch medication totals.', 1;

    DECLARE alloc CURSOR LOCAL FAST_FORWARD FOR
        SELECT Id, FlockId, ISNULL(AgeInWeeks,0), ISNULL(AgeInDays,0), ISNULL(BirdsBefore,0), ISNULL(Deaths,0),
               ISNULL(BirdsAfter, ISNULL(BirdsBefore,0)-ISNULL(Deaths,0)), FirstPickEggs, SecondPickEggs, ThirdPickEggs,
               FourthPickEggs, ISNULL(BrokenEggs,0), MeatyEggs, SoftEggs, LostEggs, TotalEggs, ISNULL(FeedKg,0), Notes
        FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id ORDER BY Id;

    DECLARE @allocId INT, @flockId INT, @aw INT, @ad INT, @birdsBefore INT, @deaths INT, @birdsAfter INT,
            @p1 INT, @p2 INT, @p3 INT, @p4 INT, @broken INT, @meaty INT, @soft INT, @lost INT, @total INT,
            @feedKg DECIMAL(18,2), @notes NVARCHAR(MAX), @newRecId INT, @feedsJson NVARCHAR(MAX), @medsJson NVARCHAR(MAX),
            @eggGrade NVARCHAR(50), @batchMedication NVARCHAR(500);
    SELECT @eggGrade = EggGrade, @batchMedication = Medication FROM dbo.ProductionBatchRecords WHERE Id = @Id;

    OPEN alloc;
    FETCH NEXT FROM alloc INTO @allocId, @flockId, @aw, @ad, @birdsBefore, @deaths, @birdsAfter,
        @p1, @p2, @p3, @p4, @broken, @meaty, @soft, @lost, @total, @feedKg, @notes;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Build [{itemId,qty}] feed/medication JSON for this allocation from the flattened usage.
        SET @feedsJson = (SELECT afu.InventoryItemId AS itemId, afu.QuantityAllocated AS qty
                          FROM dbo.ProductionBatchAllocationFeedUsage afu
                          WHERE afu.ProductionBatchAllocationId = @allocId AND afu.QuantityAllocated > 0
                          FOR JSON PATH);
        SET @medsJson = (SELECT amu.InventoryItemId AS itemId, amu.QuantityAllocated AS qty
                         FROM dbo.ProductionBatchAllocationMedicationUsage amu
                         WHERE amu.ProductionBatchAllocationId = @allocId AND amu.QuantityAllocated > 0
                         FOR JSON PATH);

        SET @newRecId = NULL;
        EXEC dbo.spProductionRecord_Insert
             @FarmId = @FarmId, @CreatedBy = @PostedBy, @UserId = @UserId,
             @AgeInWeeks = @aw, @AgeInDays = @ad, @Date = @Date,
             @NoOfBirds = @birdsBefore, @Mortality = @deaths, @NoOfBirdsLeft = @birdsAfter,
             @FeedKg = @feedKg, @Medication = @batchMedication,
             @Production9AM = @p1, @Production12PM = @p2, @Production4PM = @p3, @TotalProduction = @total,
             @FlockId = @flockId, @BrokenEggs = @broken, @Notes = @notes, @EggCount = @total,
             @EggGrade = @eggGrade, @MeatyEggs = @meaty, @SoftEggs = @soft, @LostEggs = @lost,
             @FeedsJson = @feedsJson, @MedicationsJson = @medsJson,
             @NewId = @newRecId OUTPUT;

        -- 4th pick + provenance stamp on the generated flock record.
        IF (@newRecId IS NOT NULL)
        BEGIN
            IF OBJECT_ID('dbo.spProductionRecord_SetFourthPick','P') IS NOT NULL
                EXEC dbo.spProductionRecord_SetFourthPick @RecordId = @newRecId, @FarmId = @FarmId, @Production4thPick = @p4;

            UPDATE dbo.ProductionRecords
            SET ProductionBatchId = @Id, ProductionBatchAllocationId = @allocId, SourceType = N'BatchAllocation'
            WHERE Id = @newRecId;

            UPDATE dbo.ProductionBatchAllocations SET GeneratedProductionRecordId = @newRecId WHERE Id = @allocId;
        END

        FETCH NEXT FROM alloc INTO @allocId, @flockId, @aw, @ad, @birdsBefore, @deaths, @birdsAfter,
            @p1, @p2, @p3, @p4, @broken, @meaty, @soft, @lost, @total, @feedKg, @notes;
    END
    CLOSE alloc; DEALLOCATE alloc;

    UPDATE dbo.ProductionBatchRecords
    SET Status = N'Posted', PostingVersion = ISNULL(PostingVersion,0) + 1,
        PostedBy = @PostedBy, PostedDate = SYSUTCDATETIME(), UpdatedBy = @PostedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- Reverse — delete the generated flock records (reverses their bird/egg/raw-
-- material side-effects via spProductionRecord_Delete) and mark batch Reversed.
-- Header locked (UPDLOCK,HOLDLOCK) so a concurrent reverse serializes and the
-- second sees Status <> 'Posted' and aborts (idempotent).
-- The batch is left reopened for reallocation/repost (§8,§9).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Reverse
    @Id INT, @FarmId NVARCHAR(450), @ReversedBy NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @UserId NVARCHAR(450), @Status NVARCHAR(30);
    SELECT @UserId = UserId, @Status = Status
    FROM dbo.ProductionBatchRecords WITH (UPDLOCK, HOLDLOCK)
    WHERE Id = @Id AND FarmId = @FarmId;

    IF (@Status IS NULL) THROW 51640, 'Batch production record not found.', 1;
    IF (@Status <> N'Posted') THROW 51641, 'Only a posted batch can be reversed.', 1;

    DECLARE @recId INT, @allocId INT;
    DECLARE rev CURSOR LOCAL FAST_FORWARD FOR
        SELECT Id, GeneratedProductionRecordId FROM dbo.ProductionBatchAllocations
        WHERE ProductionBatchRecordId = @Id AND GeneratedProductionRecordId IS NOT NULL;
    OPEN rev;
    FETCH NEXT FROM rev INTO @allocId, @recId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.spProductionRecord_Delete @RecordId = @recId, @UserId = @UserId, @FarmId = @FarmId;
        UPDATE dbo.ProductionBatchAllocations SET GeneratedProductionRecordId = NULL WHERE Id = @allocId;
        FETCH NEXT FROM rev INTO @allocId, @recId;
    END
    CLOSE rev; DEALLOCATE rev;

    UPDATE dbo.ProductionBatchRecords
    SET Status = N'Reversed', UpdatedBy = @ReversedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- DeleteAllocation (§10-§12) — remove the allocation rows while KEEPING the
-- parent batch record. Distinct from spProductionBatchRecord_Delete (whole
-- batch) and from Reverse (which keeps the allocation rows for audit/repost).
--   * Posted   : reverse the generated flock records first (same reversal path
--                as spProductionBatchRecord_Reverse), then drop the rows.
--   * otherwise: just drop the rows (no inventory effects to undo).
-- Either way the header returns to PendingAllocation so it can be re-allocated.
-- Header locked (UPDLOCK,HOLDLOCK) for concurrency/idempotency.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_DeleteAllocation
    @Id INT, @FarmId NVARCHAR(450), @UpdatedBy NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @UserId NVARCHAR(450), @Status NVARCHAR(30);
    SELECT @UserId = UserId, @Status = Status
    FROM dbo.ProductionBatchRecords WITH (UPDLOCK, HOLDLOCK)
    WHERE Id = @Id AND FarmId = @FarmId;

    IF (@Status IS NULL) THROW 51650, 'Batch production record not found.', 1;
    IF (@Status = N'Cancelled') THROW 51651, 'A cancelled batch has no allocation to delete.', 1;

    -- Posted -> reverse the generated flock records (reuse the flock-level delete
    -- so inventory / bird / raw-material effects are undone) before dropping rows.
    IF (@Status = N'Posted')
    BEGIN
        DECLARE @recId INT, @allocId INT;
        DECLARE del CURSOR LOCAL FAST_FORWARD FOR
            SELECT Id, GeneratedProductionRecordId FROM dbo.ProductionBatchAllocations
            WHERE ProductionBatchRecordId = @Id AND GeneratedProductionRecordId IS NOT NULL;
        OPEN del;
        FETCH NEXT FROM del INTO @allocId, @recId;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.spProductionRecord_Delete @RecordId = @recId, @UserId = @UserId, @FarmId = @FarmId;
            FETCH NEXT FROM del INTO @allocId, @recId;
        END
        CLOSE del; DEALLOCATE del;
    END

    DELETE FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id;  -- cascades feed/med usage

    UPDATE dbo.ProductionBatchRecords
    SET Status = N'PendingAllocation', UpdatedBy = @UpdatedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- Update — allow editing a Reversed batch again (§8). Terminal-for-edit is now
-- Posted or Cancelled only. Otherwise identical to migration 156.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Update
    @Id INT, @UpdatedBy NVARCHAR(450),
    @BatchSelectionType NVARCHAR(20), @SelectedBirdBatchId INT = NULL, @BatchName NVARCHAR(150) = NULL,
    @ProductionDate DATE, @AgeInWeeks INT = NULL, @AgeInDays INT = NULL, @AgeDisplay NVARCHAR(50) = NULL,
    @FirstPickCrates INT = NULL, @FirstPickLooseEggs INT = NULL, @FirstPickTotal INT = 0,
    @SecondPickCrates INT = NULL, @SecondPickLooseEggs INT = NULL, @SecondPickTotal INT = 0,
    @ThirdPickCrates INT = NULL, @ThirdPickLooseEggs INT = NULL, @ThirdPickTotal INT = 0,
    @FourthPickCrates INT = NULL, @FourthPickLooseEggs INT = NULL, @FourthPickTotal INT = 0,
    @BrokenEggs INT = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL, @TotalEggs INT = 0,
    @FeedKg DECIMAL(18,2) = NULL, @Deaths INT = 0, @BirdsLeft INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @FeedType NVARCHAR(100) = NULL, @Medication NVARCHAR(500) = NULL,
    @TotalFeedCost DECIMAL(14,2) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL, @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @Status NVARCHAR(30) = NULL, @Notes NVARCHAR(MAX) = NULL,
    @IncludedFlocksJson NVARCHAR(MAX) = NULL, @FeedsJson NVARCHAR(MAX) = NULL, @MedicationsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @CurStatus NVARCHAR(30);
    SELECT @CurStatus = Status FROM dbo.ProductionBatchRecords WITH (UPDLOCK, HOLDLOCK) WHERE Id = @Id;
    IF (@CurStatus IS NULL) THROW 51610, 'Batch production record not found.', 1;
    IF (@CurStatus IN (N'Posted', N'Cancelled'))
        THROW 51611, 'A posted or cancelled batch cannot be edited. Reverse a posted batch first.', 1;

    UPDATE dbo.ProductionBatchRecords
    SET BatchSelectionType=@BatchSelectionType, SelectedBirdBatchId=@SelectedBirdBatchId, BatchName=@BatchName,
        ProductionDate=@ProductionDate, AgeInWeeks=@AgeInWeeks, AgeInDays=@AgeInDays, AgeDisplay=@AgeDisplay,
        FirstPickCrates=@FirstPickCrates, FirstPickLooseEggs=@FirstPickLooseEggs, FirstPickTotal=ISNULL(@FirstPickTotal,0),
        SecondPickCrates=@SecondPickCrates, SecondPickLooseEggs=@SecondPickLooseEggs, SecondPickTotal=ISNULL(@SecondPickTotal,0),
        ThirdPickCrates=@ThirdPickCrates, ThirdPickLooseEggs=@ThirdPickLooseEggs, ThirdPickTotal=ISNULL(@ThirdPickTotal,0),
        FourthPickCrates=@FourthPickCrates, FourthPickLooseEggs=@FourthPickLooseEggs, FourthPickTotal=ISNULL(@FourthPickTotal,0),
        BrokenEggs=@BrokenEggs, MeatyEggs=@MeatyEggs, SoftEggs=@SoftEggs, LostEggs=@LostEggs, TotalEggs=ISNULL(@TotalEggs,0),
        FeedKg=@FeedKg, Deaths=ISNULL(@Deaths,0), BirdsLeft=@BirdsLeft, EggGrade=@EggGrade,
        FeedType=@FeedType, Medication=@Medication,
        TotalFeedCost=@TotalFeedCost, TotalMedicationCost=@TotalMedicationCost, TotalCostOfProduction=@TotalCostOfProduction,
        Status=ISNULL(@Status, Status), Notes=@Notes, UpdatedBy=@UpdatedBy, UpdatedDate=SYSUTCDATETIME()
    WHERE Id = @Id;

    EXEC dbo.spProductionBatchRecord_ReplaceChildren
         @Id, @UpdatedBy, @IncludedFlocksJson, @FeedsJson, @MedicationsJson;
    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- SaveAllocation — allow (re)allocating a Reversed batch (§8,§9). Terminal-for-
-- allocation is now Posted or Cancelled only. Otherwise identical to migration 156.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_SaveAllocation
    @Id INT, @FarmId NVARCHAR(450), @UpdatedBy NVARCHAR(450),
    @AllocationsJson NVARCHAR(MAX), @Status NVARCHAR(30) = N'Allocated'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @CurStatus NVARCHAR(30);
    SELECT @CurStatus = Status FROM dbo.ProductionBatchRecords WITH (UPDLOCK, HOLDLOCK)
    WHERE Id = @Id AND FarmId = @FarmId;
    IF (@CurStatus IS NULL) THROW 51620, 'Batch production record not found.', 1;
    IF (@CurStatus IN (N'Posted', N'Cancelled'))
        THROW 51621, 'Allocation cannot be edited for a posted or cancelled batch. Reverse a posted batch first.', 1;

    DELETE FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id;  -- cascades feed/med

    DECLARE @rows TABLE (Seq INT, Payload NVARCHAR(MAX));
    INSERT INTO @rows (Seq, Payload)
    SELECT [key] + 1, [value] FROM OPENJSON(@AllocationsJson);

    DECLARE @i INT = 1, @n INT = (SELECT ISNULL(MAX(Seq),0) FROM @rows), @p NVARCHAR(MAX), @allocId INT;
    WHILE @i <= @n
    BEGIN
        SELECT @p = Payload FROM @rows WHERE Seq = @i;

        INSERT INTO dbo.ProductionBatchAllocations (
            ProductionBatchRecordId, FlockId, FlockName, AllocationMethod, AgeInWeeks, AgeInDays,
            BirdsBefore, Deaths, BirdsAfter, FirstPickEggs, SecondPickEggs, ThirdPickEggs, FourthPickEggs,
            BrokenEggs, MeatyEggs, SoftEggs, LostEggs, TotalEggs, EggPercentage, FeedKg,
            TotalFeedCost, TotalMedicationCost, TotalCostOfProduction, Notes, CreatedBy, CreatedDate)
        SELECT @Id, j.FlockId, j.FlockName, j.AllocationMethod, j.AgeInWeeks, j.AgeInDays,
               j.BirdsBefore, ISNULL(j.Deaths,0), j.BirdsAfter, ISNULL(j.FirstPickEggs,0), ISNULL(j.SecondPickEggs,0),
               ISNULL(j.ThirdPickEggs,0), ISNULL(j.FourthPickEggs,0), j.BrokenEggs, j.MeatyEggs, j.SoftEggs, j.LostEggs,
               ISNULL(j.TotalEggs,0), j.EggPercentage, j.FeedKg, j.TotalFeedCost, j.TotalMedicationCost,
               j.TotalCostOfProduction, j.Notes, @UpdatedBy, SYSUTCDATETIME()
        FROM OPENJSON(@p) WITH (
            FlockId INT '$.flockId', FlockName NVARCHAR(150) '$.flockName', AllocationMethod NVARCHAR(30) '$.allocationMethod',
            AgeInWeeks INT '$.ageInWeeks', AgeInDays INT '$.ageInDays', BirdsBefore INT '$.birdsBefore', Deaths INT '$.deaths',
            BirdsAfter INT '$.birdsAfter', FirstPickEggs INT '$.firstPickEggs', SecondPickEggs INT '$.secondPickEggs',
            ThirdPickEggs INT '$.thirdPickEggs', FourthPickEggs INT '$.fourthPickEggs', BrokenEggs INT '$.brokenEggs',
            MeatyEggs INT '$.meatyEggs', SoftEggs INT '$.softEggs', LostEggs INT '$.lostEggs', TotalEggs INT '$.totalEggs',
            EggPercentage DECIMAL(9,2) '$.eggPercentage', FeedKg DECIMAL(18,2) '$.feedKg',
            TotalFeedCost DECIMAL(14,2) '$.totalFeedCost', TotalMedicationCost DECIMAL(14,2) '$.totalMedicationCost',
            TotalCostOfProduction DECIMAL(14,2) '$.totalCostOfProduction', Notes NVARCHAR(MAX) '$.notes') j;
        SET @allocId = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.ProductionBatchAllocationFeedUsage (
            ProductionBatchAllocationId, ProductionBatchFeedUsageId, InventoryItemId, ItemName, QuantityAllocated, UnitCost, TotalCost, CreatedBy)
        SELECT @allocId, f.BatchUsageId, f.ItemId, f.ItemName, f.Qty, f.UnitCost, f.TotalCost, @UpdatedBy
        FROM OPENJSON(@p, '$.feeds') WITH (
            BatchUsageId INT '$.batchUsageId', ItemId INT '$.itemId', ItemName NVARCHAR(150) '$.itemName',
            Qty DECIMAL(14,3) '$.qty', UnitCost DECIMAL(14,4) '$.unitCost', TotalCost DECIMAL(14,2) '$.totalCost') f
        WHERE f.ItemId IS NOT NULL;

        INSERT INTO dbo.ProductionBatchAllocationMedicationUsage (
            ProductionBatchAllocationId, ProductionBatchMedicationUsageId, InventoryItemId, ItemName, QuantityAllocated, UnitCost, TotalCost, CreatedBy)
        SELECT @allocId, m.BatchUsageId, m.ItemId, m.ItemName, m.Qty, m.UnitCost, m.TotalCost, @UpdatedBy
        FROM OPENJSON(@p, '$.medications') WITH (
            BatchUsageId INT '$.batchUsageId', ItemId INT '$.itemId', ItemName NVARCHAR(150) '$.itemName',
            Qty DECIMAL(14,3) '$.qty', UnitCost DECIMAL(14,4) '$.unitCost', TotalCost DECIMAL(14,2) '$.totalCost') m
        WHERE m.ItemId IS NOT NULL;

        SET @i += 1;
    END

    UPDATE dbo.ProductionBatchRecords
    SET Status = ISNULL(@Status, N'Allocated'), UpdatedBy = @UpdatedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;
    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- Grants to the application login.
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Insert           TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Post             TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Reverse          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_DeleteAllocation TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Update           TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_SaveAllocation   TO [Techretainer];
    PRINT '164: granted rights on batch-allocation integrity objects to Techretainer.';
END
GO

PRINT '164_BatchAllocationIntegrity.sql complete.';
GO
