-- Stored Procedures for MainFlockBatch
-- This script creates the spMainFlockBatch_GetAll stored procedure
-- Note: Adjust data types (FarmId, UserId) to match your actual table structure

-- Drop existing procedure if it exists
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spMainFlockBatch_GetAll]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[spMainFlockBatch_GetAll]
GO

-- Create GetAll stored procedure
-- Version 2: Status column does NOT exist in the table
-- The C# code will default Status to 'active' when the column is missing
CREATE PROCEDURE [dbo].[spMainFlockBatch_GetAll]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450)  -- Change to UNIQUEIDENTIFIER if your FarmId is GUID type
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        BatchId = b.BatchId,
        FarmId = b.FarmId,
        UserId = b.UserId,
        BatchCode = b.BatchCode,
        BatchName = b.BatchName,
        Breed = b.Breed,
        NumberOfBirds = b.NumberOfBirds,
        StartDate = b.StartDate,
        CreatedDate = b.CreatedDate
        -- Note: Status column not included - C# code will default to 'active'
    FROM dbo.MainFlockBatch b
    WHERE b.UserId = @UserId 
      AND b.FarmId = @FarmId
    ORDER BY b.CreatedDate DESC;
END
GO

/*
-- Version 1: If Status column EXISTS in your MainFlockBatch table, use this version:
-- (Uncomment this and comment out Version 2 above)

CREATE PROCEDURE [dbo].[spMainFlockBatch_GetAll]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT
        BatchId = b.BatchId,
        FarmId = b.FarmId,
        UserId = b.UserId,
        BatchCode = b.BatchCode,
        BatchName = b.BatchName,
        Breed = b.Breed,
        NumberOfBirds = b.NumberOfBirds,
        StartDate = b.StartDate,
        Status = ISNULL(b.Status, 'active'),
        CreatedDate = b.CreatedDate
    FROM dbo.MainFlockBatch b
    WHERE b.UserId = @UserId 
      AND b.FarmId = @FarmId
    ORDER BY b.CreatedDate DESC;
END
GO
*/

-- Note: If your FarmId column is of type UNIQUEIDENTIFIER, change the parameter type:
-- @FarmId UNIQUEIDENTIFIER
-- And convert in the WHERE clause:
-- WHERE b.UserId = @UserId AND b.FarmId = CAST(@FarmId AS UNIQUEIDENTIFIER)

