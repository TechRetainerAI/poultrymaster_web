-- Health module schema + stored procedures
-- Run this script against your Poultry database.

IF OBJECT_ID('dbo.HealthRecord', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.HealthRecord
    (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        UserId NVARCHAR(128) NOT NULL,
        FarmId NVARCHAR(128) NOT NULL,
        FlockId INT NULL,
        HouseId INT NULL,
        ItemId INT NULL,
        RecordDate DATETIME2 NOT NULL,
        Vaccination NVARCHAR(200) NULL,
        Medication NVARCHAR(200) NULL,
        WaterConsumption DECIMAL(18,2) NULL,
        Notes NVARCHAR(MAX) NULL,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_HealthRecord_CreatedDate DEFAULT SYSUTCDATETIME()
    );
END
GO

IF OBJECT_ID('dbo.spHealth_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spHealth_GetAll;
GO
CREATE PROCEDURE dbo.spHealth_GetAll
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
      AND UserId = @UserId
      AND (@FlockId IS NULL OR FlockId = @FlockId)
      AND (@HouseId IS NULL OR HouseId = @HouseId)
      AND (@ItemId IS NULL OR ItemId = @ItemId)
    ORDER BY RecordDate DESC, Id DESC;
END
GO

IF OBJECT_ID('dbo.spHealth_GetById', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spHealth_GetById;
GO
CREATE PROCEDURE dbo.spHealth_GetById
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
      AND FarmId = @FarmId
      AND UserId = @UserId;
END
GO

IF OBJECT_ID('dbo.spHealth_Insert', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spHealth_Insert;
GO
CREATE PROCEDURE dbo.spHealth_Insert
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

    INSERT INTO dbo.HealthRecord
    (
        UserId,
        FarmId,
        FlockId,
        HouseId,
        ItemId,
        RecordDate,
        Vaccination,
        Medication,
        WaterConsumption,
        Notes
    )
    VALUES
    (
        @UserId,
        @FarmId,
        @FlockId,
        @HouseId,
        @ItemId,
        @RecordDate,
        @Vaccination,
        @Medication,
        @WaterConsumption,
        @Notes
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
END
GO

IF OBJECT_ID('dbo.spHealth_Update', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spHealth_Update;
GO
CREATE PROCEDURE dbo.spHealth_Update
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
      AND FarmId = @FarmId
      AND UserId = @UserId;
END
GO

IF OBJECT_ID('dbo.spHealth_Delete', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spHealth_Delete;
GO
CREATE PROCEDURE dbo.spHealth_Delete
    @Id INT,
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.HealthRecord
    WHERE Id = @Id
      AND FarmId = @FarmId
      AND UserId = @UserId;
END
GO
