-- Receipt image bytes on expense rows. List/detail return HasAttachmentImage only (no blob in JSON).
-- Run after deploying PoultryFarmAPI. Requires dbo.Expense.

IF OBJECT_ID('dbo.Expense', 'U') IS NULL
BEGIN
    RAISERROR('dbo.Expense table not found.', 16, 1);
    RETURN;
END
GO

IF COL_LENGTH('dbo.Expense', 'AttachmentImage') IS NULL
BEGIN
    ALTER TABLE dbo.Expense ADD AttachmentImage VARBINARY(MAX) NULL;
END
GO

IF COL_LENGTH('dbo.Expense', 'AttachmentContentType') IS NULL
BEGIN
    ALTER TABLE dbo.Expense ADD AttachmentContentType NVARCHAR(64) NULL;
END
GO

IF COL_LENGTH('dbo.Expense', 'Supplier') IS NULL
BEGIN
    ALTER TABLE dbo.Expense ADD Supplier NVARCHAR(255) NULL;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetAll]
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.ExpenseId,
        e.ExpenseDate,
        e.Category,
        e.Description,
        e.Amount,
        e.PaymentMethod,
        Supplier = e.Supplier,
        e.FlockId,
        e.CreatedDate,
        e.FarmId,
        e.UserId,
        CAST(CASE WHEN e.AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.Expense e
    WHERE e.FarmId = @FarmId
    ORDER BY e.CreatedDate DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetById]
    @ExpenseId INT,
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.ExpenseId,
        e.ExpenseDate,
        e.Category,
        e.Description,
        e.Amount,
        e.PaymentMethod,
        Supplier = e.Supplier,
        e.FlockId,
        e.CreatedDate,
        e.FarmId,
        e.UserId,
        CAST(CASE WHEN e.AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.Expense e
    WHERE e.ExpenseId = @ExpenseId
      AND e.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetAttachment]
    @ExpenseId INT,
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.AttachmentImage, e.AttachmentContentType
    FROM dbo.Expense e
    WHERE e.ExpenseId = @ExpenseId
      AND e.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_Insert]
    @ExpenseDate DATETIME2(0),
    @Category NVARCHAR(100),
    @Description NVARCHAR(500) = NULL,
    @Amount DECIMAL(18,2),
    @PaymentMethod NVARCHAR(50),
    @Supplier NVARCHAR(255) = NULL,
    @FlockId INT = NULL,
    @UserId NVARCHAR(450),
    @FarmId UNIQUEIDENTIFIER,
    @AttachmentImage VARBINARY(MAX) = NULL,
    @AttachmentContentType NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Expense
    (
        ExpenseDate,
        Category,
        Description,
        Amount,
        PaymentMethod,
        Supplier,
        FlockId,
        UserId,
        FarmId,
        AttachmentImage,
        AttachmentContentType
    )
    VALUES
    (
        @ExpenseDate,
        @Category,
        @Description,
        @Amount,
        @PaymentMethod,
        @Supplier,
        @FlockId,
        @UserId,
        @FarmId,
        @AttachmentImage,
        @AttachmentContentType
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_Update]
    @ExpenseId INT,
    @ExpenseDate DATETIME2(0),
    @Category NVARCHAR(100),
    @Description NVARCHAR(500) = NULL,
    @Amount DECIMAL(18,2),
    @PaymentMethod NVARCHAR(50),
    @Supplier NVARCHAR(255) = NULL,
    @FlockId INT = NULL,
    @UserId NVARCHAR(450),
    @FarmId UNIQUEIDENTIFIER,
    @AttachmentImage VARBINARY(MAX) = NULL,
    @AttachmentContentType NVARCHAR(64) = NULL,
    @AttachmentImageSet BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE e
    SET
        ExpenseDate = @ExpenseDate,
        Category = @Category,
        Description = @Description,
        Amount = @Amount,
        PaymentMethod = @PaymentMethod,
        Supplier = @Supplier,
        FlockId = @FlockId,
        UserId = @UserId,
        AttachmentImage = CASE WHEN @AttachmentImageSet = 1 THEN @AttachmentImage ELSE e.AttachmentImage END,
        AttachmentContentType = CASE WHEN @AttachmentImageSet = 1 THEN @AttachmentContentType ELSE e.AttachmentContentType END
    FROM dbo.Expense e
    WHERE e.ExpenseId = @ExpenseId
      AND e.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spExpense_GetByFlock]
    @FlockId INT,
    @FarmId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        e.ExpenseId,
        e.ExpenseDate,
        e.Category,
        e.Description,
        e.Amount,
        e.PaymentMethod,
        Supplier = e.Supplier,
        e.FlockId,
        e.CreatedDate,
        e.FarmId,
        e.UserId,
        CAST(CASE WHEN e.AttachmentImage IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasAttachmentImage
    FROM dbo.Expense e
    WHERE e.FlockId = @FlockId
      AND e.FarmId = @FarmId
    ORDER BY e.CreatedDate DESC;
END
GO
