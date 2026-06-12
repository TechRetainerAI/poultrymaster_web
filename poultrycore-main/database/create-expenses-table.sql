-- USE YourDatabaseName;
-- If you need to switch database, uncomment the line above and set the correct name.

/*
  Idempotent script: rerunnable. Removes existing objects if present
  and recreates a consistent Expenses schema + procedures.
*/

-- Safely drop procedures (SQL Server 2016+)
DROP PROCEDURE IF EXISTS dbo.spExpense_GetAll;
DROP PROCEDURE IF EXISTS dbo.spExpense_GetById;
DROP PROCEDURE IF EXISTS dbo.spExpense_Insert;
DROP PROCEDURE IF EXISTS dbo.spExpense_Update;
DROP PROCEDURE IF EXISTS dbo.spExpense_Delete;
DROP PROCEDURE IF EXISTS dbo.spExpense_GetByFlock;
GO

-- Drop and recreate table
IF OBJECT_ID('dbo.Expenses', 'U') IS NOT NULL DROP TABLE dbo.Expenses;
GO

CREATE TABLE dbo.Expenses (
  ExpenseId     INT IDENTITY(1,1) PRIMARY KEY,
  ExpenseDate   DATETIME2(0)      NOT NULL,
  Category      NVARCHAR(100)     NOT NULL,
  Description   NVARCHAR(500)     NULL,
  Amount        DECIMAL(18,2)     NOT NULL,
  PaymentMethod NVARCHAR(50)      NOT NULL,
  Supplier      NVARCHAR(255)     NULL,
  FlockId       INT               NULL,
  CreatedDate   DATETIME2(0)      NOT NULL CONSTRAINT DF_Expenses_CreatedDate DEFAULT (SYSUTCDATETIME()),
  UserId        NVARCHAR(450)     NOT NULL,
  FarmId        UNIQUEIDENTIFIER  NOT NULL
);
GO

-- Helpful indexes
CREATE INDEX IX_Expenses_FarmId_CreatedDate ON dbo.Expenses(FarmId, CreatedDate DESC);
CREATE INDEX IX_Expenses_FlockId ON dbo.Expenses(FlockId);
GO

-- List all by FarmId
CREATE PROCEDURE dbo.spExpense_GetAll
  @FarmId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  SELECT
    ExpenseId   = e.ExpenseId,
    ExpenseDate = e.ExpenseDate,
    Category    = e.Category,
    Description = e.Description,
    Amount      = e.Amount,
    PaymentMethod = e.PaymentMethod,
    Supplier      = e.Supplier,
    FlockId     = e.FlockId,
    CreatedDate = e.CreatedDate,
    FarmId      = e.FarmId,
    UserId      = e.UserId
  FROM dbo.Expenses e
  WHERE e.FarmId = @FarmId
  ORDER BY e.CreatedDate DESC;
END
GO

-- Get one by id + farm
CREATE PROCEDURE dbo.spExpense_GetById
  @ExpenseId INT,
  @FarmId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  SELECT
    ExpenseId   = e.ExpenseId,
    ExpenseDate = e.ExpenseDate,
    Category    = e.Category,
    Description = e.Description,
    Amount      = e.Amount,
    PaymentMethod = e.PaymentMethod,
    Supplier      = e.Supplier,
    FlockId     = e.FlockId,
    CreatedDate = e.CreatedDate,
    FarmId      = e.FarmId,
    UserId      = e.UserId
  FROM dbo.Expenses e
  WHERE e.ExpenseId = @ExpenseId AND e.FarmId = @FarmId;
END
GO

-- Insert
CREATE PROCEDURE dbo.spExpense_Insert
  @ExpenseDate DATETIME2(0),
  @Category NVARCHAR(100),
  @Description NVARCHAR(500) = NULL,
  @Amount DECIMAL(18,2),
  @PaymentMethod NVARCHAR(50),
  @Supplier NVARCHAR(255) = NULL,
  @FlockId INT = NULL,
  @UserId NVARCHAR(450),
  @FarmId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  INSERT INTO dbo.Expenses(ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, UserId, FarmId)
  VALUES(@ExpenseDate, @Category, @Description, @Amount, @PaymentMethod, @Supplier, @FlockId, @UserId, @FarmId);
  SELECT SCOPE_IDENTITY() AS NewId;
END
GO

-- Update
CREATE PROCEDURE dbo.spExpense_Update
  @ExpenseId INT,
  @ExpenseDate DATETIME2(0),
  @Category NVARCHAR(100),
  @Description NVARCHAR(500) = NULL,
  @Amount DECIMAL(18,2),
  @PaymentMethod NVARCHAR(50),
  @Supplier NVARCHAR(255) = NULL,
  @FlockId INT = NULL,
  @UserId NVARCHAR(450),
  @FarmId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE e
  SET ExpenseDate=@ExpenseDate,
      Category=@Category,
      Description=@Description,
      Amount=@Amount,
      PaymentMethod=@PaymentMethod,
      Supplier=@Supplier,
      FlockId=@FlockId,
      UserId=@UserId
  FROM dbo.Expenses e
  WHERE e.ExpenseId=@ExpenseId AND e.FarmId=@FarmId;
END
GO

-- Delete
CREATE PROCEDURE dbo.spExpense_Delete
  @ExpenseId INT,
  @FarmId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  DELETE FROM dbo.Expenses WHERE ExpenseId=@ExpenseId AND FarmId=@FarmId;
END
GO

-- By flock
CREATE PROCEDURE dbo.spExpense_GetByFlock
  @FlockId INT,
  @FarmId UNIQUEIDENTIFIER
AS
BEGIN
  SET NOCOUNT ON;
  SELECT
    ExpenseId   = e.ExpenseId,
    ExpenseDate = e.ExpenseDate,
    Category    = e.Category,
    Description = e.Description,
    Amount      = e.Amount,
    PaymentMethod = e.PaymentMethod,
    Supplier      = e.Supplier,
    FlockId     = e.FlockId,
    CreatedDate = e.CreatedDate,
    FarmId      = e.FarmId,
    UserId      = e.UserId
  FROM dbo.Expenses e
  WHERE e.FlockId = @FlockId AND e.FarmId = @FarmId
  ORDER BY e.CreatedDate DESC;
END
GO


