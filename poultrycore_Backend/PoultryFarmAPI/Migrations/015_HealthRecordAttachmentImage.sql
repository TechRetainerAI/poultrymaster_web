-- Optional image bytes on health records (medication pack photos, etc.).
-- Run on the Poultry app database after deploying PoultryFarmAPI that uses these columns/procs.

IF COL_LENGTH('dbo.HealthRecord', 'AttachmentImage') IS NULL
BEGIN
    ALTER TABLE dbo.HealthRecord ADD AttachmentImage VARBINARY(MAX) NULL;
END
GO

IF COL_LENGTH('dbo.HealthRecord', 'AttachmentContentType') IS NULL
BEGIN
    ALTER TABLE dbo.HealthRecord ADD AttachmentContentType NVARCHAR(64) NULL;
END
GO

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
        CreatedDate,
        CAST(CASE WHEN AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
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
        CreatedDate,
        CAST(CASE WHEN AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.HealthRecord
    WHERE Id = @Id
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spHealth_GetAttachment]
    @Id INT,
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT AttachmentImage, AttachmentContentType
    FROM dbo.HealthRecord
    WHERE Id = @Id
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spHealth_Insert]
    @UserId NVARCHAR(128),
    @FarmId NVARCHAR(128),
    @FlockId INT = NULL,
    @HouseId INT = NULL,
    @ItemId INT = NULL,
    @RecordDate DATETIME2,
    @Vaccination NVARCHAR(200) = NULL,
    @Medication NVARCHAR(200) = NULL,
    @WaterConsumption DECIMAL(18,2) = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @AttachmentImage VARBINARY(MAX) = NULL,
    @AttachmentContentType NVARCHAR(64) = NULL
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
        Notes,
        AttachmentImage,
        AttachmentContentType
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
        @Notes,
        @AttachmentImage,
        @AttachmentContentType
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
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
    @Notes NVARCHAR(MAX) = NULL,
    @AttachmentImage VARBINARY(MAX) = NULL,
    @AttachmentContentType NVARCHAR(64) = NULL,
    @AttachmentImageSet BIT = 0
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
        Notes = @Notes,
        AttachmentImage = CASE WHEN @AttachmentImageSet = 1 THEN @AttachmentImage ELSE AttachmentImage END,
        AttachmentContentType = CASE WHEN @AttachmentImageSet = 1 THEN @AttachmentContentType ELSE AttachmentContentType END
    WHERE Id = @Id
      AND FarmId = @FarmId;
END
GO
