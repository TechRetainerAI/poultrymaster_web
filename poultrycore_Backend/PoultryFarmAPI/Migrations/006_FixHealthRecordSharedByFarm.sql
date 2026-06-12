-- Health records were filtered WHERE UserId = @UserId AND FarmId = @FarmId.
-- Staff creates rows with their AspNetUsers Id; farm owners query with a different Id → empty list for admin.
-- Align with production records / flocks: scope reads and farm-scoped edits by FarmId only.
-- @UserId remains a parameter for API compatibility; it is not used in WHERE for Get*.
--
-- Run against your Poultry database. Safe to run repeatedly (CREATE OR ALTER).

CREATE OR ALTER PROCEDURE [dbo].[spHealth_GetAll]
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128),
    @FlockId INT = NULL,
    @HouseId INT = NULL,
    @ItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id,
        UserId,
        FarmId,
        FlockId,
        HouseId,
        ItemId,
        RecordDate,
        Vaccination,
        Medication,
        WaterConsumption,
        Notes,
        CreatedDate
    FROM dbo.HealthRecord
    WHERE FarmId = @FarmId
      AND (@FlockId IS NULL OR FlockId = @FlockId)
      AND (@HouseId IS NULL OR HouseId = @HouseId)
      AND (@ItemId IS NULL OR ItemId = @ItemId)
    ORDER BY RecordDate DESC, Id DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spHealth_GetById]
    @Id INT,
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        Id,
        UserId,
        FarmId,
        FlockId,
        HouseId,
        ItemId,
        RecordDate,
        Vaccination,
        Medication,
        WaterConsumption,
        Notes,
        CreatedDate
    FROM dbo.HealthRecord
    WHERE Id = @Id
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spHealth_Update]
    @Id INT,
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128),
    @FlockId INT = NULL,
    @HouseId INT = NULL,
    @ItemId INT = NULL,
    @RecordDate DATETIME2,
    @Vaccination NVARCHAR(200) = NULL,
    @Medication NVARCHAR(200) = NULL,
    @WaterConsumption DECIMAL(18,2) = NULL,
    @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.HealthRecord
    SET
        FlockId = @FlockId,
        HouseId = @HouseId,
        ItemId = @ItemId,
        RecordDate = @RecordDate,
        Vaccination = @Vaccination,
        Medication = @Medication,
        WaterConsumption = @WaterConsumption,
        Notes = @Notes
    WHERE Id = @Id
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spHealth_Delete]
    @Id INT,
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.HealthRecord
    WHERE Id = @Id
      AND FarmId = @FarmId;
END
GO

PRINT '006_FixHealthRecordSharedByFarm: spHealth_GetAll/GetById/Update/Delete now scoped by FarmId.';
GO
