-- SQL script to create AuditLogs table
-- Run this in your SQL Server database

CREATE TABLE [dbo].[AuditLogs] (
    [Id] [uniqueidentifier] NOT NULL PRIMARY KEY DEFAULT NEWID(),
    [UserId] [nvarchar](450) NOT NULL,
    [UserName] [nvarchar](256) NULL,
    [Action] [nvarchar](100) NOT NULL,
    [Resource] [nvarchar](100) NULL,
    [ResourceId] [nvarchar](450) NULL,
    [Details] [nvarchar](max) NULL,
    [IpAddress] [nvarchar](45) NULL,
    [UserAgent] [nvarchar](500) NULL,
    [Timestamp] [datetime2](7) NOT NULL DEFAULT GETDATE(),
    [Status] [nvarchar](50) NOT NULL
) ON [PRIMARY];

-- Create indexes for better performance
CREATE INDEX IX_AuditLogs_UserId ON [dbo].[AuditLogs] ([UserId]);
CREATE INDEX IX_AuditLogs_Timestamp ON [dbo].[AuditLogs] ([Timestamp]);

-- Sample test data
INSERT INTO [dbo].[AuditLogs] ([UserId], [UserName], [Action], [Resource], [Details], [IpAddress], [Status])
VALUES 
    (N'user123', N'testuser', N'Login', N'Authentication', N'User logged in successfully', N'127.0.0.1', N'Success'),
    (N'user123', N'testuser', N'View', N'Dashboard', N'User viewed dashboard', N'127.0.0.1', N'Success'),
    (N'user123', N'testuser', N'Create', N'Customer', N'Customer created', N'127.0.0.1', N'Success');
